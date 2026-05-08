<!-- src/lib/components/layout/LogPanel.svelte
     Collapsible bottom panel that tails .bizforge/logs/ files in real-time. -->
<script lang="ts">
  import { onMount } from 'svelte';
  import { isTauri } from '$lib/utils/platform';
  import { workspaceStore } from '$lib/stores/workspace.svelte';

  interface LogEntry {
    source: string;
    lines: string[];
    size_bytes: number;
  }

  interface LogSnapshot {
    entries: LogEntry[];
    log_dir: string;
  }

  interface Props {
    onClose: () => void;
  }

  let { onClose }: Props = $props();

  let snapshot = $state<LogSnapshot | null>(null);
  let loading = $state(true);
  let error = $state<string | null>(null);
  let activeSource = $state<string | null>(null);
  let autoScroll = $state(true);
  let panelHeight = $state(280);
  let resizing = $state(false);
  let logContainerEl = $state<HTMLElement | null>(null);

  const sources = $derived(snapshot?.entries.map((e) => e.source) ?? []);
  const activeEntry = $derived(
    snapshot?.entries.find((e) => e.source === activeSource) ?? snapshot?.entries[0] ?? null,
  );

  async function fetchLogs(): Promise<void> {
    const ws = workspaceStore.activeWorkspace;
    if (ws === null && !isTauri()) {
      error = 'No active workspace';
      loading = false;
      return;
    }

    try {
      if (isTauri()) {
        const { invoke } = await import('@tauri-apps/api/core');
        let wsPath = ws?.path ?? '.';
        if (wsPath.endsWith('.bizforge')) {
          wsPath = wsPath.replace(/\/?\.bizforge$/, '');
        }
        snapshot = await invoke<LogSnapshot>('read_log_files', {
          workspacePath: wsPath,
          tailLines: 300,
        });
        if (activeSource === null && snapshot.entries.length > 0) {
          activeSource = snapshot.entries[0].source;
        }
        error = null;
      } else {
        error = 'Log tailing requires the desktop app';
      }
    } catch (e) {
      error = (e as Error).message ?? String(e);
    } finally {
      loading = false;
    }
  }

  function scrollToBottom(): void {
    if (autoScroll && logContainerEl !== null) {
      logContainerEl.scrollTop = logContainerEl.scrollHeight;
    }
  }

  function handleScroll(): void {
    if (logContainerEl === null) return;
    const { scrollTop, scrollHeight, clientHeight } = logContainerEl;
    autoScroll = scrollHeight - scrollTop - clientHeight < 40;
  }

  function startResize(e: MouseEvent): void {
    e.preventDefault();
    resizing = true;
    const startY = e.clientY;
    const startHeight = panelHeight;

    function onMove(ev: MouseEvent): void {
      const delta = startY - ev.clientY;
      panelHeight = Math.max(120, Math.min(600, startHeight + delta));
    }

    function onUp(): void {
      resizing = false;
      window.removeEventListener('mousemove', onMove);
      window.removeEventListener('mouseup', onUp);
    }

    window.addEventListener('mousemove', onMove);
    window.addEventListener('mouseup', onUp);
  }

  function handleKeyDown(e: KeyboardEvent): void {
    if (e.key === 'Escape') onClose();
  }

  function formatBytes(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }

  onMount(() => {
    void fetchLogs();
    const interval = setInterval(() => {
      void fetchLogs().then(scrollToBottom);
    }, 3000);
    window.addEventListener('keydown', handleKeyDown);
    return () => {
      clearInterval(interval);
      window.removeEventListener('keydown', handleKeyDown);
    };
  });

  $effect(() => {
    if (activeEntry !== null) {
      scrollToBottom();
    }
  });
</script>

<div
  class="log-panel"
  style="height: {panelHeight}px"
  role="region"
  aria-label="System Logs"
>
  <!-- Resize handle -->
  <div
    class="log-resize-handle"
    class:log-resize-handle--active={resizing}
    onmousedown={startResize}
    role="separator"
    aria-orientation="horizontal"
    aria-label="Resize log panel"
  ></div>

  <!-- Header -->
  <div class="log-header">
    <div class="log-header-left">
      <svg class="log-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
        <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
        <polyline points="14 2 14 8 20 8" />
        <line x1="16" y1="13" x2="8" y2="13" />
        <line x1="16" y1="17" x2="8" y2="17" />
      </svg>
      <span class="log-title">System Logs</span>
      {#if snapshot?.log_dir}
        <span class="log-dir">{snapshot.log_dir}</span>
      {/if}
    </div>
    <div class="log-header-right">
      <label class="log-autoscroll">
        <input type="checkbox" bind:checked={autoScroll} />
        <span>Auto-scroll</span>
      </label>
      <button class="log-refresh-btn" onclick={() => void fetchLogs()} aria-label="Refresh logs" title="Refresh">
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <polyline points="23 4 23 10 17 10" />
          <path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10" />
        </svg>
      </button>
      <button class="log-close-btn" onclick={onClose} aria-label="Close log panel" title="Close (Esc)">
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <line x1="18" y1="6" x2="6" y2="18" />
          <line x1="6" y1="6" x2="18" y2="18" />
        </svg>
      </button>
    </div>
  </div>

  <!-- Source tabs -->
  {#if sources.length > 1}
    <div class="log-tabs" role="tablist">
      {#each sources as src}
        {@const entry = snapshot?.entries.find((e) => e.source === src)}
        <button
          class="log-tab"
          class:log-tab--active={activeSource === src}
          onclick={() => { activeSource = src; }}
          role="tab"
          aria-selected={activeSource === src}
        >
          <span class="log-tab-name">{src}</span>
          {#if entry}
            <span class="log-tab-size">{formatBytes(entry.size_bytes)}</span>
          {/if}
        </button>
      {/each}
    </div>
  {/if}

  <!-- Log content -->
  <div
    class="log-content"
    bind:this={logContainerEl}
    onscroll={handleScroll}
  >
    {#if loading}
      <div class="log-empty">Loading logs...</div>
    {:else if error !== null}
      <div class="log-empty log-empty--error">{error}</div>
    {:else if activeEntry === null || activeEntry.lines.length === 0}
      <div class="log-empty">No log output yet.</div>
    {:else}
      <pre class="log-pre">{#each activeEntry.lines as line}<span class="log-line">{line}
</span>{/each}</pre>
    {/if}
  </div>
</div>

<style>
  .log-panel {
    display: flex;
    flex-direction: column;
    background: var(--bg-primary, #0d1117);
    border-top: 1px solid rgba(255, 255, 255, 0.08);
    position: relative;
    flex-shrink: 0;
    min-height: 120px;
    max-height: 600px;
  }

  .log-resize-handle {
    position: absolute;
    top: -3px;
    left: 0;
    right: 0;
    height: 6px;
    cursor: ns-resize;
    z-index: 10;
    transition: background 150ms ease;
  }

  .log-resize-handle:hover,
  .log-resize-handle--active {
    background: rgba(59, 130, 246, 0.4);
  }

  .log-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 6px 12px;
    border-bottom: 1px solid rgba(255, 255, 255, 0.06);
    flex-shrink: 0;
  }

  .log-header-left {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .log-header-right {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .log-icon {
    color: rgba(255, 255, 255, 0.5);
    flex-shrink: 0;
  }

  .log-title {
    font-size: 12px;
    font-weight: 600;
    color: rgba(255, 255, 255, 0.8);
  }

  .log-dir {
    font-size: 10px;
    color: rgba(255, 255, 255, 0.3);
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  }

  .log-autoscroll {
    display: flex;
    align-items: center;
    gap: 4px;
    font-size: 10px;
    color: rgba(255, 255, 255, 0.5);
    cursor: pointer;
    user-select: none;
  }

  .log-autoscroll input {
    width: 12px;
    height: 12px;
    accent-color: #3b82f6;
  }

  .log-refresh-btn,
  .log-close-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 22px;
    height: 22px;
    border: none;
    border-radius: 4px;
    background: rgba(255, 255, 255, 0.04);
    color: rgba(255, 255, 255, 0.5);
    cursor: pointer;
    transition: all 120ms ease;
  }

  .log-refresh-btn:hover,
  .log-close-btn:hover {
    background: rgba(255, 255, 255, 0.1);
    color: rgba(255, 255, 255, 0.9);
  }

  .log-tabs {
    display: flex;
    gap: 0;
    padding: 0 12px;
    border-bottom: 1px solid rgba(255, 255, 255, 0.06);
    flex-shrink: 0;
    overflow-x: auto;
  }

  .log-tab {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 6px 12px;
    border: none;
    background: none;
    color: rgba(255, 255, 255, 0.45);
    font-size: 11px;
    font-weight: 500;
    cursor: pointer;
    border-bottom: 2px solid transparent;
    transition: all 120ms ease;
    white-space: nowrap;
  }

  .log-tab:hover {
    color: rgba(255, 255, 255, 0.7);
    background: rgba(255, 255, 255, 0.03);
  }

  .log-tab--active {
    color: #60a5fa;
    border-bottom-color: #3b82f6;
  }

  .log-tab-name {
    text-transform: capitalize;
  }

  .log-tab-size {
    font-size: 9px;
    color: rgba(255, 255, 255, 0.25);
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  }

  .log-content {
    flex: 1;
    overflow: auto;
    padding: 8px 12px;
    min-height: 0;
  }

  .log-pre {
    margin: 0;
    padding: 0;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 11px;
    line-height: 1.5;
    white-space: pre-wrap;
    word-break: break-all;
  }

  .log-line {
    color: rgba(255, 255, 255, 0.7);
  }

  .log-line:hover {
    background: rgba(255, 255, 255, 0.03);
  }

  .log-empty {
    display: flex;
    align-items: center;
    justify-content: center;
    height: 100%;
    font-size: 12px;
    color: rgba(255, 255, 255, 0.35);
  }

  .log-empty--error {
    color: rgba(239, 68, 68, 0.7);
  }
</style>
