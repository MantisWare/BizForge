// src/lib/stores/settings.svelte.ts
import type { Settings, AdapterType } from "$api/types";
import { settings as settingsApi } from "$api/client";

const LOCAL_STORAGE_KEY = "bizforge-settings-local";

// Keys the backend ConfigController accepts via PATCH /config
const SERVER_KEYS: ReadonlyArray<keyof Settings> = [
  "default_model",
  "default_provider_id",
  "max_concurrent_agents",
  "session_timeout_minutes",
  "log_level",
  "telemetry_enabled",
  "budget_enforcement",
  "activity_retention_days",
] as const;

// Keys stored only on the client (localStorage / Tauri store)
const CLIENT_KEYS: ReadonlyArray<keyof Settings> = [
  "theme",
  "font_size",
  "sidebar_default_collapsed",
  "notifications_enabled",
  "auto_approve_budget_under_cents",
  "default_adapter",
  "working_directory",
] as const;

function loadLocalSettings(): Partial<Settings> {
  if (typeof localStorage === "undefined") return {};
  try {
    const raw = localStorage.getItem(LOCAL_STORAGE_KEY);
    if (raw === null) return {};
    return JSON.parse(raw) as Partial<Settings>;
  } catch {
    return {};
  }
}

function saveLocalSettings(data: Settings): void {
  if (typeof localStorage === "undefined") return;
  const local: Record<string, unknown> = {};
  for (const key of CLIENT_KEYS) {
    local[key] = data[key];
  }
  localStorage.setItem(LOCAL_STORAGE_KEY, JSON.stringify(local));
}

class SettingsStore {
  data = $state<Settings>({
    theme: "dark",
    font_size: 14,
    sidebar_default_collapsed: false,
    notifications_enabled: true,
    auto_approve_budget_under_cents: 500,
    default_adapter:
      (typeof localStorage !== "undefined"
        ? (localStorage.getItem("bizforge-default-adapter") as AdapterType)
        : null) ?? ("osa" as AdapterType),
    default_model: "claude-sonnet-4-6",
    default_provider_id: "",
    working_directory: "",
    max_concurrent_agents: 10,
    session_timeout_minutes: 60,
    log_level: "info",
    telemetry_enabled: true,
    activity_retention_days: 30,
    budget_enforcement: true,
    ...loadLocalSettings(),
  });
  miosaCloud = $state(false);
  loading = $state(false);
  error = $state<string | null>(null);
  dirty = $state(false);

  async fetch(): Promise<void> {
    this.loading = true;
    try {
      const serverData = await settingsApi.get();
      const localData = loadLocalSettings();
      this.data = { ...this.data, ...serverData, ...localData };
      this.dirty = false;
    } catch (e) {
      this.error = (e as Error).message;
    } finally {
      this.loading = false;
    }
  }

  async save(): Promise<void> {
    this.loading = true;
    this.error = null;
    try {
      saveLocalSettings(this.data);

      const serverPayload: Record<string, unknown> = {};
      for (const key of SERVER_KEYS) {
        serverPayload[key] = this.data[key];
      }
      await settingsApi.update(serverPayload as Partial<Settings>);

      await this.persistToTauriStore();

      this.dirty = false;
    } catch (e) {
      this.error = (e as Error).message;
    } finally {
      this.loading = false;
    }
  }

  update<K extends keyof Settings>(key: K, value: Settings[K]): void {
    this.data = { ...this.data, [key]: value };
    this.dirty = true;
  }

  /** Load adapter and miosaCloud settings from Tauri secure store.
   *  Must be called after the app shell mounts in Tauri context.
   */
  async loadFromTauriStore(): Promise<void> {
    try {
      const { isTauri } = await import("$lib/utils/platform");
      if (!isTauri()) return;
      const { Store } = await import("@tauri-apps/plugin-store");
      const store = await Store.load("settings.json");
      const adapter = await store.get<string>("default_adapter");
      if (adapter !== null && adapter !== undefined)
        this.data = { ...this.data, default_adapter: adapter as AdapterType };
      const cloud = await store.get<boolean>("miosa_cloud");
      if (cloud !== null && cloud !== undefined) {
        this.miosaCloud = cloud;
      }
      const localJson = await store.get<string>("local_settings");
      if (localJson !== null && localJson !== undefined) {
        try {
          const parsed = JSON.parse(localJson) as Partial<Settings>;
          this.data = { ...this.data, ...parsed };
        } catch {
          // Corrupt stored data — ignore
        }
      }
    } catch {
      // Not in Tauri or store unavailable — silently ignore
    }
  }

  private async persistToTauriStore(): Promise<void> {
    try {
      const { isTauri } = await import("$lib/utils/platform");
      if (!isTauri()) return;
      const { Store } = await import("@tauri-apps/plugin-store");
      const store = await Store.load("settings.json");
      await store.set("default_adapter", this.data.default_adapter);
      const local: Record<string, unknown> = {};
      for (const key of CLIENT_KEYS) {
        local[key] = this.data[key];
      }
      await store.set("local_settings", JSON.stringify(local));
      await store.save();
    } catch {
      // Not in Tauri — localStorage is the fallback
    }
  }
}

export const settingsStore = new SettingsStore();
