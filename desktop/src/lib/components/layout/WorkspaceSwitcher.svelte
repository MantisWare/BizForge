<!-- src/lib/components/layout/WorkspaceSwitcher.svelte -->
<script lang="ts">
  import { workspaceStore, type LocalWorkspace } from '$lib/stores/workspace.svelte';
  import { toastStore } from '$lib/stores/toasts.svelte';
  import { isTauri } from '$lib/utils/platform';

  let isOpen = $state(false);
  let isCreating = $state(false);
  let newName = $state('');
  let triggerEl = $state<HTMLButtonElement | null>(null);
  let panelEl = $state<HTMLDivElement | null>(null);

  // Delete confirmation modal state
  let deleteTarget = $state<LocalWorkspace | null>(null);
  let deleteAlsoFiles = $state(false);
  let isDeleting = $state(false);

  let active = $derived(workspaceStore.activeWorkspace);
  let workspaces = $derived(workspaceStore.workspaces);
  const healthReport = $derived(workspaceStore.healthReport);
  const healthErrors = $derived(healthReport?.issues.filter((i) => i.severity === 'error').length ?? 0);
  const healthWarnings = $derived(healthReport?.issues.filter((i) => i.severity === 'warning').length ?? 0);
  const healthColor = $derived(
    healthReport === null ? 'none'
    : healthErrors > 0 ? 'error'
    : healthWarnings > 0 ? 'warn'
    : 'ok'
  );

  /** Resolve the actual directory that will be deleted for the current deleteTarget */
  const deleteTargetDir = $derived.by(() => {
    if (deleteTarget === null) return '';
    const p = deleteTarget.path;
    return p.endsWith('.bizforge') ? p : p + '/.bizforge';
  });
  const deleteTargetDirShort = $derived(
    deleteTargetDir.replace(/^\/Users\/[^/]+/, '~').replace(/\/$/, ''),
  );

  /** Display-friendly name: if the stored name is just a path fragment like "~", derive a better label */
  function displayName(ws: { name: string; path: string }): string {
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

  /** Shorten path for display: collapse home dir to ~ */
  function shortPath(path: string): string {
    return path.replace(/^\/Users\/[^/]+/, '~').replace(/\/$/, '');
  }

  function toggle() {
    isOpen = !isOpen;
    if (!isOpen) isCreating = false;
  }

  async function selectWorkspace(id: string) {
    await workspaceStore.setActiveWorkspace(id);
    await workspaceStore.watchActive();
    isOpen = false;
  }

  async function submitCreate() {
    const name = newName.trim();
    if (!name) return;
    await workspaceStore.createWorkspace(name);
    isCreating = false;
    newName = '';
    isOpen = false;
  }

  /** Open Workspace — pick a folder with .bizforge/ in it */
  async function openWorkspace() {
    isOpen = false;
    if (!isTauri()) return;
    try {
      const { open } = await import('@tauri-apps/plugin-dialog');
      const selected = await open({ directory: true, multiple: false, title: 'Open Workspace' });
      if (!selected || typeof selected !== 'string') return;

      const scanned = await workspaceStore.scanWorkspace(selected);
      if (scanned === null) {
        return;
      }
      const wsEntry = {
        id: crypto.randomUUID(),
        path: selected,
        name: scanned.name || selected.split('/').pop() || 'Workspace',
        addedAt: new Date().toISOString(),
      };
      workspaceStore.addWorkspace(wsEntry);
      await workspaceStore.setActiveWorkspace(wsEntry.id);
      await workspaceStore.watchActive();
      toastStore.success('Workspace opened', `Loaded ${scanned.agents.length} agents`);
    } catch (e) {
      toastStore.error('Failed to open workspace', String(e));
    }
  }

  /** Create Workspace — pick a folder, scaffold .bizforge/ */
  async function createWorkspace() {
    isOpen = false;
    if (!isTauri()) return;
    try {
      const { open } = await import('@tauri-apps/plugin-dialog');
      const selected = await open({ directory: true, multiple: false, title: 'Create Workspace' });
      if (!selected || typeof selected !== 'string') return;

      const wsName = selected.split('/').pop() || 'New Workspace';
      const { invoke } = await import('@tauri-apps/api/core');
      await invoke('scaffold_bizforge_dir', {
        path: selected,
        name: wsName,
        description: null,
        agents: [],
      });

      const wsEntry = {
        id: crypto.randomUUID(),
        path: selected,
        name: wsName,
        addedAt: new Date().toISOString(),
      };
      workspaceStore.addWorkspace(wsEntry);
      await workspaceStore.setActiveWorkspace(wsEntry.id);
      await workspaceStore.watchActive();
      toastStore.success('Workspace created', `${wsName} is ready`);
    } catch (e) {
      toastStore.error('Failed to create workspace', String(e));
    }
  }

  function promptDelete(e: MouseEvent, ws: LocalWorkspace) {
    e.stopPropagation();
    deleteTarget = ws;
    deleteAlsoFiles = false;
    isDeleting = false;
  }

  function cancelDelete() {
    deleteTarget = null;
    deleteAlsoFiles = false;
    isDeleting = false;
  }

  async function confirmDelete() {
    if (deleteTarget === null || isDeleting) return;
    isDeleting = true;
    const wsName = displayName(deleteTarget);

    const resolvedDir = deleteTargetDir;

    try {
      if (deleteAlsoFiles && isTauri()) {
        const { invoke } = await import('@tauri-apps/api/core');
        try {
          await invoke('remove_dir_recursive', { path: resolvedDir });
        } catch (fsErr) {
          console.warn('[bizforge:workspace] Could not delete directory:', fsErr);
          toastStore.warning('Files not deleted', `Could not remove ${resolvedDir}. The workspace was still removed from the list.`);
        }
      }

      await workspaceStore.removeWorkspace(deleteTarget.id);
      toastStore.success(
        'Workspace removed',
        deleteAlsoFiles
          ? `"${wsName}" removed and ${deleteTargetDirShort}/ files deleted`
          : `"${wsName}" removed from list (files kept on disk)`,
      );
    } catch (err) {
      toastStore.error('Delete failed', String(err));
    } finally {
      deleteTarget = null;
      deleteAlsoFiles = false;
      isDeleting = false;
    }
  }

  function handleDeleteKeydown(e: KeyboardEvent) {
    if (e.key === 'Escape') cancelDelete();
  }

  function handleCreateKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter') { e.preventDefault(); void submitCreate(); }
    if (e.key === 'Escape') { isCreating = false; }
  }

  function handleClickOutside(e: MouseEvent) {
    if (!isOpen) return;
    const target = e.target as Node;
    if (!triggerEl?.contains(target) && !panelEl?.contains(target)) {
      isOpen = false;
      isCreating = false;
    }
  }
</script>

<svelte:window onclick={handleClickOutside} />

<div class="ws-root">
  <button
    bind:this={triggerEl}
    class="ws-trigger"
    onclick={toggle}
    aria-haspopup="listbox"
    aria-expanded={isOpen}
    aria-label="Switch workspace"
  >
    <span class="ws-trigger-icon" aria-hidden="true">
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
        <path d="M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12 18s-8.25-1.847-8.25-4.125v-3.75m16.5 0c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125" />
      </svg>
      {#if healthColor !== 'none'}
        <span
          class="ws-health-dot"
          class:ws-health-dot--ok={healthColor === 'ok'}
          class:ws-health-dot--warn={healthColor === 'warn'}
          class:ws-health-dot--error={healthColor === 'error'}
          title={healthColor === 'ok' ? 'Workspace healthy' : `${healthErrors} error${healthErrors !== 1 ? 's' : ''}, ${healthWarnings} warning${healthWarnings !== 1 ? 's' : ''}`}
        ></span>
      {/if}
    </span>
    <span class="ws-trigger-label">
      {#if active}
        <span class="ws-trigger-name">{displayName(active)}</span>
        <span class="ws-trigger-sep">&middot;</span>
        <span class="ws-trigger-path">{shortPath(active.path)}</span>
      {:else}
        <span class="ws-trigger-name">No Workspace</span>
      {/if}
    </span>
    <span class="ws-chevron" class:open={isOpen} aria-hidden="true">
      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M19 9l-7 7-7-7" />
      </svg>
    </span>
  </button>

  {#if deleteTarget !== null}
    <!-- svelte-ignore a11y_no_noninteractive_element_interactions a11y_click_events_have_key_events a11y_no_static_element_interactions -->
    <div class="ws-modal-backdrop" role="dialog" aria-modal="true" aria-label="Delete workspace confirmation" tabindex="-1" onkeydown={handleDeleteKeydown}>
      <!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
      <div class="ws-modal" onclick={(e) => e.stopPropagation()}>
        <div class="ws-modal-header">
          <svg class="ws-modal-icon" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z" />
          </svg>
          <h3 class="ws-modal-title">Remove Workspace</h3>
        </div>

        <p class="ws-modal-body">
          Are you sure you want to remove <strong>{displayName(deleteTarget)}</strong>?
        </p>
        <p class="ws-modal-path">{deleteTarget.path}</p>

        <label class="ws-modal-checkbox">
          <input type="checkbox" bind:checked={deleteAlsoFiles} />
          <span class="ws-modal-checkbox-label">
            Also delete <code>{deleteTargetDirShort}/</code> files from disk
          </span>
        </label>

        {#if deleteAlsoFiles}
          <div class="ws-modal-warning">
            This will permanently delete the <code>{deleteTargetDirShort}/</code> directory including all agent definitions, schedules, skills, and workspace configuration. Your project files outside this directory will not be touched.
          </div>
        {:else}
          <div class="ws-modal-info">
            The workspace will be removed from BizForge's list. All files on disk will remain untouched — you can re-open it later.
          </div>
        {/if}

        <div class="ws-modal-actions">
          <button class="ws-modal-btn ws-modal-btn--cancel" onclick={cancelDelete} disabled={isDeleting}>
            Cancel
          </button>
          <button
            class="ws-modal-btn"
            class:ws-modal-btn--danger={deleteAlsoFiles}
            class:ws-modal-btn--confirm={!deleteAlsoFiles}
            onclick={confirmDelete}
            disabled={isDeleting}
          >
            {#if isDeleting}
              Removing…
            {:else if deleteAlsoFiles}
              Delete Workspace & Files
            {:else}
              Remove from List
            {/if}
          </button>
        </div>
      </div>
    </div>
  {/if}

  {#if isOpen}
    <div
      bind:this={panelEl}
      class="ws-panel"
      role="listbox"
      aria-label="Workspaces"
    >
      {#if workspaces.length > 0}
        <div class="ws-list">
          {#each workspaces as ws (ws.id)}
            <div class="ws-item-wrapper" role="option" aria-selected={ws.id === active?.id}>
              <button
                class="ws-item"
                class:active={ws.id === active?.id}
                onclick={() => selectWorkspace(ws.id)}
              >
                <span class="ws-item-row">
                  {#if ws.id === active?.id}
                    <span class="ws-item-check" aria-hidden="true">
                      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                        <path d="M5 13l4 4L19 7" />
                      </svg>
                    </span>
                  {:else}
                    <span class="ws-item-check-placeholder" aria-hidden="true"></span>
                  {/if}
                  <span class="ws-item-text">
                    <span class="ws-item-name">{displayName(ws)}</span>
                    <span class="ws-item-path">{shortPath(ws.path)}</span>
                  </span>
                </span>
              </button>
              <button
                class="ws-item-delete"
                title="Remove workspace"
                aria-label="Remove workspace {displayName(ws)}"
                onclick={(e) => promptDelete(e, ws)}
              >
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                  <path d="M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 00-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 013.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 00-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 00-7.5 0" />
                </svg>
              </button>
            </div>
          {/each}
        </div>
      {:else}
        <div class="ws-empty">No workspaces</div>
      {/if}

      <div class="ws-actions">
        {#if isCreating}
          <div class="ws-create-form">
            <!-- svelte-ignore a11y_autofocus -->
            <input
              class="ws-create-input"
              type="text"
              placeholder="Workspace name…"
              bind:value={newName}
              onkeydown={handleCreateKeydown}
              autofocus
            />
            <button class="ws-create-btn" onclick={submitCreate} disabled={!newName.trim()}>
              Create
            </button>
          </div>
        {:else}
          <button class="ws-action-item" onclick={openWorkspace}>
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <path d="M3.75 9.776c.112-.017.227-.026.344-.026h15.812c.117 0 .232.009.344.026m-16.5 0a2.25 2.25 0 00-1.883 2.542l.857 6a2.25 2.25 0 002.227 1.932H19.05a2.25 2.25 0 002.227-1.932l.857-6a2.25 2.25 0 00-1.883-2.542m-16.5 0V6A2.25 2.25 0 016 3.75h3.879a1.5 1.5 0 011.06.44l2.122 2.12a1.5 1.5 0 001.06.44H18A2.25 2.25 0 0120.25 9v.776" />
            </svg>
            Open Workspace…
          </button>
          <button class="ws-action-item" onclick={createWorkspace}>
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <path d="M12 4.5v15m7.5-7.5h-15" />
            </svg>
            Create Workspace
          </button>
        {/if}
      </div>
    </div>
  {/if}
</div>

<style>
  .ws-root {
    position: relative;
  }

  .ws-trigger {
    display: flex;
    align-items: center;
    gap: 6px;
    width: 100%;
    height: 28px;
    padding: 0 8px;
    border: none;
    background: transparent;
    color: var(--text-secondary);
    cursor: pointer;
    border-radius: var(--radius-xs);
    font-size: 13px;
    text-align: left;
    transition: background 120ms ease, color 120ms ease;
  }

  .ws-trigger:hover {
    background: var(--bg-surface);
    color: var(--text-primary);
  }

  .ws-trigger-icon {
    flex-shrink: 0;
    color: var(--text-tertiary);
    display: flex;
    position: relative;
  }

  .ws-health-dot {
    position: absolute;
    top: -2px;
    right: -3px;
    width: 7px;
    height: 7px;
    border-radius: 50%;
    border: 1.5px solid var(--bg-primary);
  }

  .ws-health-dot--ok {
    background: #22c55e;
  }

  .ws-health-dot--warn {
    background: #eab308;
  }

  .ws-health-dot--error {
    background: #ef4444;
  }

  .ws-trigger-label {
    flex: 1;
    min-width: 0;
    display: flex;
    align-items: center;
    gap: 5px;
    overflow: hidden;
  }

  .ws-trigger-name {
    font-weight: 600;
    font-size: 13px;
    color: var(--text-primary);
    white-space: nowrap;
    flex-shrink: 0;
  }

  .ws-trigger-sep {
    color: var(--text-muted);
    flex-shrink: 0;
    font-size: 11px;
  }

  .ws-trigger-path {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 11px;
    color: var(--text-tertiary);
    font-weight: 400;
  }

  .ws-chevron {
    flex-shrink: 0;
    color: var(--text-tertiary);
    display: flex;
    transition: transform 160ms ease;
  }

  .ws-chevron.open {
    transform: rotate(180deg);
  }

  .ws-panel {
    position: absolute;
    top: calc(100% + 4px);
    left: 0;
    right: 0;
    z-index: 200;
    background: var(--bg-secondary);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-md);
    backdrop-filter: blur(20px);
    -webkit-backdrop-filter: blur(20px);
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.4);
    overflow: hidden;
  }

  .ws-list {
    padding: 4px;
    display: flex;
    flex-direction: column;
    gap: 1px;
    max-height: 200px;
    overflow-y: auto;
  }

  .ws-item {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    width: 100%;
    padding: 6px 8px;
    border: none;
    background: transparent;
    color: var(--text-primary);
    cursor: pointer;
    border-radius: var(--radius-xs);
    text-align: left;
    transition: background 100ms ease;
  }

  .ws-item:hover {
    background: var(--bg-surface);
  }

  .ws-item.active {
    background: var(--bg-elevated);
  }

  .ws-item-row {
    display: flex;
    align-items: center;
    gap: 8px;
    width: 100%;
  }

  .ws-item-check {
    flex-shrink: 0;
    width: 16px;
    height: 16px;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--accent-primary, #3b82f6);
  }

  .ws-item-check-placeholder {
    flex-shrink: 0;
    width: 16px;
    height: 16px;
  }

  .ws-item-text {
    display: flex;
    flex-direction: column;
    gap: 1px;
    min-width: 0;
    flex: 1;
  }

  .ws-item-name {
    font-size: 13px;
    font-weight: 500;
    color: var(--text-primary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .ws-item-path {
    font-size: 11px;
    color: var(--text-tertiary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .ws-empty {
    padding: 12px 8px;
    font-size: 12px;
    color: var(--text-tertiary);
    text-align: center;
  }

  .ws-actions {
    border-top: 1px solid var(--border-default);
    padding: 4px;
    display: flex;
    flex-direction: column;
    gap: 1px;
  }

  .ws-action-item {
    display: flex;
    align-items: center;
    gap: 7px;
    width: 100%;
    padding: 6px 8px;
    border: none;
    background: transparent;
    color: var(--text-secondary);
    cursor: pointer;
    border-radius: var(--radius-xs);
    font-size: 12px;
    text-align: left;
    transition: background 100ms ease, color 100ms ease;
  }

  .ws-action-item:hover {
    background: var(--bg-surface);
    color: var(--text-primary);
  }

  .ws-create-form {
    display: flex;
    gap: 4px;
    padding: 4px;
  }

  .ws-create-input {
    flex: 1;
    padding: 5px 8px;
    border: 1px solid var(--border-default);
    border-radius: var(--radius-xs);
    background: var(--bg-primary);
    color: var(--text-primary);
    font-size: 12px;
    outline: none;
  }

  .ws-create-input:focus {
    border-color: var(--border-active, #3b82f6);
  }

  .ws-create-btn {
    padding: 5px 10px;
    border: none;
    border-radius: var(--radius-xs);
    background: var(--accent-primary, #3b82f6);
    color: #fff;
    font-size: 12px;
    cursor: pointer;
  }

  .ws-create-btn:disabled {
    opacity: 0.4;
    cursor: default;
  }

  /* Workspace item wrapper — holds the item button + hover-reveal delete */
  .ws-item-wrapper {
    display: flex;
    align-items: stretch;
    border-radius: var(--radius-xs);
    transition: background 100ms ease;
    position: relative;
  }

  .ws-item-wrapper:hover {
    background: var(--bg-surface);
  }

  .ws-item-wrapper .ws-item {
    flex: 1;
    min-width: 0;
  }

  .ws-item-wrapper .ws-item:hover {
    background: transparent;
  }

  .ws-item-delete {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 28px;
    flex-shrink: 0;
    border: none;
    background: transparent;
    color: var(--text-muted);
    cursor: pointer;
    border-radius: var(--radius-xs);
    opacity: 0;
    transition: opacity 120ms ease, color 120ms ease, background 120ms ease;
  }

  .ws-item-wrapper:hover .ws-item-delete {
    opacity: 1;
  }

  .ws-item-delete:hover {
    color: #ef4444;
    background: rgba(239, 68, 68, 0.1);
  }

  /* Confirmation modal */
  .ws-modal-backdrop {
    position: fixed;
    inset: 0;
    z-index: 1000;
    background: rgba(0, 0, 0, 0.55);
    display: flex;
    align-items: center;
    justify-content: center;
    backdrop-filter: blur(4px);
    -webkit-backdrop-filter: blur(4px);
  }

  .ws-modal {
    background: var(--bg-secondary);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-lg, 12px);
    padding: 20px;
    width: 380px;
    max-width: 90vw;
    box-shadow: 0 16px 48px rgba(0, 0, 0, 0.5);
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .ws-modal-header {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .ws-modal-icon {
    color: #eab308;
    flex-shrink: 0;
  }

  .ws-modal-title {
    font-size: 15px;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0;
  }

  .ws-modal-body {
    font-size: 13px;
    color: var(--text-secondary);
    margin: 0;
    line-height: 1.5;
  }

  .ws-modal-path {
    font-size: 11px;
    color: var(--text-tertiary);
    font-family: var(--font-mono, monospace);
    margin: -4px 0 0;
    word-break: break-all;
  }

  .ws-modal-checkbox {
    display: flex;
    align-items: center;
    gap: 8px;
    cursor: pointer;
    padding: 8px;
    border-radius: var(--radius-xs);
    transition: background 100ms ease;
    margin: 4px 0;
  }

  .ws-modal-checkbox:hover {
    background: var(--bg-surface);
  }

  .ws-modal-checkbox input[type="checkbox"] {
    accent-color: #ef4444;
    width: 14px;
    height: 14px;
    flex-shrink: 0;
  }

  .ws-modal-checkbox-label {
    font-size: 13px;
    color: var(--text-primary);
  }

  .ws-modal-checkbox-label code {
    font-size: 12px;
    padding: 1px 4px;
    background: var(--bg-elevated);
    border-radius: 3px;
    color: var(--text-secondary);
  }

  .ws-modal-warning {
    font-size: 12px;
    color: #fbbf24;
    background: rgba(251, 191, 36, 0.08);
    border: 1px solid rgba(251, 191, 36, 0.2);
    border-radius: var(--radius-xs);
    padding: 8px 10px;
    line-height: 1.5;
  }

  .ws-modal-warning code {
    font-size: 11px;
    padding: 1px 3px;
    background: rgba(251, 191, 36, 0.12);
    border-radius: 3px;
  }

  .ws-modal-info {
    font-size: 12px;
    color: var(--text-tertiary);
    background: var(--bg-surface);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-xs);
    padding: 8px 10px;
    line-height: 1.5;
  }

  .ws-modal-actions {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
    margin-top: 4px;
  }

  .ws-modal-btn {
    padding: 6px 14px;
    border: none;
    border-radius: var(--radius-xs);
    font-size: 13px;
    font-weight: 500;
    cursor: pointer;
    transition: background 120ms ease, opacity 120ms ease;
  }

  .ws-modal-btn:disabled {
    opacity: 0.5;
    cursor: default;
  }

  .ws-modal-btn--cancel {
    background: var(--bg-surface);
    color: var(--text-secondary);
    border: 1px solid var(--border-default);
  }

  .ws-modal-btn--cancel:hover:not(:disabled) {
    background: var(--bg-elevated);
    color: var(--text-primary);
  }

  .ws-modal-btn--confirm {
    background: var(--accent-primary, #f26522);
    color: #fff;
  }

  .ws-modal-btn--confirm:hover:not(:disabled) {
    opacity: 0.9;
  }

  .ws-modal-btn--danger {
    background: #ef4444;
    color: #fff;
  }

  .ws-modal-btn--danger:hover:not(:disabled) {
    background: #dc2626;
  }
</style>
