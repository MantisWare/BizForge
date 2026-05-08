// src/lib/stores/work-products.svelte.ts
import { workProducts as workProductsApi } from "$api/client";
import { isTauri } from "$lib/utils/platform";
import { toastStore } from "./toasts.svelte";

export type WorkProductType =
  | "report"
  | "code"
  | "data"
  | "document"
  | "analysis"
  | "design";
export type WorkProductStatus = "draft" | "final" | "archived";

export interface WorkProduct {
  id: string;
  title: string;
  type: WorkProductType;
  agent_id: string;
  agent_name: string;
  session_id: string | null;
  project_id: string | null;
  content_preview: string;
  file_path: string | null;
  file_size_bytes: number | null;
  status: WorkProductStatus;
  quality_score: number | null;
  created_at: string;
  updated_at: string;
}

export interface WorkProductFilters {
  type?: WorkProductType;
  status?: WorkProductStatus;
  q?: string;
}

class WorkProductsStore {
  isLoading = $state(true);
  error = $state<string | null>(null);
  products = $state<WorkProduct[]>([]);
  selectedProduct = $state<WorkProduct | null>(null);
  filters = $state<WorkProductFilters>({});

  totalCount = $derived(this.products.length);

  byType = $derived(() => {
    const groups = new Map<WorkProductType, WorkProduct[]>();
    for (const product of this.products) {
      const list = groups.get(product.type) ?? [];
      list.push(product);
      groups.set(product.type, list);
    }
    return groups;
  });

  recentProducts = $derived(
    [...this.products]
      .sort(
        (a, b) =>
          new Date(b.created_at).getTime() - new Date(a.created_at).getTime(),
      )
      .slice(0, 10),
  );

  filteredProducts = $derived(() => {
    let list = this.products;
    const { type, status, q } = this.filters;
    if (type) list = list.filter((p) => p.type === type);
    if (status) list = list.filter((p) => p.status === status);
    if (q) {
      const lower = q.toLowerCase();
      list = list.filter(
        (p) =>
          p.title.toLowerCase().includes(lower) ||
          p.agent_name.toLowerCase().includes(lower) ||
          p.content_preview.toLowerCase().includes(lower),
      );
    }
    return list;
  });

  async fetchProducts(filters?: WorkProductFilters): Promise<void> {
    if (filters !== undefined) this.filters = filters;
    this.isLoading = true;
    this.error = null;
    try {
      const raw = (await workProductsApi.list()) as {
        products: WorkProduct[];
        count: number;
      };
      this.products = raw.products ?? [];
    } catch (e) {
      this.error = (e as Error).message;
    } finally {
      this.isLoading = false;
    }
  }

  async fetchProduct(id: string): Promise<void> {
    try {
      const raw = (await workProductsApi.get(id)) as {
        product: WorkProduct;
      };
      this.selectedProduct = raw.product ?? null;
    } catch (e) {
      this.error = (e as Error).message;
    }
  }

  async archiveProduct(id: string): Promise<void> {
    try {
      await workProductsApi.archive(id);
      this.products = this.products.map((p) =>
        p.id === id ? { ...p, status: "archived" as const } : p,
      );
      if (this.selectedProduct?.id === id) {
        this.selectedProduct = {
          ...this.selectedProduct,
          status: "archived",
        };
      }
    } catch (e) {
      this.error = (e as Error).message;
    }
  }

  setFilter(filters: WorkProductFilters): void {
    this.filters = filters;
  }

  selectProduct(product: WorkProduct | null): void {
    this.selectedProduct = product;
  }

  /**
   * Save a work product's content to the project output directory.
   * Maps work product type to the appropriate subdirectory:
   *   code → code/src/, document → docs/, report → reports/,
   *   data → data/, analysis → reports/, design → media/diagrams/
   */
  async saveToProjectDir(
    product: WorkProduct,
    content: string,
    outputPath: string,
  ): Promise<void> {
    if (!isTauri()) return;

    const TYPE_DIRS: Record<WorkProductType, string> = {
      code: "code/src",
      document: "docs",
      report: "reports",
      data: "data/exports",
      analysis: "reports",
      design: "media/diagrams",
    };

    const dir = TYPE_DIRS[product.type] ?? "docs";
    const slug = product.title.toLowerCase().replace(/\s+/g, "-").replace(/[^a-z0-9-]/g, "");
    const ext = product.type === "code" ? ".ts" : product.type === "data" ? ".json" : ".md";
    const filename = `${slug}${ext}`;
    const diskPath = `${outputPath.replace(/\/+$/, "")}/${dir}/${filename}`;

    try {
      const { invoke } = await import("@tauri-apps/api/core");
      await invoke("write_project_file", { path: diskPath, content });
      toastStore.success("Work product saved", `Written to ${dir}/${filename}`);
    } catch (e) {
      toastStore.error("Save failed", (e as Error).message);
    }
  }
}

export const workProductsStore = new WorkProductsStore();
