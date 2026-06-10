// src/lib/stores/llmInspector.svelte.ts
import type { LlmLogEntry, LlmLogDirection, LlmLogStatus } from "$api/types";
import { onLlmIntercept, type LlmInterceptEvent } from "$api/client";

const STORAGE_KEY_OPEN = "bizforge-inspector-open";
const STORAGE_KEY_WIDTH = "bizforge-inspector-width";
const STORAGE_KEY_COLORS = "bizforge-provider-colors";
const STORAGE_KEY_FONT_SIZE = "bizforge-inspector-font-size";
const MAX_ENTRIES = 500;
const FONT_SIZE_MIN = 8;
const FONT_SIZE_MAX = 16;
const FONT_SIZE_DEFAULT = 11;
const FONT_SIZE_STEP = 1;

const PASTEL_PALETTE = [
  "#FFB3BA", "#BAFFC9", "#BAE1FF", "#FFFFBA",
  "#E8BAFF", "#FFD9BA", "#BAF2FF", "#FFBAE8",
  "#C9FFBA", "#BACCFF", "#FFE4BA", "#BAFFD9",
  "#FFBACC", "#D9BAFF", "#BAFFEF", "#FFF0BA",
] as const;

function loadBoolean(key: string, fallback: boolean): boolean {
  if (typeof localStorage === "undefined") return fallback;
  const stored = localStorage.getItem(key);
  if (stored === null) return fallback;
  return stored === "true";
}

function loadNumber(key: string, fallback: number): number {
  if (typeof localStorage === "undefined") return fallback;
  const stored = localStorage.getItem(key);
  if (stored === null) return fallback;
  const parsed = Number(stored);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function loadColors(): Record<string, string> {
  if (typeof localStorage === "undefined") return {};
  try {
    const raw = localStorage.getItem(STORAGE_KEY_COLORS);
    if (raw === null) return {};
    return JSON.parse(raw) as Record<string, string>;
  } catch {
    return {};
  }
}

function persistColors(colors: Record<string, string>): void {
  if (typeof localStorage === "undefined") return;
  localStorage.setItem(STORAGE_KEY_COLORS, JSON.stringify(colors));
}

export type InspectorFilterLevel = "all" | "agent" | "team" | "department" | "division";

export interface InspectorFilter {
  level: InspectorFilterLevel;
  id: string;
  label: string;
}

export interface AddEntryParams {
  requestId: string;
  providerId: string;
  providerName: string;
  providerSlug: string;
  model: string;
  direction: LlmLogDirection;
  payload: unknown;
  tokenCount?: number;
  durationMs?: number;
  status?: LlmLogStatus;
  error?: string;
  agentId?: string;
  agentName?: string;
}

function extractPreviewLines(payload: unknown): string[] {
  if (payload === undefined || payload === null) {
    return ["(empty)"];
  }
  try {
    const text = typeof payload === "string"
      ? payload
      : JSON.stringify(payload, null, 2);
    return text.split("\n").slice(0, 3);
  } catch {
    return ["[unable to preview]"];
  }
}

class LlmInspectorStore {
  entries = $state<LlmLogEntry[]>([]);
  isOpen = $state(loadBoolean(STORAGE_KEY_OPEN, false));
  panelWidth = $state(loadNumber(STORAGE_KEY_WIDTH, 0));
  fontSize = $state(loadNumber(STORAGE_KEY_FONT_SIZE, FONT_SIZE_DEFAULT));
  providerColors = $state<Record<string, string>>(loadColors());
  searchQuery = $state("");
  activeFilter = $state<InspectorFilter>({ level: "all", id: "", label: "All" });

  private _colorIndex = 0;

  constructor() {
    const existingColors = loadColors();
    this._colorIndex = Object.keys(existingColors).length % PASTEL_PALETTE.length;
  }

  get entryCount(): number {
    return this.entries.length;
  }

  setFilter(filter: InspectorFilter): void {
    this.activeFilter = filter;
  }

  clearFilter(): void {
    this.activeFilter = { level: "all", id: "", label: "All" };
    this.searchQuery = "";
  }

  toggle(): void {
    this.isOpen = !this.isOpen;
    if (typeof localStorage !== "undefined") {
      localStorage.setItem(STORAGE_KEY_OPEN, String(this.isOpen));
    }
    if (this.isOpen && this.panelWidth === 0 && typeof window !== "undefined") {
      this.panelWidth = Math.round(window.innerWidth * 0.5);
      localStorage.setItem(STORAGE_KEY_WIDTH, String(this.panelWidth));
    }
  }

  open(): void {
    if (this.isOpen) return;
    this.toggle();
  }

  close(): void {
    if (!this.isOpen) return;
    this.toggle();
  }

  setWidth(px: number): void {
    this.panelWidth = px;
    if (typeof localStorage !== "undefined") {
      localStorage.setItem(STORAGE_KEY_WIDTH, String(px));
    }
  }

  increaseFontSize(): void {
    const next = Math.min(FONT_SIZE_MAX, this.fontSize + FONT_SIZE_STEP);
    this.setFontSize(next);
  }

  decreaseFontSize(): void {
    const next = Math.max(FONT_SIZE_MIN, this.fontSize - FONT_SIZE_STEP);
    this.setFontSize(next);
  }

  setFontSize(size: number): void {
    this.fontSize = Math.max(FONT_SIZE_MIN, Math.min(FONT_SIZE_MAX, size));
    if (typeof localStorage !== "undefined") {
      localStorage.setItem(STORAGE_KEY_FONT_SIZE, String(this.fontSize));
    }
  }

  addEntry(params: AddEntryParams): void {
    const entry: LlmLogEntry = {
      id: crypto.randomUUID(),
      requestId: params.requestId,
      timestamp: new Date().toISOString(),
      providerId: params.providerId,
      providerName: params.providerName,
      providerSlug: params.providerSlug,
      model: params.model,
      direction: params.direction,
      payload: params.payload,
      previewLines: extractPreviewLines(params.payload),
      tokenCount: params.tokenCount,
      durationMs: params.durationMs,
      status: params.status ?? "pending",
      error: params.error,
      agentId: params.agentId,
      agentName: params.agentName,
    };

    this.ensureProviderColor(params.providerSlug);
    this.entries = [entry, ...this.entries].slice(0, MAX_ENTRIES);
  }

  updateEntryStatus(requestId: string, status: LlmLogStatus, error?: string): void {
    this.entries = this.entries.map((e) =>
      e.requestId === requestId && e.direction === "sent"
        ? { ...e, status, error }
        : e,
    );
  }

  clear(): void {
    this.entries = [];
  }

  getProviderColor(slug: string): string {
    const existing = this.providerColors[slug];
    if (existing !== undefined) return existing;
    const color = PASTEL_PALETTE[this._colorIndex % PASTEL_PALETTE.length];
    this._colorIndex += 1;
    queueMicrotask(() => {
      if (this.providerColors[slug] === undefined) {
        this.providerColors = { ...this.providerColors, [slug]: color };
        persistColors(this.providerColors);
      }
    });
    return color;
  }

  setProviderColor(slug: string, color: string): void {
    this.providerColors = { ...this.providerColors, [slug]: color };
    persistColors(this.providerColors);
  }
}

export const llmInspectorStore = new LlmInspectorStore();

// ── Wire into the API client interceptor ────────────────────────────────────

let _agentsStoreRef: { getById(id: string): { name: string; display_name: string } | null } | null = null;

export function bindAgentsStore(
  store: { getById(id: string): { name: string; display_name: string } | null },
): void {
  _agentsStoreRef = store;
}

function resolveProviderFromPath(path: string): { id: string; name: string; slug: string } {
  const sessionMatch = path.match(/^\/sessions\/([^/]+)\//);
  if (sessionMatch !== null) {
    return { id: sessionMatch[1], name: "Session", slug: "session" };
  }
  const providerMatch = path.match(/^\/providers\/([^/]+)\//);
  if (providerMatch !== null) {
    return { id: providerMatch[1], name: "Provider", slug: providerMatch[1] };
  }
  const agentMatch = path.match(/^\/agents\/([^/]+)\//);
  if (agentMatch !== null) {
    return { id: agentMatch[1], name: "Agent", slug: "agent" };
  }
  const convMatch = path.match(/^\/conversations\/([^/]+)\//);
  if (convMatch !== null) {
    return { id: convMatch[1], name: "Conversation", slug: "conversation" };
  }
  if (path.includes("/reports/")) {
    return { id: "reports", name: "Reports", slug: "reports" };
  }
  return { id: "unknown", name: "API", slug: "api" };
}

function extractModel(payload: unknown): string {
  if (typeof payload !== "object" || payload === null) return "unknown";
  const obj = payload as Record<string, unknown>;
  if (typeof obj.model === "string") return obj.model;
  if (typeof obj.default_model === "string") return obj.default_model;
  return "unknown";
}

function extractAgentId(path: string, payload: unknown): string | undefined {
  const agentMatch = path.match(/^\/agents\/([^/]+)\//);
  if (agentMatch !== null) return agentMatch[1];

  const sessionMatch = path.match(/^\/sessions\/([^/]+)\//);
  if (sessionMatch !== null && typeof payload === "object" && payload !== null) {
    const obj = payload as Record<string, unknown>;
    if (typeof obj.agent_id === "string") return obj.agent_id;
  }

  if (typeof payload === "object" && payload !== null) {
    const obj = payload as Record<string, unknown>;
    if (typeof obj.agent_id === "string") return obj.agent_id;
  }

  return undefined;
}

function resolveAgentName(agentId: string | undefined): string | undefined {
  if (agentId === undefined || _agentsStoreRef === null) return undefined;
  const agent = _agentsStoreRef.getById(agentId);
  if (agent === null) return undefined;
  return agent.display_name || agent.name;
}

onLlmIntercept((event: LlmInterceptEvent) => {
  const provider = resolveProviderFromPath(event.path);
  const model = event.direction === "sent" ? extractModel(event.payload) : "—";
  const agentId = event.direction === "sent"
    ? extractAgentId(event.path, event.payload)
    : undefined;
  const agentName = resolveAgentName(agentId);

  llmInspectorStore.addEntry({
    requestId: event.requestId,
    providerId: provider.id,
    providerName: provider.name,
    providerSlug: provider.slug,
    model,
    direction: event.direction,
    payload: event.payload,
    durationMs: event.durationMs,
    status: event.status,
    error: event.error,
    agentId,
    agentName,
  });
});
