<!-- src/lib/components/monitor/BudgetGauge.svelte -->
<script lang="ts">
  import { monitorStore } from '$lib/stores/monitor.svelte';

  const pct = $derived(Math.min(monitorStore.budget.utilizationPercent, 100));
  const gaugeColor = $derived(
    pct >= 90 ? '#ef4444' : pct >= 70 ? '#eab308' : '#22c55e',
  );
  const radius = 42;
  const circumference = 2 * Math.PI * radius;
  const dashOffset = $derived(circumference - (pct / 100) * circumference);

  function formatCost(cents: number): string {
    if (cents >= 100_000) return `$${(cents / 100).toFixed(0)}`;
    return `$${(cents / 100).toFixed(2)}`;
  }
</script>

<div class="panel-title">Budget</div>

<div class="gauge-container">
  <svg viewBox="0 0 100 100" class="gauge-svg">
    <circle
      cx="50" cy="50" r={radius}
      fill="none" stroke="#1e293b" stroke-width="6"
    />
    <circle
      cx="50" cy="50" r={radius}
      fill="none" stroke={gaugeColor} stroke-width="6"
      stroke-linecap="round"
      stroke-dasharray={circumference}
      stroke-dashoffset={dashOffset}
      transform="rotate(-90 50 50)"
      style="transition: stroke-dashoffset 0.6s ease;"
    />
    <text x="50" y="46" text-anchor="middle" fill="#f1f5f9" font-size="16" font-weight="700">
      {pct}%
    </text>
    <text x="50" y="60" text-anchor="middle" fill="#64748b" font-size="7">
      utilized
    </text>
  </svg>
</div>

<div class="gauge-details">
  <div class="gauge-row">
    <span class="gauge-label">Spent</span>
    <span class="gauge-val">{formatCost(monitorStore.budget.totalSpent)}</span>
  </div>
  <div class="gauge-row">
    <span class="gauge-label">Monthly Limit</span>
    <span class="gauge-val">{formatCost(monitorStore.budget.monthlyLimit)}</span>
  </div>
</div>

<style>
  .panel-title { font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.06em; color: #64748b; margin-bottom: 8px; }
  .gauge-container { display: flex; justify-content: center; padding: 4px 0; }
  .gauge-svg { width: 100px; height: 100px; }
  .gauge-details { display: flex; flex-direction: column; gap: 6px; margin-top: 8px; }
  .gauge-row { display: flex; justify-content: space-between; }
  .gauge-label { font-size: 11px; color: #94a3b8; }
  .gauge-val { font-size: 12px; font-weight: 600; color: #f1f5f9; }
</style>
