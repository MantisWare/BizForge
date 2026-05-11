// src/lib/stores/documents.svelte.ts
// Documents store — CRUD operations against /api/v1/documents.
// Refetches automatically when the active workspace changes.

import type { Document, DocumentRevision, DocumentTreeNode } from "$api/types";
import { documents as documentsApi } from "$api/client";
import { isTauri } from "$lib/utils/platform";
import { workspaceStore } from "./workspace.svelte";

class DocumentsStore {
  documents = $state<Document[]>([]);
  tree = $state<DocumentTreeNode[]>([]);
  selected = $state<Document | null>(null);
  loading = $state(false);
  error = $state<string | null>(null);

  /** Project-scoped documents loaded via fetchByProject(). */
  projectDocuments = $state<Document[]>([]);
  projectDocsLoading = $state(false);
  projectDocsError = $state<string | null>(null);

  async fetchDocuments(): Promise<void> {
    this.loading = true;
    this.error = null;
    try {
      const workspaceId = workspaceStore.activeWorkspaceId ?? undefined;
      const data = await documentsApi.list(workspaceId);
      this.documents = data.documents;
      this.tree = data.tree;
      // Clear selection if the selected document is no longer present.
      if (
        this.selected !== null &&
        !data.documents.some((d) => d.path === this.selected!.path)
      ) {
        this.selected = null;
      }
    } catch (err) {
      this.documents = [];
      this.tree = [];
      this.error = (err as Error).message;
    } finally {
      this.loading = false;
    }
  }

  async fetchByProject(projectId: string): Promise<void> {
    this.projectDocsLoading = true;
    this.projectDocsError = null;
    try {
      const workspaceId = workspaceStore.activeWorkspaceId ?? undefined;
      const data = await documentsApi.listByProject(projectId, workspaceId);
      this.projectDocuments = data.documents;
    } catch (err) {
      this.projectDocuments = [];
      this.projectDocsError = (err as Error).message;
    } finally {
      this.projectDocsLoading = false;
    }
  }

  async createDocument(doc: {
    title: string;
    path: string;
    content: string;
    format?: Document["format"];
    project_id?: string | null;
    output_path?: string | null;
    disk_subdir?: string;
  }): Promise<Document> {
    const workspaceId = workspaceStore.activeWorkspaceId ?? undefined;
    const created = await documentsApi.create({ ...doc, workspace_id: workspaceId });
    this.documents = [...this.documents, created];
    if (created.project_id !== null) {
      this.projectDocuments = [...this.projectDocuments, created];
    }
    this._rebuildTree();

    if (doc.output_path !== undefined && doc.output_path !== null && isTauri()) {
      const subdir = doc.disk_subdir ?? "docs";
      const filename = doc.path.split("/").pop() ?? `${doc.title}.md`;
      const diskPath = `${doc.output_path.replace(/\/+$/, "")}/${subdir}/${filename}`;
      try {
        const { invoke } = await import("@tauri-apps/api/core");
        await invoke("write_project_file", { path: diskPath, content: doc.content });
      } catch {
        // Non-critical: document saved to API, disk mirror failed silently
      }
    }

    return created;
  }

  async updateDocument(
    path: string,
    updates: { content?: string; title?: string; format?: Document["format"] },
  ): Promise<Document> {
    const updated = await documentsApi.update(path, updates);
    this.documents = this.documents.map((d) => (d.path === path ? updated : d));
    // Refresh selection if the updated document is currently selected.
    if (this.selected?.path === path) {
      this.selected = updated;
    }
    return updated;
  }

  async deleteDocument(path: string): Promise<void> {
    await documentsApi.delete(path);
    this.documents = this.documents.filter((d) => d.path !== path);
    this.projectDocuments = this.projectDocuments.filter((d) => d.path !== path);
    if (this.selected?.path === path) {
      this.selected = null;
    }
    this._rebuildTree();
  }

  async fetchRevisions(documentId: string): Promise<DocumentRevision[]> {
    return documentsApi.revisions(documentId);
  }

  selectDocument(doc: Document | null): void {
    this.selected = doc;
  }

  getByPath(path: string): Document | null {
    return this.documents.find((d) => d.path === path) ?? null;
  }

  /**
   * Rebuild a simple path-based tree from the current flat document list.
   * The backend normally returns a tree on list(), but after local mutations
   * (create/delete) we can approximate it without an extra round-trip.
   * A full refetch replaces this approximation on the next fetchDocuments() call.
   */
  private _rebuildTree(): void {
    const root: DocumentTreeNode[] = [];
    const dirMap = new Map<string, DocumentTreeNode>();

    function ensureDir(segments: string[]): DocumentTreeNode[] {
      if (segments.length === 0) return root;
      const key = segments.join("/");
      if (dirMap.has(key)) return dirMap.get(key)!.children!;
      const parentChildren = ensureDir(segments.slice(0, -1));
      const node: DocumentTreeNode = {
        name: segments[segments.length - 1],
        path: key,
        type: "directory",
        children: [],
      };
      dirMap.set(key, node);
      parentChildren.push(node);
      return node.children!;
    }

    for (const doc of this.documents) {
      const parts = doc.path.split("/").filter(Boolean);
      const parentChildren = ensureDir(parts.slice(0, -1));
      parentChildren.push({
        name: parts[parts.length - 1] ?? doc.title,
        path: doc.path,
        type: "file",
      });
    }

    this.tree = root;
  }
}

export const documentsStore = new DocumentsStore();
