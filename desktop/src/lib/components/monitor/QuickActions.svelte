<!-- src/lib/components/monitor/QuickActions.svelte -->
<script lang="ts">
  import { monitorStore } from '$lib/stores/monitor.svelte';

  let confirming = $state<string | null>(null);

  function handlePause(): void {
    monitorStore.pauseAll();
  }

  function handleResume(): void {
    monitorStore.resumeAll();
  }

  function handleStop(): void {
    if (confirming === 'stop') {
      window.close();
    } else {
      confirming = 'stop';
      setTimeout(() => { confirming = null; }, 3000);
    }
  }

  function handleRefresh(): void {
    monitorStore.fetchAll();
  }
</script>

<div class="panel-title">Quick Actions</div>

<div class="actions-grid">
  {#if monitorStore.paused}
    <button class="action-btn action-resume" onclick={handleResume}>
      <span class="action-icon">\u25B6</span>
      Resume All
    </button>
  {:else}
    <button class="action-btn action-pause" onclick={handlePause}>
      <span class="action-icon">\u23F8</span>
      Pause All
    </button>
  {/if}

  <button class="action-btn action-refresh" onclick={handleRefresh}>
    <span class="action-icon">\u21BB</span>
    Refresh
  </button>

  <button
    class="action-btn action-stop"
    class:confirming={confirming === 'stop'}
    onclick={handleStop}
  >
    <span class="action-icon">\u23F9</span>
    {confirming === 'stop' ? 'Confirm Stop?' : 'Stop'}
  </button>
</div>

<div class="actions-help">
  <span class="help-key">P</span> pause &middot;
  <span class="help-key">R</span> resume
</div>

<style>
  .panel-title { font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.06em; color: #64748b; margin-bottom: 8px; }
  .actions-grid { display: flex; flex-direction: column; gap: 6px; flex: 1; }
  .action-btn {
    display: flex; align-items: center; gap: 8px;
    width: 100%; padding: 8px 12px; border: 1px solid #1e293b;
    border-radius: 6px; background: #0f172a; color: #e2e8f0;
    font-size: 12px; font-weight: 500; cursor: pointer;
    transition: background 0.15s, border-color 0.15s;
  }
  .action-btn:hover { background: #1e293b; border-color: #334155; }
  .action-icon { font-size: 14px; width: 18px; text-align: center; }
  .action-pause:hover { border-color: #eab308; color: #eab308; }
  .action-resume:hover { border-color: #22c55e; color: #22c55e; }
  .action-refresh:hover { border-color: #3b82f6; color: #3b82f6; }
  .action-stop:hover { border-color: #ef4444; color: #ef4444; }
  .action-stop.confirming { border-color: #ef4444; color: #ef4444; background: #ef444415; }
  .actions-help {
    font-size: 10px; color: #475569; padding-top: 8px;
    border-top: 1px solid #1e293b; margin-top: auto;
  }
  .help-key {
    display: inline-block; font-size: 9px; font-weight: 700; color: #94a3b8;
    background: #1e293b; padding: 1px 4px; border-radius: 3px; font-family: monospace;
  }
</style>
