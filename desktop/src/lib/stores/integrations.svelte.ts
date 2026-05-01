// src/lib/stores/integrations.svelte.ts
import type { Integration, IntegrationCategory } from "$api/types";
import { INTEGRATION_CATEGORY_LABELS } from "$api/types";
import { integrations as integrationsApi } from "$api/client";
import { toastStore } from "./toasts.svelte";

export interface CategoryGroup {
  category: IntegrationCategory;
  label: string;
  integrations: Integration[];
  connectedCount: number;
}

class IntegrationsStore {
  integrations = $state<Integration[]>([]);
  loading = $state(false);
  error = $state<string | null>(null);
  filterCategory = $state<IntegrationCategory | "all">("all");
  searchQuery = $state("");

  totalCount = $derived(this.integrations.length);
  connectedCount = $derived(
    this.integrations.filter((i) => {
      const raw = i as unknown as Record<string, unknown>;
      if (raw.connected === true) return true;
      return i.status === "connected";
    }).length,
  );

  filtered = $derived.by(() => {
    let list = this.integrations;
    if (this.filterCategory !== "all") {
      list = list.filter((i) => i.category === this.filterCategory);
    }
    const q = this.searchQuery.trim().toLowerCase();
    if (q.length > 0) {
      list = list.filter(
        (i) =>
          i.name.toLowerCase().includes(q) ||
          i.provider.toLowerCase().includes(q) ||
          i.description.toLowerCase().includes(q),
      );
    }
    return list;
  });

  grouped = $derived.by(() => {
    const map = new Map<IntegrationCategory, Integration[]>();
    for (const i of this.filtered) {
      const existing = map.get(i.category);
      if (existing !== undefined) {
        existing.push(i);
      } else {
        map.set(i.category, [i]);
      }
    }
    const groups: CategoryGroup[] = [];
    for (const [category, items] of map) {
      groups.push({
        category,
        label: INTEGRATION_CATEGORY_LABELS[category] ?? category,
        integrations: items,
        connectedCount: items.filter((i) => i.status === "connected").length,
      });
    }
    return groups;
  });

  categories = $derived.by(() => {
    const cats = new Set<IntegrationCategory>();
    for (const i of this.integrations) {
      cats.add(i.category);
    }
    return [...cats].map((c) => ({
      value: c,
      label: INTEGRATION_CATEGORY_LABELS[c] ?? c,
      count: this.integrations.filter((i) => i.category === c).length,
    }));
  });

  async fetchIntegrations(workspaceId?: string): Promise<void> {
    this.loading = true;
    try {
      this.integrations = await integrationsApi.list(workspaceId);
      this.error = null;
    } catch (e) {
      const msg = (e as Error).message;
      this.error = msg;
      if (!msg.includes("not_found") && !msg.includes("unauthorized")) {
        toastStore.error("Failed to load integrations", msg);
      }
    } finally {
      this.loading = false;
    }
  }

  async connect(slug: string, config?: Record<string, unknown>): Promise<void> {
    this.loading = true;
    try {
      await integrationsApi.connect(slug, config);
      await this.fetchIntegrations();
      this.error = null;
      toastStore.success("Integration connected", slug);
    } catch (e) {
      const msg = (e as Error).message;
      this.error = msg;
      toastStore.error("Failed to connect integration", msg);
    } finally {
      this.loading = false;
    }
  }

  async disconnect(slug: string): Promise<void> {
    this.loading = true;
    try {
      await integrationsApi.disconnect(slug);
      await this.fetchIntegrations();
      this.error = null;
      toastStore.success("Integration disconnected", slug);
    } catch (e) {
      const msg = (e as Error).message;
      this.error = msg;
      toastStore.error("Failed to disconnect integration", msg);
    } finally {
      this.loading = false;
    }
  }
}

export const integrationsStore = new IntegrationsStore();
