// src/lib/stores/tasks.svelte.ts
import type { Task, TaskStatus, TaskPriority } from "$api/types";
import { tasks as tasksApi } from "$api/client";
import { isTauri } from "$lib/utils/platform";
import { toastStore } from "./toasts.svelte";
import { agentsStore } from "./agents.svelte";

export function resolveAssigneeName(task: Task): string {
  if (task.assignee_name) return task.assignee_name;
  if (task.assignee_id) {
    const agent = agentsStore.agents.find((a) => a.id === task.assignee_id);
    return agent?.display_name ?? agent?.name ?? "Unknown Agent";
  }
  return "Unassigned";
}

type SortField = "created_at" | "updated_at" | "priority" | "title";
type SortDirection = "asc" | "desc";

const PRIORITY_ORDER: Record<TaskPriority, number> = {
  critical: 0,
  high: 1,
  medium: 2,
  low: 3,
};

class TasksStore {
  tasks = $state<Task[]>([]);
  selected = $state<Task | null>(null);
  loading = $state(false);
  error = $state<string | null>(null);

  // Filters
  filterStatus = $state<TaskStatus | "all">("all");
  filterPriority = $state<TaskPriority | "all">("all");
  filterAssignee = $state<string | "all">("all");
  searchQuery = $state("");

  // Sort
  sortField = $state<SortField>("created_at");
  sortDirection = $state<SortDirection>("desc");

  // Derived: filtered + sorted list
  filteredTasks = $derived.by(() => {
    let result = this.tasks;

    if (this.filterStatus !== "all") {
      result = result.filter((t) => t.status === this.filterStatus);
    }
    if (this.filterPriority !== "all") {
      result = result.filter((t) => t.priority === this.filterPriority);
    }
    if (this.filterAssignee !== "all") {
      result = result.filter((t) => t.assignee_id === this.filterAssignee);
    }
    if (this.searchQuery) {
      const q = this.searchQuery.toLowerCase();
      result = result.filter(
        (t) =>
          t.title.toLowerCase().includes(q) ||
          (t.description ?? "").toLowerCase().includes(q),
      );
    }

    const field = this.sortField;
    const dir = this.sortDirection;

    return [...result].sort((a, b) => {
      let cmp = 0;
      if (field === "priority") {
        cmp = PRIORITY_ORDER[a.priority] - PRIORITY_ORDER[b.priority];
      } else if (field === "title") {
        cmp = a.title.localeCompare(b.title);
      } else {
        cmp = new Date(a[field]).getTime() - new Date(b[field]).getTime();
      }
      return dir === "asc" ? cmp : -cmp;
    });
  });

  // Derived: kanban columns grouped by status
  kanbanColumns = $derived.by(() => {
    const statuses: TaskStatus[] = [
      "backlog",
      "todo",
      "in_progress",
      "in_review",
      "done",
    ];
    return statuses.map((status) => ({
      status,
      tasks: this.filteredTasks.filter((t) => t.status === status),
    }));
  });

  openCount = $derived(this.tasks.filter((t) => t.status !== "done").length);

  async fetchTasks(workspaceId?: string): Promise<void> {
    this.loading = true;
    try {
      this.tasks = await tasksApi.list(workspaceId);
      // Refresh selected from the new array so stale references don't keep
      // detail panels rendered after the underlying data changes.
      if (this.selected) {
        const refreshed = this.tasks.find((t) => t.id === this.selected!.id);
        this.selected = refreshed ?? null;
      }
      this.error = null;
    } catch (e) {
      const msg = (e as Error).message;
      this.error = msg;
      if (!msg.includes("not_found") && !msg.includes("unauthorized")) {
        toastStore.error("Failed to load tasks", msg);
      }
    } finally {
      this.loading = false;
    }
  }

  async createTask(data: Partial<Task>): Promise<Task | null> {
    this.loading = true;
    try {
      const created = await tasksApi.create(data);
      this.tasks = [created, ...this.tasks];
      this.error = null;
      toastStore.success("Task created", created.title);
      return created;
    } catch (e) {
      const msg = (e as Error).message;
      this.error = msg;
      toastStore.error("Failed to create task", msg);
      return null;
    } finally {
      this.loading = false;
    }
  }

  async updateTask(id: string, data: Partial<Task>): Promise<Task | null> {
    const previous = this.tasks;
    // Optimistic update
    this.tasks = this.tasks.map((t) => (t.id === id ? { ...t, ...data } : t));
    if (this.selected?.id === id) {
      this.selected = { ...this.selected, ...data };
    }
    try {
      const updated = await tasksApi.update(id, data);
      this.tasks = this.tasks.map((t) => (t.id === id ? updated : t));
      if (this.selected?.id === id) {
        this.selected = updated;
      }
      this.error = null;
      return updated;
    } catch (e) {
      this.tasks = previous;
      if (this.selected?.id === id) {
        this.selected = previous.find((t) => t.id === id) ?? this.selected;
      }
      const msg = (e as Error).message;
      this.error = msg;
      toastStore.error("Failed to update task", msg);
      return null;
    }
  }

  async changeStatus(id: string, status: TaskStatus): Promise<void> {
    await this.updateTask(id, { status });
  }

  async deleteTask(id: string): Promise<void> {
    const previous = this.tasks;
    this.tasks = this.tasks.filter((t) => t.id !== id);
    if (this.selected?.id === id) {
      this.selected = null;
    }
    try {
      await tasksApi.delete(id);
      this.error = null;
      toastStore.success("Task deleted");
    } catch (e) {
      this.tasks = previous;
      const msg = (e as Error).message;
      this.error = msg;
      toastStore.error("Failed to delete task", msg);
    }
  }

  async dispatch(taskId: string): Promise<boolean> {
    try {
      const result = await tasksApi.dispatch(taskId);
      toastStore.success("Task dispatched", result.message);
      return result.ok;
    } catch (e) {
      const msg = (e as Error).message;
      toastStore.error("Failed to dispatch task", msg);
      return false;
    }
  }

  async batchCreateTasks(
    items: Partial<Task>[],
    outputPath?: string | null,
  ): Promise<Task[]> {
    const created: Task[] = [];
    const errors: string[] = [];
    for (const data of items) {
      try {
        const task = await tasksApi.create(data);
        created.push(task);
      } catch (e) {
        errors.push(`"${data.title ?? "Untitled"}": ${(e as Error).message}`);
      }
    }
    if (created.length > 0) {
      this.tasks = [...created, ...this.tasks];
    }
    this.error = errors.length > 0 ? errors.join('; ') : null;
    if (created.length > 0) {
      toastStore.success(
        `${created.length} task${created.length !== 1 ? 's' : ''} created`,
        errors.length > 0
          ? `${errors.length} failed — see details`
          : `Batch-created from documentation analysis`,
      );

      if (outputPath !== undefined && outputPath !== null && isTauri()) {
        void this._exportTasksToDisk(created, outputPath);
      }
    }
    if (errors.length > 0 && created.length === 0) {
      toastStore.error('Failed to create tasks', errors[0]);
    }
    return created;
  }

  private async _exportTasksToDisk(
    tasks: Task[],
    outputPath: string,
  ): Promise<void> {
    try {
      const { invoke } = await import("@tauri-apps/api/core");
      const lines = tasks.map(
        (task) =>
          `## ${task.title}\n\n**Priority:** ${task.priority}\n**Status:** ${task.status}\n**Labels:** ${(task.labels ?? []).join(", ") || "none"}\n\n${task.description ?? ""}`,
      );
      const content = `# Generated Tasks\n\nCreated: ${new Date().toISOString()}\n\n---\n\n${lines.join("\n\n---\n\n")}`;
      const timestamp = new Date().toISOString().slice(0, 10);
      const diskPath = `${outputPath.replace(/\/+$/, "")}/tasks/generated-${timestamp}.md`;
      await invoke("write_project_file", { path: diskPath, content });
    } catch {
      // Best-effort disk export; tasks are already in the API
    }
  }

  selectTask(task: Task | null): void {
    this.selected = task;
  }

  setSort(field: SortField, direction?: SortDirection): void {
    if (this.sortField === field && direction === undefined) {
      this.sortDirection = this.sortDirection === "asc" ? "desc" : "asc";
    } else {
      this.sortField = field;
      this.sortDirection = direction ?? "desc";
    }
  }
}

export const tasksStore = new TasksStore();
