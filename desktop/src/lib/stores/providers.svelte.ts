// src/lib/stores/providers.svelte.ts
import type {
  AIProvider,
  AIProviderCreateRequest,
  AIProviderTestResult,
} from "$api/types";
import { providers as providersApi } from "$api/client";
import { toastStore } from "./toasts.svelte";

const CACHE_KEY = "bizforge-providers-cache";

function loadCache(): AIProvider[] {
  if (typeof localStorage === "undefined") return [];
  const raw = localStorage.getItem(CACHE_KEY);
  if (raw === null) return [];
  try {
    const parsed = JSON.parse(raw) as AIProvider[];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function saveCache(data: AIProvider[]): void {
  if (typeof localStorage === "undefined") return;
  localStorage.setItem(CACHE_KEY, JSON.stringify(data));
}

class ProvidersStore {
  providers = $state<AIProvider[]>(loadCache());
  loading = $state(false);
  error = $state<string | null>(null);

  totalCount = $derived(this.providers.length);
  configuredCount = $derived(
    this.providers.filter((p) => p.status === "connected").length,
  );
  configured = $derived(
    this.providers.filter((p) => p.status === "connected"),
  );
  defaultProvider = $derived(
    this.providers.find((p) => p.is_default) ?? null,
  );

  /** Flat list of all models across providers that have at least one model. */
  allModels = $derived.by(() => {
    const result: { providerId: string; providerName: string; model: string }[] = [];
    for (const p of this.providers) {
      if (p.models.length === 0) continue;
      for (const m of p.models) {
        result.push({ providerId: p.id, providerName: p.name, model: m });
      }
    }
    return result;
  });

  private persist(): void {
    saveCache(this.providers);
  }

  private fetchAbort: AbortController | null = null;

  async fetch(workspaceId?: string): Promise<void> {
    if (this.fetchAbort !== null) {
      this.fetchAbort.abort();
    }
    this.fetchAbort = new AbortController();
    this.loading = true;
    this.error = null;
    try {
      const result = await Promise.race([
        providersApi.list(workspaceId),
        new Promise<never>((_, reject) => {
          const timer = setTimeout(
            () => reject(new Error("Provider fetch timed out after 15s")),
            15_000,
          );
          this.fetchAbort?.signal.addEventListener("abort", () => {
            clearTimeout(timer);
            reject(new Error("aborted"));
          });
        }),
      ]);
      if (result.length > 0 || this.providers.length === 0) {
        this.providers = result;
        this.persist();
      }
      this.error = null;
    } catch (e) {
      const msg = (e as Error).message;
      if (msg === "aborted") return;
      this.error = msg;
      if (!msg.includes("not_found") && !msg.includes("unauthorized")) {
        toastStore.error("Failed to load providers", msg);
      }
    } finally {
      this.loading = false;
      this.fetchAbort = null;
    }
  }

  async create(
    req: AIProviderCreateRequest,
  ): Promise<AIProvider | null> {
    this.loading = true;
    try {
      const created = await providersApi.create(req);
      this.providers = [created, ...this.providers];
      this.persist();
      this.error = null;
      toastStore.success("Provider added", created.name);
      return created;
    } catch (e) {
      const msg = (e as Error).message;
      this.error = msg;
      toastStore.error("Failed to add provider", msg);
      return null;
    } finally {
      this.loading = false;
    }
  }

  async update(
    id: string,
    data: Partial<AIProviderCreateRequest>,
  ): Promise<AIProvider | null> {
    const previous = this.providers;
    this.providers = this.providers.map((p) =>
      p.id === id ? { ...p, ...data } : p,
    );
    try {
      const updated = await providersApi.update(id, data);
      this.providers = this.providers.map((p) =>
        p.id === id ? updated : p,
      );
      this.persist();
      this.error = null;
      toastStore.success("Provider updated", updated.name);
      return updated;
    } catch (e) {
      this.providers = previous;
      const msg = (e as Error).message;
      this.error = msg;
      toastStore.error("Failed to update provider", msg);
      return null;
    }
  }

  async remove(id: string): Promise<void> {
    const previous = this.providers;
    this.providers = this.providers.filter((p) => p.id !== id);
    try {
      await providersApi.delete(id);
      this.persist();
      this.error = null;
      toastStore.success("Provider removed");
    } catch (e) {
      this.providers = previous;
      const msg = (e as Error).message;
      this.error = msg;
      toastStore.error("Failed to remove provider", msg);
    }
  }

  async test(
    id: string,
  ): Promise<AIProviderTestResult | null> {
    try {
      const { provider, test_result } = await providersApi.test(id);
      this.providers = this.providers.map((p) =>
        p.id === id ? provider : p,
      );
      this.persist();
      this.error = null;
      if (test_result.status === "connected") {
        toastStore.success(
          "Connection successful",
          `Latency: ${test_result.latency_ms ?? "—"}ms`,
        );
      } else {
        toastStore.error(
          "Connection failed",
          test_result.error_message ?? "Unknown error",
        );
      }
      return test_result;
    } catch (e) {
      const msg = (e as Error).message;
      this.error = msg;
      toastStore.error("Test failed", msg);
      return null;
    }
  }

  async setDefault(id: string): Promise<void> {
    const previous = this.providers;
    this.providers = this.providers.map((p) => ({
      ...p,
      is_default: p.id === id,
    }));
    try {
      await providersApi.update(id, { is_default: true });
      this.persist();
      this.error = null;
    } catch (e) {
      this.providers = previous;
      const msg = (e as Error).message;
      this.error = msg;
      toastStore.error("Failed to set default provider", msg);
    }
  }

  getById(id: string): AIProvider | null {
    return this.providers.find((p) => p.id === id) ?? null;
  }

  /**
   * Fetch available models from a provider endpoint via the backend proxy.
   * Avoids CORS issues with cloud providers.
   */
  async fetchModelsFromEndpoint(
    endpoint: string,
    apiKey?: string,
    slug?: string,
  ): Promise<{ models: string[]; error?: string }> {
    const result = await providersApi.fetchModels(endpoint, apiKey, slug);
    if (result.error !== undefined) {
      toastStore.error("Failed to fetch models", result.error);
    } else if (result.models.length > 0) {
      toastStore.success(
        "Models retrieved",
        `${result.models.length} model${result.models.length !== 1 ? "s" : ""} available`,
      );
    } else {
      toastStore.error("No models found", "The provider returned an empty model list");
    }
    return result;
  }

  /**
   * Fetch models for an already-saved provider (by id). The backend reads the
   * stored API key from the database. Updates the provider model list in-place.
   */
  async fetchModelsForProvider(id: string): Promise<string[]> {
    const result = await providersApi.fetchModelsById(id);
    if (result.error !== undefined) {
      toastStore.error("Failed to fetch models", result.error);
    } else if (result.models.length > 0) {
      toastStore.success(
        "Models retrieved",
        `${result.models.length} model${result.models.length !== 1 ? "s" : ""} available`,
      );
      this.providers = this.providers.map((p) =>
        p.id === id ? { ...p, models: result.models } : p,
      );
      this.persist();
    } else {
      toastStore.error("No models found", "The provider returned an empty model list");
    }

    return result.models;
  }
}

export const providersStore = new ProvidersStore();
