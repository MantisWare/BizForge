import type { AIProvider, AIProviderTestResult } from "../types";

const STORAGE_KEY = "bizforge-providers";

const DEFAULT_PROVIDERS: AIProvider[] = [
  {
    id: "prov-1",
    slug: "anthropic",
    name: "Anthropic",
    category: "cloud",
    api_key_set: true,
    endpoint: "https://api.anthropic.com",
    config: { temperature: 0.7 },
    models: [
      "claude-sonnet-4-6",
      "claude-opus-4-6",
      "claude-haiku-4-5-20251001",
    ],
    is_default: true,
    status: "connected",
    last_tested_at: new Date(Date.now() - 300_000).toISOString(),
    workspace_id: "ws-1",
    created_at: "2026-03-01T00:00:00Z",
    updated_at: "2026-03-01T00:00:00Z",
  },
  {
    id: "prov-3",
    slug: "claude-code",
    name: "Claude Code",
    category: "cloud",
    api_key_set: true,
    endpoint: "https://api.anthropic.com",
    config: { temperature: 0.3 },
    models: [
      "claude-sonnet-4-6",
      "claude-opus-4-6",
      "claude-haiku-4-5-20251001",
    ],
    is_default: false,
    status: "connected",
    last_tested_at: new Date(Date.now() - 450_000).toISOString(),
    workspace_id: "ws-1",
    created_at: "2026-03-01T12:00:00Z",
    updated_at: "2026-03-01T12:00:00Z",
  },
  {
    id: "prov-2",
    slug: "local",
    name: "Local Provider",
    category: "local",
    api_key_set: false,
    endpoint: "http://localhost:11434",
    config: { temperature: 0.5, local_runtime: "ollama", local_endpoint: "http://localhost:11434" },
    models: ["llama3.2", "codellama", "mistral"],
    is_default: false,
    status: "connected",
    last_tested_at: new Date(Date.now() - 600_000).toISOString(),
    workspace_id: "ws-1",
    created_at: "2026-03-02T00:00:00Z",
    updated_at: "2026-03-02T00:00:00Z",
  },
];

function loadFromStorage(): AIProvider[] {
  if (typeof localStorage === "undefined") return DEFAULT_PROVIDERS;
  const raw = localStorage.getItem(STORAGE_KEY);
  if (raw === null) return DEFAULT_PROVIDERS;
  try {
    const parsed = JSON.parse(raw) as AIProvider[];
    return Array.isArray(parsed) ? parsed : DEFAULT_PROVIDERS;
  } catch {
    return DEFAULT_PROVIDERS;
  }
}

function saveToStorage(data: AIProvider[]): void {
  if (typeof localStorage === "undefined") return;
  localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
}

let mockProviderData: AIProvider[] = loadFromStorage();

export function mockProviders(): AIProvider[] {
  return mockProviderData;
}

export function getProviderById(id: string): AIProvider | undefined {
  return mockProviderData.find((p) => p.id === id);
}

export function addProvider(provider: AIProvider): void {
  mockProviderData = [provider, ...mockProviderData];
  saveToStorage(mockProviderData);
}

export function updateProvider(
  id: string,
  data: Partial<AIProvider>,
): AIProvider | undefined {
  const idx = mockProviderData.findIndex((p) => p.id === id);
  if (idx === -1) return undefined;
  mockProviderData[idx] = { ...mockProviderData[idx], ...data };
  saveToStorage(mockProviderData);
  return mockProviderData[idx];
}

export function deleteProvider(id: string): boolean {
  const len = mockProviderData.length;
  mockProviderData = mockProviderData.filter((p) => p.id !== id);
  if (mockProviderData.length < len) {
    saveToStorage(mockProviderData);
    return true;
  }
  return false;
}

export function testProvider(_id: string): AIProviderTestResult {
  return {
    status: "connected",
    latency_ms: 85 + Math.floor(Math.random() * 200),
    models: ["claude-sonnet-4-6", "claude-opus-4-6"],
  };
}

export function setProviderDefault(id: string): void {
  mockProviderData = mockProviderData.map((p) => ({
    ...p,
    is_default: p.id === id,
  }));
  saveToStorage(mockProviderData);
}
