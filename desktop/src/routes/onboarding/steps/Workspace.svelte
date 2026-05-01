<script lang="ts">
  import { onMount } from 'svelte';
  import { isTauri } from '$lib/utils/platform';
  import { workspaces as workspacesApi, getToken } from '$api/client';
  import type { Workspace as BackendWorkspace } from '$api/types';
  import type { BizforgeWorkspace } from '$lib/types/bizforge';

  interface Props {
    workspacePath: string;
    workspaceName: string;
    workspaceDesc: string;
    existingWorkspaceId?: string;
    existsOnDisk?: boolean;
  }

  let {
    workspacePath = $bindable(),
    workspaceName = $bindable(),
    workspaceDesc = $bindable(),
    existingWorkspaceId = $bindable(''),
    existsOnDisk = $bindable(false),
  }: Props = $props();

  // Bindable props consumed by parent via bind: — suppress TS "declared but never read"
  void existingWorkspaceId;
  void existsOnDisk;

  let foundOnDisk = $state(false);
  let foundOnBackend = $state(false);
  let checkingWorkspace = $state(false);

  let lastAutoPath = $state(workspacePath);

  function parseFrontmatterField(md: string, field: string): string | undefined {
    const trimmed = md.trim();
    if (!trimmed.startsWith('---')) return undefined;
    const afterFirst = trimmed.slice(3);
    const end = afterFirst.indexOf('---');
    if (end === -1) return undefined;
    const yaml = afterFirst.slice(0, end);
    const match = yaml.match(new RegExp(`^${field}:\\s*(.+)$`, 'm'));
    return match?.[1]?.trim() ?? undefined;
  }

  async function resolveHomePath(p: string): Promise<string> {
    if (!p.startsWith('~')) return p;
    if (isTauri()) {
      try {
        const { homeDir } = await import('@tauri-apps/api/path');
        const home = await homeDir();
        return p.replace('~', home.replace(/\/$/, ''));
      } catch { /* fallback */ }
    }
    return p;
  }

  async function checkExistingWorkspace(path: string): Promise<void> {
    checkingWorkspace = true;
    foundOnDisk = false;
    foundOnBackend = false;
    existingWorkspaceId = '';
    existsOnDisk = false;

    try {
      // ── Tauri-first: scan the filesystem directly ──────────────────────
      if (isTauri()) {
        const resolved = await resolveHomePath(path);
        const bizforgePath = resolved.endsWith('.bizforge')
          ? resolved
          : resolved + '/.bizforge';

        try {
          const { invoke } = await import('@tauri-apps/api/core');
          const scan = await invoke<BizforgeWorkspace>('scan_bizforge_dir', {
            path: bizforgePath,
          });

          foundOnDisk = true;
          existsOnDisk = true;
          workspaceName = scan.name ?? workspaceName;

          const desc = scan.system_md !== null
            ? (parseFrontmatterField(scan.system_md, 'description') ?? '')
            : '';
          if (desc) workspaceDesc = desc;
        } catch {
          // .bizforge dir doesn't exist — that's fine, will create later
        }
      }

      // ── Backend lookup: match by path to get the workspace ID ──────────
      if (getToken() !== null) {
        try {
          const all = await workspacesApi.list();
          const resolved = await resolveHomePath(path);
          const normalizedPath = resolved.replace(/\/+$/, '');
          const match = all.find((w: BackendWorkspace) => {
            const wsPath = (w.path ?? w.directory ?? '').replace(/\/+$/, '');
            return wsPath === normalizedPath
              || wsPath === normalizedPath + '/.bizforge'
              || wsPath + '/.bizforge' === normalizedPath;
          }) ?? null;

          if (match !== null) {
            foundOnBackend = true;
            existingWorkspaceId = match.id;
            if (!foundOnDisk) {
              workspaceName = match.name;
              workspaceDesc = match.description ?? '';
            }
          }
        } catch {
          // Backend unavailable — rely on disk scan
        }
      }
    } finally {
      checkingWorkspace = false;
    }
  }

  const existingFound = $derived(foundOnDisk || foundOnBackend);

  $effect(() => {
    const p = workspacePath;
    if (p === lastAutoPath) return;
    lastAutoPath = p;

    if (!existingFound) {
      const parts = p.split('/');
      const last = parts[parts.length - 1];
      if (last && last !== '~' && last !== '.bizforge') {
        workspaceName = last.replace(/[-_]/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
      } else if (p.includes('.bizforge') || p === '~/.bizforge') {
        workspaceName = 'My Workspace';
      }
    }

    checkExistingWorkspace(p);
  });

  onMount(() => {
    checkExistingWorkspace(workspacePath);
  });

  async function choosePath() {
    if (isTauri()) {
      try {
        const { open } = await import('@tauri-apps/plugin-dialog');
        const selected = await open({ directory: true, multiple: false, title: 'Choose Workspace Directory' });
        if (selected && typeof selected === 'string') {
          workspacePath = selected;
        }
      } catch {
        // Dialog cancelled or unavailable
      }
      return;
    }

    const entered = prompt('Enter the full directory path for your workspace:', workspacePath);
    if (entered !== null && entered.trim().length > 0) {
      workspacePath = entered.trim();
    }
  }

  function dirBaseName(path: string): string {
    const trimmed = path.replace(/\/$/, '');
    return trimmed.split('/').pop() ?? trimmed;
  }
</script>

<div class="ob-step">
  <div class="ob-step-icon">
    <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" width="28" height="28">
      <path d="M3 7a2 2 0 012-2h3.586a1 1 0 01.707.293L10.707 6.7A1 1 0 0011.414 7H15a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2V7z"/>
    </svg>
  </div>
  <h1 class="ob-title">Workspace</h1>
  <p class="ob-subtitle">Where your agents live</p>

  <div class="ob-field">
    <label class="ob-label" for="ob-path">DIRECTORY PATH</label>
    <div class="ob-path-row">
      <input
        id="ob-path"
        class="ob-input ob-input--path"
        type="text"
        placeholder="~/.bizforge"
        autocomplete="off"
        bind:value={workspacePath}
      />
      <button class="ob-btn ob-btn--secondary ob-btn--sm" onclick={choosePath}>
        <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" width="14" height="14"><path d="M2 4a1 1 0 011-1h3l1.5 1.5H13a1 1 0 011 1V12a1 1 0 01-1 1H3a1 1 0 01-1-1V4z"/></svg>
        Choose
      </button>
    </div>
  </div>

  <div class="ob-field">
    <label class="ob-label" for="ob-ws-name">WORKSPACE NAME</label>
    <input
      id="ob-ws-name"
      class="ob-input"
      type="text"
      placeholder="My Workspace"
      autocomplete="off"
      bind:value={workspaceName}
      disabled={existingFound}
    />
  </div>

  <div class="ob-field">
    <label class="ob-label" for="ob-ws-desc">DESCRIPTION (OPTIONAL)</label>
    <input
      id="ob-ws-desc"
      class="ob-input"
      type="text"
      placeholder="What this workspace is for..."
      autocomplete="off"
      bind:value={workspaceDesc}
      disabled={existingFound}
    />
  </div>

  {#if checkingWorkspace}
    <div class="ob-status ob-status--checking">
      <span class="ob-status-dot ob-status-dot--checking"></span>
      Checking for existing workspace…
    </div>
  {:else if existingFound}
    <div class="ob-status ob-status--found">
      <span class="ob-status-dot ob-status-dot--found"></span>
      {#if foundOnDisk && foundOnBackend}
        Existing workspace found on disk and backend — will reconnect
      {:else if foundOnDisk}
        Existing .bizforge directory found — will register with backend
      {:else}
        Workspace found on backend — will reconnect
      {/if}
    </div>
  {:else}
    <div class="ob-tree-wrap">
      <p class="ob-label">WILL CREATE</p>
      <pre class="ob-tree">{dirBaseName(workspacePath) || '.bizforge'}/
├── .bizforge/
│   ├── workspace.json
│   ├── agents/
│   │   └── (agent configs)
│   ├── sessions/
│   └── logs/</pre>
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

  .ob-step-icon {
    width: 52px;
    height: 52px;
    border-radius: 14px;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid rgba(255, 255, 255, 0.08);
    display: flex;
    align-items: center;
    justify-content: center;
    color: rgba(255, 255, 255, 0.6);
    margin: 0 auto 1.25rem;
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

  .ob-input--path {
    flex: 1;
    font-family: 'SF Mono', 'Fira Code', monospace;
    font-size: 0.8125rem;
  }

  .ob-path-row {
    display: flex;
    gap: 0.5rem;
    align-items: center;
  }

  .ob-tree-wrap {
    width: 100%;
    margin-top: 0.25rem;
  }

  .ob-tree {
    background: rgba(0, 0, 0, 0.3);
    border: 1px solid rgba(255, 255, 255, 0.07);
    border-radius: 8px;
    padding: 0.875rem 1rem;
    font-size: 0.75rem;
    font-family: 'SF Mono', 'Fira Code', 'Cascadia Code', monospace;
    color: rgba(255, 255, 255, 0.45);
    margin: 0.375rem 0 0;
    line-height: 1.7;
    white-space: pre;
    overflow-x: auto;
  }

  .ob-btn {
    display: inline-flex;
    align-items: center;
    gap: 0.375rem;
    border-radius: 9999px;
    font-size: 0.875rem;
    font-weight: 500;
    cursor: pointer;
    border: none;
    padding: 0.625rem 1.25rem;
    transition: background 150ms ease, opacity 150ms ease, transform 150ms ease, box-shadow 150ms ease;
  }

  .ob-btn--secondary {
    background: rgba(255, 255, 255, 0.05);
    backdrop-filter: blur(10px);
    -webkit-backdrop-filter: blur(10px);
    color: #a1a1a6;
    border: 1px solid rgba(255, 255, 255, 0.1);
    box-shadow: 0 1px 0 0 rgba(255, 255, 255, 0.04) inset;
  }

  .ob-btn--secondary:not(:disabled):hover {
    background: rgba(255, 255, 255, 0.1);
    border-color: rgba(255, 255, 255, 0.15);
  }

  .ob-btn--sm {
    padding: 0.5rem 0.75rem;
    font-size: 0.8125rem;
    flex-shrink: 0;
  }

  .ob-status {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.8125rem;
    padding: 0.75rem 1rem;
    border-radius: 8px;
    margin-top: 0.25rem;
    width: 100%;
    box-sizing: border-box;
  }

  .ob-status--checking {
    color: rgba(255, 255, 255, 0.4);
    background: rgba(255, 255, 255, 0.03);
    border: 1px solid rgba(255, 255, 255, 0.06);
  }

  .ob-status--found {
    color: #4ade80;
    background: rgba(74, 222, 128, 0.06);
    border: 1px solid rgba(74, 222, 128, 0.15);
  }

  .ob-status-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    flex-shrink: 0;
  }

  .ob-status-dot--checking {
    background: rgba(255, 255, 255, 0.3);
    animation: pulse 1.2s ease-in-out infinite;
  }

  .ob-status-dot--found {
    background: #4ade80;
  }

  @keyframes pulse {
    0%, 100% { opacity: 0.3; }
    50% { opacity: 1; }
  }

  .ob-input:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
</style>
