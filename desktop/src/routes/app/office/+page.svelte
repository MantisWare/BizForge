<!-- src/routes/app/office/+page.svelte -->
<script lang="ts">
  import PageShell from '$lib/components/layout/PageShell.svelte';
  import VirtualOffice from '$lib/components/office/VirtualOffice.svelte';
  import LoadingSpinner from '$lib/components/shared/LoadingSpinner.svelte';
  import AgentIcon from '$lib/components/shared/AgentIcon.svelte';
  import { agentsStore } from '$lib/stores/agents.svelte';
  import { workspaceStore } from '$lib/stores/workspace.svelte';

  let viewMode = $state<'2d' | '3d'>('2d');

  // Re-fetch whenever the active workspace changes (mirrors /app/agents pattern)
  $effect(() => {
    const wsId = workspaceStore.activeWorkspaceId ?? undefined;
    void agentsStore.fetchAgents(wsId);
  });
</script>

<PageShell
  title="Virtual Office"
  subtitle="{agentsStore.activeCount} active · {agentsStore.totalCount} total"
  noPadding
>
  {#snippet actions()}
    <span class="op-hint">Click an agent to inspect</span>
  {/snippet}

  {#snippet children()}
    {#if agentsStore.loading && agentsStore.agents.length === 0}
      <div class="op-loading" aria-label="Loading office" aria-live="polite">
        <LoadingSpinner size="md" />
        <span>Loading agents…</span>
      </div>
    {:else if agentsStore.error && agentsStore.agents.length === 0}
      <div class="op-empty" role="status">
        {#if agentsStore.error.includes('not_found') || agentsStore.error.includes('unauthorized')}
          <span class="op-empty-icon" aria-hidden="true"><AgentIcon value="office-building" size={32} /></span>
          <p class="op-empty-title">Your office is empty</p>
          <p class="op-empty-desc">Deploy agents from the Library to populate your virtual office.</p>
          <a class="op-empty-action" href="/app/library">Browse Library</a>
        {:else}
          <span class="op-empty-icon" aria-hidden="true"><AgentIcon value="warning" size={32} /></span>
          <p class="op-empty-title">Couldn't load agents</p>
          <p class="op-empty-desc">Something went wrong. Check your connection and try again.</p>
          <button
            class="op-retry-btn"
            onclick={() => void agentsStore.fetchAgents(workspaceStore.activeWorkspaceId ?? undefined)}
          >
            Retry
          </button>
        {/if}
      </div>
    {:else}
      <VirtualOffice
        agents={agentsStore.agents}
        {viewMode}
        onViewModeChange={(m) => { viewMode = m; }}
      />
    {/if}
  {/snippet}
</PageShell>

<style>
  .op-hint {
    font-size: 12px;
    color: var(--text-muted, #4a4870);
  }

  .op-loading {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 12px;
    height: 100%;
    min-height: 300px;
    color: var(--text-tertiary);
    font-size: 13px;
  }

  .op-empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 8px;
    height: 100%;
    min-height: 300px;
    text-align: center;
    padding: 24px;
  }

  .op-empty-icon {
    display: flex;
    align-items: center;
    color: #f26522;
    margin-bottom: 4px;
  }

  .op-empty-title {
    font-size: 15px;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0;
  }

  .op-empty-desc {
    font-size: 13px;
    color: var(--text-tertiary);
    margin: 0;
    max-width: 320px;
    line-height: 1.5;
  }

  .op-empty-action {
    display: inline-flex;
    align-items: center;
    margin-top: 8px;
    padding: 7px 18px;
    border-radius: 6px;
    background: #f26522;
    color: #fff;
    font-size: 13px;
    font-weight: 500;
    text-decoration: none;
    transition: background 0.15s;
  }

  .op-empty-action:hover {
    background: #d9551a;
  }

  .op-retry-btn {
    margin-top: 8px;
    padding: 6px 16px;
    border-radius: 6px;
    border: 1px solid var(--border-default, #2a2848);
    background: transparent;
    color: var(--text-secondary);
    font-size: 12px;
    cursor: pointer;
    transition: all 120ms ease;
  }

  .op-retry-btn:hover {
    background: #1e1e38;
    border-color: #3a3860;
    color: var(--text-primary);
  }
</style>
