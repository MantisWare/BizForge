<!-- src/lib/components/agents/hire/AgentModelConfig.svelte -->
<script lang="ts">
  import { providersStore } from '$lib/stores/providers.svelte';

  interface Props {
    model: string;
    systemPrompt: string;
    selectedSkills: string[];
    displayName: string;
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
    errors,
    providerId,
    temperature,
    onModel,
    onSystemPrompt,
    onToggleSkill,
    onProviderId,
    onTemperature,
  }: Props = $props();

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

  function handleProviderChange(newId: string) {
    onProviderId(newId);
    const prov = providersStore.getById(newId);
    if (prov !== null && prov.models.length > 0 && !prov.models.includes(model)) {
      onModel(prov.models[0]);
    }
    if (prov !== null && prov.config.temperature !== undefined) {
      onTemperature(prov.config.temperature.toString());
    }
  }
</script>

<!-- Provider -->
<section class="hmc-section">
  <h3 class="hmc-section-title">Provider</h3>
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
  <h3 class="hmc-section-title">Model</h3>
  <div class="hmc-field">
    <label class="hmc-label" for="hmc-model">Model <span class="hmc-required">*</span></label>
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
    <span id="hmc-model-hint" class="hmc-hint">
      {#if providerModels.length > 0}
        Pick from the provider's available models or type a custom one
      {:else}
        Type a model identifier
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
  <h3 class="hmc-section-title">System Prompt</h3>
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
  <h3 class="hmc-section-title">Skills</h3>
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
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.6px;
    color: var(--text-tertiary);
    margin: 0;
    padding-bottom: 8px;
    border-bottom: 1px solid var(--border-default);
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

  .hmc-model-wrap {
    position: relative;
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
