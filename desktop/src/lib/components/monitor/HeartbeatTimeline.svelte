<!-- src/lib/components/monitor/HeartbeatTimeline.svelte -->
<script lang="ts">
  import { monitorStore } from '$lib/stores/monitor.svelte';

  const eventColor: Record<string, string> = {
    'run.started': '#3b82f6',
    'run.completed': '#22c55e',
    'run.failed': '#ef4444',
  };

  const eventIcon: Record<string, string> = {
    'run.started': '\u25B6',
    'run.completed': '\u2713',
    'run.failed': '\u2717',
  };

  function formatTime(ts: string): string {
    return new Date(ts).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  }

  function formatCost(cents: number | undefined): string {
    if (cents === undefined || cents === 0) return '';
    return `${(cents / 100).toFixed(2)}\u00A2`;
  }
</script>

<div class="panel-title">Heartbeat Timeline</div>

<div class="timeline-scroll">
  {#if monitorStore.heartbeatEvents.length === 0}
    <div class="timeline-empty">
      <span class="timeline-empty-icon">\u2764</span>
      <span>Waiting for heartbeat events...</span>
    </div>
  {:else}
    {#each monitorStore.heartbeatEvents as event, i (i)}
      {@const color = eventColor[event.event] ?? '#64748b'}
      <div class="timeline-entry">
        <div class="timeline-marker" style="background: {color}; box-shadow: 0 0 4px {color}60;">
          <span class="timeline-icon">{eventIcon[event.event] ?? '\u25CF'}</span>
        </div>
        <div class="timeline-line" class:last={i === monitorStore.heartbeatEvents.length - 1}></div>
        <div class="timeline-content">
          <div class="timeline-row">
            <span class="timeline-agent">{event.agentName}</span>
            <span class="timeline-time">{formatTime(event.timestamp)}</span>
          </div>
          <div class="timeline-row">
            <span class="timeline-event" style="color: {color};">{event.event}</span>
            {#if event.cost}
              <span class="timeline-cost">{formatCost(event.cost)}</span>
            {/if}
          </div>
        </div>
      </div>
    {/each}
  {/if}
</div>

<style>
  .panel-title { font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.06em; color: #64748b; margin-bottom: 8px; }
  .timeline-scroll { flex: 1; overflow-y: auto; display: flex; flex-direction: column; gap: 0; }
  .timeline-empty { display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100%; gap: 8px; color: #475569; font-size: 13px; }
  .timeline-empty-icon { font-size: 24px; opacity: 0.4; }
  .timeline-entry { display: flex; gap: 10px; position: relative; padding-bottom: 12px; }
  .timeline-marker {
    width: 20px; height: 20px; border-radius: 50%;
    display: flex; align-items: center; justify-content: center;
    flex-shrink: 0; z-index: 1;
  }
  .timeline-icon { font-size: 10px; color: #fff; }
  .timeline-line {
    position: absolute; left: 9px; top: 22px; bottom: 0; width: 2px;
    background: #1e293b;
  }
  .timeline-line.last { display: none; }
  .timeline-content { flex: 1; min-width: 0; }
  .timeline-row { display: flex; justify-content: space-between; align-items: center; }
  .timeline-agent { font-size: 12px; font-weight: 600; color: #e2e8f0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .timeline-time { font-size: 10px; color: #64748b; flex-shrink: 0; }
  .timeline-event { font-size: 11px; font-weight: 500; }
  .timeline-cost { font-size: 11px; color: #f26522; font-weight: 600; }

  .timeline-scroll::-webkit-scrollbar { width: 4px; }
  .timeline-scroll::-webkit-scrollbar-track { background: transparent; }
  .timeline-scroll::-webkit-scrollbar-thumb { background: #1e293b; border-radius: 2px; }
</style>
