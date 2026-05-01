<!-- src/routes/app/settings/tabs/ProvidersSettings.svelte -->
<script lang="ts">
  import { onMount } from 'svelte';
  import { providersStore } from '$lib/stores/providers.svelte';
  import type { AIProviderCreateRequest, AIProviderConfig, AIProviderCategory } from '$api/types';
  import {
    ALL_PROVIDERS,
    LOCAL_RUNTIMES,
    findProvider,
    getDefaultEndpoint,
    type LocalRuntime,
    type ProviderCatalogEntry,
  } from '$lib/data/provider-catalog';

  onMount(() => {
    void providersStore.fetch();
  });

  // ── Add provider form state ────────────────────────────────────────────────

  let showAddForm = $state(false);
  let addCategory = $state<AIProviderCategory>('cloud');
  let addSlug = $state('');
  let addApiKey = $state('');
  let addEndpoint = $state('');
  let addLocalRuntime = $state<LocalRuntime>('ollama');
  let addIsDefault = $state(false);

  // Advanced config
  let showAdvanced = $state(false);
  let addTemperature = $state('');
  let addMaxTokens = $state('');
  let addTopP = $state('');
  let addTopK = $state('');
  let addFreqPenalty = $state('');
  let addPresPenalty = $state('');

  // Per-provider test-in-progress
  let testingId = $state<string | null>(null);
  let fetchingModelsId = $state<string | null>(null);

  // Pre-add connection test state
  let preTestLoading = $state(false);
  let preTestResult = $state<{ status: 'idle' | 'success' | 'error'; models: string[]; error?: string }>({ status: 'idle', models: [] });

  // Edit state
  let editingId = $state<string | null>(null);
  let editApiKey = $state('');
  let editEndpoint = $state('');
  let editTemperature = $state('');
  let editMaxTokens = $state('');

  let catalogOptions = $derived(
    ALL_PROVIDERS.filter((cp) =>
      addCategory === 'local'
        ? cp.category === 'local'
        : cp.category === 'cloud',
    ),
  );

  let selectedCatalogEntry = $derived<ProviderCatalogEntry | undefined>(
    findProvider(addSlug),
  );

  function resetAddForm() {
    showAddForm = false;
    addCategory = 'cloud';
    addSlug = '';
    addApiKey = '';
    addEndpoint = '';
    addLocalRuntime = 'ollama';
    addIsDefault = false;
    showAdvanced = false;
    addTemperature = '';
    addMaxTokens = '';
    addTopP = '';
    addTopK = '';
    addFreqPenalty = '';
    addPresPenalty = '';
    preTestResult = { status: 'idle', models: [] };
    preTestLoading = false;
  }

  function onCategoryChange() {
    addSlug = addCategory === 'local' ? 'local' : '';
    addEndpoint = '';
    addApiKey = '';
  }

  function onSlugChange() {
    if (addCategory === 'local') {
      addEndpoint = getDefaultEndpoint('local', addLocalRuntime);
    } else {
      addEndpoint = selectedCatalogEntry?.defaultEndpoint ?? '';
    }
  }

  function onRuntimeChange() {
    addEndpoint = getDefaultEndpoint('local', addLocalRuntime);
  }

  function buildConfig(): AIProviderConfig {
    const cfg: AIProviderConfig = {};
    if (addTemperature !== '') cfg.temperature = parseFloat(addTemperature);
    if (addMaxTokens !== '') cfg.max_tokens = parseInt(addMaxTokens, 10);
    if (addTopP !== '') cfg.top_p = parseFloat(addTopP);
    if (addTopK !== '') cfg.top_k = parseInt(addTopK, 10);
    if (addFreqPenalty !== '') cfg.frequency_penalty = parseFloat(addFreqPenalty);
    if (addPresPenalty !== '') cfg.presence_penalty = parseFloat(addPresPenalty);
    if (addCategory === 'local') {
      cfg.local_runtime = addLocalRuntime;
      cfg.local_endpoint = addEndpoint || getDefaultEndpoint('local', addLocalRuntime);
    }
    return cfg;
  }

  async function handlePreTest() {
    const entry = findProvider(addSlug);
    const endpoint = addEndpoint || entry?.defaultEndpoint || getDefaultEndpoint(addSlug, addLocalRuntime);
    if (!endpoint) return;

    preTestLoading = true;
    preTestResult = { status: 'idle', models: [] };

    const result = await providersStore.fetchModelsFromEndpoint(endpoint, addApiKey || undefined, addSlug);
    if (result.error !== undefined) {
      preTestResult = { status: 'error', models: [], error: result.error };
    } else if (result.models.length > 0) {
      preTestResult = { status: 'success', models: result.models };
    } else {
      preTestResult = { status: 'error', models: [], error: 'No models returned' };
    }
    preTestLoading = false;
  }

  async function handleAdd() {
    if (!addSlug) return;
    const entry = findProvider(addSlug);
    const fetchedModels = preTestResult.models.length > 0 ? preTestResult.models : (entry?.defaultModels ?? []);
    const req: AIProviderCreateRequest = {
      slug: addSlug,
      name: entry?.name ?? addSlug,
      category: addCategory,
      api_key: addApiKey || undefined,
      endpoint: addEndpoint || entry?.defaultEndpoint || undefined,
      config: buildConfig(),
      models: fetchedModels,
      is_default: addIsDefault,
    };
    const created = await providersStore.create(req);
    if (created !== null) resetAddForm();
  }

  async function handleTest(id: string) {
    testingId = id;
    await providersStore.test(id);
    testingId = null;
  }

  async function handleFetchModels(id: string) {
    fetchingModelsId = id;
    await providersStore.fetchModelsForProvider(id);
    fetchingModelsId = null;
  }

  async function handleRemove(id: string) {
    await providersStore.remove(id);
  }

  async function handleSetDefault(id: string) {
    await providersStore.setDefault(id);
  }

  function startEdit(prov: import('$api/types').AIProvider) {
    editingId = prov.id;
    editApiKey = '';
    editEndpoint = prov.endpoint ?? '';
    editTemperature = prov.config.temperature?.toString() ?? '';
    editMaxTokens = prov.config.max_tokens?.toString() ?? '';
  }

  async function saveEdit() {
    if (editingId === null) return;
    const updates: Partial<AIProviderCreateRequest> = {};
    if (editApiKey) updates.api_key = editApiKey;
    if (editEndpoint) updates.endpoint = editEndpoint;
    const cfg: AIProviderConfig = {};
    if (editTemperature !== '') cfg.temperature = parseFloat(editTemperature);
    if (editMaxTokens !== '') cfg.max_tokens = parseInt(editMaxTokens, 10);
    if (Object.keys(cfg).length > 0) updates.config = cfg;
    await providersStore.update(editingId, updates);
    editingId = null;
  }

  function statusDot(status: string): string {
    if (status === 'connected') return 'pst-dot--ok';
    if (status === 'error') return 'pst-dot--error';
    return 'pst-dot--untested';
  }
</script>

<section class="pst-section">
  <div class="pst-header">
    <div>
      <h2 class="pst-title">AI Providers</h2>
      <p class="pst-subtitle">
        Configure the AI providers available to your agents.
        {#if providersStore.totalCount > 0}
          <span class="pst-count">{providersStore.configuredCount} of {providersStore.totalCount} connected</span>
        {/if}
      </p>
    </div>
    {#if !showAddForm}
      <button class="pst-add-btn" onclick={() => { showAddForm = true; }}>
        <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" width="14" height="14"><path d="M8 3v10M3 8h10"/></svg>
        Add Provider
      </button>
    {/if}
  </div>

  <!-- Add Provider Form -->
  {#if showAddForm}
    <div class="pst-card pst-add-card">
      <h3 class="pst-card-title">Add Provider</h3>

      <!-- Category Toggle -->
      <div class="pst-toggle-row">
        <button
          class="pst-toggle"
          class:pst-toggle--active={addCategory === 'cloud'}
          onclick={() => { addCategory = 'cloud'; onCategoryChange(); }}
        >Cloud</button>
        <button
          class="pst-toggle"
          class:pst-toggle--active={addCategory === 'local'}
          onclick={() => { addCategory = 'local'; onCategoryChange(); }}
        >Local</button>
      </div>

      {#if addCategory === 'cloud'}
        <div class="pst-field">
          <label class="pst-label" for="pst-slug">Provider</label>
          <select
            id="pst-slug"
            class="pst-select"
            value={addSlug}
            onchange={(e) => { addSlug = (e.target as HTMLSelectElement).value; onSlugChange(); }}
          >
            <option value="" disabled>Select a provider...</option>
            {#each catalogOptions as cp (cp.slug)}
              <option value={cp.slug}>{cp.name} — {cp.description}</option>
            {/each}
          </select>
        </div>

        {#if addSlug}
          <div class="pst-field">
            <label class="pst-label" for="pst-key">API Key</label>
            <input
              id="pst-key"
              class="pst-input"
              type="password"
              placeholder="sk-..."
              autocomplete="off"
              value={addApiKey}
              oninput={(e) => { addApiKey = (e.target as HTMLInputElement).value; }}
            />
          </div>

          <div class="pst-field">
            <label class="pst-label" for="pst-endpoint">Endpoint <span class="pst-optional">(optional)</span></label>
            <input
              id="pst-endpoint"
              class="pst-input"
              type="text"
              placeholder={selectedCatalogEntry?.defaultEndpoint ?? 'https://api.example.com'}
              value={addEndpoint}
              oninput={(e) => { addEndpoint = (e.target as HTMLInputElement).value; }}
            />
          </div>
        {/if}
      {:else}
        <!-- Local provider -->
        <div class="pst-field">
          <label class="pst-label" for="pst-runtime">Runtime</label>
          <div class="pst-runtime-grid">
            {#each LOCAL_RUNTIMES as rt (rt.id)}
              <button
                class="pst-runtime-card"
                class:pst-runtime-card--active={addLocalRuntime === rt.id}
                onclick={() => { addLocalRuntime = rt.id; addSlug = 'local'; onRuntimeChange(); }}
              >
                <span class="pst-runtime-name">{rt.name}</span>
                <span class="pst-runtime-desc">{rt.description}</span>
                <span class="pst-runtime-ep">{rt.defaultEndpoint}</span>
              </button>
            {/each}
          </div>
        </div>

        <div class="pst-field">
          <label class="pst-label" for="pst-local-ep">Endpoint</label>
          <input
            id="pst-local-ep"
            class="pst-input"
            type="text"
            value={addEndpoint}
            oninput={(e) => { addEndpoint = (e.target as HTMLInputElement).value; }}
          />
        </div>
      {/if}

      <!-- Advanced Config -->
      <button class="pst-advanced-toggle" onclick={() => { showAdvanced = !showAdvanced; }}>
        <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" width="12" height="12" style="transform: rotate({showAdvanced ? 180 : 0}deg); transition: transform 150ms ease">
          <path d="M4 6l4 4 4-4"/>
        </svg>
        Advanced Configuration
      </button>

      {#if showAdvanced}
        <div class="pst-adv-grid">
          <div class="pst-field pst-field--half">
            <label class="pst-label" for="pst-temp">Temperature</label>
            <input id="pst-temp" class="pst-input" type="number" step="0.1" min="0" max="2" placeholder="0.7" value={addTemperature} oninput={(e) => { addTemperature = (e.target as HTMLInputElement).value; }} />
          </div>
          <div class="pst-field pst-field--half">
            <label class="pst-label" for="pst-maxtok">Max Tokens</label>
            <input id="pst-maxtok" class="pst-input" type="number" step="256" min="1" placeholder="4096" value={addMaxTokens} oninput={(e) => { addMaxTokens = (e.target as HTMLInputElement).value; }} />
          </div>
          <div class="pst-field pst-field--half">
            <label class="pst-label" for="pst-topp">Top P</label>
            <input id="pst-topp" class="pst-input" type="number" step="0.05" min="0" max="1" placeholder="1.0" value={addTopP} oninput={(e) => { addTopP = (e.target as HTMLInputElement).value; }} />
          </div>
          <div class="pst-field pst-field--half">
            <label class="pst-label" for="pst-topk">Top K</label>
            <input id="pst-topk" class="pst-input" type="number" step="1" min="0" placeholder="40" value={addTopK} oninput={(e) => { addTopK = (e.target as HTMLInputElement).value; }} />
          </div>
          <div class="pst-field pst-field--half">
            <label class="pst-label" for="pst-freq">Frequency Penalty</label>
            <input id="pst-freq" class="pst-input" type="number" step="0.1" min="-2" max="2" placeholder="0" value={addFreqPenalty} oninput={(e) => { addFreqPenalty = (e.target as HTMLInputElement).value; }} />
          </div>
          <div class="pst-field pst-field--half">
            <label class="pst-label" for="pst-pres">Presence Penalty</label>
            <input id="pst-pres" class="pst-input" type="number" step="0.1" min="-2" max="2" placeholder="0" value={addPresPenalty} oninput={(e) => { addPresPenalty = (e.target as HTMLInputElement).value; }} />
          </div>
        </div>
      {/if}

      <!-- Default checkbox -->
      <label class="pst-check-row">
        <input type="checkbox" checked={addIsDefault} onchange={() => { addIsDefault = !addIsDefault; }} />
        <span>Set as default provider</span>
      </label>

      <!-- Pre-add test results -->
      {#if preTestResult.status === 'success'}
        <div class="pst-pretest pst-pretest--success">
          <div class="pst-pretest-header">
            <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" width="14" height="14"><path d="M13.5 4.5l-7 7L3 8"/></svg>
            <span>Connection successful — {preTestResult.models.length} model{preTestResult.models.length !== 1 ? 's' : ''} available</span>
          </div>
          <div class="pst-pretest-models">
            {#each preTestResult.models.slice(0, 12) as m}
              <span class="pst-model-tag">{m}</span>
            {/each}
            {#if preTestResult.models.length > 12}
              <span class="pst-model-tag pst-model-tag--more">+{preTestResult.models.length - 12}</span>
            {/if}
          </div>
        </div>
      {:else if preTestResult.status === 'error'}
        <div class="pst-pretest pst-pretest--error">
          <div class="pst-pretest-header">
            <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" width="14" height="14"><path d="M8 5v3M8 10.5v.5"/><circle cx="8" cy="8" r="6"/></svg>
            <span>Connection failed</span>
          </div>
          {#if preTestResult.error}
            <span class="pst-pretest-error">{preTestResult.error}</span>
          {/if}
        </div>
      {/if}

      <div class="pst-form-actions">
        <button class="pst-btn pst-btn--secondary" onclick={resetAddForm}>Cancel</button>
        <button
          class="pst-btn pst-btn--test"
          onclick={handlePreTest}
          disabled={!addSlug || preTestLoading}
        >
          {#if preTestLoading}
            <svg class="pst-spinner" viewBox="0 0 16 16" width="13" height="13"><circle cx="8" cy="8" r="6" fill="none" stroke="currentColor" stroke-width="1.5" stroke-dasharray="28" stroke-dashoffset="8"/></svg>
            Testing...
          {:else}
            <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" width="13" height="13"><path d="M13.5 8A5.5 5.5 0 112.5 8a5.5 5.5 0 0111 0z"/><path d="M8 5v3l2 1.5"/></svg>
            Test Connection
          {/if}
        </button>
        <button class="pst-btn pst-btn--primary" onclick={handleAdd} disabled={!addSlug}>Add Provider</button>
      </div>
    </div>
  {/if}

  <!-- Provider List -->
  {#if providersStore.loading && providersStore.totalCount === 0}
    <div class="pst-empty">Loading providers...</div>
  {:else if providersStore.totalCount === 0 && !showAddForm}
    <div class="pst-empty">
      <p>No providers configured yet.</p>
      <button class="pst-btn pst-btn--primary" onclick={() => { showAddForm = true; }}>Add your first provider</button>
    </div>
  {:else}
    <div class="pst-list">
      {#each providersStore.providers as prov (prov.id)}
        <div class="pst-card pst-provider-card">
          <div class="pst-provider-header">
            <span class="pst-dot {statusDot(prov.status)}"></span>
            <span class="pst-provider-name">{prov.name}</span>
            <span class="pst-provider-slug">{prov.slug}</span>
            {#if prov.is_default}
              <span class="pst-badge">Default</span>
            {/if}
            {#if prov.category === 'local'}
              <span class="pst-badge pst-badge--local">Local</span>
            {/if}
          </div>

          <div class="pst-provider-meta">
            {#if prov.endpoint}
              <span class="pst-meta-item">{prov.endpoint}</span>
            {/if}
            {#if prov.models.length > 0}
              <span class="pst-meta-item">{prov.models.length} model{prov.models.length !== 1 ? 's' : ''}</span>
            {/if}
            {#if prov.last_tested_at}
              <span class="pst-meta-item">Tested {new Date(prov.last_tested_at).toLocaleString()}</span>
            {/if}
            {#if prov.config.temperature !== undefined}
              <span class="pst-meta-item">temp: {prov.config.temperature}</span>
            {/if}
            {#if prov.config.local_runtime !== undefined}
              <span class="pst-meta-item">runtime: {prov.config.local_runtime}</span>
            {/if}
          </div>

          {#if prov.status === 'error' && prov.error_message}
            <div class="pst-error-msg">{prov.error_message}</div>
          {/if}

          {#if prov.models.length > 0}
            <div class="pst-models">
              {#each prov.models.slice(0, 6) as m}
                <span class="pst-model-tag">{m}</span>
              {/each}
              {#if prov.models.length > 6}
                <span class="pst-model-tag pst-model-tag--more">+{prov.models.length - 6}</span>
              {/if}
            </div>
          {/if}

          <!-- Edit form -->
          {#if editingId === prov.id}
            <div class="pst-edit-form">
              <div class="pst-field">
                <label class="pst-label">API Key <span class="pst-optional">(leave blank to keep current)</span></label>
                <input class="pst-input" type="password" placeholder="New API key..." autocomplete="off" value={editApiKey} oninput={(e) => { editApiKey = (e.target as HTMLInputElement).value; }} />
              </div>
              <div class="pst-field">
                <label class="pst-label">Endpoint</label>
                <input class="pst-input" type="text" value={editEndpoint} oninput={(e) => { editEndpoint = (e.target as HTMLInputElement).value; }} />
              </div>
              <div class="pst-adv-grid">
                <div class="pst-field pst-field--half">
                  <label class="pst-label">Temperature</label>
                  <input class="pst-input" type="number" step="0.1" min="0" max="2" value={editTemperature} oninput={(e) => { editTemperature = (e.target as HTMLInputElement).value; }} />
                </div>
                <div class="pst-field pst-field--half">
                  <label class="pst-label">Max Tokens</label>
                  <input class="pst-input" type="number" step="256" min="1" value={editMaxTokens} oninput={(e) => { editMaxTokens = (e.target as HTMLInputElement).value; }} />
                </div>
              </div>
              <div class="pst-form-actions">
                <button class="pst-btn pst-btn--secondary" onclick={() => { editingId = null; }}>Cancel</button>
                <button class="pst-btn pst-btn--primary" onclick={saveEdit}>Save</button>
              </div>
            </div>
          {/if}

          <div class="pst-provider-actions">
            <button
              class="pst-action-btn"
              onclick={() => handleTest(prov.id)}
              disabled={testingId === prov.id}
            >
              {#if testingId === prov.id}
                <svg class="pst-spinner" viewBox="0 0 16 16" width="13" height="13"><circle cx="8" cy="8" r="6" fill="none" stroke="currentColor" stroke-width="1.5" stroke-dasharray="28" stroke-dashoffset="8"/></svg>
                Testing...
              {:else}
                <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" width="13" height="13"><path d="M13.5 8A5.5 5.5 0 112.5 8a5.5 5.5 0 0111 0z"/><path d="M8 5v3l2 1.5"/></svg>
                Test
              {/if}
            </button>
            <button
              class="pst-action-btn"
              onclick={() => handleFetchModels(prov.id)}
              disabled={fetchingModelsId === prov.id}
            >
              {#if fetchingModelsId === prov.id}
                <svg class="pst-spinner" viewBox="0 0 16 16" width="13" height="13"><circle cx="8" cy="8" r="6" fill="none" stroke="currentColor" stroke-width="1.5" stroke-dasharray="28" stroke-dashoffset="8"/></svg>
                Fetching...
              {:else}
                <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" width="13" height="13"><path d="M3 8h10M10 5l3 3-3 3"/></svg>
                Fetch Models
              {/if}
            </button>
            <button class="pst-action-btn" onclick={() => startEdit(prov)} disabled={editingId === prov.id}>
              <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" width="13" height="13"><path d="M11.5 2.5l2 2-8 8H3.5v-2l8-8z"/></svg>
              Edit
            </button>
            {#if !prov.is_default}
              <button class="pst-action-btn" onclick={() => handleSetDefault(prov.id)}>
                <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" width="13" height="13"><path d="M8 1.5l2 4.5 5 .5-3.75 3.5L12.25 15 8 12.5 3.75 15l1-5-3.75-3.5 5-.5z"/></svg>
                Set Default
              </button>
            {/if}
            <button class="pst-action-btn pst-action-btn--danger" onclick={() => handleRemove(prov.id)}>
              <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" width="13" height="13"><path d="M2.5 4.5h11M5.5 4.5V3a1 1 0 011-1h3a1 1 0 011 1v1.5m1.5 0v8a1 1 0 01-1 1h-6a1 1 0 01-1-1v-8"/></svg>
              Remove
            </button>
          </div>
        </div>
      {/each}
    </div>
  {/if}
</section>

<style>
  .pst-section { max-width: 720px; }

  .pst-header {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    gap: 16px;
    margin-bottom: 16px;
  }

  .pst-title {
    font-size: 15px;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0 0 4px;
  }

  .pst-subtitle {
    font-size: 12px;
    color: var(--text-tertiary);
    margin: 0;
    line-height: 1.5;
  }

  .pst-count {
    font-weight: 500;
    color: var(--text-secondary);
  }

  .pst-add-btn {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 7px 14px;
    font-size: 13px;
    font-weight: 500;
    color: #fff;
    background: var(--accent-primary);
    border: none;
    border-radius: var(--radius-sm);
    cursor: pointer;
    white-space: nowrap;
    transition: opacity var(--transition-fast);
  }

  .pst-add-btn:hover { opacity: 0.9; }

  .pst-card {
    background: var(--bg-surface);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-md);
    padding: 16px;
  }

  .pst-add-card {
    margin-bottom: 16px;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .pst-card-title {
    font-size: 14px;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0;
  }

  .pst-toggle-row {
    display: flex;
    gap: 4px;
    background: var(--bg-elevated);
    border-radius: var(--radius-sm);
    padding: 3px;
    width: fit-content;
  }

  .pst-toggle {
    padding: 5px 14px;
    font-size: 12px;
    font-weight: 500;
    color: var(--text-secondary);
    background: transparent;
    border: none;
    border-radius: var(--radius-xs);
    cursor: pointer;
    transition: background var(--transition-fast), color var(--transition-fast);
  }

  .pst-toggle--active {
    background: var(--bg-surface);
    color: var(--text-primary);
    box-shadow: 0 1px 2px rgba(0,0,0,0.1);
  }

  .pst-field {
    display: flex;
    flex-direction: column;
    gap: 5px;
  }

  .pst-field--half { flex: 1; min-width: 0; }

  .pst-label {
    font-size: 12px;
    font-weight: 500;
    color: var(--text-secondary);
  }

  .pst-optional {
    font-weight: 400;
    color: var(--text-muted);
  }

  .pst-input {
    width: 100%;
    padding: 7px 10px;
    font-size: 13px;
    color: var(--text-primary);
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-sm);
    outline: none;
    transition: border-color var(--transition-fast);
    box-sizing: border-box;
  }

  .pst-input:focus { border-color: var(--border-focus); }
  .pst-input::placeholder { color: var(--text-muted); }

  .pst-select {
    width: 100%;
    padding: 7px 10px;
    font-size: 13px;
    color: var(--text-primary);
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-sm);
    outline: none;
    cursor: pointer;
    appearance: auto;
  }

  .pst-select:focus { border-color: var(--border-focus); }

  .pst-runtime-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 6px;
  }

  .pst-runtime-card {
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: 8px 10px;
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-sm);
    cursor: pointer;
    text-align: left;
    transition: border-color var(--transition-fast), background var(--transition-fast);
  }

  .pst-runtime-card:hover { border-color: var(--border-hover); }

  .pst-runtime-card--active {
    border-color: var(--accent-primary);
    background: rgba(var(--accent-primary-rgb, 59, 130, 246), 0.06);
  }

  .pst-runtime-name {
    font-size: 12px;
    font-weight: 600;
    color: var(--text-primary);
  }

  .pst-runtime-desc {
    font-size: 10px;
    color: var(--text-tertiary);
    line-height: 1.3;
  }

  .pst-runtime-ep {
    font-size: 10px;
    font-family: var(--font-mono);
    color: var(--text-muted);
    margin-top: 2px;
  }

  .pst-advanced-toggle {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 4px 0;
    font-size: 12px;
    font-weight: 500;
    color: var(--text-tertiary);
    background: none;
    border: none;
    cursor: pointer;
    transition: color var(--transition-fast);
  }

  .pst-advanced-toggle:hover { color: var(--text-secondary); }

  .pst-adv-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 10px;
  }

  .pst-check-row {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 12px;
    color: var(--text-secondary);
    cursor: pointer;
  }

  .pst-form-actions {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
    padding-top: 4px;
  }

  .pst-btn {
    padding: 7px 16px;
    font-size: 13px;
    font-weight: 500;
    border: none;
    border-radius: var(--radius-sm);
    cursor: pointer;
    transition: opacity var(--transition-fast);
  }

  .pst-btn:disabled { opacity: 0.5; cursor: not-allowed; }

  .pst-btn--primary {
    background: var(--accent-primary);
    color: #fff;
  }

  .pst-btn--primary:hover:not(:disabled) { opacity: 0.9; }

  .pst-btn--secondary {
    background: var(--bg-elevated);
    color: var(--text-secondary);
    border: 1px solid var(--border-default);
  }

  .pst-btn--secondary:hover:not(:disabled) {
    background: var(--bg-surface);
  }

  /* Provider List */

  .pst-list {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .pst-provider-card {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .pst-provider-header {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .pst-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    flex-shrink: 0;
  }

  .pst-dot--ok { background: #22c55e; }
  .pst-dot--error { background: #ef4444; }
  .pst-dot--untested { background: var(--text-muted); }

  .pst-provider-name {
    font-size: 14px;
    font-weight: 600;
    color: var(--text-primary);
  }

  .pst-provider-slug {
    font-size: 11px;
    font-family: var(--font-mono);
    color: var(--text-muted);
  }

  .pst-badge {
    font-size: 10px;
    font-weight: 600;
    letter-spacing: 0.04em;
    padding: 1px 7px;
    border-radius: 100px;
    background: rgba(var(--accent-primary-rgb, 59, 130, 246), 0.12);
    color: var(--accent-primary);
    border: 1px solid rgba(var(--accent-primary-rgb, 59, 130, 246), 0.25);
  }

  .pst-badge--local {
    background: rgba(249, 115, 22, 0.12);
    color: #f97316;
    border-color: rgba(249, 115, 22, 0.25);
  }

  .pst-provider-meta {
    display: flex;
    flex-wrap: wrap;
    gap: 12px;
  }

  .pst-meta-item {
    font-size: 11px;
    color: var(--text-tertiary);
  }

  .pst-error-msg {
    font-size: 11px;
    color: #ef4444;
    padding: 4px 8px;
    background: rgba(239, 68, 68, 0.08);
    border-radius: var(--radius-xs);
  }

  .pst-models {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
  }

  .pst-model-tag {
    font-size: 10px;
    font-family: var(--font-mono);
    color: var(--text-tertiary);
    padding: 2px 6px;
    background: var(--bg-elevated);
    border-radius: var(--radius-xs);
    border: 1px solid var(--border-default);
  }

  .pst-model-tag--more {
    color: var(--text-muted);
    font-style: italic;
  }

  .pst-edit-form {
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding: 10px 0;
    border-top: 1px solid var(--border-default);
  }

  .pst-provider-actions {
    display: flex;
    gap: 4px;
    border-top: 1px solid var(--border-default);
    padding-top: 8px;
  }

  .pst-action-btn {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    padding: 5px 10px;
    font-size: 11px;
    font-weight: 500;
    color: var(--text-secondary);
    background: transparent;
    border: 1px solid var(--border-default);
    border-radius: var(--radius-xs);
    cursor: pointer;
    transition: background var(--transition-fast), color var(--transition-fast);
  }

  .pst-action-btn:hover:not(:disabled) {
    background: var(--bg-elevated);
    color: var(--text-primary);
  }

  .pst-action-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .pst-action-btn--danger:hover:not(:disabled) {
    color: #ef4444;
    border-color: rgba(239, 68, 68, 0.3);
    background: rgba(239, 68, 68, 0.06);
  }

  .pst-spinner {
    animation: pst-spin 1s linear infinite;
  }

  @keyframes pst-spin {
    to { transform: rotate(360deg); }
  }

  .pst-empty {
    text-align: center;
    padding: 40px 20px;
    color: var(--text-tertiary);
    font-size: 13px;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 12px;
  }

  .pst-btn--test {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    background: var(--bg-elevated);
    color: var(--text-secondary);
    border: 1px solid var(--border-default);
  }

  .pst-btn--test:hover:not(:disabled) {
    background: var(--bg-surface);
    color: var(--text-primary);
    border-color: var(--border-hover);
  }

  .pst-pretest {
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 10px 12px;
    border-radius: var(--radius-sm);
    font-size: 12px;
  }

  .pst-pretest--success {
    background: rgba(34, 197, 94, 0.06);
    border: 1px solid rgba(34, 197, 94, 0.25);
  }

  .pst-pretest--error {
    background: rgba(239, 68, 68, 0.06);
    border: 1px solid rgba(239, 68, 68, 0.25);
  }

  .pst-pretest-header {
    display: flex;
    align-items: center;
    gap: 6px;
    font-weight: 500;
  }

  .pst-pretest--success .pst-pretest-header {
    color: #22c55e;
  }

  .pst-pretest--error .pst-pretest-header {
    color: #ef4444;
  }

  .pst-pretest-models {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
  }

  .pst-pretest-error {
    font-size: 11px;
    color: var(--text-tertiary);
  }
</style>
