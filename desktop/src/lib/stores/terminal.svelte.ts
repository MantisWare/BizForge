// src/lib/stores/terminal.svelte.ts

export interface TerminalTab {
  id: string;
  label: string;
  cwd: string;
  active: boolean;
  scrollback: string[];
}

function isTauriEnv(): boolean {
  return typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
}

class TerminalStore {
  tabs = $state<TerminalTab[]>([]);
  activeTabId = $state<string | null>(null);
  isTauri = $state(false);

  constructor() {
    this.isTauri = isTauriEnv();
  }

  get activeTab(): TerminalTab | undefined {
    return this.tabs.find((t) => t.id === this.activeTabId);
  }

  createTab(label?: string): string {
    const id = `term-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
    const home =
      typeof window !== "undefined"
        ? (window as unknown as Record<string, string>).__HOME_DIR__ ?? "~"
        : "~";

    this.tabs.push({
      id,
      label: label ?? `Terminal ${this.tabs.length + 1}`,
      cwd: home,
      active: true,
      scrollback: [],
    });

    if (this.activeTabId !== null) {
      const prev = this.tabs.find((t) => t.id === this.activeTabId);
      if (prev !== undefined) prev.active = false;
    }
    this.activeTabId = id;
    return id;
  }

  switchTab(id: string): void {
    for (const tab of this.tabs) {
      tab.active = tab.id === id;
    }
    this.activeTabId = id;
  }

  closeTab(id: string): void {
    const idx = this.tabs.findIndex((t) => t.id === id);
    if (idx === -1) return;
    this.tabs.splice(idx, 1);

    if (this.activeTabId === id) {
      const next = this.tabs[Math.min(idx, this.tabs.length - 1)];
      this.activeTabId = next?.id ?? null;
      if (next !== undefined) next.active = true;
    }
  }

  appendScrollback(tabId: string, data: string): void {
    const tab = this.tabs.find((t) => t.id === tabId);
    if (tab !== undefined) {
      tab.scrollback.push(data);
      if (tab.scrollback.length > 10_000) {
        tab.scrollback.splice(0, tab.scrollback.length - 10_000);
      }
    }
  }

  updateCwd(tabId: string, cwd: string): void {
    const tab = this.tabs.find((t) => t.id === tabId);
    if (tab !== undefined) tab.cwd = cwd;
  }
}

export const terminalStore = new TerminalStore();
