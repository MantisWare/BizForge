// src/lib/stores/environment.svelte.ts
import { environment as envApi } from "$api/client";
import { isTauri } from "$lib/utils/platform";
import { toastStore } from "./toasts.svelte";

interface DetectedApp {
  id: string;
  name: string;
  process_name: string;
  status: "running" | "stopped";
  port: number | null;
  pid: number | null;
  category:
    | "development"
    | "database"
    | "automation"
    | "browser"
    | "design"
    | "communication"
    | "other";
  agent_access: string[];
}

interface AgentApp {
  id: string;
  name: string;
  agent_id: string;
  agent_name: string;
  template_source: string | null;
  status: "running" | "stopped" | "building" | "error";
  port: number | null;
  directory: string | null;
  created_at: string;
}

interface SystemResources {
  cpu_percent?: number;
  memory_used_gb?: number;
  memory_total_gb?: number;
  disk_free_gb?: number;
  disk_total_gb?: number;
  network_connections?: number;
}

interface Capability {
  id: string;
  name: string;
  available: boolean;
  details: string;
}

class EnvironmentStore {
  apps = $state<DetectedApp[]>([]);
  agentApps = $state<AgentApp[]>([]);
  resources = $state<SystemResources | null>(null);
  capabilities = $state<Capability[]>([]);
  loading = $state(false);
  error = $state<string | null>(null);

  // Derived
  runningApps = $derived(this.apps.filter((a) => a.status === "running"));
  runningCount = $derived(this.runningApps.length);
  agentAppCount = $derived(this.agentApps.length);

  async fetchAll(): Promise<void> {
    this.loading = true;
    this.error = null;
    try {
      await Promise.all([
        this.fetchApps(),
        this.fetchAgentApps(),
        this.fetchResources(),
        this.fetchCapabilities(),
      ]);
    } catch (e) {
      const msg = (e as Error).message;
      this.error = msg;
      if (!msg.includes("not_found") && !msg.includes("unauthorized")) {
        toastStore.error("Failed to load environment", msg);
      }
    } finally {
      this.loading = false;
    }
  }

  async fetchApps(): Promise<void> {
    try {
      this.apps = (await envApi.apps()) as DetectedApp[];
      this.error = null;
    } catch (e) {
      const msg = (e as Error).message;
      this.error = msg;
      if (!msg.includes("not_found") && !msg.includes("unauthorized")) {
        toastStore.error("Failed to load detected apps", msg);
      }
    }
  }

  async fetchAgentApps(): Promise<void> {
    try {
      this.agentApps = (await envApi.agentApps()) as AgentApp[];
      this.error = null;
    } catch (e) {
      const msg = (e as Error).message;
      this.error = msg;
      if (!msg.includes("not_found") && !msg.includes("unauthorized")) {
        toastStore.error("Failed to load agent apps", msg);
      }
    }
  }

  async fetchResources(): Promise<void> {
    // Prefer real OS metrics from Tauri IPC when running as a desktop app
    if (isTauri()) {
      try {
        const { invoke } = await import("@tauri-apps/api/core");
        const info = await invoke<{
          cpu_usage_pct: number;
          memory_used_gb: number;
          memory_total_gb: number;
          memory_free_gb: number;
          disk_total_gb: number;
          disk_free_gb: number;
        }>("get_system_resources");

        this.resources = {
          cpu_percent: info.cpu_usage_pct,
          memory_used_gb: info.memory_used_gb,
          memory_total_gb: info.memory_total_gb,
          disk_free_gb: info.disk_free_gb,
          disk_total_gb: info.disk_total_gb,
          network_connections: 0,
        };
        this.error = null;
        return;
      } catch {
        // Fall through to HTTP API
      }
    }

    try {
      const data = await envApi.resources();
      if (data !== null && data !== undefined && typeof data === "object") {
        this.resources = data as SystemResources;
      } else {
        this.resources = null;
      }
      this.error = null;
    } catch (e) {
      const msg = (e as Error).message;
      this.error = msg;
      if (!msg.includes("not_found") && !msg.includes("unauthorized")) {
        toastStore.error("Failed to load system resources", msg);
      }
    }
  }

  async fetchCapabilities(): Promise<void> {
    try {
      this.capabilities = (await envApi.capabilities()) as Capability[];
      this.error = null;
    } catch (e) {
      const msg = (e as Error).message;
      this.error = msg;
      if (!msg.includes("not_found") && !msg.includes("unauthorized")) {
        toastStore.error("Failed to load capabilities", msg);
      }
    }
  }

  async grantAccess(appId: string, agentId: string): Promise<void> {
    try {
      await envApi.grantAccess(appId, agentId);
      // Optimistic local update
      this.apps = this.apps.map((app) =>
        app.id === appId && !app.agent_access.includes(agentId)
          ? { ...app, agent_access: [...app.agent_access, agentId] }
          : app,
      );
      this.error = null;
      toastStore.success("Access granted");
    } catch (e) {
      const msg = (e as Error).message;
      this.error = msg;
      toastStore.error("Failed to grant access", msg);
    }
  }

  async revokeAccess(appId: string, agentId: string): Promise<void> {
    try {
      await envApi.revokeAccess(appId, agentId);
      // Optimistic local update
      this.apps = this.apps.map((app) =>
        app.id === appId
          ? {
              ...app,
              agent_access: app.agent_access.filter((id) => id !== agentId),
            }
          : app,
      );
      this.error = null;
      toastStore.success("Access revoked");
    } catch (e) {
      const msg = (e as Error).message;
      this.error = msg;
      toastStore.error("Failed to revoke access", msg);
    }
  }
}

export const environmentStore = new EnvironmentStore();
