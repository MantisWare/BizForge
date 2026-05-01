<!-- src/lib/components/library/LibraryAgentCard.svelte -->
<script lang="ts">
  import type { LibraryAgent } from '$lib/api/mock/library';
  import AgentIcon from '$lib/components/shared/AgentIcon.svelte';

  interface Props {
    agent: LibraryAgent;
    onAdd?: (agent: LibraryAgent) => void;
  }

  let { agent, onAdd }: Props = $props();

  let added = $state(false);

  function handleAdd() {
    added = true;
    onAdd?.(agent);
    setTimeout(() => { added = false; }, 2000);
  }
</script>

<article class="lac-card" aria-label={agent.name}>
  <!-- Top row: emoji + name + visibility icon -->
  <div class="lac-top">
    <span class="lac-emoji" aria-hidden="true"><AgentIcon value={agent.emoji} size={24} /></span>
    <div class="lac-name-wrap">
      <div class="lac-name">{agent.name}</div>
      <div class="lac-badges">
        <span class="lac-role-badge">{agent.category}</span>
        {#if agent.isOfficial}
          <span class="lac-source-badge lac-source-badge--official">official</span>
        {:else}
          <span class="lac-source-badge lac-source-badge--community">community</span>
        {/if}
      </div>
    </div>
    <span class="lac-version">v{agent.version}</span>
    <span class="lac-visibility" title={agent.visibility === 'public' ? 'Public — visible to everyone' : agent.visibility === 'unlisted' ? 'Unlisted — only accessible via direct link' : 'Private — only visible to you'} aria-label="Visibility: {agent.visibility}">
      {#if agent.visibility === 'public'}
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/>
          <circle cx="12" cy="12" r="3"/>
        </svg>
      {:else if agent.visibility === 'unlisted'}
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <path d="M17.94 17.94A10.07 10.07 0 0112 20c-7 0-11-8-11-8a18.45 18.45 0 015.06-5.94"/>
          <path d="M9.9 4.24A9.12 9.12 0 0112 4c7 0 11 8 11 8a18.5 18.5 0 01-2.16 3.19"/>
          <line x1="1" y1="1" x2="23" y2="23"/>
        </svg>
      {:else}
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <rect x="3" y="11" width="18" height="11" rx="2" ry="2"/>
          <path d="M7 11V7a5 5 0 0110 0v4"/>
        </svg>
      {/if}
    </span>
  </div>

  <!-- Description -->
  <p class="lac-desc">{agent.description}</p>

  <!-- Tags -->
  <div class="lac-tags" aria-label="Tags">
    {#each agent.tags.slice(0, 3) as tag}
      <span class="lac-tag">{tag}</span>
    {/each}
  </div>

  <!-- CTA button -->
  <button
    class="lac-btn"
    class:lac-btn--added={added}
    onclick={handleAdd}
    aria-label="{added ? 'Added' : 'Add'} {agent.name} to workspace"
    type="button"
  >
    {added ? '✓ Added' : 'Add to Workspace'}
  </button>
</article>

<style>
  .lac-card {
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding: 16px;
    border-radius: var(--radius-md);
    background: rgba(255, 255, 255, 0.03);
    border: 1px solid rgba(255, 255, 255, 0.07);
    backdrop-filter: blur(12px);
    transition:
      border-color 150ms ease,
      transform 150ms ease,
      background 150ms ease,
      box-shadow 150ms ease;
    cursor: default;
  }

  .lac-card:hover {
    border-color: rgba(255, 255, 255, 0.14);
    background: rgba(255, 255, 255, 0.05);
    transform: translateY(-2px);
    box-shadow: 0 4px 24px rgba(0, 0, 0, 0.25), 0 0 0 1px rgba(255, 255, 255, 0.06);
  }

  /* Top row */
  .lac-top {
    display: flex;
    align-items: flex-start;
    gap: 10px;
  }

  .lac-emoji {
    display: flex;
    align-items: center;
    color: #f26522;
    flex-shrink: 0;
    margin-top: 1px;
  }

  .lac-name-wrap {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 5px;
  }

  .lac-name {
    font-size: 14px;
    font-weight: 600;
    color: var(--text-primary);
    line-height: 1.3;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .lac-badges {
    display: flex;
    align-items: center;
    gap: 5px;
    flex-wrap: wrap;
  }

  .lac-role-badge {
    display: inline-block;
    font-size: 10px;
    font-weight: 500;
    padding: 2px 7px;
    border-radius: var(--radius-full);
    text-transform: capitalize;
    letter-spacing: 0.02em;
    background: rgba(255, 255, 255, 0.06);
    color: var(--text-secondary);
    border: 1px solid rgba(255, 255, 255, 0.09);
  }

  .lac-source-badge {
    display: inline-block;
    font-size: 9px;
    font-weight: 600;
    padding: 2px 6px;
    border-radius: var(--radius-full);
    text-transform: uppercase;
    letter-spacing: 0.06em;
  }

  .lac-source-badge--official {
    background: rgba(249, 115, 22, 0.15);
    color: #fdba74;
    border: 1px solid rgba(249, 115, 22, 0.25);
  }

  .lac-source-badge--community {
    background: rgba(255, 255, 255, 0.05);
    color: var(--text-tertiary);
    border: 1px solid rgba(255, 255, 255, 0.08);
  }

  .lac-version {
    flex-shrink: 0;
    font-size: 10px;
    color: var(--text-muted);
    font-variant-numeric: tabular-nums;
    margin-top: 4px;
  }

  .lac-visibility {
    flex-shrink: 0;
    color: var(--text-muted);
    display: flex;
    align-items: center;
    margin-top: 3px;
    cursor: help;
  }

  /* Description */
  .lac-desc {
    font-size: 12px;
    color: var(--text-secondary);
    line-height: 1.55;
    margin: 0;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }

  /* Tags */
  .lac-tags {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
  }

  .lac-tag {
    font-size: 10px;
    font-weight: 500;
    padding: 2px 7px;
    border-radius: var(--radius-full);
    background: rgba(255, 255, 255, 0.04);
    color: var(--text-tertiary);
    border: 1px solid rgba(255, 255, 255, 0.07);
    text-transform: lowercase;
  }

  /* CTA */
  .lac-btn {
    width: 100%;
    padding: 7px 12px;
    border-radius: var(--radius-sm);
    border: 1px solid var(--border-default);
    background: rgba(255, 255, 255, 0.04);
    color: var(--text-secondary);
    font-size: 12px;
    font-weight: 500;
    cursor: pointer;
    transition: all 150ms ease;
    white-space: nowrap;
  }

  .lac-btn:hover {
    background: rgba(59, 130, 246, 0.12);
    border-color: rgba(59, 130, 246, 0.3);
    color: #7ab3f8;
  }

  .lac-btn--added {
    background: rgba(34, 197, 94, 0.08);
    border-color: rgba(34, 197, 94, 0.22);
    color: rgba(34, 197, 94, 0.6);
  }

  .lac-btn:focus-visible {
    outline: 2px solid var(--accent-primary);
    outline-offset: 2px;
  }
</style>
