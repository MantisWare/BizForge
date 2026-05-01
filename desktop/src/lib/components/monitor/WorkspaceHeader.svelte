<!-- src/lib/components/monitor/WorkspaceHeader.svelte -->
<script lang="ts">
  import { monitorStore } from '$lib/stores/monitor.svelte';

  const uptimeFormatted = $derived.by(() => {
    const s = monitorStore.health.uptime;
    if (s < 60) return `${s}s`;
    if (s < 3600) return `${Math.floor(s / 60)}m ${s % 60}s`;
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    return `${h}h ${m}m`;
  });

  const connectionDot = $derived(monitorStore.connected ? 'dot-ok' : 'dot-err');
</script>

<header class="ws-header">
  <div class="ws-left">
    <button class="ws-back" onclick={() => monitorStore.backToSelector()} title="Switch workspace (Esc)">
      \u2190
    </button>
    <span class="ws-logo">BF</span>
    <div class="ws-info">
      <h1 class="ws-name">{monitorStore.workspaceName}</h1>
      <span class="ws-sub">Headless Monitor</span>
    </div>
  </div>

  <div class="ws-stats">
    <div class="ws-stat">
      <span class="ws-stat-value">{monitorStore.agentCounts.total}</span>
      <span class="ws-stat-label">Agents</span>
    </div>
    <div class="ws-stat">
      <span class="ws-stat-value">{monitorStore.taskCounts.total}</span>
      <span class="ws-stat-label">Tasks</span>
    </div>
    <div class="ws-stat">
      <span class="ws-stat-value">{uptimeFormatted}</span>
      <span class="ws-stat-label">Uptime</span>
    </div>
  </div>

  <div class="ws-right">
    <span class="dot {connectionDot}"></span>
    <span class="ws-status">{monitorStore.connected ? 'Connected' : 'Disconnected'}</span>
    {#if monitorStore.paused}
      <span class="ws-paused">PAUSED</span>
    {/if}
  </div>
</header>

<style>
  .ws-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 8px 16px;
    background: #111827;
    border: 1px solid #1e293b;
    border-radius: 8px;
    gap: 16px;
  }
  .ws-left { display: flex; align-items: center; gap: 10px; }
  .ws-back {
    background: none; border: 1px solid #1e293b; border-radius: 6px;
    color: #94a3b8; font-size: 14px; width: 28px; height: 28px;
    display: flex; align-items: center; justify-content: center;
    cursor: pointer; transition: background 0.15s, color 0.15s;
    flex-shrink: 0;
  }
  .ws-back:hover { background: #1e293b; color: #f1f5f9; }
  .ws-logo {
    width: 32px; height: 32px; border-radius: 6px;
    background: linear-gradient(135deg, #f26522, #e04b18);
    display: flex; align-items: center; justify-content: center;
    font-weight: 800; font-size: 13px; color: #fff;
  }
  .ws-info { display: flex; flex-direction: column; }
  .ws-name { font-size: 15px; font-weight: 700; color: #f1f5f9; margin: 0; }
  .ws-sub { font-size: 11px; color: #64748b; }
  .ws-stats { display: flex; gap: 24px; }
  .ws-stat { display: flex; flex-direction: column; align-items: center; }
  .ws-stat-value { font-size: 18px; font-weight: 700; color: #f1f5f9; }
  .ws-stat-label { font-size: 10px; color: #64748b; text-transform: uppercase; letter-spacing: 0.05em; }
  .ws-right { display: flex; align-items: center; gap: 8px; }
  .dot { width: 8px; height: 8px; border-radius: 50%; }
  .dot-ok { background: #22c55e; box-shadow: 0 0 6px #22c55e80; }
  .dot-err { background: #ef4444; box-shadow: 0 0 6px #ef444480; }
  .ws-status { font-size: 12px; color: #94a3b8; }
  .ws-paused {
    font-size: 10px; font-weight: 700; color: #eab308;
    background: #eab30815; padding: 2px 8px; border-radius: 4px;
  }
</style>
