// src/lib/stores/connection.svelte.ts
import { health, isMockEnabled } from "$api/client";
import type { HealthResponse } from "$api/types";

const LOG = "[bizforge:connection]";

export type ConnectionStatus =
  | "connecting"
  | "connected"
  | "reconnecting"
  | "disconnected"
  | "mock";

class ConnectionStore {
  status = $state<ConnectionStatus>("connecting");
  lastChecked = $state<Date | null>(null);
  lastConnectedAt = $state<Date | null>(null);
  error = $state<string | null>(null);
  health = $state<HealthResponse | null>(null);
  isChecking = $state(false);
  reconnectAttempts = $state(0);
  offlineQueueSize = $state(0);

  #pollInterval: ReturnType<typeof setInterval> | null = null;
  #reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  #pollMs: number = 30_000;
  #maxReconnectAttempts = 5;

  get isConnected(): boolean {
    return this.status === "connected" || this.status === "mock";
  }

  get isReady(): boolean {
    return this.status === "connected" || this.status === "mock";
  }

  async check(): Promise<void> {
    if (this.isChecking) return;
    this.isChecking = true;
    const prevStatus = this.status;
    try {
      const data = await health.get();
      this.health = data;
      if (isMockEnabled()) {
        if (this.status !== "mock") {
          console.log(`${LOG} Status: ${prevStatus} → mock`);
          this.status = "mock";
        }
      } else {
        if (this.status !== "connected") {
          console.log(`${LOG} Status: ${prevStatus} → connected`);
          this.lastConnectedAt = new Date();
          if (prevStatus === "reconnecting") {
            console.log(`${LOG} Reconnected after ${this.reconnectAttempts} attempts — syncing offline queue`);
            this.reconnectAttempts = 0;
            await this.#syncOnReconnect();
          }
        }
        this.status = "connected";
      }
      this.error = null;
    } catch (e) {
      if (isMockEnabled()) {
        if (this.status !== "mock") {
          console.log(`${LOG} Status: ${prevStatus} → mock (health check errored but mock active)`);
          this.status = "mock";
        }
        this.error = null;
      } else {
        this.health = null;
        if (prevStatus === "connected") {
          console.warn(`${LOG} Lost connection — starting reconnect cycle`);
          this.#startReconnecting();
        } else if (this.status !== "reconnecting") {
          console.warn(`${LOG} Status: ${prevStatus} → disconnected — ${(e as Error).message}`);
          this.status = "disconnected";
        }
        this.error = (e as Error).message;
      }
    } finally {
      this.isChecking = false;
      this.lastChecked = new Date();
    }
  }

  startPolling(intervalMs: number = this.#pollMs): () => void {
    this.#pollMs = intervalMs;
    console.log(`${LOG} Polling started (interval: ${intervalMs}ms)`);
    void this.check();
    this.#pollInterval = setInterval(() => void this.check(), intervalMs);
    return () => this.stopPolling();
  }

  stopPolling(): void {
    if (this.#pollInterval !== null) {
      console.log(`${LOG} Polling stopped`);
      clearInterval(this.#pollInterval);
      this.#pollInterval = null;
    }
    if (this.#reconnectTimer !== null) {
      clearTimeout(this.#reconnectTimer);
      this.#reconnectTimer = null;
    }
  }

  updateQueueSize(size: number): void {
    this.offlineQueueSize = size;
  }

  #startReconnecting(): void {
    if (this.status === "reconnecting") return;
    this.status = "reconnecting";
    this.reconnectAttempts = 0;
    console.warn(`${LOG} Reconnecting (max ${this.#maxReconnectAttempts} attempts)...`);
    void this.#attemptReconnect();
  }

  async #attemptReconnect(): Promise<void> {
    if (this.status !== "reconnecting") return;
    this.reconnectAttempts++;
    console.log(`${LOG} Reconnect attempt ${this.reconnectAttempts}/${this.#maxReconnectAttempts}`);
    try {
      const data = await health.get();
      this.health = data;
      this.status = "connected";
      this.error = null;
      this.lastChecked = new Date();
      this.lastConnectedAt = new Date();
      this.reconnectAttempts = 0;
      console.log(`${LOG} Reconnect successful — syncing`);
      await this.#syncOnReconnect();
      if (this.#pollInterval === null) this.startPolling(this.#pollMs);
      return;
    } catch {
      /* still offline */
    }
    if (this.reconnectAttempts >= this.#maxReconnectAttempts) {
      console.error(`${LOG} Max reconnection attempts (${this.#maxReconnectAttempts}) reached — giving up`);
      this.status = "disconnected";
      this.error = "Max reconnection attempts reached";
      return;
    }
    const delay = Math.min(2000 * 2 ** (this.reconnectAttempts - 1), 30_000);
    console.log(`${LOG} Next reconnect in ${delay}ms`);
    this.#reconnectTimer = setTimeout(
      () => void this.#attemptReconnect(),
      delay,
    );
  }

  async #syncOnReconnect(): Promise<void> {
    const { flushOfflineQueue, clearCache, disableMock } =
      await import("$api/client");
    await disableMock();
    clearCache();
    const result = await flushOfflineQueue();
    this.offlineQueueSize = 0;
    if (result.failed > 0) {
      console.warn(`${LOG} Offline sync: ${result.failed} requests failed`);
      this.error = `${result.failed} queued requests failed to sync`;
    } else {
      console.log(`${LOG} Offline sync complete: ${result.succeeded} synced`);
    }
  }
}

export const connectionStore = new ConnectionStore();
