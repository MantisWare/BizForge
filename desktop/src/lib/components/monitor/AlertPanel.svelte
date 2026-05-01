<!-- src/lib/components/monitor/AlertPanel.svelte -->
<script lang="ts">
  import { monitorStore } from '$lib/stores/monitor.svelte';

  const severityColor: Record<string, string> = {
    critical: '#ef4444',
    warning: '#eab308',
    info: '#3b82f6',
  };

  const recentAlerts = $derived(monitorStore.alerts.filter((a) => a.enabled).slice(0, 10));
</script>

<div class="panel-title">
  Alerts
  {#if monitorStore.activeAlertCount > 0}
    <span class="alert-badge">{monitorStore.activeAlertCount}</span>
  {/if}
</div>

<div class="alert-scroll">
  {#if recentAlerts.length === 0}
    <div class="alert-empty">
      <span class="alert-empty-icon">\u2713</span>
      <span>No active alerts</span>
    </div>
  {:else}
    {#each recentAlerts as alert (alert.id)}
      {@const color = severityColor[alert.severity ?? 'info'] ?? '#3b82f6'}
      <div class="alert-card">
        <div class="alert-bar" style="background: {color};"></div>
        <div class="alert-body">
          <span class="alert-name">{alert.name}</span>
          <span class="alert-desc">
            {alert.entity_type} &middot; {alert.field} {alert.operator} {alert.threshold}
          </span>
        </div>
      </div>
    {/each}
  {/if}
</div>

<style>
  .panel-title {
    font-size: 11px; font-weight: 600; text-transform: uppercase;
    letter-spacing: 0.06em; color: #64748b; margin-bottom: 8px;
    display: flex; align-items: center; gap: 8px;
  }
  .alert-badge {
    font-size: 10px; font-weight: 700; color: #fff;
    background: #ef4444; border-radius: 8px; padding: 1px 6px;
    line-height: 1.4;
  }
  .alert-scroll { flex: 1; overflow-y: auto; display: flex; flex-direction: column; gap: 6px; }
  .alert-empty {
    display: flex; flex-direction: column; align-items: center; justify-content: center;
    height: 100%; gap: 6px; color: #22c55e; font-size: 12px;
  }
  .alert-empty-icon { font-size: 20px; }
  .alert-card { display: flex; gap: 8px; background: #0f172a; border-radius: 6px; overflow: hidden; }
  .alert-bar { width: 3px; flex-shrink: 0; }
  .alert-body { padding: 6px 8px; display: flex; flex-direction: column; gap: 2px; min-width: 0; }
  .alert-name { font-size: 12px; font-weight: 600; color: #e2e8f0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .alert-desc { font-size: 10px; color: #64748b; }

  .alert-scroll::-webkit-scrollbar { width: 4px; }
  .alert-scroll::-webkit-scrollbar-track { background: transparent; }
  .alert-scroll::-webkit-scrollbar-thumb { background: #1e293b; border-radius: 2px; }
</style>
