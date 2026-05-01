<!-- src/lib/components/monitor/TokenBurn.svelte -->
<script lang="ts">
  import { monitorStore } from '$lib/stores/monitor.svelte';

  const totalCost = $derived(monitorStore.costSummary?.total_cost ?? 0);
  const inputTokens = $derived(monitorStore.costSummary?.total_input_tokens ?? 0);
  const outputTokens = $derived(monitorStore.costSummary?.total_output_tokens ?? 0);
  const cacheTokens = $derived(monitorStore.costSummary?.total_cache_tokens ?? 0);

  function formatCost(cents: number): string {
    return `$${(cents / 100).toFixed(2)}`;
  }

  function formatTokens(n: number): string {
    if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
    if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
    return n.toString();
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
    <span class="burn-metric">Input</span>
    <span class="burn-val">{formatTokens(inputTokens)}</span>
  </div>
  <div class="burn-row">
    <span class="burn-dot" style="background: #22c55e;"></span>
    <span class="burn-metric">Output</span>
    <span class="burn-val">{formatTokens(outputTokens)}</span>
  </div>
  <div class="burn-row">
    <span class="burn-dot" style="background: #8b5cf6;"></span>
    <span class="burn-metric">Cache</span>
    <span class="burn-val">{formatTokens(cacheTokens)}</span>
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
