// src/lib/stores/issues.svelte.ts
import type { Issue, IssueStatus, IssuePriority } from "$api/types";
import { issues as issuesApi } from "$api/client";
import { toastStore } from "./toasts.svelte";
import { agentsStore } from "./agents.svelte";

export function resolveAssigneeName(issue: Issue): string {
  if (issue.assignee_name) return issue.assignee_name;
  if (issue.assignee_id) {
    const agent = agentsStore.agents.find((a) => a.id === issue.assignee_id);
    return agent?.display_name ?? agent?.name ?? "Unknown Agent";
  }
  return "Unassigned";
}

type SortField = "created_at" | "updated_at" | "priority" | "title";
type SortDirection = "asc" | "desc";

const PRIORITY_ORDER: Record<IssuePriority, number> = {
  critical: 0,
  high: 1,
  medium: 2,
  low: 3,
};

class IssuesStore {
  issues = $state<Issue[]>([]);
  selected = $state<Issue | null>(null);
  loading = $state(false);
  error = $state<string | null>(null);

  // Filters
  filterStatus = $state<IssueStatus | "all">("all");
  filterPriority = $state<IssuePriority | "all">("all");
  filterAssignee = $state<string | "all">("all");
  searchQuery = $state("");

  // Sort
  sortField = $state<SortField>("created_at");
  sortDirection = $state<SortDirection>("desc");

  // Derived: filtered + sorted list
  filteredIssues = $derived.by(() => {
    let result = this.issues;

    if (this.filterStatus !== "all") {
      result = result.filter((i) => i.status === this.filterStatus);
    }
    if (this.filterPriority !== "all") {
      result = result.filter((i) => i.priority === this.filterPriority);
    }
    if (this.filterAssignee !== "all") {
      result = result.filter((i) => i.assignee_id === this.filterAssignee);
    }
    if (this.searchQuery) {
      const q = this.searchQuery.toLowerCase();
      result = result.filter(
        (i) =>
          i.title.toLowerCase().includes(q) ||
          (i.description ?? "").toLowerCase().includes(q),
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
    const statuses: IssueStatus[] = [
      "backlog",
      "todo",
      "in_progress",
      "in_review",
      "done",
    ];
    return statuses.map((status) => ({
      status,
      issues: this.filteredIssues.filter((i) => i.status === status),
    }));
  });

  openCount = $derived(this.issues.filter((i) => i.status !== "done").length);

  async fetchIssues(workspaceId?: string): Promise<void> {
    this.loading = true;
    try {
      this.issues = await issuesApi.list(workspaceId);
      // Refresh selected from the new array so stale references don't keep
      // detail panels rendered after the underlying data changes.
      if (this.selected) {
        const refreshed = this.issues.find((i) => i.id === this.selected!.id);
        this.selected = refreshed ?? null;
      }
      this.error = null;
    } catch (e) {
      const msg = (e as Error).message;
      this.error = msg;
      if (!msg.includes("not_found") && !msg.includes("unauthorized")) {
        toastStore.error("Failed to load issues", msg);
      }
    } finally {
      this.loading = false;
    }
  }

  async createIssue(data: Partial<Issue>): Promise<Issue | null> {
    this.loading = true;
    try {
      const created = await issuesApi.create(data);
      this.issues = [created, ...this.issues];
      this.error = null;
      toastStore.success("Issue created", created.title);
      return created;
    } catch (e) {
      const msg = (e as Error).message;
      this.error = msg;
      toastStore.error("Failed to create issue", msg);
      return null;
    } finally {
      this.loading = false;
    }
  }

  async updateIssue(id: string, data: Partial<Issue>): Promise<Issue | null> {
    const previous = this.issues;
    // Optimistic update
    this.issues = this.issues.map((i) => (i.id === id ? { ...i, ...data } : i));
    if (this.selected?.id === id) {
      this.selected = { ...this.selected, ...data };
    }
    try {
      const updated = await issuesApi.update(id, data);
      this.issues = this.issues.map((i) => (i.id === id ? updated : i));
      if (this.selected?.id === id) {
        this.selected = updated;
      }
      this.error = null;
      return updated;
    } catch (e) {
      this.issues = previous;
      if (this.selected?.id === id) {
        this.selected = previous.find((i) => i.id === id) ?? this.selected;
      }
      const msg = (e as Error).message;
      this.error = msg;
      toastStore.error("Failed to update issue", msg);
      return null;
    }
  }

  async changeStatus(id: string, status: IssueStatus): Promise<void> {
    await this.updateIssue(id, { status });
  }

  async deleteIssue(id: string): Promise<void> {
    const previous = this.issues;
    this.issues = this.issues.filter((i) => i.id !== id);
    if (this.selected?.id === id) {
      this.selected = null;
    }
    try {
      await issuesApi.delete(id);
      this.error = null;
      toastStore.success("Issue deleted");
    } catch (e) {
      this.issues = previous;
      const msg = (e as Error).message;
      this.error = msg;
      toastStore.error("Failed to delete issue", msg);
    }
  }

  async dispatch(issueId: string): Promise<boolean> {
    try {
      const result = await issuesApi.dispatch(issueId);
      toastStore.success("Issue dispatched", result.message);
      return result.ok;
    } catch (e) {
      const msg = (e as Error).message;
      toastStore.error("Failed to dispatch issue", msg);
      return false;
    }
  }

  async batchCreateIssues(items: Partial<Issue>[]): Promise<Issue[]> {
    const created: Issue[] = [];
    const errors: string[] = [];
    for (const data of items) {
      try {
        const issue = await issuesApi.create(data);
        created.push(issue);
      } catch (e) {
        errors.push(`"${data.title ?? "Untitled"}": ${(e as Error).message}`);
      }
    }
    if (created.length > 0) {
      this.issues = [...created, ...this.issues];
    }
    this.error = errors.length > 0 ? errors.join('; ') : null;
    if (created.length > 0) {
      toastStore.success(
        `${created.length} issue${created.length !== 1 ? 's' : ''} created`,
        errors.length > 0
          ? `${errors.length} failed — see details`
          : `Batch-created from documentation analysis`,
      );
    }
    if (errors.length > 0 && created.length === 0) {
      toastStore.error('Failed to create issues', errors[0]);
    }
    return created;
  }

  selectIssue(issue: Issue | null): void {
    this.selected = issue;
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

export const issuesStore = new IssuesStore();
