<!-- src/lib/components/monitor/LogStream.svelte -->
<script lang="ts">
  import { monitorStore } from '$lib/stores/monitor.svelte';

  let filterLevel = $state('all');

  const filteredLogs = $derived(
    filterLevel === 'all'
      ? monitorStore.logEntries
      : monitorStore.logEntries.filter((l) => l.level === filterLevel),
  );

  const levelColor: Record<string, string> = {
    info: '#3b82f6',
    warning: '#eab308',
    error: '#ef4444',
    debug: '#8b5cf6',
  };

  function formatTime(ts: string): string {
    return new Date(ts).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  }
</script>

<div class="log-header">
  <span class="panel-title">Log Stream</span>
  <select class="log-filter" bind:value={filterLevel}>
    <option value="all">All</option>
    <option value="info">Info</option>
    <option value="warning">Warn</option>
    <option value="error">Error</option>
  </select>
</div>

<div class="log-scroll">
  {#if filteredLogs.length === 0}
    <div class="log-empty">No log entries yet</div>
  {:else}
    {#each filteredLogs as entry, i (i)}
      <div class="log-entry">
        <span class="log-time">{formatTime(entry.timestamp)}</span>
        <span class="log-level" style="color: {levelColor[entry.level] ?? '#64748b'};">
          {entry.level.toUpperCase().slice(0, 4)}
        </span>
        <span class="log-msg">{entry.message}</span>
      </div>
    {/each}
  {/if}
</div>

<style>
  .log-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 6px; }
  .panel-title { font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.06em; color: #64748b; }
  .log-filter {
    font-size: 10px; background: #1e293b; border: 1px solid #334155; color: #e2e8f0;
    border-radius: 4px; padding: 2px 6px; outline: none;
  }
  .log-scroll {
    flex: 1; overflow-y: auto; font-family: 'SF Mono', 'Fira Code', monospace;
    display: flex; flex-direction: column; gap: 2px;
  }
  .log-empty { font-size: 12px; color: #475569; padding: 16px 0; text-align: center; }
  .log-entry { display: flex; gap: 6px; font-size: 10px; line-height: 1.5; padding: 1px 0; }
  .log-time { color: #475569; flex-shrink: 0; }
  .log-level { font-weight: 700; width: 32px; flex-shrink: 0; }
  .log-msg { color: #cbd5e1; word-break: break-all; }

  .log-scroll::-webkit-scrollbar { width: 4px; }
  .log-scroll::-webkit-scrollbar-track { background: transparent; }
  .log-scroll::-webkit-scrollbar-thumb { background: #1e293b; border-radius: 2px; }
</style>
