<!-- Context window usage gauge -->
<script lang="ts">
  interface Props {
    used?: number;
    total?: number;
    label?: string;
  }

  let { used = 0, total = 128_000, label = 'Context' }: Props = $props();

  const pct = $derived(total > 0 ? Math.min(100, Math.round((used / total) * 100)) : 0);
  const level = $derived(pct >= 90 ? 'critical' : pct >= 70 ? 'warning' : 'normal');
</script>

<div class="cg" title="{label}: {used.toLocaleString()} / {total.toLocaleString()} tokens">
  <span class="cg-label">{label}</span>
  <div class="cg-track" role="progressbar" aria-valuenow={pct} aria-valuemin={0} aria-valuemax={100}>
    <div class="cg-fill cg-fill--{level}" style="width: {pct}%"></div>
  </div>
  <span class="cg-pct">{pct}%</span>
</div>

<style>
  .cg {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    font-size: 11px;
    color: var(--text-tertiary);
  }
  .cg-track {
    width: 72px;
    height: 4px;
    background: var(--bg-elevated);
    border-radius: 2px;
    overflow: hidden;
  }
  .cg-fill {
    height: 100%;
    border-radius: 2px;
    transition: width 200ms ease;
  }
  .cg-fill--normal { background: var(--accent-success); }
  .cg-fill--warning { background: var(--accent-warning); }
  .cg-fill--critical { background: var(--accent-error); }
  .cg-pct { min-width: 28px; text-align: right; }
</style>
