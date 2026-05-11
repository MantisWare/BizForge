<!-- src/lib/components/tasks/TaskList.svelte -->
<script lang="ts">
  import type { Task } from '$api/types';
  import { tasksStore, resolveAssigneeName } from '$lib/stores/tasks.svelte';
  import TimeAgo from '$lib/components/shared/TimeAgo.svelte';

  interface Props {
    tasks: Task[];
  }

  let { tasks }: Props = $props();

  let dispatching = $state<Record<string, boolean>>({});

  function canDispatch(task: Task): boolean {
    return (
      task.assignee_id !== null &&
      (task.status === 'backlog' || task.status === 'todo')
    );
  }

  async function handleDispatch(e: MouseEvent, task: Task) {
    e.stopPropagation();
    dispatching[task.id] = true;
    await tasksStore.dispatch(task.id);
    dispatching[task.id] = false;
  }

  const PRIORITY_ICONS: Record<string, { path: string; color: string }> = {
    low:      { path: 'M5 15l7-7 7 7', color: '#3b82f6' },
    medium:   { path: 'M8 12h8', color: '#f59e0b' },
    high:     { path: 'M5 9l7 7 7-7', color: '#f97316' },
    critical: { path: 'M12 9v4m0 4h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z', color: '#ef4444' },
  };

  const STATUS_LABELS: Record<string, { label: string; variant: string }> = {
    backlog:     { label: 'Backlog',     variant: 'default' },
    todo:        { label: 'Todo',        variant: 'info'    },
    in_progress: { label: 'In Progress', variant: 'warning' },
    in_review:   { label: 'In Review',   variant: 'accent'  },
    done:        { label: 'Done',        variant: 'success' },
  };

  const STATUS_COLORS: Record<string, string> = {
    default: 'rgba(255,255,255,0.08)',
    info:    'rgba(59,130,246,0.15)',
    warning: 'rgba(245,158,11,0.15)',
    accent:  'rgba(249,115,22,0.15)',
    success: 'rgba(34,197,94,0.15)',
  };

  const STATUS_TEXT: Record<string, string> = {
    default: 'var(--text-secondary)',
    info:    '#93c5fd',
    warning: '#fde047',
    accent:  '#fdba74',
    success: 'rgba(34, 197, 94, 0.7)',
  };

  const LABEL_COLORS = ['#3b82f6','#f97316','rgba(34,197,94,0.7)','#f59e0b','#ec4899','#06b6d4'];
  function labelColor(label: string): string {
    let hash = 0;
    for (let i = 0; i < label.length; i++) hash = (hash * 31 + label.charCodeAt(i)) | 0;
    return LABEL_COLORS[Math.abs(hash) % LABEL_COLORS.length];
  }
</script>

<div class="il-list" role="list" aria-label="Tasks list">
  {#if tasks.length === 0}
    <div class="il-empty" role="status">No tasks match your filters.</div>
  {:else}
    {#each tasks as task (task.id)}
      {@const priority = PRIORITY_ICONS[task.priority]}
      {@const statusInfo = STATUS_LABELS[task.status]}
      {@const assigneeName = resolveAssigneeName(task)}
      <!-- svelte-ignore a11y_no_noninteractive_element_interactions a11y_no_noninteractive_tabindex -->
      <div
        class="il-row"
        class:il-row--selected={tasksStore.selected?.id === task.id}
        onclick={() => tasksStore.selectTask(task)}
        onkeydown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); tasksStore.selectTask(task); } }}
        aria-label="Task: {task.title}"
        aria-current={tasksStore.selected?.id === task.id ? 'true' : undefined}
        role="row"
        tabindex="0"
      >
        <span class="il-priority" aria-label="Priority: {task.priority}" style="color: {priority?.color ?? '#666'}">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" aria-hidden="true">
            <path d={priority?.path ?? 'M8 12h8'} />
          </svg>
        </span>

        <span class="il-title">{task.title}</span>

        <div class="il-labels" aria-label="Labels">
          {#each task.labels.slice(0, 3) as label (label)}
            <span
              class="il-label"
              style="background: {labelColor(label)}22; color: {labelColor(label)}; border-color: {labelColor(label)}44"
            >{label}</span>
          {/each}
        </div>

        <span
          class="il-status"
          style="background: {STATUS_COLORS[statusInfo?.variant ?? 'default']}; color: {STATUS_TEXT[statusInfo?.variant ?? 'default']}"
          aria-label="Status: {statusInfo?.label}"
        >
          {statusInfo?.label ?? task.status}
        </span>

        <span class="il-assignee" aria-label={task.assignee_id !== null ? 'Assigned to ' + assigneeName : 'Unassigned'}>
          {#if task.assignee_id !== null}
            <span class="il-avatar" aria-hidden="true">{assigneeName[0].toUpperCase()}</span>
            <span class="il-assignee-name">{assigneeName}</span>
          {:else}
            <span class="il-no-assignee">—</span>
          {/if}
        </span>

        <span class="il-comments" aria-label="{task.comments_count} comments">
          {#if task.comments_count > 0}
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
              <path d="M21 15a2 2 0 01-2 2H7l-4 4V5a2 2 0 012-2h14a2 2 0 012 2z"/>
            </svg>
            {task.comments_count}
          {/if}
        </span>

        <span class="il-updated">
          <TimeAgo date={task.updated_at} />
        </span>

        <span class="il-dispatch-cell">
          {#if canDispatch(task)}
            <button
              class="il-dispatch-btn"
              class:il-dispatch-btn--loading={dispatching[task.id]}
              onclick={(e) => handleDispatch(e, task)}
              disabled={dispatching[task.id]}
              aria-label="Dispatch task to {assigneeName}"
              type="button"
            >
              {#if dispatching[task.id]}
                <span class="il-dispatch-spinner" aria-hidden="true"></span>
              {:else}
                <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" aria-hidden="true">
                  <path d="M22 2L11 13M22 2l-7 20-4-9-9-4 20-7z" />
                </svg>
                <span class="il-dispatch-agent">{assigneeName}</span>
              {/if}
            </button>
          {:else}
            <span></span>
          {/if}
        </span>
      </div>
    {/each}
  {/if}
</div>

<style>
  .il-list { display: flex; flex-direction: column; width: 100%; }
  .il-empty { padding: 40px 16px; text-align: center; color: var(--text-tertiary); font-size: 13px; }
  .il-row { display: grid; grid-template-columns: 20px 1fr auto auto auto auto auto auto; align-items: center; gap: 10px; height: 40px; padding: 0 12px; border: none; border-bottom: 1px solid var(--border-default); background: transparent; cursor: pointer; text-align: left; color: inherit; font: inherit; width: 100%; transition: background 100ms ease; }
  .il-row:hover { background: rgba(255,255,255,0.04); }
  .il-row--selected { background: rgba(59,130,246,0.08); border-color: rgba(59,130,246,0.2); }
  .il-row:focus-visible { outline: 2px solid var(--accent-primary); outline-offset: -2px; }
  .il-priority { display: flex; align-items: center; justify-content: center; flex-shrink: 0; }
  .il-title { font-size: 13px; font-weight: 500; color: var(--text-primary); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .il-labels { display: flex; align-items: center; gap: 4px; flex-shrink: 0; }
  .il-label { font-size: 10px; font-weight: 500; padding: 1px 6px; border-radius: 9999px; border: 1px solid transparent; white-space: nowrap; }
  .il-status { font-size: 11px; font-weight: 500; padding: 2px 8px; border-radius: 9999px; white-space: nowrap; flex-shrink: 0; }
  .il-assignee { display: flex; align-items: center; gap: 5px; flex-shrink: 0; }
  .il-avatar { width: 18px; height: 18px; border-radius: 50%; background: var(--accent-primary); color: #fff; font-size: 10px; font-weight: 600; display: flex; align-items: center; justify-content: center; flex-shrink: 0; }
  .il-assignee-name { font-size: 12px; color: var(--text-secondary); max-width: 80px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .il-no-assignee { font-size: 12px; color: var(--text-muted); }
  .il-comments { display: flex; align-items: center; gap: 3px; font-size: 11px; color: var(--text-tertiary); flex-shrink: 0; min-width: 24px; }
  .il-updated { flex-shrink: 0; text-align: right; }
  .il-dispatch-cell { flex-shrink: 0; display: flex; align-items: center; justify-content: flex-end; }
  .il-dispatch-btn { display: flex; align-items: center; gap: 4px; height: 22px; padding: 0 8px; background: transparent; border: 1px solid var(--border-default); border-radius: var(--radius-xs); color: var(--text-tertiary); font-size: 11px; font-weight: 500; font-family: inherit; cursor: pointer; white-space: nowrap; transition: background 150ms ease, color 150ms ease, border-color 150ms ease; }
  .il-dispatch-btn:hover:not(:disabled) { background: rgba(34, 197, 94, 0.08); border-color: rgba(34, 197, 94, 0.3); color: rgba(34, 197, 94, 0.8); }
  .il-dispatch-btn:focus-visible { outline: 2px solid var(--accent-primary); outline-offset: 2px; }
  .il-dispatch-btn:disabled { opacity: 0.6; cursor: not-allowed; }
  .il-dispatch-btn--loading { min-width: 50px; justify-content: center; }
  .il-dispatch-agent { max-width: 80px; overflow: hidden; text-overflow: ellipsis; }
  .il-dispatch-spinner { width: 10px; height: 10px; border: 1.5px solid currentColor; border-top-color: transparent; border-radius: 50%; animation: il-spin 0.7s linear infinite; flex-shrink: 0; }
  @keyframes il-spin { to { transform: rotate(360deg); } }
</style>
