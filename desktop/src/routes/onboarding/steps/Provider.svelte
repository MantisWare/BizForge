<script lang="ts" module>
  import type { LocalRuntime } from '$lib/data/provider-catalog';

  export interface ProviderSetup {
    slug: string;
    apiKey: string;
    localRuntime?: LocalRuntime;
    endpoint?: string;
  }
</script>

<script lang="ts">
  import {
    FEATURED_PROVIDERS,
    MORE_PROVIDERS,
    LOCAL_RUNTIMES,
    findProvider,
    getDefaultEndpoint,
  } from '$lib/data/provider-catalog';

  interface Props {
    selectedProviders: ProviderSetup[];
  }

  let {
    selectedProviders = $bindable(),
  }: Props = $props();

  let showMoreProviders = $state(false);
  let testingSlug = $state<string | null>(null);
  let testResults = $state<Record<string, { ok: boolean; msg: string }>>({});

  function isSelected(slug: string): boolean {
    return selectedProviders.some((p) => p.slug === slug);
  }

  function toggleProvider(slug: string) {
    if (isSelected(slug)) {
      selectedProviders = selectedProviders.filter((p) => p.slug !== slug);
    } else {
      const entry = findProvider(slug);
      const setup: ProviderSetup = { slug, apiKey: '' };
      if (slug === 'local') {
        setup.localRuntime = 'ollama';
        setup.endpoint = getDefaultEndpoint('local', 'ollama');
      } else if (entry?.defaultEndpoint) {
        setup.endpoint = entry.defaultEndpoint;
      }
      selectedProviders = [...selectedProviders, setup];
    }
  }

  function getSetup(slug: string): ProviderSetup | undefined {
    return selectedProviders.find((p) => p.slug === slug);
  }

  function updateKey(slug: string, key: string) {
    selectedProviders = selectedProviders.map((p) =>
      p.slug === slug ? { ...p, apiKey: key } : p,
    );
  }

  function updateRuntime(slug: string, runtime: LocalRuntime) {
    selectedProviders = selectedProviders.map((p) =>
      p.slug === slug
        ? { ...p, localRuntime: runtime, endpoint: getDefaultEndpoint('local', runtime) }
        : p,
    );
  }

  async function handleTest(slug: string) {
    testingSlug = slug;
    const setup = getSetup(slug);
    if (setup === undefined) { testingSlug = null; return; }

    try {
      const endpoint = setup.endpoint ?? findProvider(slug)?.defaultEndpoint ?? '';
      const { providers } = await import('$api/client');
      const result = await providers.fetchModels(endpoint, setup.apiKey, slug);
      if (result.models.length > 0) {
        testResults = { ...testResults, [slug]: { ok: true, msg: 'Connected' } };
      } else {
        testResults = { ...testResults, [slug]: { ok: false, msg: result.error ?? 'No models returned' } };
      }
    } catch (e) {
      testResults = { ...testResults, [slug]: { ok: false, msg: (e as Error).message } };
    } finally {
      testingSlug = null;
    }
  }
</script>

<div class="ob-step">
  <div class="ob-step-icon">
    <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" width="28" height="28">
      <circle cx="10" cy="10" r="7.5"/>
      <path d="M10 6v4l2.5 2.5"/>
    </svg>
  </div>
  <h1 class="ob-title">Configure Providers</h1>
  <p class="ob-subtitle">Select one or more AI providers — you can add keys and test each one</p>

  <div class="ob-providers">
    {#each FEATURED_PROVIDERS as p}
      {@const selected = isSelected(p.slug)}
      {@const setup = getSetup(p.slug)}
      <button
        class="ob-provider-card"
        class:ob-provider-card--selected={selected}
        onclick={() => toggleProvider(p.slug)}
      >
        <div class="ob-provider-header">
          <span class="ob-provider-check">
            {#if selected}
              <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" width="12" height="12"><path d="M3.5 8.5l3 3 6-7"/></svg>
            {:else}
              <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" width="12" height="12"><rect x="2" y="2" width="12" height="12" rx="3"/></svg>
            {/if}
          </span>
          <span class="ob-provider-name">{p.name}</span>
          {#if p.recommended}
            <span class="ob-badge">Recommended</span>
          {/if}
          {#if p.noKey}
            <span class="ob-badge ob-badge--accent">No key needed</span>
          {/if}
        </div>
        <p class="ob-provider-desc">{p.description}</p>

        {#if selected}
          <div class="ob-provider-config" onclick={(e) => e.stopPropagation()} role="none">
            {#if p.slug === 'local'}
              <!-- Local runtime picker -->
              <div class="ob-runtime-row">
                {#each LOCAL_RUNTIMES as rt (rt.id)}
                  <button
                    class="ob-runtime-chip"
                    class:ob-runtime-chip--active={setup?.localRuntime === rt.id}
                    onclick={() => updateRuntime(p.slug, rt.id)}
                  >
                    {rt.name}
                  </button>
                {/each}
              </div>
              <input
                class="ob-input ob-input--key"
                type="text"
                placeholder={setup?.endpoint ?? 'http://localhost:11434'}
                value={setup?.endpoint ?? ''}
                oninput={(e) => {
                  selectedProviders = selectedProviders.map((s) =>
                    s.slug === p.slug ? { ...s, endpoint: (e.currentTarget as HTMLInputElement).value } : s,
                  );
                }}
              />
            {:else if !p.noKey}
              <input
                class="ob-input ob-input--key"
                type="password"
                placeholder="sk-..."
                autocomplete="off"
                value={setup?.apiKey ?? ''}
                oninput={(e) => updateKey(p.slug, (e.currentTarget as HTMLInputElement).value)}
              />
            {/if}

            <!-- Test button -->
            <div class="ob-test-row">
              <button
                class="ob-test-btn"
                onclick={() => handleTest(p.slug)}
                disabled={testingSlug === p.slug}
              >
                {testingSlug === p.slug ? 'Testing...' : 'Test Connection'}
              </button>
              {#if testResults[p.slug] !== undefined}
                <span class="ob-test-result" class:ob-test-result--ok={testResults[p.slug].ok} class:ob-test-result--fail={!testResults[p.slug].ok}>
                  {testResults[p.slug].msg}
                </span>
              {/if}
            </div>
          </div>
        {/if}
      </button>
    {/each}
  </div>

  <button class="ob-show-more" onclick={() => showMoreProviders = !showMoreProviders}>
    <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" width="14" height="14" style="transform: rotate({showMoreProviders ? 180 : 0}deg); transition: transform 200ms ease">
      <path d="M4 6l4 4 4-4"/>
    </svg>
    {showMoreProviders ? 'Show fewer' : 'Show more providers'}
  </button>

  {#if showMoreProviders}
    <div class="ob-providers ob-providers--more">
      {#each MORE_PROVIDERS as p}
        {@const selected = isSelected(p.slug)}
        {@const setup = getSetup(p.slug)}
        <button
          class="ob-provider-card ob-provider-card--compact"
          class:ob-provider-card--selected={selected}
          onclick={() => toggleProvider(p.slug)}
        >
          <div class="ob-provider-header">
            <span class="ob-provider-check">
              {#if selected}
                <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" width="11" height="11"><path d="M3.5 8.5l3 3 6-7"/></svg>
              {:else}
                <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" width="11" height="11"><rect x="2" y="2" width="12" height="12" rx="3"/></svg>
              {/if}
            </span>
            <span class="ob-provider-name">{p.name}</span>
          </div>
          <p class="ob-provider-desc">{p.description}</p>
          {#if selected}
            <div class="ob-provider-config" onclick={(e) => e.stopPropagation()} role="none">
              <input
                class="ob-input ob-input--key"
                type="password"
                placeholder="API key..."
                autocomplete="off"
                value={setup?.apiKey ?? ''}
                oninput={(e) => updateKey(p.slug, (e.currentTarget as HTMLInputElement).value)}
              />
              <div class="ob-test-row">
                <button
                  class="ob-test-btn"
                  onclick={() => handleTest(p.slug)}
                  disabled={testingSlug === p.slug}
                >
                  {testingSlug === p.slug ? 'Testing...' : 'Test'}
                </button>
                {#if testResults[p.slug] !== undefined}
                  <span class="ob-test-result" class:ob-test-result--ok={testResults[p.slug].ok} class:ob-test-result--fail={!testResults[p.slug].ok}>
                    {testResults[p.slug].msg}
                  </span>
                {/if}
              </div>
            </div>
          {/if}
        </button>
      {/each}
    </div>
  {/if}
</div>

<style>
  .ob-step {
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: center;
    flex: 1;
    gap: 0;
  }

  .ob-step-icon {
    width: 52px;
    height: 52px;
    border-radius: 14px;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid rgba(255, 255, 255, 0.08);
    display: flex;
    align-items: center;
    justify-content: center;
    color: rgba(255, 255, 255, 0.6);
    margin: 0 auto 1.25rem;
  }

  .ob-title {
    font-size: 1.625rem;
    font-weight: 700;
    color: #ffffff;
    margin: 0 0 0.375rem;
    letter-spacing: -0.02em;
  }

  .ob-subtitle {
    font-size: 0.875rem;
    color: rgba(255, 255, 255, 0.45);
    margin: 0 0 1.75rem;
  }

  .ob-providers {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0.5rem;
    width: 100%;
    margin-bottom: 0.75rem;
  }

  .ob-providers--more {
    grid-template-columns: 1fr 1fr 1fr;
    margin-top: 0.5rem;
  }

  .ob-provider-card {
    background: rgba(255, 255, 255, 0.03);
    border: 1px solid rgba(255, 255, 255, 0.07);
    border-radius: 10px;
    padding: 0.75rem;
    text-align: left;
    cursor: pointer;
    transition: background 150ms ease, border-color 150ms ease;
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
  }

  .ob-provider-card:hover {
    background: rgba(255, 255, 255, 0.06);
    border-color: rgba(255, 255, 255, 0.12);
  }

  .ob-provider-card--selected {
    background: rgba(242, 101, 34, 0.07);
    border-color: rgba(242, 101, 34, 0.4);
  }

  .ob-provider-card--compact {
    padding: 0.5rem 0.625rem;
  }

  .ob-provider-header {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    flex-wrap: wrap;
  }

  .ob-provider-check {
    color: rgba(255, 255, 255, 0.4);
    display: flex;
    align-items: center;
    flex-shrink: 0;
  }

  .ob-provider-card--selected .ob-provider-check {
    color: #f26522;
  }

  .ob-provider-name {
    font-size: 0.8125rem;
    font-weight: 600;
    color: #e0e0e0;
    flex: 1;
  }

  .ob-provider-desc {
    font-size: 0.6875rem;
    color: rgba(255, 255, 255, 0.35);
    margin: 0;
    line-height: 1.4;
  }

  .ob-badge {
    font-size: 0.625rem;
    font-weight: 600;
    letter-spacing: 0.04em;
    padding: 1px 6px;
    border-radius: 100px;
    background: rgba(255, 255, 255, 0.1);
    color: rgba(255, 255, 255, 0.55);
    border: 1px solid rgba(255, 255, 255, 0.12);
    white-space: nowrap;
  }

  .ob-badge--accent {
    background: rgba(242, 101, 34, 0.12);
    color: #f26522;
    border-color: rgba(242, 101, 34, 0.25);
  }

  .ob-provider-config {
    display: flex;
    flex-direction: column;
    gap: 0.375rem;
    margin-top: 0.375rem;
  }

  .ob-runtime-row {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
  }

  .ob-runtime-chip {
    padding: 3px 8px;
    font-size: 0.6875rem;
    font-weight: 500;
    color: rgba(255, 255, 255, 0.5);
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid rgba(255, 255, 255, 0.1);
    border-radius: 100px;
    cursor: pointer;
    transition: background 150ms ease, border-color 150ms ease, color 150ms ease;
  }

  .ob-runtime-chip:hover {
    background: rgba(255, 255, 255, 0.08);
  }

  .ob-runtime-chip--active {
    background: rgba(242, 101, 34, 0.15);
    border-color: rgba(242, 101, 34, 0.4);
    color: #f26522;
  }

  .ob-test-row {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .ob-test-btn {
    padding: 3px 10px;
    font-size: 0.6875rem;
    font-weight: 500;
    color: rgba(255, 255, 255, 0.6);
    background: rgba(255, 255, 255, 0.06);
    border: 1px solid rgba(255, 255, 255, 0.12);
    border-radius: 6px;
    cursor: pointer;
    transition: background 150ms ease;
    white-space: nowrap;
  }

  .ob-test-btn:hover:not(:disabled) {
    background: rgba(255, 255, 255, 0.1);
  }

  .ob-test-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .ob-test-result {
    font-size: 0.625rem;
    font-weight: 500;
  }

  .ob-test-result--ok { color: #22c55e; }
  .ob-test-result--fail { color: #ef4444; }

  .ob-show-more {
    display: flex;
    align-items: center;
    gap: 0.375rem;
    background: none;
    border: none;
    color: rgba(255, 255, 255, 0.4);
    font-size: 0.8125rem;
    cursor: pointer;
    padding: 0.375rem 0;
    transition: color 150ms ease;
    align-self: flex-start;
  }

  .ob-show-more:hover {
    color: rgba(255, 255, 255, 0.7);
  }

  .ob-input {
    width: 100%;
    background: rgba(255, 255, 255, 0.04);
    border: 1px solid rgba(255, 255, 255, 0.1);
    border-radius: 8px;
    padding: 0.625rem 0.875rem;
    font-size: 0.9375rem;
    color: #f0f0f0;
    outline: none;
    transition: border-color 150ms ease;
    box-sizing: border-box;
  }

  .ob-input::placeholder {
    color: rgba(255, 255, 255, 0.2);
  }

  .ob-input:focus {
    border-color: rgba(242, 101, 34, 0.5);
  }

  .ob-input--key {
    font-size: 0.875rem;
  }
</style>
