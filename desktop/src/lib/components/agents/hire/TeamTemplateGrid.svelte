<!-- src/lib/components/agents/hire/TeamTemplateGrid.svelte -->
<script lang="ts">
  import { HIREABLE_TEAM_TEMPLATES, TEMPLATE_AGENTS } from '$lib/data/team-templates';
  import type { TeamTemplateId, TeamTemplateMeta } from '$lib/data/team-templates';
  import AgentIcon from '$lib/components/shared/AgentIcon.svelte';

  interface Props {
    onSelect: (templateId: TeamTemplateId) => void;
  }

  let { onSelect }: Props = $props();

  let hoveredId = $state<TeamTemplateId | null>(null);
  const previewAgents = $derived(
    hoveredId !== null ? TEMPLATE_AGENTS[hoveredId] : [],
  );
</script>

<div class="ttg-root">
  <p class="ttg-heading">Choose a team template</p>
  <p class="ttg-subtext">Select a pre-built team to hire multiple agents at once.</p>

  <div class="ttg-grid" role="listbox" aria-label="Team templates">
    {#each HIREABLE_TEAM_TEMPLATES as t (t.id)}
      <button
        class="ttg-card"
        role="option"
        aria-selected="false"
        onmouseenter={() => hoveredId = t.id}
        onmouseleave={() => hoveredId = null}
        onclick={() => onSelect(t.id)}
      >
        <div class="ttg-card-top">
          <span class="ttg-card-name">
            <AgentIcon value={t.icon} size={15} />
            {t.name}
          </span>
          <span class="ttg-card-count">
            {t.count === 1 ? '1 agent' : `${t.count} agents`}
          </span>
        </div>
        <p class="ttg-card-desc">{t.description}</p>
        <div class="ttg-card-agents" aria-label="Agents in template">
          {#each TEMPLATE_AGENTS[t.id] as agent (agent.id)}
            <span class="ttg-agent-chip">
              <AgentIcon value={agent.emoji} size={12} />
              <span class="ttg-agent-chip-name">{agent.name}</span>
            </span>
          {/each}
        </div>
      </button>
    {/each}
  </div>
</div>

<style>
  .ttg-root {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .ttg-heading {
    font-size: 14px;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0;
  }

  .ttg-subtext {
    font-size: 12px;
    color: var(--text-muted);
    margin: 0 0 12px;
  }

  .ttg-grid {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 10px;
  }

  .ttg-card {
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding: 14px;
    border-radius: var(--radius-md, 8px);
    border: 1px solid var(--border-default);
    background: var(--bg-surface);
    cursor: pointer;
    text-align: left;
    transition: background 120ms ease, border-color 120ms ease, box-shadow 120ms ease;
  }

  .ttg-card:hover {
    border-color: rgba(249, 115, 22, 0.4);
    background: rgba(249, 115, 22, 0.06);
    box-shadow: 0 0 0 1px rgba(249, 115, 22, 0.15);
  }

  .ttg-card:active {
    transform: scale(0.99);
  }

  .ttg-card-top {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 8px;
  }

  .ttg-card-name {
    font-size: 13px;
    font-weight: 600;
    color: var(--text-primary);
    display: inline-flex;
    align-items: center;
    gap: 6px;
  }

  .ttg-card-count {
    font-size: 11px;
    color: var(--text-tertiary);
    flex-shrink: 0;
  }

  .ttg-card-desc {
    font-size: 11px;
    color: var(--text-muted);
    margin: 0;
    line-height: 1.4;
  }

  .ttg-card-agents {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
    margin-top: 4px;
  }

  .ttg-agent-chip {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    padding: 2px 7px 2px 4px;
    border-radius: 100px;
    background: rgba(255, 255, 255, 0.04);
    border: 1px solid rgba(255, 255, 255, 0.06);
    font-size: 10px;
    color: var(--text-secondary);
  }

  .ttg-agent-chip-name {
    white-space: nowrap;
  }
</style>
