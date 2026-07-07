// Multi-run chat session management — background conversations with active tab switching

import type { Conversation } from "$api/types";
import { conversationsStore } from "./conversations.svelte";

export interface ChatRun {
  runId: string;
  conversationId: string | null;
  agentId: string;
  title: string;
  loading: boolean;
  createdAt: number;
}

const STORAGE_KEY = "bizforge-chat-runs";

function mintRunId(): string {
  return `run-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
}

function readPersisted(): { runs: ChatRun[]; activeRunId: string | null } | null {
  if (typeof localStorage === "undefined") return null;
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    return JSON.parse(raw) as { runs: ChatRun[]; activeRunId: string | null };
  } catch {
    return null;
  }
}

class ChatRunsStore {
  runs = $state<ChatRun[]>([]);
  activeRunId = $state<string | null>(null);

  activeRun = $derived(
    this.runs.find((r) => r.runId === this.activeRunId) ?? null,
  );

  loadingRunIds = $derived(
    new Set(this.runs.filter((r) => r.loading).map((r) => r.runId)),
  );

  constructor() {
    const persisted = readPersisted();
    if (persisted && persisted.runs.length > 0) {
      this.runs = persisted.runs;
      this.activeRunId = persisted.activeRunId;
    }
  }

  #persist(): void {
    if (typeof localStorage === "undefined") return;
    localStorage.setItem(
      STORAGE_KEY,
      JSON.stringify({ runs: this.runs, activeRunId: this.activeRunId }),
    );
  }

  mintRun(agentId: string, title = "New chat"): ChatRun {
    const run: ChatRun = {
      runId: mintRunId(),
      conversationId: null,
      agentId,
      title,
      loading: false,
      createdAt: Date.now(),
    };
    this.runs = [...this.runs, run];
    this.activeRunId = run.runId;
    this.#persist();
    return run;
  }

  setActive(runId: string): void {
    if (this.runs.some((r) => r.runId === runId)) {
      this.activeRunId = runId;
      this.#persist();
    }
  }

  patchRun(runId: string, patch: Partial<ChatRun>): void {
    this.runs = this.runs.map((r) =>
      r.runId === runId ? { ...r, ...patch } : r,
    );
    this.#persist();
  }

  setLoading(runId: string, loading: boolean): void {
    this.patchRun(runId, { loading });
  }

  setTitle(runId: string, title: string): void {
    this.patchRun(runId, { title: title.slice(0, 60) });
  }

  bindConversation(runId: string, conv: Conversation): void {
    this.patchRun(runId, {
      conversationId: conv.id,
      title: conv.title ?? conv.agent_name ?? "Chat",
    });
  }

  async openConversation(conv: Conversation): Promise<void> {
    const existing = this.runs.find((r) => r.conversationId === conv.id);
    if (existing) {
      this.setActive(existing.runId);
      conversationsStore.setActiveConversation(conv);
      await conversationsStore.fetchConversation(conv.id);
      return;
    }

    const run = this.mintRun(
      conv.agent_id,
      conv.title ?? conv.agent_name ?? "Chat",
    );
    this.patchRun(run.runId, { conversationId: conv.id });
    conversationsStore.setActiveConversation(conv);
    await conversationsStore.fetchConversation(conv.id);
  }

  closeRun(runId: string): void {
    const idx = this.runs.findIndex((r) => r.runId === runId);
    if (idx < 0) return;
    const next = this.runs.filter((r) => r.runId !== runId);
    this.runs = next;
    if (this.activeRunId === runId) {
      this.activeRunId = next[idx]?.runId ?? next[idx - 1]?.runId ?? null;
    }
    this.#persist();
  }

  syncFromConversations(conversations: Conversation[]): void {
    for (const conv of conversations.slice(0, 8)) {
      if (this.runs.some((r) => r.conversationId === conv.id)) continue;
      this.runs = [
        ...this.runs,
        {
          runId: mintRunId(),
          conversationId: conv.id,
          agentId: conv.agent_id,
          title: conv.title ?? conv.agent_name ?? "Chat",
          loading: false,
          createdAt: new Date(conv.last_message_at ?? conv.inserted_at).getTime(),
        },
      ];
    }
    if (!this.activeRunId && this.runs.length > 0) {
      this.activeRunId = this.runs[0].runId;
    }
    if (this.activeRunId) {
      const active = this.runs.find((r) => r.runId === this.activeRunId);
      if (active?.conversationId) {
        const conv = conversations.find((c) => c.id === active.conversationId);
        if (conv) {
          conversationsStore.setActiveConversation(conv);
        }
      }
    }
    this.#persist();
  }
}

export const chatRunsStore = new ChatRunsStore();
