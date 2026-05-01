// src/lib/stores/skills.svelte.ts
import type { Skill, SkillCategory, SkillSource } from "$api/types";
import { skills as skillsApi } from "$api/client";
import type { LibrarySkill } from "$lib/api/mock/library/types";
import { toastStore } from "./toasts.svelte";

class SkillsStore {
  skills = $state<Skill[]>([]);
  loading = $state(false);
  error = $state<string | null>(null);

  searchQuery = $state("");

  // Derived
  enabledCount = $derived(this.skills.filter((s) => s.enabled).length);
  totalCount = $derived(this.skills.length);

  filteredSkills = $derived.by(() => {
    const q = this.searchQuery.toLowerCase().trim();
    const filtered = q
      ? this.skills.filter((s) => s.name.toLowerCase().includes(q))
      : this.skills;
    return [...filtered].sort((a, b) => a.name.localeCompare(b.name));
  });

  async fetchSkills(workspaceId?: string): Promise<void> {
    this.loading = true;
    try {
      this.skills = await skillsApi.list(workspaceId);
      this.error = null;
    } catch (e) {
      const msg = (e as Error).message;
      this.error = msg;
      if (!msg.includes("not_found") && !msg.includes("unauthorized")) {
        toastStore.error("Failed to load skills", msg);
      }
    } finally {
      this.loading = false;
    }
  }

  async toggleSkill(id: string): Promise<void> {
    const previous = this.skills;
    this.skills = this.skills.map((s) =>
      s.id === id ? { ...s, enabled: !s.enabled } : s,
    );
    try {
      const updated = await skillsApi.toggle(id);
      this.skills = this.skills.map((s) => (s.id === id ? updated : s));
      this.error = null;
    } catch (e) {
      this.skills = previous;
      const msg = (e as Error).message;
      this.error = msg;
      toastStore.error("Failed to toggle skill", msg);
    }
  }

  /**
   * Install library skills into the workspace.
   * Skills already present get bulk-enabled; new skills are imported.
   */
  async installFromLibrary(librarySkills: LibrarySkill[]): Promise<number> {
    if (librarySkills.length === 0) return 0;

    const existingIds = new Set(this.skills.map((s) => s.id));
    const toEnable: string[] = [];
    const toImport: LibrarySkill[] = [];

    for (const ls of librarySkills) {
      if (existingIds.has(ls.id)) {
        const existing = this.skills.find((s) => s.id === ls.id);
        if (existing !== undefined && !existing.enabled) {
          toEnable.push(ls.id);
        }
      } else {
        toImport.push(ls);
      }
    }

    try {
      if (toEnable.length > 0) {
        await skillsApi.bulkEnable(toEnable);
        this.skills = this.skills.map((s) =>
          toEnable.includes(s.id) ? { ...s, enabled: true } : s,
        );
      }

      for (const ls of toImport) {
        await skillsApi.importSkill({
          id: ls.id,
          name: ls.name,
          description: ls.description,
          category: ls.category,
          version: ls.version,
        });

        const newSkill: Skill = {
          id: ls.id,
          name: ls.name,
          description: ls.description,
          category: ls.category as SkillCategory,
          source: "library" as SkillSource,
          enabled: true,
          triggers: [],
          version: ls.version,
          author: "Library",
        };
        this.skills = [...this.skills, newSkill];
      }

      this.error = null;
      const total = toEnable.length + toImport.length;
      if (total > 0) {
        toastStore.success(
          "Skills installed",
          `${total} skill${total === 1 ? "" : "s"} added to workspace.`,
        );
      }
      return total;
    } catch (e) {
      const msg = (e as Error).message;
      this.error = msg;
      toastStore.error("Failed to install skills", msg);
      return 0;
    }
  }
}

export const skillsStore = new SkillsStore();
