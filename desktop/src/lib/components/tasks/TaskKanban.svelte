<!-- src/lib/components/tasks/TaskKanban.svelte -->
<script lang="ts">
  import type { TaskStatus } from '$api/types';
  import { tasksStore } from '$lib/stores/tasks.svelte';
  import TaskCard from './TaskCard.svelte';

  interface Props {
    onSelect?: (taskId: string) => void;
  }

  let { onSelect }: Props = $props();

  const COLUMNS: { status: TaskStatus; label: string }[] = [
    { status: 'backlog',     label: 'Backlog'      },
    { status: 'todo',        label: 'Todo'         },
    { status: 'in_progress', label: 'In Progress'  },
    { status: 'in_review',   label: 'In Review'    },
    { status: 'done',        label: 'Done'         },
  ];

  const COL_COLORS: Record<TaskStatus, string> = {
    backlog:     'rgba(102,102,102,0.15)',
    todo:        'rgba(59,130,246,0.12)',
    in_progress: 'rgba(245,158,11,0.12)',
    in_review:   'rgba(249,115,22,0.12)',
    done:        'rgba(34,197,94,0.08)',
  };

  let draggingId = $state<string | null>(null);
  let overStatus = $state<TaskStatus | null>(null);

  function handleDragStart(e: DragEvent, taskId: string) {
    draggingId = taskId;
    e.dataTransfer?.setData('text/plain', taskId);
    if (e.dataTransfer) e.dataTransfer.effectAllowed = 'move';
  }

  function handleDragOver(e: DragEvent, status: TaskStatus) {
    e.preventDefault();
    overStatus = status;
    if (e.dataTransfer) e.dataTransfer.dropEffect = 'move';
  }

  function handleDragLeave() { overStatus = null; }

  async function handleDrop(e: DragEvent, status: TaskStatus) {
    e.preventDefault();
    overStatus = null;
    const id = e.dataTransfer?.getData('text/plain') ?? draggingId;
    if (id === null) return;
    const task = tasksStore.tasks.find(t => t.id === id);
    if (task === undefined || task.status === status) { draggingId = null; return; }
    await tasksStore.changeStatus(id!, status);
    draggingId = null;
  }

  function handleDragEnd() { draggingId = null; overStatus = null; }
</script>

<div class="kb-board" role="region" aria-label="Task kanban board">
  {#each COLUMNS as col (col.status)}
    {@const colTasks = tasksStore.kanbanColumns.find(c => c.status === col.status)?.tasks ?? []}
    <section
      class="kb-column"
      class:kb-column--over={overStatus === col.status}
      style="--col-accent: {COL_COLORS[col.status]}"
      aria-label="{col.label} column, {colTasks.length} tasks"
      ondragover={(e) => handleDragOver(e, col.status)}
      ondragleave={handleDragLeave}
      ondrop={(e) => handleDrop(e, col.status)}
    >
      <header class="kb-col-header">
        <span class="kb-col-label">{col.label}</span>
        <span class="kb-col-count" aria-label="{colTasks.length} tasks">{colTasks.length}</span>
      </header>
      <div class="kb-cards" role="list">
        {#each colTasks as task (task.id)}
          <TaskCard
            {task}
            ondragstart={(e) => handleDragStart(e, task.id)}
            ondragend={handleDragEnd}
            onclick={() => onSelect?.(task.id)}
          />
        {/each}
        {#if colTasks.length === 0}
          <div class="kb-empty" role="status" aria-label="No tasks in {col.label}">Drop tasks here</div>
        {/if}
      </div>
    </section>
  {/each}
</div>

<style>
  .kb-board { display: flex; flex-direction: row; gap: 12px; height: 100%; overflow-x: auto; padding-bottom: 8px; }
  .kb-board::-webkit-scrollbar { height: 6px; }
  .kb-board::-webkit-scrollbar-track { background: transparent; }
  .kb-board::-webkit-scrollbar-thumb { background: var(--border-default); border-radius: 3px; }
  .kb-column { min-width: 240px; width: 260px; flex-shrink: 0; display: flex; flex-direction: column; background: var(--col-accent); border: 1px solid var(--border-default); border-radius: var(--radius-md); overflow: hidden; transition: border-color 150ms ease, box-shadow 150ms ease; }
  .kb-column--over { border-color: var(--accent-primary); box-shadow: 0 0 0 2px rgba(59,130,246,0.15); }
  .kb-col-header { display: flex; align-items: center; justify-content: space-between; padding: 10px 12px; border-bottom: 1px solid var(--border-default); flex-shrink: 0; background: rgba(0,0,0,0.15); }
  .kb-col-label { font-size: 12px; font-weight: 600; color: var(--text-secondary); text-transform: uppercase; letter-spacing: 0.04em; }
  .kb-col-count { font-size: 11px; font-weight: 600; color: var(--text-tertiary); background: rgba(255,255,255,0.08); border: 1px solid var(--border-default); border-radius: 9999px; padding: 0 6px; min-width: 20px; height: 20px; display: flex; align-items: center; justify-content: center; }
  .kb-cards { flex: 1; overflow-y: auto; padding: 10px 8px; display: flex; flex-direction: column; gap: 8px; }
  .kb-cards::-webkit-scrollbar { width: 4px; }
  .kb-cards::-webkit-scrollbar-track { background: transparent; }
  .kb-cards::-webkit-scrollbar-thumb { background: var(--border-default); border-radius: 2px; }
  .kb-empty { padding: 24px 12px; text-align: center; font-size: 12px; color: var(--text-muted); border: 1px dashed var(--border-default); border-radius: var(--radius-sm); }
</style>
