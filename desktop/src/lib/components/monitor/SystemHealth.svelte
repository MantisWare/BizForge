<!-- src/lib/components/monitor/SystemHealth.svelte -->
<script lang="ts">
  import { monitorStore } from '$lib/stores/monitor.svelte';

  const statusColor = $derived(
    monitorStore.health.status === 'ok' || monitorStore.health.status === 'healthy'
      ? '#22c55e'
      : monitorStore.health.status === 'degraded'
        ? '#eab308'
        : '#ef4444',
  );
</script>

<div class="panel-title">System Health</div>

<div class="health-grid">
  <div class="health-item">
    <span class="health-dot" style="background: {statusColor}; box-shadow: 0 0 6px {statusColor}80;"></span>
    <span class="health-label">Status</span>
    <span class="health-value" style="color: {statusColor};">{monitorStore.health.status}</span>
  </div>

  <div class="health-item">
    <span class="health-label">Active Agents</span>
    <span class="health-value">{monitorStore.health.activeAgents}</span>
  </div>

  <div class="health-item">
    <span class="health-label">Version</span>
    <span class="health-value">{monitorStore.health.version}</span>
  </div>

  <div class="health-item">
    <span class="health-label">Last Check</span>
    <span class="health-value">
      {monitorStore.lastUpdated !== null
        ? new Date(monitorStore.lastUpdated).toLocaleTimeString()
        : '--'}
    </span>
  </div>
</div>

<style>
  .panel-title { font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.06em; color: #64748b; margin-bottom: 10px; }
  .health-grid { display: flex; flex-direction: column; gap: 8px; }
  .health-item { display: flex; align-items: center; gap: 8px; }
  .health-dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
  .health-label { font-size: 12px; color: #94a3b8; flex: 1; }
  .health-value { font-size: 13px; font-weight: 600; color: #f1f5f9; }
</style>
