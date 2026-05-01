<!-- src/lib/components/monitor/AgentActivity.svelte -->
<script lang="ts">
  import { monitorStore } from '$lib/stores/monitor.svelte';

  const statusBadge: Record<string, { color: string; label: string }> = {
    active: { color: '#22c55e', label: 'Active' },
    running: { color: '#22c55e', label: 'Running' },
    working: { color: '#3b82f6', label: 'Working' },
    idle: { color: '#64748b', label: 'Idle' },
    paused: { color: '#eab308', label: 'Paused' },
    error: { color: '#ef4444', label: 'Error' },
  };

  function badge(status: string): { color: string; label: string } {
    return statusBadge[status] ?? { color: '#64748b', label: status };
  }
</script>

<div class="panel-title">Agent Activity</div>

<div class="agent-counts">
  <span class="count-chip count-active">{monitorStore.agentCounts.active + monitorStore.agentCounts.working} active</span>
  <span class="count-chip count-idle">{monitorStore.agentCounts.idle} idle</span>
  <span class="count-chip count-paused">{monitorStore.agentCounts.paused} paused</span>
  {#if monitorStore.agentCounts.errored > 0}
    <span class="count-chip count-error">{monitorStore.agentCounts.errored} error</span>
  {/if}
</div>

<div class="agent-list">
  {#each monitorStore.agents.slice(0, 8) as agent (agent.id)}
    {@const b = badge(agent.status)}
    <div class="agent-row">
      <span class="agent-dot" style="background: {b.color};"></span>
      <span class="agent-name">{agent.display_name ?? agent.name}</span>
      <span class="agent-status" style="color: {b.color};">{b.label}</span>
    </div>
  {/each}
  {#if monitorStore.agents.length > 8}
    <div class="agent-more">+{monitorStore.agents.length - 8} more</div>
  {/if}
</div>

<style>
  .panel-title { font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.06em; color: #64748b; margin-bottom: 8px; }
  .agent-counts { display: flex; gap: 6px; flex-wrap: wrap; margin-bottom: 8px; }
  .count-chip { font-size: 10px; font-weight: 600; padding: 2px 8px; border-radius: 4px; }
  .count-active { color: #22c55e; background: #22c55e15; }
  .count-idle { color: #64748b; background: #64748b15; }
  .count-paused { color: #eab308; background: #eab30815; }
  .count-error { color: #ef4444; background: #ef444415; }
  .agent-list { display: flex; flex-direction: column; gap: 4px; overflow-y: auto; flex: 1; }
  .agent-row { display: flex; align-items: center; gap: 8px; padding: 3px 0; }
  .agent-dot { width: 6px; height: 6px; border-radius: 50%; flex-shrink: 0; }
  .agent-name { font-size: 12px; color: #e2e8f0; flex: 1; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .agent-status { font-size: 10px; font-weight: 600; flex-shrink: 0; }
  .agent-more { font-size: 11px; color: #64748b; padding-top: 4px; }
</style>
