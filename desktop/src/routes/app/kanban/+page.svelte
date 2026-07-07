<!-- Dedicated Kanban board page -->
<script lang="ts">
  import { goto } from '$app/navigation';
  import type { Task } from '$api/types';
  import PageShell from '$lib/components/layout/PageShell.svelte';
  import TaskKanban from '$lib/components/tasks/TaskKanban.svelte';
  import TaskForm from '$lib/components/tasks/TaskForm.svelte';
  import EmptyState from '$lib/components/ui/EmptyState.svelte';
  import Button from '$lib/components/ui/Button.svelte';
  import { tasksStore } from '$lib/stores/tasks.svelte';
  import { agentsStore } from '$lib/stores/agents.svelte';
  import { workspaceStore } from '$lib/stores/workspace.svelte';

  let showForm = $state(false);
  let selectedTaskId = $state<string | null>(null);

  const selectedTask = $derived(
    selectedTaskId
      ? tasksStore.tasks.find((t) => t.id === selectedTaskId) ?? null
      : null,
  );

  $effect(() => {
    const wsId = workspaceStore.activeWorkspaceId ?? undefined;
    void Promise.all([
      tasksStore.fetchTasks(wsId),
      agentsStore.fetchAgents(wsId),
    ]);
  });

  async function handleSubmit(data: Partial<Task>): Promise<void> {
    await tasksStore.createTask(data);
    showForm = false;
  }
</script>

<PageShell title="Kanban" badge={tasksStore.tasks.length}>
  {#snippet actions()}
    <Button variant="primary" onclick={() => { showForm = true; }}>New Task</Button>
  {/snippet}

  <div class="kb-page">
    {#if tasksStore.loading && tasksStore.tasks.length === 0}
      <div class="kb-loading" role="status">Loading board…</div>
    {:else if tasksStore.tasks.length === 0}
      <EmptyState
        title="No tasks yet"
        description="Create tasks and drag them across columns to track agent work."
      >
        {#snippet actions()}
          <Button variant="primary" onclick={() => { showForm = true; }}>Create first task</Button>
        {/snippet}
      </EmptyState>
    {:else}
      <TaskKanban onSelect={(id) => { selectedTaskId = id; }} />
    {/if}
  </div>
</PageShell>

{#if selectedTask}
  <aside class="kb-drawer" aria-label="Task details">
    <header class="kb-drawer-header">
      <h3>{selectedTask.title}</h3>
      <button class="kb-drawer-close" onclick={() => { selectedTaskId = null; }} aria-label="Close">×</button>
    </header>
    <div class="kb-drawer-body">
      <p class="kb-drawer-status">Status: {selectedTask.status.replace('_', ' ')}</p>
      {#if selectedTask.description}
        <p>{selectedTask.description}</p>
      {/if}
      {#if selectedTask.assignee_name ?? selectedTask.assignee_id}
        <p class="kb-drawer-assignee">Assignee: {selectedTask.assignee_name ?? selectedTask.assignee_id}</p>
      {/if}
      <Button variant="secondary" onclick={() => void goto(`/app/tasks?selected=${selectedTask.id}`)}>
        Open in Tasks
      </Button>
    </div>
  </aside>
{/if}

{#if showForm}
  <TaskForm onSubmit={handleSubmit} onCancel={() => { showForm = false; }} />
{/if}

<style>
  .kb-page {
    height: 100%;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }
  .kb-loading {
    display: flex;
    align-items: center;
    justify-content: center;
    height: 200px;
    color: var(--text-tertiary);
    font-size: 13px;
  }
  .kb-drawer {
    position: fixed;
    top: 0;
    right: 0;
    width: 360px;
    height: 100%;
    background: var(--bg-secondary);
    border-left: 1px solid var(--border-default);
    z-index: 500;
    display: flex;
    flex-direction: column;
    box-shadow: var(--shadow-lg);
  }
  .kb-drawer-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 16px;
    border-bottom: 1px solid var(--border-default);
  }
  .kb-drawer-header h3 {
    margin: 0;
    font-size: 14px;
    font-weight: 600;
    color: var(--text-primary);
  }
  .kb-drawer-close {
    background: none;
    border: none;
    color: var(--text-muted);
    font-size: 20px;
    cursor: pointer;
  }
  .kb-drawer-body {
    padding: 16px;
    font-size: 13px;
    color: var(--text-secondary);
    display: flex;
    flex-direction: column;
    gap: 12px;
  }
  .kb-drawer-status {
    text-transform: capitalize;
    font-weight: 500;
    color: var(--text-primary);
  }
  .kb-drawer-assignee {
    font-size: 12px;
    color: var(--text-muted);
  }
</style>
