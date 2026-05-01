<!-- src/lib/components/agents/HireTeamDialog.svelte -->
<script lang="ts">
  import { onMount } from 'svelte';
  import { agentsStore } from '$lib/stores/agents.svelte';
  import { settingsStore } from '$lib/stores/settings.svelte';
  import { providersStore } from '$lib/stores/providers.svelte';
  import { skillsStore } from '$lib/stores/skills.svelte';
  import { teams as teamsApi } from '$api/client';
  import { HIREABLE_TEAM_TEMPLATES, TEMPLATE_AGENTS } from '$lib/data/team-templates';
  import type { TeamTemplateId } from '$lib/data/team-templates';
  import type { AgentTemplateData } from '$lib/stores/onboarding.svelte';
  import type { AgentCreateRequest, AdapterType } from '$api/types';
  import {
    resolveSkillsForTeam,
    partitionSkills,
    lookupLibrarySkills,
  } from '$lib/data/skill-dependencies';
  import type { LibrarySkill } from '$lib/api/mock/library/types';

  import { getTemplatesForRole } from '$lib/data/prompt-templates';
  import TeamTemplateGrid from './hire/TeamTemplateGrid.svelte';
  import TeamAgentReview from './hire/TeamAgentReview.svelte';
  import AgentAdapterPicker from './hire/AgentAdapterPicker.svelte';
  import AgentBudgetConfig from './hire/AgentBudgetConfig.svelte';

  interface Props {
    open: boolean;
    onClose: () => void;
  }

  let { open, onClose }: Props = $props();

  type Step = 'template' | 'review' | 'config';

  let step = $state<Step>('template');
  let selectedTemplateId = $state<TeamTemplateId | null>(null);
  let agents = $state<AgentTemplateData[]>([]);

  // Shared config (step 3)
  let adapter = $state<AdapterType>(settingsStore.data.default_adapter ?? 'osa');
  let model = $state('claude-sonnet-4-6');
  let providerId = $state('');
  let teamName = $state('');
  let createTeamEntity = $state(true);
  let dailyLimitDollars = $state('10.00');
  let monthlyLimitDollars = $state('100.00');
  let warningThreshold = $state(80);
  let hardStop = $state(true);

  let isSubmitting = $state(false);
  let progress = $state(0);

  onMount(() => {
    if (providersStore.totalCount === 0) void providersStore.fetch();
  });

  const STUB_PROMPT_THRESHOLD = 120;

  function assignDefaultPrompt(agent: AgentTemplateData): AgentTemplateData {
    const existing = agent.system_prompt ?? '';
    if (existing.length >= STUB_PROMPT_THRESHOLD) return agent;

    const group = getTemplatesForRole(agent.role);
    const bestTemplate = group.templates[0];
    if (bestTemplate === undefined) return agent;

    return { ...agent, system_prompt: bestTemplate.prompt };
  }

  function selectTemplate(id: TeamTemplateId) {
    selectedTemplateId = id;
    agents = TEMPLATE_AGENTS[id].map((a) => assignDefaultPrompt({ ...a }));
    const meta = HIREABLE_TEAM_TEMPLATES.find((t) => t.id === id);
    teamName = meta?.name ?? '';
    step = 'review';
  }

  function goBack() {
    if (step === 'review') {
      step = 'template';
    } else if (step === 'config') {
      step = 'review';
    }
  }

  function goToConfig() {
    if (agents.length === 0) return;
    step = 'config';
  }

  function toSlug(name: string): string {
    return name
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/(^-|-$)/g, '');
  }

  async function handleSubmit() {
    if (agents.length === 0) return;

    isSubmitting = true;
    progress = 0;

    // Install required skills before creating agents
    if (teamSkillPartition.toAdd.length > 0) {
      await skillsStore.installFromLibrary(teamSkillPartition.toAdd);
    }

    const requests: AgentCreateRequest[] = agents.map((a) => ({
      name: toSlug(a.name),
      display_name: a.name,
      avatar_emoji: a.emoji,
      role: a.role,
      adapter,
      model,
      provider_id: providerId || undefined,
      system_prompt: a.system_prompt ?? undefined,
      skills: a.skills.length > 0 ? a.skills : undefined,
      budget_policy: {
        daily_limit_cents: Math.round(parseFloat(dailyLimitDollars) * 100),
        monthly_limit_cents: Math.round(parseFloat(monthlyLimitDollars) * 100),
        warning_threshold: warningThreshold / 100,
        hard_stop: hardStop,
      },
    }));

    const result = await agentsStore.createAgentBatch(requests);
    progress = 100;

    if (createTeamEntity && result.created.length > 0) {
      try {
        const team = await teamsApi.create({ name: teamName.trim() || 'New Team' });
        for (const created of result.created) {
          try {
            await teamsApi.addMember(team.id, created.id);
          } catch {
            // membership assignment is best-effort
          }
        }
      } catch {
        // team creation is best-effort; agents are already created
      }
    }

    isSubmitting = false;
    if (result.created.length > 0) {
      resetAndClose();
    }
  }

  function resetAndClose() {
    step = 'template';
    selectedTemplateId = null;
    agents = [];
    adapter = settingsStore.data.default_adapter ?? 'osa';
    model = 'claude-sonnet-4-6';
    providerId = providersStore.defaultProvider?.id ?? '';
    teamName = '';
    createTeamEntity = true;
    dailyLimitDollars = '10.00';
    monthlyLimitDollars = '100.00';
    warningThreshold = 80;
    hardStop = true;
    progress = 0;
    onClose();
  }

  function handleBackdrop(e: MouseEvent) {
    if ((e.target as HTMLElement).classList.contains('htd-overlay')) resetAndClose();
  }

  function handleKeyDown(e: KeyboardEvent) {
    if (e.key === 'Escape') resetAndClose();
  }

  // Resolved skills for the current team
  let teamSkillIds = $derived(resolveSkillsForTeam(agents));
  let teamSkillPartition = $derived(partitionSkills(teamSkillIds, skillsStore.skills));
  let skillsExpanded = $state(false);

  const stepLabel = $derived(
    step === 'template' ? 'Choose Template'
    : step === 'review' ? 'Review Agents'
    : 'Configure & Hire',
  );

  const canProceed = $derived.by(() => {
    if (step === 'review') return agents.length > 0;
    if (step === 'config') return agents.length > 0 && model.trim() !== '';
    return false;
  });
</script>

{#if open}
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    class="htd-overlay"
    onclick={handleBackdrop}
    onkeydown={handleKeyDown}
  >
    <!-- svelte-ignore a11y_click_events_have_key_events -->
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div
      class="htd-modal"
      role="dialog"
      aria-modal="true"
      aria-label="Hire an agent team"
      onclick={(e) => e.stopPropagation()}
    >
      <header class="htd-header">
        <div class="htd-header-left">
          {#if step !== 'template'}
            <button class="htd-back" onclick={goBack} aria-label="Go back">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                <path d="M15 18l-6-6 6-6" />
              </svg>
            </button>
          {/if}
          <h2 class="htd-title">Hire Team</h2>
          <span class="htd-step-label">{stepLabel}</span>
        </div>
        <button class="htd-close" onclick={resetAndClose} aria-label="Close dialog">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <path d="M18 6 6 18M6 6l12 12" />
          </svg>
        </button>
      </header>

      <!-- Steps indicator -->
      <div class="htd-steps" aria-hidden="true">
        <div class="htd-step-dot" class:htd-step-dot--active={step === 'template'} class:htd-step-dot--done={step === 'review' || step === 'config'}></div>
        <div class="htd-step-line" class:htd-step-line--done={step === 'review' || step === 'config'}></div>
        <div class="htd-step-dot" class:htd-step-dot--active={step === 'review'} class:htd-step-dot--done={step === 'config'}></div>
        <div class="htd-step-line" class:htd-step-line--done={step === 'config'}></div>
        <div class="htd-step-dot" class:htd-step-dot--active={step === 'config'}></div>
      </div>

      <div class="htd-body">
        {#if step === 'template'}
          <TeamTemplateGrid onSelect={selectTemplate} />

        {:else if step === 'review'}
          <TeamAgentReview {agents} onUpdate={(updated) => agents = updated} />

          {#if teamSkillIds.length > 0}
            <section class="htd-skills-summary">
              <button
                type="button"
                class="htd-skills-toggle"
                onclick={() => skillsExpanded = !skillsExpanded}
                aria-expanded={skillsExpanded}
              >
                <span class="htd-skills-toggle-icon" class:htd-skills-toggle-icon--open={skillsExpanded}>▸</span>
                Skills that will be added ({teamSkillPartition.toAdd.length} new, {teamSkillPartition.alreadyActive.length} existing)
              </button>
              {#if skillsExpanded}
                <div class="htd-skills-list">
                  {#if teamSkillPartition.toAdd.length > 0}
                    <div class="htd-skills-group">
                      <span class="htd-skills-label htd-skills-label--add">Will be added</span>
                      <div class="htd-skill-chips">
                        {#each teamSkillPartition.toAdd as skill}
                          <span class="htd-skill-chip htd-skill-chip--add" title={skill.description}>{skill.name}</span>
                        {/each}
                      </div>
                    </div>
                  {/if}
                  {#if teamSkillPartition.alreadyActive.length > 0}
                    <div class="htd-skills-group">
                      <span class="htd-skills-label htd-skills-label--active">Already active</span>
                      <div class="htd-skill-chips">
                        {#each teamSkillPartition.alreadyActive as skill}
                          <span class="htd-skill-chip htd-skill-chip--active" title={skill.description}>{skill.name}</span>
                        {/each}
                      </div>
                    </div>
                  {/if}
                </div>
              {/if}
            </section>
          {/if}

        {:else if step === 'config'}
          <div class="htd-config">
            <!-- Team name -->
            <section class="htd-section">
              <h3 class="htd-section-title">Team</h3>
              <div class="htd-field">
                <label class="htd-label" for="htd-team-name">Team name</label>
                <input
                  id="htd-team-name"
                  class="htd-input"
                  type="text"
                  value={teamName}
                  oninput={(e) => teamName = (e.target as HTMLInputElement).value}
                  placeholder="e.g. Dev Team"
                  aria-label="Team name"
                />
              </div>
              <label class="htd-toggle-row">
                <input
                  type="checkbox"
                  class="htd-checkbox"
                  checked={createTeamEntity}
                  onchange={(e) => createTeamEntity = (e.target as HTMLInputElement).checked}
                  aria-label="Group agents into a team"
                />
                <span class="htd-toggle-label">Create team grouping</span>
                <span class="htd-toggle-hint">Agents will be organized under a team entity</span>
              </label>
            </section>

            <AgentAdapterPicker {adapter} onAdapter={(v) => adapter = v} />

            <!-- Model / Provider -->
            <section class="htd-section">
              <h3 class="htd-section-title">Model</h3>
              <div class="htd-row">
                <div class="htd-field htd-field--flex">
                  <label class="htd-label" for="htd-model">Model (applied to all agents)</label>
                  <input
                    id="htd-model"
                    class="htd-input"
                    type="text"
                    value={model}
                    oninput={(e) => model = (e.target as HTMLInputElement).value}
                    placeholder="claude-sonnet-4-6"
                    aria-label="Model name"
                  />
                </div>
                {#if providersStore.connected.length > 0}
                  <div class="htd-field htd-field--flex">
                    <label class="htd-label" for="htd-provider">Provider</label>
                    <select
                      id="htd-provider"
                      class="htd-select"
                      value={providerId}
                      onchange={(e) => providerId = (e.target as HTMLSelectElement).value}
                      aria-label="Provider"
                    >
                      <option value="">Default</option>
                      {#each providersStore.connected as p}
                        <option value={p.id}>{p.name}</option>
                      {/each}
                    </select>
                  </div>
                {/if}
              </div>
            </section>

            <AgentBudgetConfig
              {dailyLimitDollars}
              {monthlyLimitDollars}
              {warningThreshold}
              {hardStop}
              onDailyLimit={(v) => dailyLimitDollars = v}
              onMonthlyLimit={(v) => monthlyLimitDollars = v}
              onWarningThreshold={(v) => warningThreshold = v}
              onHardStop={(v) => hardStop = v}
            />
          </div>
        {/if}
      </div>

      <footer class="htd-footer">
        {#if step === 'template'}
          <div class="htd-footer-spacer"></div>
          <button class="htd-btn htd-btn--secondary" onclick={resetAndClose}>Cancel</button>
        {:else if step === 'review'}
          <button class="htd-btn htd-btn--secondary" onclick={goBack}>Back</button>
          <div class="htd-footer-spacer"></div>
          <button
            type="button"
            class="htd-btn htd-btn--primary"
            onclick={goToConfig}
          >
            Next: Configure
          </button>
        {:else}
          <button class="htd-btn htd-btn--secondary" onclick={goBack} disabled={isSubmitting}>Back</button>
          <div class="htd-footer-spacer"></div>
          <button
            type="button"
            class="htd-btn htd-btn--primary"
            disabled={isSubmitting || !canProceed}
            onclick={handleSubmit}
            aria-busy={isSubmitting}
          >
            {#if isSubmitting}
              <span class="htd-spinner" aria-hidden="true"></span>
              Hiring {agents.length} agent{agents.length === 1 ? '' : 's'}…
            {:else}
              Hire {agents.length} Agent{agents.length === 1 ? '' : 's'}
            {/if}
          </button>
        {/if}
      </footer>
    </div>
  </div>
{/if}

<style>
  .htd-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.6);
    backdrop-filter: blur(4px);
    -webkit-backdrop-filter: blur(4px);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1000;
    padding: 24px;
  }

  .htd-modal {
    background: var(--bg-tertiary);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-xl);
    width: 80vw;
    max-width: 780px;
    max-height: 80vh;
    display: flex;
    flex-direction: column;
    box-shadow: 0 24px 80px rgba(0, 0, 0, 0.5);
    overflow: hidden;
  }

  /* Header */
  .htd-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 16px 20px;
    border-bottom: 1px solid var(--border-default);
    flex-shrink: 0;
  }

  .htd-header-left {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .htd-title {
    font-size: 15px;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0;
  }

  .htd-step-label {
    font-size: 12px;
    color: var(--text-muted);
    padding-left: 8px;
    border-left: 1px solid var(--border-default);
  }

  .htd-back {
    width: 28px;
    height: 28px;
    border-radius: var(--radius-xs);
    border: 1px solid transparent;
    background: transparent;
    color: var(--text-tertiary);
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: all 120ms ease;
  }

  .htd-back:hover {
    background: var(--bg-elevated);
    border-color: var(--border-default);
    color: var(--text-primary);
  }

  .htd-close {
    width: 28px;
    height: 28px;
    border-radius: var(--radius-xs);
    border: 1px solid transparent;
    background: transparent;
    color: var(--text-tertiary);
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: all 120ms ease;
  }

  .htd-close:hover {
    background: var(--bg-elevated);
    border-color: var(--border-default);
    color: var(--text-primary);
  }

  /* Steps indicator */
  .htd-steps {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 0;
    padding: 12px 20px 0;
    flex-shrink: 0;
  }

  .htd-step-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--border-default);
    transition: background 200ms ease, box-shadow 200ms ease;
  }

  .htd-step-dot--active {
    background: rgba(249, 115, 22, 0.8);
    box-shadow: 0 0 0 3px rgba(249, 115, 22, 0.2);
  }

  .htd-step-dot--done {
    background: rgba(34, 197, 94, 0.7);
  }

  .htd-step-line {
    width: 48px;
    height: 2px;
    background: var(--border-default);
    transition: background 200ms ease;
  }

  .htd-step-line--done {
    background: rgba(34, 197, 94, 0.4);
  }

  /* Body */
  .htd-body {
    flex: 1 1 auto;
    overflow-y: auto;
    padding: 20px;
    position: relative;
    z-index: 1;
    min-height: 0;
  }

  .htd-body::-webkit-scrollbar {
    width: 5px;
  }

  .htd-body::-webkit-scrollbar-thumb {
    background: var(--border-default);
    border-radius: 3px;
  }

  /* Config step */
  .htd-config {
    display: flex;
    flex-direction: column;
    gap: 24px;
  }

  .htd-section {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .htd-section-title {
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.6px;
    color: var(--text-tertiary);
    margin: 0;
    padding-bottom: 8px;
    border-bottom: 1px solid var(--border-default);
  }

  .htd-row {
    display: flex;
    gap: 12px;
  }

  .htd-field {
    display: flex;
    flex-direction: column;
    gap: 5px;
  }

  .htd-field--flex {
    flex: 1;
  }

  .htd-label {
    font-size: 12px;
    font-weight: 500;
    color: var(--text-secondary);
  }

  .htd-input,
  .htd-select {
    height: 34px;
    padding: 0 10px;
    border-radius: var(--radius-sm);
    border: 1px solid var(--border-default);
    background: var(--bg-surface);
    color: var(--text-primary);
    font-size: 13px;
    font-family: var(--font-sans);
    outline: none;
    transition: border-color 120ms ease;
  }

  .htd-input:focus,
  .htd-select:focus {
    border-color: var(--border-focus);
  }

  .htd-select {
    cursor: pointer;
    appearance: none;
    padding-right: 28px;
    background-image: url("data:image/svg+xml,%3Csvg width='10' height='6' viewBox='0 0 10 6' fill='none' xmlns='http://www.w3.org/2000/svg'%3E%3Cpath d='M1 1l4 4 4-4' stroke='%23666' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E");
    background-repeat: no-repeat;
    background-position: right 8px center;
  }

  .htd-toggle-row {
    display: flex;
    align-items: center;
    gap: 10px;
    cursor: pointer;
  }

  .htd-checkbox {
    width: 14px;
    height: 14px;
    cursor: pointer;
    accent-color: var(--accent-primary);
    flex-shrink: 0;
  }

  .htd-toggle-label {
    font-size: 12px;
    font-weight: 500;
    color: var(--text-secondary);
  }

  .htd-toggle-hint {
    font-size: 11px;
    color: var(--text-muted);
  }

  /* Footer */
  .htd-footer {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 14px 20px;
    border-top: 1px solid var(--border-default);
    flex-shrink: 0;
    background: var(--bg-secondary);
    position: relative;
    z-index: 2;
  }

  .htd-footer-spacer {
    flex: 1;
  }

  .htd-btn {
    height: 34px;
    padding: 0 16px;
    border-radius: var(--radius-sm);
    font-size: 13px;
    font-weight: 500;
    font-family: var(--font-sans);
    cursor: pointer;
    display: flex;
    align-items: center;
    gap: 6px;
    transition: all 120ms ease;
    border: 1px solid transparent;
    white-space: nowrap;
  }

  .htd-btn--secondary {
    background: transparent;
    border-color: var(--border-default);
    color: var(--text-secondary);
  }

  .htd-btn--secondary:hover:not(:disabled) {
    background: var(--bg-elevated);
    border-color: var(--border-hover);
    color: var(--text-primary);
  }

  .htd-btn--primary {
    background: rgba(249, 115, 22, 0.2);
    border-color: rgba(251, 146, 60, 0.5);
    color: #fdba74;
  }

  .htd-btn--primary:hover:not(:disabled) {
    background: rgba(249, 115, 22, 0.3);
    border-color: rgba(251, 146, 60, 0.7);
    color: #fed7aa;
  }

  .htd-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .htd-spinner {
    width: 12px;
    height: 12px;
    border: 2px solid rgba(251, 146, 60, 0.3);
    border-top-color: #fdba74;
    border-radius: 50%;
    animation: htd-spin 0.7s linear infinite;
  }

  @keyframes htd-spin {
    to { transform: rotate(360deg); }
  }

  .htd-skills-summary {
    margin-top: 8px;
    border: 1px solid var(--border-default);
    border-radius: var(--radius-sm);
    overflow: hidden;
  }

  .htd-skills-toggle {
    width: 100%;
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 10px 14px;
    background: var(--bg-secondary);
    border: none;
    color: var(--text-secondary);
    font-size: 12px;
    font-weight: 500;
    font-family: var(--font-sans);
    cursor: pointer;
    text-align: left;
    transition: background 120ms ease;
  }

  .htd-skills-toggle:hover {
    background: var(--bg-elevated);
  }

  .htd-skills-toggle-icon {
    display: inline-block;
    transition: transform 120ms ease;
    font-size: 11px;
    color: var(--text-muted);
  }

  .htd-skills-toggle-icon--open {
    transform: rotate(90deg);
  }

  .htd-skills-list {
    padding: 10px 14px;
    display: flex;
    flex-direction: column;
    gap: 10px;
    border-top: 1px solid var(--border-default);
  }

  .htd-skills-group {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .htd-skills-label {
    font-size: 10px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }

  .htd-skills-label--add {
    color: #fdba74;
  }

  .htd-skills-label--active {
    color: rgba(34, 197, 94, 0.8);
  }

  .htd-skill-chips {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
  }

  .htd-skill-chip {
    display: inline-flex;
    align-items: center;
    height: 22px;
    padding: 0 7px;
    border-radius: var(--radius-xs);
    font-size: 10px;
    font-weight: 500;
  }

  .htd-skill-chip--add {
    background: rgba(249, 115, 22, 0.12);
    border: 1px solid rgba(249, 115, 22, 0.3);
    color: #fdba74;
  }

  .htd-skill-chip--active {
    background: rgba(34, 197, 94, 0.1);
    border: 1px solid rgba(34, 197, 94, 0.25);
    color: rgba(34, 197, 94, 0.8);
  }
</style>
