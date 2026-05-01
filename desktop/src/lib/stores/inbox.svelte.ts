// src/lib/stores/inbox.svelte.ts
import type { InboxItem, InboxItemStatus, InboxItemType } from "$api/types";
import { inbox as inboxApi } from "$api/client";
import { connectSSE, type StreamController } from "$api/sse";
import { toastStore } from "./toasts.svelte";

class InboxStore {
  items = $state<InboxItem[]>([]);
  selected = $state<InboxItem | null>(null);
  loading = $state(false);
  error = $state<string | null>(null);
  private streamController: StreamController | null = null;

  // Filters
  filterType = $state<InboxItemType | "all">("all");
  filterStatus = $state<InboxItemStatus | "all">("all");
  searchQuery = $state("");

  // Derived
  unreadCount = $derived(
    this.items.filter((i) => i.status === "unread").length,
  );

  filteredItems = $derived.by(() => {
    let result = this.items;
    if (this.filterType !== "all") {
      result = result.filter((i) => i.type === this.filterType);
    }
    if (this.filterStatus !== "all") {
      result = result.filter((i) => i.status === this.filterStatus);
    }
    if (this.searchQuery) {
      const q = this.searchQuery.toLowerCase();
      result = result.filter(
        (i) =>
          i.title.toLowerCase().includes(q) || i.body.toLowerCase().includes(q),
      );
    }
    // Unread first, then by date descending
    return [...result].sort((a, b) => {
      const unreadA = a.status === "unread" ? 0 : 1;
      const unreadB = b.status === "unread" ? 0 : 1;
      if (unreadA !== unreadB) return unreadA - unreadB;
      return (
        new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
      );
    });
  });

  typeGroups = $derived.by(() => {
    const types: InboxItemType[] = [
      "approval",
      "alert",
      "mention",
      "failure",
      "report",
      "budget_warning",
      "message",
      "integration",
    ];
    return types
      .map((type) => ({
        type,
        items: this.filteredItems.filter((i) => i.type === type),
        unread: this.items.filter(
          (i) => i.type === type && i.status === "unread",
        ).length,
      }))
      .filter((g) => g.items.length > 0);
  });

  async fetchItems(workspaceId?: string): Promise<void> {
    this.loading = true;
    try {
      this.items = await inboxApi.list(workspaceId);
      this.error = null;
    } catch (e) {
      const msg = (e as Error).message;
      this.error = msg;
      if (!msg.includes("not_found") && !msg.includes("unauthorized")) {
        toastStore.error("Failed to load inbox", msg);
      }
    } finally {
      this.loading = false;
    }
  }

  async performAction(itemId: string, actionId: string): Promise<void> {
    // Optimistic: mark as actioned
    const previous = this.items;
    this.items = this.items.map((i) =>
      i.id === itemId ? { ...i, status: "actioned" as InboxItemStatus } : i,
    );
    if (this.selected?.id === itemId) {
      this.selected = { ...this.selected, status: "actioned" };
    }
    try {
      await inboxApi.action(itemId, actionId);
      this.error = null;
    } catch (e) {
      this.items = previous;
      if (this.selected?.id === itemId) {
        this.selected = previous.find((i) => i.id === itemId) ?? this.selected;
      }
      const msg = (e as Error).message;
      this.error = msg;
      toastStore.error("Action failed", msg);
    }
  }

  async dismiss(itemId: string): Promise<void> {
    const previous = this.items;
    this.items = this.items.map((i) =>
      i.id === itemId ? { ...i, status: "dismissed" as InboxItemStatus } : i,
    );
    if (this.selected?.id === itemId) {
      this.selected = { ...this.selected, status: "dismissed" };
    }
    try {
      await inboxApi.dismiss(itemId);
      this.error = null;
    } catch (e) {
      this.items = previous;
      if (this.selected?.id === itemId) {
        this.selected = previous.find((i) => i.id === itemId) ?? this.selected;
      }
      const msg = (e as Error).message;
      this.error = msg;
      toastStore.error("Failed to dismiss item", msg);
    }
  }

  async markRead(itemId: string): Promise<void> {
    const previous = this.items;
    const previousSelected = this.selected;
    this.items = this.items.map((i) =>
      i.id === itemId && i.status === "unread"
        ? { ...i, status: "read" as InboxItemStatus }
        : i,
    );
    if (this.selected?.id === itemId && this.selected.status === "unread") {
      this.selected = { ...this.selected, status: "read" };
    }
    try {
      await inboxApi.read(itemId);
    } catch (e) {
      this.items = previous;
      this.selected = previousSelected;
      const msg = (e as Error).message;
      this.error = msg;
      toastStore.error("Failed to mark as read", msg);
    }
  }

  async markAllRead(): Promise<void> {
    const previous = this.items;
    const previousSelected = this.selected;
    this.items = this.items.map((i) =>
      i.status === "unread" ? { ...i, status: "read" as InboxItemStatus } : i,
    );
    if (this.selected && this.selected.status === "unread") {
      this.selected = { ...this.selected, status: "read" };
    }
    try {
      await inboxApi.readAll();
    } catch (e) {
      this.items = previous;
      this.selected = previousSelected;
      const msg = (e as Error).message;
      this.error = msg;
      toastStore.error("Failed to mark all as read", msg);
    }
  }

  connectStream(workspaceId?: string): void {
    this.disconnectStream();

    const qs = workspaceId ? `?workspace_id=${workspaceId}` : "";

    this.streamController = connectSSE(`/inbox/stream${qs}`, {
      onEvent: (event) => {
        if (
          event.type === "notification.created" &&
          (event as Record<string, unknown>).data !== undefined
        ) {
          const data = (event as Record<string, unknown>).data as InboxItem;
          if (data.id !== undefined && !this.items.some((i) => i.id === data.id)) {
            this.items = [data, ...this.items];
          }
        }
      },
      onError: () => {
        // SSE will auto-reconnect via connectSSE
      },
    });
  }

  disconnectStream(): void {
    if (this.streamController !== null) {
      this.streamController.abort();
      this.streamController = null;
    }
  }

  async replyToItem(itemId: string, body: string): Promise<boolean> {
    try {
      await inboxApi.reply(itemId, body);
      toastStore.success("Reply sent");
      return true;
    } catch (e) {
      const msg = (e as Error).message;
      toastStore.error("Failed to send reply", msg);
      return false;
    }
  }

  selectItem(item: InboxItem | null): void {
    this.selected = item;
    if (item && item.status === "unread") {
      void this.markRead(item.id);
    }
  }
}

export const inboxStore = new InboxStore();
