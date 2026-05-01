// src/lib/stores/mcp.svelte.ts

export interface McpStatus {
  ready: boolean;
  server_path: string;
  server_exists: boolean;
}

export interface McpClientConfig {
  mcpServers: {
    bizforge: {
      command: string;
      args: string[];
      env: Record<string, string>;
    };
  };
}

function isTauriEnv(): boolean {
  return typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
}

class McpStore {
  status = $state<McpStatus>({
    ready: false,
    server_path: "",
    server_exists: false,
  });
  clientConfig = $state<McpClientConfig | null>(null);
  loading = $state(false);
  error = $state<string | null>(null);
  building = $state(false);

  get isReady(): boolean {
    return this.status.ready;
  }

  async fetchStatus(): Promise<void> {
    if (!isTauriEnv()) return;
    try {
      const { invoke } = await import("@tauri-apps/api/core");
      const result = await invoke<McpStatus>("mcp_status");
      this.status = result;
      this.error = null;
    } catch (e) {
      this.error = (e as Error).message ?? String(e);
    }
  }

  async fetchClientConfig(): Promise<void> {
    if (!isTauriEnv()) return;
    try {
      const { invoke } = await import("@tauri-apps/api/core");
      const result = await invoke<McpClientConfig>("mcp_client_config");
      this.clientConfig = result;
    } catch (e) {
      this.error = (e as Error).message ?? String(e);
    }
  }

  async build(): Promise<void> {
    if (!isTauriEnv()) return;
    this.building = true;
    this.error = null;
    try {
      const { invoke } = await import("@tauri-apps/api/core");
      const result = await invoke<McpStatus>("mcp_build");
      this.status = result;
    } catch (e) {
      this.error = (e as Error).message ?? String(e);
    } finally {
      this.building = false;
    }
  }
}

export const mcpStore = new McpStore();
