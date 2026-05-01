// src/lib/stores/workspace.svelte.ts
import { browser } from "$app/environment";
import { isTauri } from "$lib/utils/platform";
import type { Workspace as BackendWorkspace } from "$api/types";
import { toastStore } from "./toasts.svelte";
import { workspaces as workspacesApi, isMockEnabled } from "$api/client";
import type { BizforgeWorkspace, WorkspaceHealthReport, RepairResult } from "$lib/types/bizforge";

/**
 * Extract the `description` field from YAML frontmatter in a markdown file.
 * Returns undefined if the file has no frontmatter or no description key.
 */
function parseSystemMdDescription(content: string): string | undefined {
  const trimmed = content.trim();
  if (!trimmed.startsWith("---")) return undefined;
  const afterFirst = trimmed.slice(3);
  const end = afterFirst.indexOf("---");
  if (end === -1) return undefined;
  const yaml = afterFirst.slice(0, end);
  const match = yaml.match(/^description:\s*(.+)$/m);
  return match?.[1]?.trim() || undefined;
}

/** Resolve ~ to actual home directory path */
async function resolveHomePath(p: string): Promise<string> {
  if (!p.startsWith("~")) return p;
  if (isTauri()) {
    try {
      const { homeDir } = await import("@tauri-apps/api/path");
      const home = await homeDir();
      return p.replace("~", home.replace(/\/$/, ""));
    } catch {
      // fallback
    }
  }
  return p;
}

export interface LocalWorkspace {
  id: string;
  path: string;
  name: string;
  description?: string;
  addedAt: string;
}

/** Tauri IPC scan result — structurally identical to BizforgeWorkspace. */
type BizforgeWorkspaceScan = BizforgeWorkspace;

const STORAGE_KEY = "bizforge-workspaces";
const ACTIVE_KEY = "bizforge-active-workspace";

class WorkspaceStore {
  workspaces = $state<LocalWorkspace[]>([]);
  activeWorkspaceId = $state<string | null>(null);
  isLoading = $state(false);
  error = $state<string | null>(null);
  lastScan = $state<BizforgeWorkspaceScan | null>(null);
  healthReport = $state<WorkspaceHealthReport | null>(null);

  get activeWorkspace(): LocalWorkspace | null {
    return (
      this.workspaces.find((w) => w.id === this.activeWorkspaceId) ??
      this.workspaces[0] ??
      null
    );
  }

  /** Hydrate from localStorage */
  fetchWorkspaces(): void {
    if (!browser) return;
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (raw) this.workspaces = JSON.parse(raw) as LocalWorkspace[];
      const activeId = localStorage.getItem(ACTIVE_KEY);
      if (activeId && this.workspaces.some((w) => w.id === activeId)) {
        this.activeWorkspaceId = activeId;
      } else if (this.workspaces.length > 0) {
        this.activeWorkspaceId = this.workspaces[0].id;
      }
      console.log(`[bizforge:workspace] Loaded ${this.workspaces.length} workspace(s) from localStorage, active: ${this.activeWorkspaceId ?? "none"}`);
    } catch {
      console.warn("[bizforge:workspace] Could not parse stored workspaces — starting fresh");
    }
  }

  /** Persist to localStorage */
  #persist(): void {
    if (!browser) return;
    localStorage.setItem(STORAGE_KEY, JSON.stringify(this.workspaces));
    if (this.activeWorkspaceId) {
      localStorage.setItem(ACTIVE_KEY, this.activeWorkspaceId);
    }
  }

  /** Scan a directory via Tauri IPC — auto-repairs (creates) .bizforge/ if missing */
  async scanWorkspace(path: string): Promise<BizforgeWorkspaceScan | null> {
    if (!isTauri()) return null;
    console.log(`[bizforge:workspace] Scanning ${path}...`);
    try {
      const { invoke } = await import("@tauri-apps/api/core");
      const bizforgePath = path.endsWith(".bizforge") ? path : path + "/.bizforge";
      const result = await invoke<BizforgeWorkspaceScan>("scan_bizforge_dir", {
        path: bizforgePath,
      });
      this.lastScan = result;
      console.log(`[bizforge:workspace] Scan OK: ${result.agents.length} agents, ${result.projects.length} projects, ${result.skills.length} skills`);
      return result;
    } catch (e) {
      console.warn(`[bizforge:workspace] Scan failed for ${path}:`, e);

      // Auto-repair: create the .bizforge directory structure and retry
      console.log(`[bizforge:workspace] Attempting auto-repair for ${path}...`);
      try {
        const repairResult = await this.repairWorkspace(path);
        if (repairResult !== null && repairResult.repaired.length > 0) {
          console.log(`[bizforge:workspace] Auto-repair succeeded (${repairResult.repaired.length} fixes), retrying scan...`);
          toastStore.success(
            "Workspace created",
            `.bizforge directory initialized at ${path}`,
          );
          const { invoke } = await import("@tauri-apps/api/core");
          const bizforgePath = path.endsWith(".bizforge") ? path : path + "/.bizforge";
          const result = await invoke<BizforgeWorkspaceScan>("scan_bizforge_dir", {
            path: bizforgePath,
          });
          this.lastScan = result;
          return result;
        }
      } catch (repairErr) {
        console.warn(`[bizforge:workspace] Auto-repair also failed:`, repairErr);
      }

      toastStore.warning(
        "Workspace scan failed",
        `Could not initialize .bizforge directory at ${path}`,
      );
      return null;
    }
  }

  /** Add a workspace entry — no-ops on duplicate path */
  addWorkspace(ws: LocalWorkspace): void {
    if (this.workspaces.some((w) => w.path === ws.path)) return;
    console.log(`[bizforge:workspace] Added workspace "${ws.name}" at ${ws.path}`);
    this.workspaces = [...this.workspaces, ws];
    this.#persist();
  }

  /** Set active workspace — page $effects are the single source of data refresh */
  async setActiveWorkspace(id: string): Promise<void> {
    const ws = this.workspaces.find((w) => w.id === id);
    console.log(`[bizforge:workspace] Switching active workspace → "${ws?.name ?? id}" (${id})`);
    this.activeWorkspaceId = id;
    this.#persist();

    // 1. Tell the backend which workspace is now active so it scopes
    //    subsequent queries (agents, sessions, issues, etc.) correctly.
    try {
      const { workspaces: workspacesApi } = await import("$api/client");
      await workspacesApi.activate(id);
    } catch {
      // Non-fatal: backend may be unavailable or workspace may not exist there
    }

    // 2. Bust the response cache so stale data for the previous workspace is
    //    not served to the new workspace's API calls.
    const { clearCache } = await import("$api/client");
    clearCache();

    // 3. Try Tauri filesystem scan first (desktop app only).
    //    NOTE: Store fetches are intentionally omitted here. Each page component
    //    has a $effect watching activeWorkspaceId that triggers the appropriate
    //    fetch. Calling fetches here as well would cause a double-fetch on every
    //    workspace switch.
    if (ws) {
      await this.scanAndLoadAgents(ws.path);
    }
  }

  /** Scan workspace and load agents, skills, and context files into stores */
  async scanAndLoadAgents(path: string): Promise<void> {
    const scan = await this.scanWorkspace(path);
    if (!scan) return;

    // Update the active workspace's name/description from SYSTEM.md frontmatter
    if (scan.name || scan.system_md) {
      const ws = this.workspaces.find(
        (w) => w.path === path || path.startsWith(w.path),
      );
      if (ws) {
        const descFromSystem = scan.system_md
          ? parseSystemMdDescription(scan.system_md)
          : undefined;
        const nameChanged = scan.name && ws.name !== scan.name;
        const descChanged = descFromSystem && ws.description !== descFromSystem;
        if (nameChanged || descChanged) {
          this.workspaces = this.workspaces.map((w) =>
            w.path === ws.path
              ? {
                  ...w,
                  name: scan.name || w.name,
                  description: descFromSystem ?? w.description,
                }
              : w,
          );
          this.#persist();
        }
      }
    }

    // Run health check after scan so report is always current
    await this.checkHealth(path);

    if (scan.agents.length === 0) return;

    // Dynamic import to avoid circular deps
    const { bizforgeDefToAgent } = await import("$lib/utils/agents");
    const { agentsStore } = await import("./agents.svelte");

    const agents = scan.agents.map(bizforgeDefToAgent);
    // Merge scanned agents with existing, deduplicating by ID (API record wins)
    agentsStore.agents = [
      ...new Map(
        [...agents, ...agentsStore.agents].map((a) => [a.id, a]),
      ).values(),
    ];
  }

  /** Check workspace health via Tauri IPC — validates .bizforge/ structure and content */
  async checkHealth(path?: string): Promise<WorkspaceHealthReport | null> {
    const ws = this.activeWorkspace;
    const targetPath = path ?? ws?.path;
    if (!targetPath || !isTauri()) return null;

    try {
      const { invoke } = await import("@tauri-apps/api/core");
      const report = await invoke<WorkspaceHealthReport>("check_workspace_health", {
        path: targetPath,
      });
      this.healthReport = report;

      if (!report.healthy) {
        const errorCount = report.issues.filter((i) => i.severity === "error").length;
        const warnCount = report.issues.filter((i) => i.severity === "warning").length;
        const parts: string[] = [];
        if (errorCount > 0) parts.push(`${errorCount} error${errorCount > 1 ? "s" : ""}`);
        if (warnCount > 0) parts.push(`${warnCount} warning${warnCount > 1 ? "s" : ""}`);
        console.warn(`[bizforge:workspace] Health check: ${parts.join(", ")}`);
      } else {
        console.log("[bizforge:workspace] Health check: OK");
      }

      return report;
    } catch (e) {
      console.warn("[bizforge:workspace] Health check failed:", e);
      return null;
    }
  }

  /** Repair workspace issues via Tauri IPC — fixes missing dirs/files */
  async repairWorkspace(path?: string): Promise<RepairResult | null> {
    const ws = this.activeWorkspace;
    const targetPath = path ?? ws?.path;
    if (!targetPath || !isTauri()) return null;

    try {
      const { invoke } = await import("@tauri-apps/api/core");
      const result = await invoke<RepairResult>("repair_workspace", {
        path: targetPath,
      });
      this.healthReport = result.health_after;

      if (result.repaired.length > 0) {
        toastStore.success(
          "Workspace repaired",
          `Fixed ${result.repaired.length} issue${result.repaired.length > 1 ? "s" : ""}`,
        );
      }
      if (result.failed.length > 0) {
        toastStore.warning(
          "Some repairs failed",
          result.failed.join("; "),
        );
      }

      // Re-scan agents after repair
      if (result.repaired.length > 0) {
        await this.scanAndLoadAgents(targetPath);
      }

      return result;
    } catch (e) {
      toastStore.error("Repair failed", String(e));
      return null;
    }
  }

  /** Watch active workspace for file changes via Tauri IPC */
  async watchActive(): Promise<void> {
    const ws = this.activeWorkspace;
    if (!ws || !isTauri()) return;

    try {
      const { invoke } = await import("@tauri-apps/api/core");
      const { listen } = await import("@tauri-apps/api/event");

      const bizforgePath = ws.path.endsWith(".bizforge")
        ? ws.path
        : ws.path + "/.bizforge";
      await invoke("watch_bizforge_dir", { path: bizforgePath });

      listen("bizforge-fs-event", async () => {
        const active = this.activeWorkspace;
        if (active) {
          await this.scanAndLoadAgents(active.path);
        }
      });
    } catch {
      // File watcher unavailable — workspace changes will not be auto-detected
    }
  }

  /** Remove a workspace */
  async removeWorkspace(id: string): Promise<void> {
    // Clean up deployed agents for this workspace
    try {
      const { clearMockWorkspaceAgents } = await import("$api/mock/agents");
      clearMockWorkspaceAgents(id);
    } catch {
      // Mock module may not be available
    }

    this.workspaces = this.workspaces.filter((w) => w.id !== id);
    if (this.activeWorkspaceId === id) {
      this.activeWorkspaceId = this.workspaces[0]?.id ?? null;
    }
    this.#persist();
    // Page $effects watching activeWorkspaceId handle data refresh.
  }

  /** Sync workspaces from the backend and set the active one */
  async syncFromBackend(): Promise<void> {
    try {
      const { workspaces: workspacesApi, clearMockData } =
        await import("$api/client");
      const backendWorkspaces: BackendWorkspace[] = await workspacesApi.list();
      if (!backendWorkspaces || backendWorkspaces.length === 0) return;

      // Backend responded with real workspace data — purge any mock agents or
      // other mock state that may have been persisted to localStorage during a
      // prior offline session. This must happen before any agents store fetch
      // so that stale mock agents cannot be merged with real backend agents.
      await clearMockData();

      // Prefer the first "active" workspace, fall back to the first in the list
      const activeBackendWs =
        backendWorkspaces.find((w) => w.status === "active") ??
        backendWorkspaces[0];

      // Register any backend workspaces not yet in local store
      for (const bws of backendWorkspaces) {
        if (!this.workspaces.some((w) => w.id === bws.id)) {
          const localWs: LocalWorkspace = {
            id: bws.id,
            name: bws.name,
            path:
              bws.path ??
              bws.directory ??
              `~/.bizforge/${bws.name.toLowerCase().replace(/\s+/g, "-")}`,
            addedAt: bws.created_at ?? new Date().toISOString(),
          };
          this.workspaces = [...this.workspaces, localWs];
        }
      }
      this.#persist();

      // Point the active workspace at the backend's active one.
      // If this differs from what we had locally, bust the cache so that
      // subsequent data fetches (agents, dashboard, etc.) reflect the correct
      // workspace — not stale data from a previously active workspace.
      if (this.activeWorkspaceId !== activeBackendWs.id) {
        const { clearCache } = await import("$api/client");
        clearCache();
      }
      this.activeWorkspaceId = activeBackendWs.id;
      this.#persist();
    } catch {
      // Backend not available — keep existing local workspaces
    }
  }

  /** Create workspace — scaffolds .bizforge/ on disk and registers with backend */
  async createWorkspace(
    name: string,
    directory?: string,
  ): Promise<LocalWorkspace | null> {
    const rawPath =
      directory ?? `~/.bizforge/${name.toLowerCase().replace(/\s+/g, "-")}`;
    const resolvedPath = await resolveHomePath(rawPath);

    // Scaffold the .bizforge directory structure on disk (Tauri only)
    if (isTauri()) {
      try {
        const { invoke } = await import("@tauri-apps/api/core");
        await invoke("scaffold_bizforge_dir", {
          path: resolvedPath,
          name,
          description: `Workspace: ${name}`,
          agents: [],
        });
        console.log(`[bizforge:workspace] Scaffolded .bizforge/ at ${resolvedPath}`);
      } catch (e) {
        console.warn(`[bizforge:workspace] Scaffold failed for ${resolvedPath}:`, e);
      }
    }

    let backendId: string | null = null;

    // Create workspace in backend so agents can reference it
    if (!isMockEnabled()) {
      try {
        const created = await workspacesApi.create({
          name,
          directory: resolvedPath,
        });
        backendId =
          (created as any).workspace?.id ?? (created as any).id ?? null;
      } catch {
        // Backend create failed — fall back to local-only
      }
    }

    const ws: LocalWorkspace = {
      id: backendId ?? crypto.randomUUID(),
      path: resolvedPath,
      name,
      addedAt: new Date().toISOString(),
    };
    this.addWorkspace(ws);
    this.activeWorkspaceId = ws.id;
    this.#persist();
    return ws;
  }
}

export const workspaceStore = new WorkspaceStore();
