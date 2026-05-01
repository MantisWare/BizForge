<script lang="ts">
  import type { AdapterType } from '$lib/stores/onboarding.svelte';
  import { isTauri } from '$lib/utils/platform';
  import { browser } from '$app/environment';
  import type { LocalWorkspace } from '$lib/stores/workspace.svelte';

  interface Props {
    displayName: string;
    onImport: (result: {
      workspacePath: string;
      workspaceName: string;
      adapter: AdapterType;
      teamTemplate: 'solo' | 'dev-team' | 'research' | 'custom';
      agents: import('$lib/stores/onboarding.svelte').AgentTemplateData[];
      jumpToStep: number;
    }) => void;
    onOpenRecent?: (workspace: LocalWorkspace) => void;
  }

  let { displayName = $bindable(), onImport, onOpenRecent }: Props = $props();

  const MAX_RECENT = 5;

  const recentWorkspaces: LocalWorkspace[] = (() => {
    if (!browser) return [];
    try {
      const raw = localStorage.getItem('bizforge-workspaces');
      if (raw === null) return [];
      const all = JSON.parse(raw) as LocalWorkspace[];
      return [...all]
        .sort((a, b) => new Date(b.addedAt).getTime() - new Date(a.addedAt).getTime())
        .slice(0, MAX_RECENT);
    } catch {
      return [];
    }
  })();

  function shortPath(path: string): string {
    return path.replace(/^\/Users\/[^/]+/, '~').replace(/\/$/, '');
  }

  function workspaceDisplayName(ws: LocalWorkspace): string {
    const name = ws.name?.trim();
    if (name === '~' || name === '/') return '~ HOME/ROOT';
    if (name !== undefined && name !== '' && !name.startsWith('~/.')) {
      return name;
    }
    const segments = ws.path.replace(/\/+$/, '').split('/');
    const last = segments[segments.length - 1];
    if (last === '.bizforge' && segments.length >= 2) {
      return segments[segments.length - 2] ?? 'Workspace';
    }
    return last ?? 'Workspace';
  }

  async function importWorkspace() {
    if (!isTauri()) {
      onImport({ workspacePath: '', workspaceName: '', adapter: 'osa', teamTemplate: 'custom', agents: [], jumpToStep: 3 });
      return;
    }
    try {
      const { open } = await import('@tauri-apps/plugin-dialog');
      const selected = await open({ directory: true, multiple: false, title: 'Import Existing Workspace' });
      if (!selected || typeof selected !== 'string') return;

      const { invoke } = await import('@tauri-apps/api/core');
      try {
        const workspace = await invoke('scan_bizforge_dir', { path: selected }) as {
          name?: string;
          agents?: { id: string; name: string; adapter: string; role: string }[];
        };

        let adapter: AdapterType = 'osa';
        let agents: import('$lib/stores/onboarding.svelte').AgentTemplateData[] = [];

        if (workspace.agents && workspace.agents.length > 0) {
          adapter = (workspace.agents[0].adapter?.replace(/_/g, '-') as AdapterType) ?? 'osa';
          agents = workspace.agents.map(a => ({
            id: a.id,
            name: a.name,
            emoji: 'robot',
            role: a.role || 'engineer',
            adapter: a.adapter || 'osa',
            skills: [],
          }));
        }

        onImport({
          workspacePath: selected,
          workspaceName: workspace.name ?? '',
          adapter,
          teamTemplate: 'custom',
          agents,
          jumpToStep: 6,
        });
      } catch {
        onImport({ workspacePath: selected, workspaceName: '', adapter: 'osa', teamTemplate: 'custom', agents: [], jumpToStep: 3 });
      }
    } catch {
      // Dialog cancelled or unavailable — no action needed
    }
  }
</script>

<div class="ob-step">
  <div class="ob-logo-wrap">
    <img class="ob-logo-img" src="/OSAIconLogo.png" alt="BizForge" width="120" height="120" />
  </div>
  <h1 class="ob-title">Welcome to Bizforge</h1>
  <p class="ob-subtitle">Your AI agent command center</p>
  <div class="ob-field">
    <label class="ob-label" for="ob-name">YOUR NAME</label>
    <input
      id="ob-name"
      class="ob-input"
      type="text"
      placeholder="e.g. Waldo"
      autocomplete="off"
      bind:value={displayName}
    />
  </div>
  <div class="ob-import-section">
    <span class="ob-import-divider">
      <span class="ob-import-divider-line"></span>
      <span class="ob-import-divider-text">or</span>
      <span class="ob-import-divider-line"></span>
    </span>
    <button class="ob-import-btn" onclick={importWorkspace}>
      <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" width="16" height="16"><path d="M3 10v5a2 2 0 002 2h10a2 2 0 002-2v-5"/><path d="M10 3v10M6 7l4-4 4 4"/></svg>
      Import existing workspace
    </button>
    <p class="ob-import-hint">Have a .bizforge/ workspace already? Import it and we'll detect your config.</p>
  </div>

  {#if recentWorkspaces.length > 0}
    <div class="ob-recent-section">
      <span class="ob-import-divider">
        <span class="ob-import-divider-line"></span>
        <span class="ob-import-divider-text">recent workspaces</span>
        <span class="ob-import-divider-line"></span>
      </span>
      <div class="ob-recent-list">
        {#each recentWorkspaces as ws (ws.id)}
          <button
            class="ob-recent-item"
            onclick={() => onOpenRecent?.(ws)}
            title={ws.path}
          >
            <span class="ob-recent-icon" aria-hidden="true">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" width="14" height="14">
                <path d="M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375" />
              </svg>
            </span>
            <span class="ob-recent-text">
              <span class="ob-recent-name">{workspaceDisplayName(ws)}</span>
              <span class="ob-recent-path">{shortPath(ws.path)}</span>
            </span>
            <span class="ob-recent-arrow" aria-hidden="true">
              <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" width="12" height="12"><path d="M6 4l4 4-4 4"/></svg>
            </span>
          </button>
        {/each}
      </div>
    </div>
  {/if}
</div>

<style>
  .ob-step {
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: center;
    flex: 1;
    gap: 0;
  }

  .ob-logo-wrap {
    width: 120px;
    height: 120px;
    margin: 0 auto 1.25rem;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .ob-logo-img {
    width: 120px;
    height: 120px;
    object-fit: contain;
  }

  .ob-title {
    font-size: 1.625rem;
    font-weight: 700;
    color: #ffffff;
    margin: 0 0 0.375rem;
    letter-spacing: -0.02em;
  }

  .ob-subtitle {
    font-size: 0.875rem;
    color: rgba(255, 255, 255, 0.45);
    margin: 0 0 1.75rem;
  }

  .ob-label {
    display: block;
    font-size: 0.6875rem;
    font-weight: 600;
    letter-spacing: 0.08em;
    color: rgba(255, 255, 255, 0.35);
    margin-bottom: 0.375rem;
    text-align: left;
  }

  .ob-field {
    width: 100%;
    text-align: left;
    margin-bottom: 1rem;
  }

  .ob-input {
    width: 100%;
    background: rgba(255, 255, 255, 0.04);
    border: 1px solid rgba(255, 255, 255, 0.1);
    border-radius: 8px;
    padding: 0.625rem 0.875rem;
    font-size: 0.9375rem;
    color: #f0f0f0;
    outline: none;
    transition: border-color 150ms ease;
    box-sizing: border-box;
  }

  .ob-input::placeholder {
    color: rgba(255, 255, 255, 0.2);
  }

  .ob-input:focus {
    border-color: rgba(242, 101, 34, 0.5);
  }

  .ob-import-section {
    width: 100%;
    max-width: 320px;
    margin-top: 1.25rem;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.5rem;
  }

  .ob-import-divider {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    width: 100%;
    margin-bottom: 0.25rem;
  }

  .ob-import-divider-line {
    flex: 1;
    height: 1px;
    background: rgba(255, 255, 255, 0.08);
  }

  .ob-import-divider-text {
    font-size: 0.75rem;
    color: rgba(255, 255, 255, 0.3);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .ob-import-btn {
    display: inline-flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.5rem 1rem;
    border-radius: 9999px;
    border: 1px solid rgba(255, 255, 255, 0.1);
    background: rgba(255, 255, 255, 0.04);
    color: rgba(255, 255, 255, 0.6);
    font-size: 0.8125rem;
    font-weight: 500;
    cursor: pointer;
    transition: all 150ms ease;
  }

  .ob-import-btn:hover {
    background: rgba(255, 255, 255, 0.08);
    color: rgba(255, 255, 255, 0.85);
    border-color: rgba(255, 255, 255, 0.18);
  }

  .ob-import-hint {
    font-size: 0.6875rem;
    color: rgba(255, 255, 255, 0.25);
    text-align: center;
    margin: 0;
    line-height: 1.4;
  }

  /* ─── Recent workspaces ───────────────────────────────────────────── */

  .ob-recent-section {
    width: 100%;
    margin-top: 1.25rem;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.5rem;
  }

  .ob-recent-list {
    width: 100%;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .ob-recent-item {
    display: flex;
    align-items: center;
    gap: 0.625rem;
    width: 100%;
    padding: 0.5rem 0.75rem;
    border-radius: 8px;
    border: 1px solid transparent;
    background: rgba(255, 255, 255, 0.03);
    color: rgba(255, 255, 255, 0.6);
    font-size: 0.8125rem;
    cursor: pointer;
    text-align: left;
    transition: all 150ms ease;
  }

  .ob-recent-item:hover {
    background: rgba(255, 255, 255, 0.07);
    border-color: rgba(255, 255, 255, 0.1);
    color: rgba(255, 255, 255, 0.9);
  }

  .ob-recent-icon {
    flex-shrink: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    width: 28px;
    height: 28px;
    border-radius: 6px;
    background: rgba(242, 101, 34, 0.12);
    color: rgba(242, 101, 34, 0.7);
  }

  .ob-recent-item:hover .ob-recent-icon {
    background: rgba(242, 101, 34, 0.18);
    color: #f26522;
  }

  .ob-recent-text {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 1px;
  }

  .ob-recent-name {
    font-size: 0.8125rem;
    font-weight: 500;
    color: rgba(255, 255, 255, 0.8);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .ob-recent-item:hover .ob-recent-name {
    color: #ffffff;
  }

  .ob-recent-path {
    font-size: 0.6875rem;
    color: rgba(255, 255, 255, 0.3);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .ob-recent-arrow {
    flex-shrink: 0;
    display: flex;
    color: rgba(255, 255, 255, 0.15);
    transition: color 150ms ease, transform 150ms ease;
  }

  .ob-recent-item:hover .ob-recent-arrow {
    color: rgba(242, 101, 34, 0.6);
    transform: translateX(2px);
  }
</style>
