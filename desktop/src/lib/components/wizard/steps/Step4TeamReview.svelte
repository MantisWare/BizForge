<!-- src/lib/components/wizard/steps/Step4TeamReview.svelte -->
<script lang="ts">
  import { wizardStore } from '$lib/stores/wizard.svelte';
  import { settingsStore } from '$lib/stores/settings.svelte';
  import { providersStore } from '$lib/stores/providers.svelte';
  import { resolveSkillsForTeam, partitionSkills, lookupLibrarySkills } from '$lib/data/skill-dependencies';
  import type { WizardAgent } from '$api/types';
  import type { AdapterType } from '$api/types';

  let expandedAgent = $state<string | null>(null);

  const groupedAgents = $derived(() => {
    const groups = new Map<string, WizardAgent[]>();
    for (const agent of wizardStore.agents) {
      const list = groups.get(agent.teamId) ?? [];
      list.push(agent);
      groups.set(agent.teamId, list);
    }
    return groups;
  });

  const skillSummary = $derived(() => {
    const allSkillTags = wizardStore.agents.flatMap((a) => a.skills);
    const resolved = lookupLibrarySkills(allSkillTags);
    const { toInstall, alreadyActive } = partitionSkills(resolved);
    return { total: resolved.length, toInstall: toInstall.length, alreadyActive: alreadyActive.length };
  });

  function toggleExpand(id: string): void {
    expandedAgent = expandedAgent === id ? null : id;
  }

  function updateAgentField(id: string, field: keyof WizardAgent, value: string): void {
    wizardStore.agents = wizardStore.agents.map((a) =>
      a.id === id ? { ...a, [field]: value } : a,
    );
  }

  function removeAgent(id: string): void {
    wizardStore.removeAgent(id);
  }

  function applySharedConfig(): void {
    wizardStore.agents = wizardStore.agents.map((a) => ({
      ...a,
      adapter: wizardStore.sharedAdapter,
      model: wizardStore.sharedModel,
    }));
  }

  const models = $derived(providersStore.allModels ?? []);
</script>

<div class="s4-container">
  <h3 class="s4-heading">Review Your Team</h3>
  <p class="s4-desc">Customize agents, roles, and configuration before deployment. Each agent can be individually tuned.</p>

  <!-- Shared config panel -->
  <div class="s4-shared">
    <div class="s4-shared-header">
      <span class="s4-shared-label">Shared Configuration</span>
      <button class="s4-apply-btn" onclick={applySharedConfig}>Apply to all</button>
    </div>
    <div class="s4-shared-fields">
      <label class="s4-field">
        <span class="s4-field-label">Adapter</span>
        <select class="s4-select" bind:value={wizardStore.sharedAdapter}>
          <option value="osa">OSA</option>
          <option value="claude-code">Claude Code</option>
          <option value="cursor-cli">Cursor CLI</option>
          <option value="bash">Bash</option>
        </select>
      </label>
      <label class="s4-field">
        <span class="s4-field-label">Model</span>
        {#if models.length > 0}
          <select class="s4-select" bind:value={wizardStore.sharedModel}>
            {#each models as m}
              <option value={m}>{m}</option>
            {/each}
          </select>
        {:else}
          <input type="text" class="s4-input" bind:value={wizardStore.sharedModel} placeholder="claude-sonnet-4-6" />
        {/if}
      </label>
    </div>
  </div>

  <!-- Agent list by team -->
  <div class="s4-teams">
    {#each [...groupedAgents().entries()] as [teamId, teamAgents] (teamId)}
      {@const teamName = teamAgents[0]?.teamName ?? teamId}
      <div class="s4-team-group">
        <div class="s4-team-header">
          <span class="s4-team-name">{teamName}</span>
          <span class="s4-team-count">{teamAgents.length} agent{teamAgents.length !== 1 ? 's' : ''}</span>
        </div>
        <div class="s4-agent-list">
          {#each teamAgents as agent (agent.id)}
            <div class="s4-agent" class:expanded={expandedAgent === agent.id}>
              <button class="s4-agent-row" onclick={() => toggleExpand(agent.id)}>
                <span class="s4-agent-emoji">{agent.emoji === 'robot' ? '🤖' : agent.emoji === 'flag' ? '🚩' : agent.emoji === 'light-bulb' ? '💡' : agent.emoji === 'code-bracket' ? '💻' : agent.emoji === 'magnifying' ? '🔍' : agent.emoji === 'shield-check' ? '🛡️' : agent.emoji === 'chart-bar' ? '📊' : agent.emoji === 'globe' ? '🌐' : agent.emoji === 'cog' ? '⚙️' : agent.emoji === 'paint-brush' ? '🎨' : agent.emoji === 'document-text' ? '📄' : agent.emoji === 'lock-closed' ? '🔒' : agent.emoji === 'envelope' ? '📧' : agent.emoji === 'circle-stack' ? '🗄️' : agent.emoji === 'chat-bubble' ? '💬' : agent.emoji === 'compass' ? '🧭' : '🤖'}</span>
                <span class="s4-agent-name">{agent.name}</span>
                <span class="s4-agent-role">{agent.role}</span>
                <span class="s4-agent-skills">{agent.skills.length} skills</span>
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="s4-chevron" class:rotated={expandedAgent === agent.id} aria-hidden="true">
                  <path d="M19.5 8.25l-7.5 7.5-7.5-7.5" />
                </svg>
              </button>

              {#if expandedAgent === agent.id}
                <div class="s4-agent-detail">
                  <div class="s4-detail-grid">
                    <label class="s4-field">
                      <span class="s4-field-label">Name</span>
                      <input type="text" class="s4-input" value={agent.name} onchange={(e) => updateAgentField(agent.id, 'name', (e.target as HTMLInputElement).value)} />
                    </label>
                    <label class="s4-field">
                      <span class="s4-field-label">Role</span>
                      <input type="text" class="s4-input" value={agent.role} onchange={(e) => updateAgentField(agent.id, 'role', (e.target as HTMLInputElement).value)} />
                    </label>
                    <label class="s4-field">
                      <span class="s4-field-label">Adapter</span>
                      <select class="s4-select" value={agent.adapter} onchange={(e) => updateAgentField(agent.id, 'adapter', (e.target as HTMLSelectElement).value)}>
                        <option value="osa">OSA</option>
                        <option value="claude-code">Claude Code</option>
                        <option value="cursor-cli">Cursor CLI</option>
                        <option value="bash">Bash</option>
                      </select>
                    </label>
                    <label class="s4-field">
                      <span class="s4-field-label">Model</span>
                      <input type="text" class="s4-input" value={agent.model} onchange={(e) => updateAgentField(agent.id, 'model', (e.target as HTMLInputElement).value)} />
                    </label>
                  </div>
                  <div class="s4-prompt-section">
                    <span class="s4-field-label">System Prompt</span>
                    <textarea
                      class="s4-prompt"
                      rows="4"
                      value={agent.system_prompt}
                      onchange={(e) => updateAgentField(agent.id, 'system_prompt', (e.target as HTMLTextAreaElement).value)}
                    ></textarea>
                  </div>
                  <div class="s4-skill-chips">
                    {#each agent.skills as skill}
                      <span class="s4-skill-chip">{skill}</span>
                    {/each}
                  </div>
                  <button class="s4-remove-btn" onclick={() => removeAgent(agent.id)}>Remove agent</button>
                </div>
              {/if}
            </div>
          {/each}
        </div>
      </div>
    {/each}
  </div>

  <!-- Skill summary -->
  {#if wizardStore.agents.length > 0}
    <div class="s4-skill-summary">
      <span class="s4-skill-summary-text">
        {skillSummary().total} skills will be resolved ({skillSummary().toInstall} new, {skillSummary().alreadyActive} already active)
      </span>
    </div>
  {/if}
</div>

<style>
  .s4-container { max-width: 700px; margin: 0 auto; }
  .s4-heading { font-size: 18px; font-weight: 600; margin: 0 0 6px; color: var(--text-primary); }
  .s4-desc { font-size: 13px; color: var(--text-secondary); margin: 0 0 20px; line-height: 1.5; }

  .s4-shared {
    padding: 14px; border-radius: 10px;
    background: rgba(255,255,255,0.02);
    border: 1px solid var(--border-subtle, rgba(255,255,255,0.06));
    margin-bottom: 20px;
  }
  .s4-shared-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 12px; }
  .s4-shared-label { font-size: 13px; font-weight: 600; color: var(--text-primary); }
  .s4-apply-btn {
    font-size: 11px; padding: 4px 10px; border-radius: 6px;
    background: rgba(249,115,22,0.1); color: var(--accent, #f97316);
    border: none; cursor: pointer; font-weight: 500;
  }
  .s4-apply-btn:hover { background: rgba(249,115,22,0.2); }
  .s4-shared-fields { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }

  .s4-field { display: flex; flex-direction: column; gap: 4px; }
  .s4-field-label { font-size: 11px; font-weight: 500; color: var(--text-secondary); }
  .s4-input, .s4-select {
    background: rgba(255,255,255,0.04);
    border: 1px solid var(--border-subtle, rgba(255,255,255,0.08));
    border-radius: 6px; padding: 7px 10px;
    color: var(--text-primary); font-size: 13px; font-family: inherit;
  }
  .s4-input:focus, .s4-select:focus { outline: none; border-color: var(--accent, #f97316); }
  .s4-select { appearance: auto; }

  .s4-teams { display: flex; flex-direction: column; gap: 16px; }
  .s4-team-group {
    border: 1px solid var(--border-subtle, rgba(255,255,255,0.06));
    border-radius: 10px; overflow: hidden;
  }
  .s4-team-header {
    display: flex; align-items: center; justify-content: space-between;
    padding: 10px 14px;
    background: rgba(255,255,255,0.02);
    border-bottom: 1px solid var(--border-subtle, rgba(255,255,255,0.04));
  }
  .s4-team-name { font-size: 13px; font-weight: 600; color: var(--text-primary); }
  .s4-team-count { font-size: 11px; color: var(--text-tertiary); }
  .s4-agent-list { display: flex; flex-direction: column; }
  .s4-agent { border-bottom: 1px solid var(--border-subtle, rgba(255,255,255,0.03)); }
  .s4-agent:last-child { border-bottom: none; }
  .s4-agent-row {
    display: grid; grid-template-columns: 28px 1fr 120px 70px 20px;
    align-items: center; gap: 8px; padding: 10px 14px;
    background: none; border: none; color: var(--text-primary);
    cursor: pointer; width: 100%; text-align: left; font-size: 13px;
    transition: background 0.1s;
  }
  .s4-agent-row:hover { background: rgba(255,255,255,0.02); }
  .s4-agent-emoji { font-size: 16px; text-align: center; }
  .s4-agent-name { font-weight: 500; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .s4-agent-role { color: var(--text-secondary); font-size: 12px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .s4-agent-skills { color: var(--text-tertiary); font-size: 11px; text-align: right; }
  .s4-chevron { color: var(--text-tertiary); transition: transform 0.15s; justify-self: end; }
  .s4-chevron.rotated { transform: rotate(180deg); }
  .s4-agent-detail { padding: 12px 14px 14px; background: rgba(255,255,255,0.01); }
  .s4-detail-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-bottom: 12px; }
  .s4-prompt-section { margin-bottom: 10px; }
  .s4-prompt {
    width: 100%; background: rgba(255,255,255,0.04);
    border: 1px solid var(--border-subtle, rgba(255,255,255,0.08));
    border-radius: 6px; padding: 8px 10px;
    color: var(--text-primary); font-size: 12px; font-family: inherit;
    resize: vertical; min-height: 60px; margin-top: 4px;
  }
  .s4-prompt:focus { outline: none; border-color: var(--accent, #f97316); }
  .s4-skill-chips { display: flex; flex-wrap: wrap; gap: 4px; margin-bottom: 10px; }
  .s4-skill-chip {
    padding: 2px 8px; border-radius: 4px;
    background: rgba(249,115,22,0.1); color: var(--accent, #f97316);
    font-size: 10px; font-weight: 500;
  }
  .s4-remove-btn {
    background: none; border: none; color: #ef4444;
    font-size: 12px; cursor: pointer; padding: 4px 0;
  }
  .s4-remove-btn:hover { text-decoration: underline; }

  .s4-skill-summary {
    margin-top: 16px; padding: 10px 14px; border-radius: 8px;
    background: rgba(249,115,22,0.05);
    border: 1px solid rgba(249,115,22,0.1);
  }
  .s4-skill-summary-text { font-size: 12px; color: var(--text-secondary); }
</style>
