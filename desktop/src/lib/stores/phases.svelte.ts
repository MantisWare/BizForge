// src/lib/stores/phases.svelte.ts
import type { Phase, PhaseTreeNode, PhaseStatus, PhasePriority } from "$api/types";
import { phases as phasesApi } from "$api/client";
import { toastStore } from "./toasts.svelte";

class PhasesStore {
  phases = $state<PhaseTreeNode[]>([]);
  selected = $state<PhaseTreeNode | null>(null);
  loading = $state(false);
  error = $state<string | null>(null);

  // Active project context
  activeProjectId = $state<string | null>(null);

  // Filters
  filterStatus = $state<PhaseStatus | "all">("all");
  filterPriority = $state<PhasePriority | "all">("all");
  searchQuery = $state("");

  // Derived: flat list from tree
  flatPhases = $derived.by(() => {
    const flatten = (nodes: PhaseTreeNode[]): PhaseTreeNode[] =>
      nodes.flatMap((n) => [n, ...flatten(n.children)]);
    return flatten(this.phases);
  });

  // Derived: filtered flat list
  filteredPhases = $derived.by(() => {
    let result = this.flatPhases;
    if (this.filterStatus !== "all") {
      result = result.filter((p) => p.status === this.filterStatus);
    }
    if (this.filterPriority !== "all") {
      result = result.filter((p) => p.priority === this.filterPriority);
    }
    if (this.searchQuery) {
      const q = this.searchQuery.toLowerCase();
      result = result.filter(
        (p) =>
          p.title.toLowerCase().includes(q) ||
          (p.description ?? "").toLowerCase().includes(q),
      );
    }
    return result;
  });

  // Derived: aggregate progress across all root phases
  overallProgress = $derived.by(() => {
    const roots = this.phases;
    if (roots.length === 0) return 0;
    const total = roots.reduce((sum, p) => sum + p.progress, 0);
    return Math.round(total / roots.length);
  });

  completedCount = $derived(
    this.flatPhases.filter((p) => p.status === "completed").length,
  );
  totalCount = $derived(this.flatPhases.length);

  async fetchPhases(projectId: string): Promise<void> {
    this.loading = true;
    this.activeProjectId = projectId;
    try {
      this.phases = await phasesApi.list(projectId);
      // Refresh selected from the new tree so stale references don't keep
      // the PhaseDetail backdrop rendered and blocking the page.
      if (this.selected) {
        const flat = (nodes: PhaseTreeNode[]): PhaseTreeNode[] =>
          nodes.flatMap((n) => [n, ...flat(n.children)]);
        const refreshed = flat(this.phases).find(
          (p) => p.id === this.selected!.id,
        );
        this.selected = refreshed ?? null;
      }
      this.error = null;
    } catch (e) {
      const msg = (e as Error).message;
      this.error = msg;
      if (!msg.includes("not_found") && !msg.includes("unauthorized") && !msg.includes("rate_limited")) {
        toastStore.error("Failed to load phases", msg);
      } else if (msg.includes("rate_limited")) {
        toastStore.warning("Phases loading slowly", "Server is busy — retrying automatically.");
      }
    } finally {
      this.loading = false;
    }
  }

  async createPhase(data: Partial<Phase>): Promise<Phase | null> {
    if (!this.activeProjectId) {
      toastStore.error(
        "No active project",
        "Select a project before creating phases.",
      );
      return null;
    }
    try {
      // Inject workspace_id from the workspace store
      const { workspaceStore } = await import("./workspace.svelte");
      const enriched = {
        ...data,
        workspace_id: workspaceStore.activeWorkspaceId ?? undefined,
      };
      const created = await phasesApi.create(this.activeProjectId, enriched);
      // Re-fetch the full tree to get correct children/task_count.
      // fetchPhases manages loading state, so we don't duplicate it here.
      await this.fetchPhases(this.activeProjectId);
      this.error = null;
      toastStore.success("Phase created", created.title);
      return created;
    } catch (e) {
      const msg = (e as Error).message;
      this.error = msg;
      toastStore.error("Failed to create phase", msg);
      return null;
    }
  }

  async updatePhase(id: string, data: Partial<Phase>): Promise<Phase | null> {
    if (!this.activeProjectId) {
      toastStore.error("No active project");
      return null;
    }
    // Optimistic update on flat data embedded in tree nodes
    const applyUpdate = (nodes: PhaseTreeNode[]): PhaseTreeNode[] =>
      nodes.map((n) =>
        n.id === id
          ? { ...n, ...data, children: applyUpdate(n.children) }
          : { ...n, children: applyUpdate(n.children) },
      );
    const previousPhases = this.phases;
    this.phases = applyUpdate(this.phases);
    if (this.selected?.id === id) {
      this.selected = { ...this.selected, ...data };
    }
    try {
      const updated = await phasesApi.update(this.activeProjectId, id, data);
      // Re-fetch to sync computed fields (progress, task_count, children)
      await this.fetchPhases(this.activeProjectId);
      if (this.selected?.id === id) {
        const refreshed = this.flatPhases.find((p) => p.id === id);
        this.selected = refreshed ?? null;
      }
      this.error = null;
      return updated;
    } catch (e) {
      this.phases = previousPhases;
      if (this.selected?.id === id) {
        const prev = previousPhases
          .flatMap((n) => [n, ...n.children])
          .find((p) => p.id === id);
        this.selected = prev ?? this.selected;
      }
      const msg = (e as Error).message;
      this.error = msg;
      toastStore.error("Failed to update phase", msg);
      return null;
    }
  }

  async decompose(
    phaseId: string,
    opts?: { max_tasks?: number; auto_assign?: boolean },
  ): Promise<boolean> {
    try {
      const result = await phasesApi.decompose(phaseId, opts);
      toastStore.success(
        "Decomposition started",
        result.message || "Tasks will appear when the AI finishes processing.",
      );
      // Poll for new tasks after a delay (the backend runs async)
      setTimeout(() => {
        if (this.activeProjectId) {
          void this.fetchPhases(this.activeProjectId);
        }
      }, 5000);
      return true;
    } catch (e) {
      const msg = (e as Error).message;
      toastStore.error("Failed to decompose phase", msg);
      return false;
    }
  }

  selectPhase(phase: PhaseTreeNode | null): void {
    this.selected = phase;
  }

  async deletePhase(id: string): Promise<void> {
    if (!this.activeProjectId) {
      toastStore.error("No active project");
      return;
    }
    // Optimistic removal from tree
    const removeFromTree = (nodes: PhaseTreeNode[]): PhaseTreeNode[] =>
      nodes
        .filter((n) => n.id !== id)
        .map((n) => ({ ...n, children: removeFromTree(n.children) }));
    const previousPhases = this.phases;
    const previousSelected = this.selected;
    this.phases = removeFromTree(this.phases);
    if (this.selected?.id === id) {
      this.selected = null;
    }
    try {
      await phasesApi.delete(id);
      this.error = null;
      toastStore.success("Phase deleted");
    } catch (e) {
      this.phases = previousPhases;
      this.selected = previousSelected;
      const msg = (e as Error).message;
      this.error = msg;
      toastStore.error("Failed to delete phase", msg);
    }
  }

  setActiveProject(projectId: string): void {
    this.activeProjectId = projectId;
    this.phases = [];
    this.selected = null;
  }
}

export const phasesStore = new PhasesStore();
