<!-- src/routes/app/tasks/+page.svelte -->
<script lang="ts">
  import { page } from '$app/stores';
  import { goto } from '$app/navigation';
  import type { Task } from '$api/types';

  import PageShell from '$lib/components/layout/PageShell.svelte';
  import TaskViewSwitcher from '$lib/components/tasks/TaskViewSwitcher.svelte';
  import TaskKanban from '$lib/components/tasks/TaskKanban.svelte';
  import TaskList from '$lib/components/tasks/TaskList.svelte';
  import TaskTable from '$lib/components/tasks/TaskTable.svelte';
  import TaskForm from '$lib/components/tasks/TaskForm.svelte';
  import { tasksStore } from '$lib/stores/tasks.svelte';
  import { agentsStore } from '$lib/stores/agents.svelte';
  import { workspaceStore } from '$lib/stores/workspace.svelte';

  type ViewMode = 'kanban' | 'list' | 'table';
  let viewMode = $state<ViewMode>('kanban');
  let showForm = $state(false);

  $effect(() => {
    showForm = $page.url.searchParams.get('new') === '1';
  });

  $effect(() => {
    const wsId = workspaceStore.activeWorkspaceId ?? undefined;
    void Promise.all([
      tasksStore.fetchTasks(wsId),
      agentsStore.fetchAgents(wsId),
    ]);
  });

  function openNewTask() { goto('?new=1'); }
  function closeForm() { goto('?'); }

  async function handleSubmit(data: Partial<Task>) {
    await tasksStore.createTask(data);
    closeForm();
  }
</script>

<PageShell title="Tasks" badge={tasksStore.tasks.length}>
  {#snippet actions()}
    <TaskViewSwitcher {viewMode} onViewChange={(m) => viewMode = m} onNewTask={openNewTask} />
  {/snippet}

  <div class="ip-content" class:ip-content--kanban={viewMode === 'kanban'}>
    {#if tasksStore.loading && tasksStore.tasks.length === 0}
      <div class="ip-loading" role="status" aria-label="Loading tasks">
        <div class="ip-spinner" aria-hidden="true"></div>
        <span>Loading tasks…</span>
      </div>
    {:else if viewMode === 'kanban'}
      <TaskKanban />
    {:else if viewMode === 'list'}
      <TaskList tasks={tasksStore.filteredTasks} />
    {:else}
      <TaskTable tasks={tasksStore.filteredTasks} />
    {/if}
  </div>
</PageShell>

{#if showForm}
  <TaskForm onSubmit={handleSubmit} onCancel={closeForm} />
{/if}

<style>
  .ip-content { height: 100%; display: flex; flex-direction: column; }
  .ip-content--kanban { overflow: hidden; }
  .ip-loading { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 12px; height: 200px; color: var(--text-tertiary); font-size: 13px; }
  .ip-spinner { width: 24px; height: 24px; border: 2px solid var(--border-default); border-top-color: var(--accent-primary); border-radius: 50%; animation: ip-spin 0.7s linear infinite; }
  @keyframes ip-spin { to { transform: rotate(360deg); } }
</style>
