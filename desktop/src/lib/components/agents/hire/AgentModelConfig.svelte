<!-- src/lib/components/agents/hire/AgentModelConfig.svelte -->
<script lang="ts">
  import { providersStore } from '$lib/stores/providers.svelte';
  import { getTemplatesForRole, ALL_PROMPT_GROUPS } from '$lib/data/prompt-templates';
  import type { PromptTemplateGroup } from '$lib/data/prompt-templates';

  interface Props {
    model: string;
    systemPrompt: string;
    selectedSkills: string[];
    displayName: string;
    role: string;
    errors: Record<string, string>;
    providerId: string;
    temperature: string;
    onModel: (v: string) => void;
    onSystemPrompt: (v: string) => void;
    onToggleSkill: (skill: string) => void;
    onProviderId: (v: string) => void;
    onTemperature: (v: string) => void;
  }

  let {
    model,
    systemPrompt,
    selectedSkills,
    displayName,
    role,
    errors,
    providerId,
    temperature,
    onModel,
    onSystemPrompt,
    onToggleSkill,
    onProviderId,
    onTemperature,
  }: Props = $props();

  let showAllGroups = $state(false);

  const matchedGroup: PromptTemplateGroup = $derived(getTemplatesForRole(role));

  const visibleGroups: readonly PromptTemplateGroup[] = $derived(
    showAllGroups ? ALL_PROMPT_GROUPS : [matchedGroup],
  );

  function applyTemplate(prompt: string) {
    onSystemPrompt(prompt);
  }

  const SKILL_OPTIONS = [
    'code-review', 'security-scan', 'dependency-audit', 'doc-writer',
    'markdown-formatter', 'changelog-generator', 'refactoring',
    'architecture-analysis', 'research', 'summarization', 'knowledge-graph',
    'security-monitor', 'alert-triage', 'incident-response', 'notification-dispatch',
    'ci-cd', 'build-optimization', 'test-runner', 'ui-design', 'accessibility-audit',
    'domo-app-scaffold', 'domo-appdb-manage', 'domo-app-publish', 'domo-code-engine',
    'domo-connector-build', 'domo-dataset-manage', 'domo-magic-etl',
    'domo-workflow-automate', 'domo-embed-analytics', 'domo-api-integrate',
    'domo-governance', 'domo-data-science',
  ];

  let promptPlaceholder = $derived(`You are ${displayName || 'an AI agent'}…`);

  let selectedProvider = $derived(
    providerId ? providersStore.getById(providerId) : null,
  );

  let providerModels = $derived(
    selectedProvider?.models ?? [],
  );

  let fetchingModels = $state(false);

  function handleProviderChange(newId: string) {
    onProviderId(newId);
    const prov = providersStore.getById(newId);
    if (prov === null) return;

    const models = Array.isArray(prov.models) ? prov.models : [];
    if (prov.default_model !== undefined && prov.default_model !== null && models.includes(prov.default_model)) {
      onModel(prov.default_model);
    } else if (models.length > 0 && !models.includes(model)) {
      onModel(models[0]);
    }
    if (prov.config?.temperature !== undefined) {
      onTemperature(prov.config.temperature.toString());
    }
  }

  async function handleFetchModels() {
    if (!providerId) return;
    fetchingModels = true;
    const models = await providersStore.fetchModelsForProvider(providerId);
    if (models.length > 0 && !models.includes(model)) {
      onModel(models[0]);
    }
    fetchingModels = false;
  }
</script>

<!-- Provider -->
<section class="hmc-section">
  <h3 class="hmc-section-title">
    Provider
    <span class="hmc-info" title="The AI service that powers this agent's reasoning — e.g. Anthropic, OpenAI, or a local model host. Determines which LLMs are available.">
      <svg class="hmc-info-icon" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
        <path d="M8 1a7 7 0 1 0 0 14A7 7 0 0 0 8 1Zm0 12.5a5.5 5.5 0 1 1 0-11 5.5 5.5 0 0 1 0 11ZM8 5a.75.75 0 1 1 0-1.5A.75.75 0 0 1 8 5Zm-1 2.25a.25.25 0 0 1 .25-.25h.5a.75.75 0 0 1 .75.75V11a.25.25 0 0 1-.25.25h-.5A.75.75 0 0 1 7 10.5V7.25Z"/>
      </svg>
    </span>
  </h3>
  <div class="hmc-field">
    <label class="hmc-label" for="hmc-provider">AI Provider</label>
    {#if providersStore.providers.length > 0}
      <select
        id="hmc-provider"
        class="hmc-select"
        value={providerId}
        onchange={(e) => handleProviderChange((e.target as HTMLSelectElement).value)}
      >
        <option value="">Select a provider...</option>
        {#each providersStore.providers as prov (prov.id)}
          <option value={prov.id}>
            {prov.name}
            {#if prov.is_default} (default){/if}
            {#if prov.status === 'connected'} — connected{/if}
            {#if prov.status === 'error'} — error{/if}
          </option>
        {/each}
      </select>
      <span class="hmc-hint">Only configured providers are shown — manage in Settings &gt; AI Providers</span>
    {:else}
      <p class="hmc-hint">No providers configured. <a href="/app/settings" class="hmc-link">Add providers in Settings</a></p>
    {/if}
  </div>
</section>

<!-- Model -->
<section class="hmc-section">
  <h3 class="hmc-section-title">
    Model
    <span class="hmc-info" title="The specific LLM to use — e.g. claude-sonnet-4-6. Affects quality, speed, cost, and context window. Pick from the provider's list or type a custom identifier.">
      <svg class="hmc-info-icon" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
        <path d="M8 1a7 7 0 1 0 0 14A7 7 0 0 0 8 1Zm0 12.5a5.5 5.5 0 1 1 0-11 5.5 5.5 0 0 1 0 11ZM8 5a.75.75 0 1 1 0-1.5A.75.75 0 0 1 8 5Zm-1 2.25a.25.25 0 0 1 .25-.25h.5a.75.75 0 0 1 .75.75V11a.25.25 0 0 1-.25.25h-.5A.75.75 0 0 1 7 10.5V7.25Z"/>
      </svg>
    </span>
  </h3>
  <div class="hmc-field">
    <label class="hmc-label" for="hmc-model">Model <span class="hmc-required">*</span></label>
    <div class="hmc-model-row">
      <div class="hmc-model-wrap">
        <input
          id="hmc-model"
          class="hmc-input"
          class:hmc-input--error={errors.model}
          type="text"
          value={model}
          oninput={(e) => onModel((e.target as HTMLInputElement).value)}
          placeholder="claude-sonnet-4-6"
          list="hmc-model-presets"
          autocomplete="off"
          aria-describedby={errors.model ? 'hmc-model-error' : 'hmc-model-hint'}
          aria-required="true"
        />
        <datalist id="hmc-model-presets">
          {#each providerModels as pm}
            <option value={pm}>{pm}</option>
          {/each}
        </datalist>
      </div>
      <button
        type="button"
        class="hmc-fetch-btn"
        onclick={handleFetchModels}
        disabled={!providerId || fetchingModels}
        title="Fetch available models from the provider"
        aria-label="Fetch available models"
      >
        {#if fetchingModels}
          <svg class="hmc-spinner" viewBox="0 0 16 16" width="14" height="14"><circle cx="8" cy="8" r="6" fill="none" stroke="currentColor" stroke-width="1.5" stroke-dasharray="28" stroke-dashoffset="8"/></svg>
        {:else}
          <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" width="14" height="14"><path d="M13.5 8A5.5 5.5 0 112.5 8a5.5 5.5 0 0111 0z"/><path d="M8 5v3l2 1.5"/></svg>
        {/if}
      </button>
    </div>
    <span id="hmc-model-hint" class="hmc-hint">
      {#if providerModels.length > 0}
        {providerModels.length} model{providerModels.length !== 1 ? 's' : ''} available — pick from list or type a custom one
      {:else if providerId}
        Click the refresh button to fetch models from the provider
      {:else}
        Select a provider first, then fetch available models
      {/if}
    </span>
    {#if errors.model}
      <span id="hmc-model-error" class="hmc-error" role="alert">{errors.model}</span>
    {/if}
  </div>

  <!-- Temperature -->
  <div class="hmc-field">
    <label class="hmc-label" for="hmc-temperature">Temperature <span class="hmc-optional">(optional)</span></label>
    <input
      id="hmc-temperature"
      class="hmc-input hmc-input--narrow"
      type="number"
      step="0.1"
      min="0"
      max="2"
      placeholder={selectedProvider?.config.temperature?.toString() ?? '0.7'}
      value={temperature}
      oninput={(e) => onTemperature((e.target as HTMLInputElement).value)}
    />
    <span class="hmc-hint">Override the provider's default temperature for this agent</span>
  </div>
</section>

<!-- System Prompt -->
<section class="hmc-section">
  <h3 class="hmc-section-title">
    System Prompt
    <span class="hmc-info" title="Instructions that define the agent's personality, behavior, and constraints. This is sent at the start of every conversation to guide the model's responses.">
      <svg class="hmc-info-icon" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
        <path d="M8 1a7 7 0 1 0 0 14A7 7 0 0 0 8 1Zm0 12.5a5.5 5.5 0 1 1 0-11 5.5 5.5 0 0 1 0 11ZM8 5a.75.75 0 1 1 0-1.5A.75.75 0 0 1 8 5Zm-1 2.25a.25.25 0 0 1 .25-.25h.5a.75.75 0 0 1 .75.75V11a.25.25 0 0 1-.25.25h-.5A.75.75 0 0 1 7 10.5V7.25Z"/>
      </svg>
    </span>
  </h3>

  <div class="hmc-templates">
    <div class="hmc-templates-header">
      <span class="hmc-templates-label">Quick-fill from template</span>
      <button
        type="button"
        class="hmc-templates-toggle"
        onclick={() => showAllGroups = !showAllGroups}
      >
        {showAllGroups ? 'Show matched' : 'Show all categories'}
      </button>
    </div>
    {#each visibleGroups as group (group.category)}
      {#if showAllGroups}
        <span class="hmc-templates-category">{group.category}</span>
      {/if}
      <div class="hmc-templates-row">
        {#each group.templates as tpl (tpl.id)}
          <button
            type="button"
            class="hmc-tpl-btn"
            onclick={() => applyTemplate(tpl.prompt)}
            title={tpl.prompt}
          >{tpl.label}</button>
        {/each}
      </div>
    {/each}
  </div>

  <div class="hmc-field">
    <label class="hmc-label" for="hmc-system-prompt">Instructions</label>
    <textarea
      id="hmc-system-prompt"
      class="hmc-textarea"
      value={systemPrompt}
      oninput={(e) => onSystemPrompt((e.target as HTMLTextAreaElement).value)}
      placeholder={promptPlaceholder}
      rows="5"
      aria-label="Agent system prompt"
    ></textarea>
  </div>
</section>

<!-- Skills -->
<section class="hmc-section">
  <h3 class="hmc-section-title">
    Skills
    <span class="hmc-info" title="Capabilities the agent can use when executing tasks. Enable relevant skills to give the agent specialized knowledge and tools for its role.">
      <svg class="hmc-info-icon" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
        <path d="M8 1a7 7 0 1 0 0 14A7 7 0 0 0 8 1Zm0 12.5a5.5 5.5 0 1 1 0-11 5.5 5.5 0 0 1 0 11ZM8 5a.75.75 0 1 1 0-1.5A.75.75 0 0 1 8 5Zm-1 2.25a.25.25 0 0 1 .25-.25h.5a.75.75 0 0 1 .75.75V11a.25.25 0 0 1-.25.25h-.5A.75.75 0 0 1 7 10.5V7.25Z"/>
      </svg>
    </span>
  </h3>
  <div class="hmc-skills-grid" role="group" aria-label="Select agent skills">
    {#each SKILL_OPTIONS as skill}
      <label class="hmc-skill-item">
        <input
          type="checkbox"
          class="hmc-checkbox"
          checked={selectedSkills.includes(skill)}
          onchange={() => onToggleSkill(skill)}
          aria-label="Enable skill: {skill}"
        />
        <span class="hmc-skill-name">{skill}</span>
      </label>
    {/each}
  </div>
</section>

<style>
  .hmc-section {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .hmc-section-title {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.6px;
    color: var(--text-tertiary);
    margin: 0;
    padding-bottom: 8px;
    border-bottom: 1px solid var(--border-default);
  }

  .hmc-info {
    display: inline-flex;
    align-items: center;
    cursor: help;
    position: relative;
  }

  .hmc-info-icon {
    width: 13px;
    height: 13px;
    color: var(--text-muted);
    opacity: 0.6;
    transition: opacity 150ms ease, color 150ms ease;
  }

  .hmc-info:hover .hmc-info-icon {
    opacity: 1;
    color: var(--accent-primary);
  }

  .hmc-field {
    display: flex;
    flex-direction: column;
    gap: 5px;
  }

  .hmc-label {
    font-size: 12px;
    font-weight: 500;
    color: var(--text-secondary);
  }

  .hmc-required {
    color: var(--accent-error);
  }

  .hmc-optional {
    font-weight: 400;
    color: var(--text-muted);
    font-size: 11px;
  }

  .hmc-hint {
    font-size: 11px;
    color: var(--text-muted);
  }

  .hmc-error {
    font-size: 11px;
    color: var(--accent-error);
  }

  .hmc-link {
    color: var(--accent-primary);
    text-decoration: none;
  }

  .hmc-link:hover {
    text-decoration: underline;
  }

  .hmc-input {
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

  .hmc-input:focus {
    border-color: var(--border-focus);
  }

  .hmc-input--error {
    border-color: var(--accent-error);
  }

  .hmc-input--narrow {
    max-width: 120px;
  }

  .hmc-select {
    height: 34px;
    padding: 0 10px;
    border-radius: var(--radius-sm);
    border: 1px solid var(--border-default);
    background: var(--bg-surface);
    color: var(--text-primary);
    font-size: 13px;
    font-family: var(--font-sans);
    outline: none;
    cursor: pointer;
    appearance: auto;
    transition: border-color 120ms ease;
  }

  .hmc-select:focus {
    border-color: var(--border-focus);
  }

  .hmc-model-row {
    display: flex;
    align-items: center;
    gap: 6px;
  }

  .hmc-model-wrap {
    position: relative;
    flex: 1;
  }

  .hmc-fetch-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 34px;
    height: 34px;
    border-radius: var(--radius-sm);
    border: 1px solid var(--border-default);
    background: var(--bg-surface);
    color: var(--text-secondary);
    cursor: pointer;
    flex-shrink: 0;
    transition: border-color 120ms ease, color 120ms ease, background 120ms ease;
  }

  .hmc-fetch-btn:hover:not(:disabled) {
    border-color: var(--border-hover);
    color: var(--accent-primary);
    background: var(--bg-elevated);
  }

  .hmc-fetch-btn:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }

  .hmc-spinner {
    animation: hmc-spin 1s linear infinite;
  }

  @keyframes hmc-spin {
    to { transform: rotate(360deg); }
  }

  .hmc-templates {
    display: flex;
    flex-direction: column;
    gap: 6px;
    margin-bottom: 8px;
  }

  .hmc-templates-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }

  .hmc-templates-label {
    font-size: 11px;
    color: var(--text-muted);
    font-weight: 500;
  }

  .hmc-templates-toggle {
    font-size: 10px;
    color: var(--accent-primary);
    background: none;
    border: none;
    cursor: pointer;
    padding: 0;
    font-family: var(--font-sans);
    opacity: 0.8;
    transition: opacity 120ms ease;
  }

  .hmc-templates-toggle:hover {
    opacity: 1;
    text-decoration: underline;
  }

  .hmc-templates-category {
    font-size: 10px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    color: var(--text-tertiary);
    margin-top: 4px;
  }

  .hmc-templates-row {
    display: flex;
    flex-wrap: wrap;
    gap: 5px;
  }

  .hmc-tpl-btn {
    height: 24px;
    padding: 0 10px;
    border-radius: 100px;
    border: 1px solid var(--border-default);
    background: var(--bg-surface);
    color: var(--text-secondary);
    font-size: 11px;
    font-family: var(--font-sans);
    cursor: pointer;
    white-space: nowrap;
    transition: all 120ms ease;
  }

  .hmc-tpl-btn:hover {
    border-color: rgba(249, 115, 22, 0.4);
    background: rgba(249, 115, 22, 0.08);
    color: var(--text-primary);
  }

  .hmc-tpl-btn:active {
    transform: scale(0.97);
  }

  .hmc-textarea {
    padding: 8px 10px;
    border-radius: var(--radius-sm);
    border: 1px solid var(--border-default);
    background: var(--bg-surface);
    color: var(--text-primary);
    font-size: 12px;
    font-family: var(--font-mono);
    resize: vertical;
    outline: none;
    transition: border-color 120ms ease;
    line-height: 1.5;
  }

  .hmc-textarea:focus {
    border-color: var(--border-focus);
  }

  .hmc-skills-grid {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 6px;
  }

  .hmc-skill-item {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 8px;
    border-radius: var(--radius-xs);
    border: 1px solid transparent;
    cursor: pointer;
    transition: background 100ms ease;
  }

  .hmc-skill-item:hover {
    background: var(--bg-elevated);
  }

  .hmc-checkbox {
    width: 14px;
    height: 14px;
    cursor: pointer;
    accent-color: var(--accent-primary);
    flex-shrink: 0;
  }

  .hmc-skill-name {
    font-size: 12px;
    color: var(--text-secondary);
    font-family: var(--font-mono);
  }
</style>
