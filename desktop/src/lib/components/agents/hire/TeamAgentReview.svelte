<!-- src/lib/components/agents/hire/TeamAgentReview.svelte -->
<script lang="ts">
  import type { AgentTemplateData } from '$lib/stores/onboarding.svelte';
  import AgentIcon from '$lib/components/shared/AgentIcon.svelte';
  import { getTemplatesForRole } from '$lib/data/prompt-templates';

  interface Props {
    agents: AgentTemplateData[];
    onUpdate: (agents: AgentTemplateData[]) => void;
  }

  let { agents, onUpdate }: Props = $props();

  let expandedId = $state<string | null>(null);

  function removeAgent(id: string) {
    onUpdate(agents.filter((a) => a.id !== id));
  }

  function updateField(id: string, field: keyof AgentTemplateData, value: string) {
    onUpdate(
      agents.map((a) => (a.id === id ? { ...a, [field]: value } : a)),
    );
  }

  function toggleExpand(id: string) {
    expandedId = expandedId === id ? null : id;
  }
</script>

<div class="tar-root">
  <div class="tar-header">
    <p class="tar-heading">Review agents</p>
    <span class="tar-count">{agents.length} agent{agents.length === 1 ? '' : 's'}</span>
  </div>
  <p class="tar-subtext">Edit names, roles, or remove agents you don't need.</p>

  {#if agents.length === 0}
    <div class="tar-empty" role="status">
      <p>All agents removed. Go back to pick a different template.</p>
    </div>
  {:else}
    <ul class="tar-list" role="list" aria-label="Agents to hire">
      {#each agents as agent (agent.id)}
        <li class="tar-item">
          <div class="tar-row">
            <span class="tar-icon">
              <AgentIcon value={agent.emoji} size={18} />
            </span>

            <div class="tar-fields">
              <input
                class="tar-input tar-input--name"
                type="text"
                value={agent.name}
                oninput={(e) => updateField(agent.id, 'name', (e.target as HTMLInputElement).value)}
                aria-label="Agent display name"
                placeholder="Name"
              />
              <input
                class="tar-input tar-input--role"
                type="text"
                value={agent.role}
                oninput={(e) => updateField(agent.id, 'role', (e.target as HTMLInputElement).value)}
                aria-label="Agent role"
                placeholder="Role"
              />
            </div>

            <div class="tar-skills">
              {#each agent.skills as skill}
                <span class="tar-skill">{skill}</span>
              {/each}
            </div>

            <div class="tar-actions">
              <button
                class="tar-btn-expand"
                onclick={() => toggleExpand(agent.id)}
                aria-label={expandedId === agent.id ? 'Collapse details' : 'Expand details'}
                aria-expanded={expandedId === agent.id}
                title="Edit system prompt"
              >
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                  {#if expandedId === agent.id}
                    <path d="M18 15l-6-6-6 6" />
                  {:else}
                    <path d="M6 9l6 6 6-6" />
                  {/if}
                </svg>
              </button>
              <button
                class="tar-btn-remove"
                onclick={() => removeAgent(agent.id)}
                aria-label="Remove {agent.name}"
                title="Remove from team"
              >
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                  <path d="M18 6 6 18M6 6l12 12" />
                </svg>
              </button>
            </div>
          </div>

          {#if expandedId === agent.id}
            {@const promptGroup = getTemplatesForRole(agent.role)}
            <div class="tar-expanded">
              <label class="tar-prompt-label" for="tar-prompt-{agent.id}">System prompt</label>
              <div class="tar-tpl-row">
                {#each promptGroup.templates as tpl (tpl.id)}
                  <button
                    type="button"
                    class="tar-tpl-btn"
                    onclick={() => updateField(agent.id, 'system_prompt', tpl.prompt)}
                    title={tpl.prompt}
                  >{tpl.label}</button>
                {/each}
              </div>
              <textarea
                id="tar-prompt-{agent.id}"
                class="tar-textarea"
                rows="3"
                value={agent.system_prompt ?? ''}
                oninput={(e) => updateField(agent.id, 'system_prompt', (e.target as HTMLTextAreaElement).value)}
                placeholder="Optional system prompt for this agent…"
              ></textarea>
            </div>
          {/if}
        </li>
      {/each}
    </ul>
  {/if}
</div>

<style>
  .tar-root {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .tar-header {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 8px;
  }

  .tar-heading {
    font-size: 14px;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0;
  }

  .tar-count {
    font-size: 11px;
    color: var(--text-tertiary);
  }

  .tar-subtext {
    font-size: 12px;
    color: var(--text-muted);
    margin: 0 0 10px;
  }

  .tar-empty {
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 32px 16px;
    border: 1px dashed var(--border-default);
    border-radius: var(--radius-md, 8px);
    color: var(--text-muted);
    font-size: 13px;
  }

  .tar-empty p {
    margin: 0;
  }

  .tar-list {
    list-style: none;
    padding: 0;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .tar-item {
    border: 1px solid var(--border-default);
    border-radius: var(--radius-sm);
    background: var(--bg-surface);
    overflow: hidden;
    transition: border-color 120ms ease;
  }

  .tar-item:hover {
    border-color: var(--border-hover);
  }

  .tar-row {
    display: grid;
    grid-template-columns: 28px minmax(120px, 1.5fr) minmax(90px, 1fr) 1fr auto;
    align-items: center;
    gap: 10px;
    padding: 10px 12px;
  }

  .tar-icon {
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
    width: 28px;
    height: 28px;
    border-radius: var(--radius-xs, 4px);
    background: rgba(255, 255, 255, 0.04);
  }

  .tar-fields {
    display: contents;
  }

  .tar-input {
    height: 28px;
    padding: 0 8px;
    border-radius: var(--radius-xs, 4px);
    border: 1px solid transparent;
    background: transparent;
    color: var(--text-primary);
    font-size: 12px;
    font-family: var(--font-sans);
    outline: none;
    transition: border-color 120ms ease, background 120ms ease;
    min-width: 0;
  }

  .tar-input:hover {
    border-color: var(--border-default);
    background: var(--bg-elevated);
  }

  .tar-input:focus {
    border-color: var(--border-focus);
    background: var(--bg-elevated);
  }

  .tar-input--name {
    font-weight: 600;
  }

  .tar-input--role {
    color: var(--text-secondary);
  }

  .tar-skills {
    display: flex;
    gap: 4px;
    flex-shrink: 0;
    overflow: hidden;
  }

  .tar-skill {
    font-size: 10px;
    padding: 1px 6px;
    border-radius: 100px;
    background: rgba(255, 255, 255, 0.04);
    color: var(--text-muted);
    white-space: nowrap;
  }

  .tar-actions {
    display: flex;
    gap: 4px;
    flex-shrink: 0;
  }

  .tar-btn-expand,
  .tar-btn-remove {
    width: 26px;
    height: 26px;
    border: 1px solid transparent;
    border-radius: var(--radius-xs, 4px);
    background: transparent;
    color: var(--text-muted);
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: all 120ms ease;
  }

  .tar-btn-expand:hover {
    background: var(--bg-elevated);
    border-color: var(--border-default);
    color: var(--text-primary);
  }

  .tar-btn-remove:hover {
    background: rgba(239, 68, 68, 0.12);
    border-color: rgba(239, 68, 68, 0.3);
    color: #f87171;
  }

  .tar-expanded {
    padding: 0 12px 12px;
    display: flex;
    flex-direction: column;
    gap: 4px;
    border-top: 1px solid var(--border-default);
    padding-top: 10px;
    margin: 0 12px;
  }

  .tar-prompt-label {
    font-size: 11px;
    font-weight: 500;
    color: var(--text-tertiary);
  }

  .tar-tpl-row {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
  }

  .tar-tpl-btn {
    height: 22px;
    padding: 0 8px;
    border-radius: 100px;
    border: 1px solid var(--border-default);
    background: var(--bg-elevated);
    color: var(--text-secondary);
    font-size: 10px;
    font-family: var(--font-sans);
    cursor: pointer;
    white-space: nowrap;
    transition: all 120ms ease;
  }

  .tar-tpl-btn:hover {
    border-color: rgba(249, 115, 22, 0.4);
    background: rgba(249, 115, 22, 0.08);
    color: var(--text-primary);
  }

  .tar-tpl-btn:active {
    transform: scale(0.97);
  }

  .tar-textarea {
    width: 100%;
    padding: 8px;
    border-radius: var(--radius-sm);
    border: 1px solid var(--border-default);
    background: var(--bg-elevated);
    color: var(--text-primary);
    font-size: 12px;
    font-family: var(--font-sans);
    line-height: 1.5;
    resize: vertical;
    outline: none;
    transition: border-color 120ms ease;
  }

  .tar-textarea:focus {
    border-color: var(--border-focus);
  }
</style>
