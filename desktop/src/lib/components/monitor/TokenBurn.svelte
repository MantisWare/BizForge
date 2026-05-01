<!-- src/lib/components/monitor/TokenBurn.svelte -->
<script lang="ts">
  import { monitorStore } from '$lib/stores/monitor.svelte';

  const totalCost = $derived(monitorStore.costSummary?.month_cents ?? 0);
  const todayCost = $derived(monitorStore.costSummary?.today_cents ?? 0);
  const weekCost = $derived(monitorStore.costSummary?.week_cents ?? 0);
  const cacheSavings = $derived(monitorStore.costSummary?.cache_savings_cents ?? 0);

  function formatCost(cents: number): string {
    return `$${(cents / 100).toFixed(2)}`;
  }
</script>

<div class="panel-title">Token Burn</div>

<div class="burn-total">
  <span class="burn-cost">{formatCost(totalCost)}</span>
  <span class="burn-label">total spend</span>
</div>

<div class="burn-breakdown">
  <div class="burn-row">
    <span class="burn-dot" style="background: #3b82f6;"></span>
    <span class="burn-metric">Today</span>
    <span class="burn-val">{formatCost(todayCost)}</span>
  </div>
  <div class="burn-row">
    <span class="burn-dot" style="background: #22c55e;"></span>
    <span class="burn-metric">This Week</span>
    <span class="burn-val">{formatCost(weekCost)}</span>
  </div>
  <div class="burn-row">
    <span class="burn-dot" style="background: #f97316;"></span>
    <span class="burn-metric">Cache Savings</span>
    <span class="burn-val">{formatCost(cacheSavings)}</span>
  </div>
</div>

<style>
  .panel-title { font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.06em; color: #64748b; margin-bottom: 8px; }
  .burn-total { display: flex; align-items: baseline; gap: 8px; margin-bottom: 14px; }
  .burn-cost { font-size: 26px; font-weight: 800; color: #f26522; }
  .burn-label { font-size: 12px; color: #64748b; }
  .burn-breakdown { display: flex; flex-direction: column; gap: 8px; }
  .burn-row { display: flex; align-items: center; gap: 8px; }
  .burn-dot { width: 8px; height: 8px; border-radius: 2px; flex-shrink: 0; }
  .burn-metric { font-size: 12px; color: #94a3b8; flex: 1; }
  .burn-val { font-size: 13px; font-weight: 700; color: #f1f5f9; }
</style>
