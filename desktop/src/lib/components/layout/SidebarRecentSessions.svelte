<!-- Sidebar recent sessions quick-resume -->
<script lang="ts">
  import { goto } from '$app/navigation';
  import { sessionsStore } from '$lib/stores/sessions.svelte';
  import { workspaceStore } from '$lib/stores/workspace.svelte';

  interface Props {
    collapsed?: boolean;
  }

  let { collapsed = false }: Props = $props();

  let expanded = $state(true);

  $effect(() => {
    if (collapsed) return;
    const wsId = workspaceStore.activeWorkspaceId ?? undefined;
    void sessionsStore.fetch(wsId);
  });

  const recentSessions = $derived(
    [...sessionsStore.sessions]
      .sort((a, b) => new Date(b.started_at).getTime() - new Date(a.started_at).getTime())
      .slice(0, 6),
  );

  async function resumeSession(sessionId: string): Promise<void> {
    await sessionsStore.fetchById(sessionId);
    void goto(`/app/sessions/${sessionId}`);
  }
</script>

{#if recentSessions.length > 0 && !collapsed}
  <div class="srs">
    <button class="srs-header" onclick={() => { expanded = !expanded; }} aria-expanded={expanded}>
      <span class="srs-title">Recent</span>
      <svg class="srs-caret" class:srs-caret--up={expanded} width="10" height="10" viewBox="0 0 10 10" fill="none" aria-hidden="true">
        <path d="M2 4L5 7L8 4" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/>
      </svg>
    </button>
    {#if expanded}
      <ul class="srs-list">
        {#each recentSessions as session (session.id)}
          <li>
            <button class="srs-item" onclick={() => resumeSession(session.id)}>
              {#if session.status === 'active'}
                <span class="srs-spinner" aria-hidden="true"></span>
              {:else}
                <span class="srs-dot srs-dot--{session.status}" aria-hidden="true"></span>
              {/if}
              <span class="srs-name">{session.agent_name || session.title || 'Session'}</span>
            </button>
          </li>
        {/each}
      </ul>
    {/if}
  </div>
{/if}

<style>
  .srs {
    padding: 4px 8px 8px;
    border-top: 1px solid var(--border-default);
  }
  .srs-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    width: 100%;
    padding: 6px 8px;
    background: none;
    border: none;
    color: var(--text-muted);
    font-size: 10px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    cursor: pointer;
  }
  .srs-list {
    list-style: none;
    margin: 0;
    padding: 0;
  }
  .srs-item {
    display: flex;
    align-items: center;
    gap: 8px;
    width: 100%;
    padding: 6px 8px;
    background: none;
    border: none;
    border-radius: var(--radius-xs);
    color: var(--text-secondary);
    font-size: 12px;
    cursor: pointer;
    text-align: left;
  }
  .srs-item:hover {
    background: var(--bg-surface);
    color: var(--text-primary);
  }
  .srs-name {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .srs-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    flex-shrink: 0;
    background: var(--text-muted);
  }
  .srs-dot--completed { background: var(--accent-success); }
  .srs-dot--failed { background: var(--accent-error); }
  .srs-dot--active { background: var(--accent-primary); }
  .srs-spinner {
    width: 8px;
    height: 8px;
    border: 1.5px solid var(--border-default);
    border-top-color: var(--accent-primary);
    border-radius: 50%;
    animation: spin 0.7s linear infinite;
    flex-shrink: 0;
  }
  .srs-caret { transition: transform 150ms ease; }
  .srs-caret--up { transform: rotate(180deg); }
</style>
