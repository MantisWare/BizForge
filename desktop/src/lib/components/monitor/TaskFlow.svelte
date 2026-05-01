<!-- src/lib/components/monitor/TaskFlow.svelte -->
<script lang="ts">
  import { monitorStore } from '$lib/stores/monitor.svelte';

  interface FlowItem {
    label: string;
    count: number;
    color: string;
  }

  const flows: FlowItem[] = $derived([
    { label: 'Open', count: monitorStore.taskCounts.open, color: '#3b82f6' },
    { label: 'In Progress', count: monitorStore.taskCounts.inProgress, color: '#f59e0b' },
    { label: 'Completed', count: monitorStore.taskCounts.completed, color: '#22c55e' },
    { label: 'Blocked', count: monitorStore.taskCounts.blocked, color: '#ef4444' },
  ]);

  const maxCount = $derived(Math.max(1, ...flows.map((f) => f.count)));
</script>

<div class="panel-title">Task Flow</div>

<div class="flow-total">
  <span class="flow-total-num">{monitorStore.taskCounts.total}</span>
  <span class="flow-total-label">total tasks</span>
</div>

<div class="flow-bars">
  {#each flows as flow (flow.label)}
    <div class="flow-row">
      <span class="flow-label">{flow.label}</span>
      <div class="flow-bar-track">
        <div
          class="flow-bar-fill"
          style="width: {(flow.count / maxCount) * 100}%; background: {flow.color};"
        ></div>
      </div>
      <span class="flow-count" style="color: {flow.color};">{flow.count}</span>
    </div>
  {/each}
</div>

<style>
  .panel-title { font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.06em; color: #64748b; margin-bottom: 8px; }
  .flow-total { display: flex; align-items: baseline; gap: 6px; margin-bottom: 12px; }
  .flow-total-num { font-size: 24px; font-weight: 700; color: #f1f5f9; }
  .flow-total-label { font-size: 12px; color: #64748b; }
  .flow-bars { display: flex; flex-direction: column; gap: 8px; }
  .flow-row { display: flex; align-items: center; gap: 8px; }
  .flow-label { font-size: 11px; color: #94a3b8; width: 72px; flex-shrink: 0; }
  .flow-bar-track { flex: 1; height: 6px; background: #1e293b; border-radius: 3px; overflow: hidden; }
  .flow-bar-fill { height: 100%; border-radius: 3px; transition: width 0.4s ease; }
  .flow-count { font-size: 12px; font-weight: 700; width: 28px; text-align: right; }
</style>
