<!-- src/routes/app/integrations/+page.svelte -->
<script lang="ts">
  import { onMount } from 'svelte';
  import PageShell from '$lib/components/layout/PageShell.svelte';
  import { integrationsStore } from '$lib/stores/integrations.svelte';
  import { detectAdapters, installAdapter, checkAdapterHealth } from '$lib/services/adapters';
  import type { AdapterStatus } from '$lib/services/adapters';
  import { getProviderCredentials } from '$lib/services/credentials';
  import { checkOsaHealth, findOsaPort, setupOsa } from '$lib/services/osa';
  import type { OsaHealth, OsaSetupStep } from '$lib/services/osa';
  import { isTauri } from '$lib/utils/platform';

  let adapters = $state<AdapterStatus[]>([]);
  let adapterLoading = $state(true);
  let installingId = $state<string | null>(null);
  let installOutput = $state<string | null>(null);
  let providerSlug = $state<string | null>(null);
  let activeTab = $state<'adapters' | 'integrations'>('adapters');

  // OSA setup state
  let osaHealth = $state<OsaHealth | null>(null);
  let osaPort = $state<number | null>(null);
  let osaSetupSteps = $state<OsaSetupStep[]>([]);
  let osaSetupRunning = $state(false);
  let osaElixirInstalled = $state<boolean | null>(null);
  let osaFound = $state<boolean | null>(null);

  onMount(async () => {
    const [, creds,] = await Promise.all([
      loadAdapters(),
      getProviderCredentials(),
      checkOsa(),
    ]);
    if (creds) providerSlug = creds.slug;
    // Re-check OSA after adapters load (for elixir/osa detection via adapter list)
    await checkOsa();
    void integrationsStore.fetchIntegrations();
  });

  async function loadAdapters() {
    adapterLoading = true;
    try {
      adapters = await detectAdapters();
    } catch {
      adapters = [];
    }
    adapterLoading = false;
  }

  async function handleInstall(id: string) {
    installingId = id;
    installOutput = null;
    try {
      const result = await installAdapter(id);
      installOutput = result.success ? 'Installed successfully' : result.output;
      await loadAdapters();
    } catch (e) {
      installOutput = (e as Error).message;
    }
    installingId = null;
  }

  async function handleHealthCheck(id: string) {
    const result = await checkAdapterHealth(id);
    const idx = adapters.findIndex(a => a.id === id);
    if (idx >= 0) {
      adapters[idx] = { ...adapters[idx], running: result.healthy };
      adapters = [...adapters];
    }
  }

  const installedCount = $derived(adapters.filter(a => a.installed).length);
  const runningCount = $derived(adapters.filter(a => a.running).length);

  // ── OSA Setup ─────────────────────────────────────────────────────────────

  async function checkOsa() {
    osaHealth = await checkOsaHealth();
    osaPort = await findOsaPort();

    // Derive elixir/osa status from adapter detection
    const osaAdapter = adapters.find(a => a.id === 'osa');
    if (osaAdapter) {
      osaElixirInstalled = osaAdapter.installed || osaAdapter.running;
      osaFound = osaAdapter.installed;
    } else {
      // If adapters haven't loaded yet, just check health
      osaElixirInstalled = null;
      osaFound = null;
    }
  }

  async function runOsaSetup() {
    osaSetupRunning = true;
    osaSetupSteps = [];
    try {
      osaSetupSteps = await setupOsa();
      // Derive statuses from setup results
      const elixirStep = osaSetupSteps.find(s => s.step === 'elixir');
      if (elixirStep) osaElixirInstalled = elixirStep.success;
      const locateStep = osaSetupSteps.find(s => s.step === 'locate');
      if (locateStep) osaFound = locateStep.success;
    } catch (e) {
      osaSetupSteps = [{ step: 'error', success: false, message: String(e) }];
    }
    osaSetupRunning = false;
    await checkOsa();
    await loadAdapters();
  }

  async function locateOsa() {
    if (!isTauri()) return;
    const { open } = await import('@tauri-apps/plugin-dialog');
    const selected = await open({ directory: true, title: 'Locate OSA Directory' });
    if (selected && typeof selected === 'string') {
      osaSetupRunning = true;
      osaSetupSteps = [];
      try {
        osaSetupSteps = await setupOsa(selected);
      } catch (e) {
        osaSetupSteps = [{ step: 'error', success: false, message: String(e) }];
      }
      osaSetupRunning = false;
      await checkOsa();
      await loadAdapters();
    }
  }
</script>

<PageShell
  title="Integrations"
  subtitle={activeTab === 'adapters'
    ? `${installedCount} adapters installed, ${runningCount} running`
    : `${integrationsStore.connectedCount} of ${integrationsStore.totalCount} services connected`}
>
  <div class="int-tabs">
    <button
      class="int-tab"
      class:int-tab--active={activeTab === 'adapters'}
      onclick={() => activeTab = 'adapters'}
    >
      <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" width="14" height="14"><rect x="3" y="3" width="6" height="6" rx="1"/><rect x="11" y="3" width="6" height="6" rx="1"/><rect x="3" y="11" width="6" height="6" rx="1"/><rect x="11" y="11" width="6" height="6" rx="1"/></svg>
      Adapters
      <span class="int-tab-count">{adapters.length}</span>
    </button>
    <button
      class="int-tab"
      class:int-tab--active={activeTab === 'integrations'}
      onclick={() => activeTab = 'integrations'}
    >
      <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" width="14" height="14"><circle cx="10" cy="10" r="7.5"/><path d="M10 6v4l2.5 2.5"/></svg>
      Services
      <span class="int-tab-count">{integrationsStore.connectedCount}</span>
    </button>
  </div>

  {#if activeTab === 'adapters'}
    <!-- Adapter Detection & Management -->
    {#if adapterLoading}
      <div class="int-loading" role="status">
        <div class="int-spinner"></div>
        <span>Detecting installed adapters...</span>
      </div>
    {:else}
      <div class="int-section-header">
        <p class="int-section-desc">Adapters determine how your agents execute tasks. Install and connect the ones you need.</p>
        <button class="int-refresh" onclick={loadAdapters} aria-label="Re-scan adapters">
          <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" width="14" height="14"><path d="M2 8a6 6 0 0111.3-2.7M14 8a6 6 0 01-11.3 2.7"/><path d="M14 2v4h-4M2 14v-4h4"/></svg>
          Re-scan
        </button>
      </div>

      {#if installOutput}
        <div class="int-toast" role="status">
          <span>{installOutput}</span>
          <button onclick={() => installOutput = null} aria-label="Dismiss">
            <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" width="12" height="12"><path d="M4 4l8 8M12 4l-8 8"/></svg>
          </button>
        </div>
      {/if}

      <!-- OSA Quick Setup -->
      {#if osaHealth}
        <div class="osa-connected" role="status">
          <div class="osa-connected-left">
            <div class="osa-dot osa-dot--live"></div>
            <strong class="osa-label">OSA</strong>
            {#if osaHealth.version}
              <span class="osa-ver">v{osaHealth.version}</span>
            {/if}
            <span class="osa-port">port {osaPort}</span>
          </div>
          <span class="osa-badge-running">Running</span>
        </div>
      {:else}
        <div class="osa-setup" role="region" aria-label="OSA Setup">
          <div class="osa-setup-top">
            <div class="osa-setup-info">
              <strong class="osa-setup-title">Set up OSA</strong>
              <p class="osa-setup-desc">The recommended agent runtime. Let's get it running.</p>
            </div>
          </div>

          {#if osaSetupSteps.length > 0}
            <div class="osa-steps">
              {#each osaSetupSteps as step (step.step + step.message)}
                <div class="osa-step" class:osa-step--ok={step.success} class:osa-step--fail={!step.success}>
                  <span class="osa-step-icon">{step.success ? '\u2713' : '\u2717'}</span>
                  <span class="osa-step-label">{step.step}</span>
                  <span class="osa-step-msg">{step.message}</span>
                </div>
              {/each}
            </div>
          {/if}

          <div class="osa-setup-actions">
            {#if osaElixirInstalled === false}
              <p class="osa-hint">Install Elixir first: <code>brew install elixir</code></p>
            {:else if osaFound === false}
              <button class="adp-btn adp-btn--secondary" onclick={locateOsa} disabled={osaSetupRunning}>
                Locate OSA Directory
              </button>
              <p class="osa-hint">Or: <code>git clone https://github.com/Miosa-osa/OptimalSystemAgent</code></p>
            {:else}
              <button class="adp-btn adp-btn--primary" onclick={runOsaSetup} disabled={osaSetupRunning}>
                {#if osaSetupRunning}
                  <div class="int-spinner int-spinner--sm"></div>
                  Setting up...
                {:else}
                  Auto-Setup OSA
                {/if}
              </button>
            {/if}
          </div>
        </div>
      {/if}

      <div class="adp-grid" role="list">
        {#each adapters as adapter (adapter.id)}
          <div class="adp-card" class:adp-card--installed={adapter.installed} class:adp-card--running={adapter.running} role="listitem">
            <div class="adp-header">
              <div class="adp-status-dot" class:adp-status-dot--running={adapter.running} class:adp-status-dot--installed={adapter.installed && !adapter.running} title={adapter.running ? 'Running' : adapter.installed ? 'Installed' : 'Not installed'}></div>
              <span class="adp-name">{adapter.name}</span>
              {#if adapter.version}
                <span class="adp-version">v{adapter.version}</span>
              {/if}
            </div>

            {#if adapter.path}
              <div class="adp-path">{adapter.path}</div>
            {/if}

            <div class="adp-status-text">
              {#if adapter.running}
                <span class="adp-badge adp-badge--running">Connected</span>
              {:else if adapter.installed}
                <span class="adp-badge adp-badge--installed">Installed</span>
              {:else}
                <span class="adp-badge adp-badge--missing">Not installed</span>
              {/if}
            </div>

            <div class="adp-actions">
              {#if !adapter.installed}
                {#if installingId === adapter.id}
                  <button class="adp-btn adp-btn--primary" disabled>
                    <div class="int-spinner int-spinner--sm"></div>
                    Installing...
                  </button>
                {:else if adapter.installHint === 'Already installed' || adapter.installHint === 'No installation needed'}
                  <span class="adp-hint">Built-in</span>
                {:else}
                  <button class="adp-btn adp-btn--primary" onclick={() => handleInstall(adapter.id)}>
                    Install
                  </button>
                  <span class="adp-hint">{adapter.installHint}</span>
                {/if}
              {:else if !adapter.running}
                <button class="adp-btn adp-btn--secondary" onclick={() => handleHealthCheck(adapter.id)}>
                  Check Connection
                </button>
              {:else}
                <span class="adp-hint adp-hint--connected">Ready to use</span>
              {/if}
            </div>
          </div>
        {/each}
      </div>

      {#if providerSlug}
        <div class="int-provider-status">
          <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" width="14" height="14"><circle cx="8" cy="8" r="6.5"/><path d="M8 5v3l2 1.5"/></svg>
          <span>LLM Provider: <strong>{providerSlug}</strong> (configured in onboarding)</span>
        </div>
      {/if}
    {/if}

  {:else}
    <!-- Services / External Integrations -->
    {#if integrationsStore.loading && integrationsStore.integrations.length === 0}
      <div class="int-loading" role="status">
        <div class="int-spinner"></div>
        <span>Loading services...</span>
      </div>
    {:else if integrationsStore.integrations.length === 0}
      <div class="int-empty" role="status">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" width="32" height="32"><circle cx="12" cy="12" r="10"/><path d="M12 8v4l3 3"/></svg>
        <p>No service integrations available yet.</p>
      </div>
    {:else}
      <!-- Search & Filter Bar -->
      <div class="svc-toolbar">
        <div class="svc-search">
          <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" width="14" height="14"><circle cx="6.5" cy="6.5" r="4.5"/><path d="M10 10l4 4"/></svg>
          <input
            type="text"
            class="svc-search-input"
            placeholder="Search services..."
            bind:value={integrationsStore.searchQuery}
          />
          {#if integrationsStore.searchQuery.length > 0}
            <button class="svc-search-clear" onclick={() => integrationsStore.searchQuery = ''} aria-label="Clear search">
              <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" width="12" height="12"><path d="M4 4l8 8M12 4l-8 8"/></svg>
            </button>
          {/if}
        </div>
        <div class="svc-summary">
          <span class="svc-summary-count">{integrationsStore.connectedCount}</span> of <span class="svc-summary-count">{integrationsStore.totalCount}</span> connected
        </div>
      </div>

      <!-- Category Filter Pills -->
      <div class="svc-filters">
        <button
          class="svc-pill"
          class:svc-pill--active={integrationsStore.filterCategory === 'all'}
          onclick={() => integrationsStore.filterCategory = 'all'}
        >
          All
          <span class="svc-pill-count">{integrationsStore.totalCount}</span>
        </button>
        {#each integrationsStore.categories as cat (cat.value)}
          <button
            class="svc-pill"
            class:svc-pill--active={integrationsStore.filterCategory === cat.value}
            onclick={() => integrationsStore.filterCategory = cat.value}
          >
            {cat.label}
            <span class="svc-pill-count">{cat.count}</span>
          </button>
        {/each}
      </div>

      <!-- Grouped Service Cards -->
      {#if integrationsStore.filtered.length === 0}
        <div class="int-empty" role="status">
          <p>No services match your search.</p>
        </div>
      {:else}
        {#each integrationsStore.grouped as group (group.category)}
          <div class="svc-category">
            <div class="svc-category-header">
              <h3 class="svc-category-title">{group.label}</h3>
              <span class="svc-category-stat">
                {group.connectedCount}/{group.integrations.length} connected
              </span>
            </div>
            <div class="svc-grid" role="list">
              {#each group.integrations as integration (integration.id)}
                <div class="svc-card" class:svc-card--connected={integration.status === 'connected'} class:svc-card--error={integration.status === 'error'} role="listitem">
                  <div class="svc-card-top">
                    <div class="svc-card-identity">
                      <div class="svc-card-icon" class:svc-card-icon--connected={integration.status === 'connected'}>
                        {#if integration.icon_url}
                          <img src={integration.icon_url} alt="" width="20" height="20" />
                        {:else}
                          <span class="svc-card-initial">{integration.name.charAt(0)}</span>
                        {/if}
                      </div>
                      <div class="svc-card-meta">
                        <span class="svc-card-name">{integration.name}</span>
                        <span class="svc-card-provider">{integration.provider}</span>
                      </div>
                    </div>
                    <span class="svc-status svc-status--{integration.status}">
                      {#if integration.status === 'connected'}
                        <span class="svc-status-dot svc-status-dot--connected"></span>
                        Connected
                      {:else if integration.status === 'error'}
                        <span class="svc-status-dot svc-status-dot--error"></span>
                        Error
                      {:else}
                        Available
                      {/if}
                    </span>
                  </div>

                  <p class="svc-card-desc">{integration.description}</p>

                  {#if integration.features.length > 0}
                    <div class="svc-card-features">
                      {#each integration.features as feature}
                        <span class="svc-feature-tag">{feature}</span>
                      {/each}
                    </div>
                  {/if}

                  <div class="svc-card-footer">
                    {#if integration.status === 'connected'}
                      <button
                        class="svc-btn svc-btn--disconnect"
                        onclick={() => integrationsStore.disconnect(integration.provider)}
                      >
                        Disconnect
                      </button>
                      {#if integration.last_sync_at}
                        <span class="svc-card-sync">
                          Synced {new Date(integration.last_sync_at).toLocaleDateString()}
                        </span>
                      {/if}
                    {:else}
                      <button
                        class="svc-btn svc-btn--connect"
                        onclick={() => integrationsStore.connect(integration.provider)}
                      >
                        Connect
                      </button>
                    {/if}
                    {#if integration.docs_url}
                      <a class="svc-docs-link" href={integration.docs_url} target="_blank" rel="noopener noreferrer" aria-label="View {integration.name} docs">
                        <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" width="12" height="12"><path d="M12 9v4H3V4h4"/><path d="M8 8L14 2"/><path d="M10 2h4v4"/></svg>
                        Docs
                      </a>
                    {/if}
                  </div>
                </div>
              {/each}
            </div>
          </div>
        {/each}
      {/if}
    {/if}
  {/if}
</PageShell>

<style>
  /* ─── Tabs ─────────────────────────────────────────────────────────────── */
  .int-tabs {
    display: flex; gap: 2px; padding: 0 24px;
    border-bottom: 1px solid var(--dbd, rgba(255,255,255,0.08));
    margin-bottom: 16px;
  }
  .int-tab {
    display: flex; align-items: center; gap: 6px;
    padding: 10px 16px; border: none; background: none;
    color: var(--dt3, #777); font-size: 13px; font-weight: 500;
    cursor: pointer; border-bottom: 2px solid transparent;
    transition: color 150ms, border-color 150ms;
  }
  .int-tab:hover { color: var(--dt2, #aaa); }
  .int-tab--active {
    color: var(--dt, #fff);
    border-bottom-color: #3b82f6;
  }
  .int-tab-count {
    font-size: 11px; padding: 1px 6px; border-radius: 10px;
    background: var(--dbg3, rgba(255,255,255,0.06)); color: var(--dt3, #777);
  }

  /* ─── Section Header ───────────────────────────────────────────────────── */
  .int-section-header {
    display: flex; align-items: center; justify-content: space-between;
    padding: 0 24px 12px; gap: 12px;
  }
  .int-section-desc { font-size: 13px; color: var(--dt3, #777); margin: 0; }
  .int-refresh {
    display: flex; align-items: center; gap: 4px;
    padding: 5px 10px; border-radius: 6px; border: 1px solid var(--dbd, rgba(255,255,255,0.08));
    background: transparent; color: var(--dt3, #777); font-size: 12px;
    cursor: pointer; transition: all 150ms;
  }
  .int-refresh:hover { background: var(--dbg2, rgba(255,255,255,0.04)); color: var(--dt2, #aaa); }

  /* ─── Toast ────────────────────────────────────────────────────────────── */
  .int-toast {
    display: flex; align-items: center; justify-content: space-between;
    padding: 8px 16px; margin: 0 24px 12px; border-radius: 8px;
    background: rgba(255, 255, 255, 0.05); border: 1px solid rgba(255, 255, 255, 0.1);
    font-size: 12px; color: var(--dt2, #aaa);
  }
  .int-toast button { background: none; border: none; color: inherit; cursor: pointer; padding: 2px; }

  /* ─── Adapter Grid ─────────────────────────────────────────────────────── */
  .adp-grid {
    display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
    gap: 12px; padding: 0 24px 24px;
  }
  .adp-card {
    padding: 16px; border-radius: 10px;
    background: var(--dbg2, #141414); border: 1px solid var(--dbd, rgba(255,255,255,0.06));
    transition: border-color 200ms;
  }
  .adp-card--running { border-color: rgba(59, 130, 246, 0.25); }
  .adp-card--installed { border-color: rgba(59, 130, 246, 0.2); }

  .adp-header { display: flex; align-items: center; gap: 8px; margin-bottom: 6px; }
  .adp-status-dot {
    width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0;
    background: var(--dt4, #555);
  }
  .adp-status-dot--running { background: #4ade80; box-shadow: 0 0 6px rgba(74, 222, 128, 0.4); }
  .adp-status-dot--installed { background: #3b82f6; }
  .adp-name { font-size: 14px; font-weight: 600; color: var(--dt, #fff); }
  .adp-version { font-size: 11px; color: var(--dt3, #777); margin-left: auto; }
  .adp-path { font-size: 11px; color: var(--dt4, #555); font-family: monospace; margin-bottom: 8px; }

  .adp-status-text { margin-bottom: 10px; }
  .adp-badge {
    font-size: 11px; padding: 2px 8px; border-radius: 4px; font-weight: 500;
  }
  .adp-badge--running { background: rgba(255, 255, 255, 0.08); color: rgba(255, 255, 255, 0.6); border: 1px solid rgba(255, 255, 255, 0.1); }
  .adp-badge--installed { background: rgba(59, 130, 246, 0.12); color: #93c5fd; }
  .adp-badge--missing { background: transparent; color: rgba(255, 255, 255, 0.35); }

  .adp-actions { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
  .adp-btn {
    padding: 5px 14px; border-radius: 9999px; font-size: 12px; font-weight: 500;
    cursor: pointer; border: none; transition: all 150ms;
    display: inline-flex; align-items: center; gap: 4px;
  }
  .adp-btn--primary {
    background: rgba(255, 255, 255, 0.08);
    color: rgba(255, 255, 255, 0.6);
    border: 1px solid rgba(255, 255, 255, 0.1);
  }
  .adp-btn--primary:hover {
    background: rgba(255, 255, 255, 0.12);
    color: rgba(255, 255, 255, 0.8);
  }
  .adp-btn--primary:disabled { opacity: 0.5; cursor: not-allowed; }
  .adp-btn--secondary {
    background: transparent; color: var(--dt2, #aaa);
    border: 1px solid var(--dbd, rgba(255,255,255,0.1));
  }
  .adp-btn--secondary:hover { background: var(--dbg3, rgba(255,255,255,0.04)); }
  .adp-hint { font-size: 11px; color: var(--dt4, #555); font-family: monospace; }
  .adp-hint--connected { color: rgba(255, 255, 255, 0.5); font-family: inherit; }

  /* ─── Provider Status ──────────────────────────────────────────────────── */
  .int-provider-status {
    display: flex; align-items: center; gap: 8px;
    padding: 10px 16px; margin: 0 24px 24px; border-radius: 8px;
    background: var(--dbg2, #141414); border: 1px solid var(--dbd, rgba(255,255,255,0.06));
    font-size: 12px; color: var(--dt3, #777);
  }
  .int-provider-status strong { color: var(--dt, #fff); }

  /* ─── Shared ───────────────────────────────────────────────────────────── */
  .int-loading, .int-empty, .int-error {
    display: flex; flex-direction: column; align-items: center;
    justify-content: center; gap: 12px; height: 200px;
    color: var(--dt3, #777); font-size: 13px;
  }
  .int-spinner {
    width: 24px; height: 24px; border-radius: 50%;
    border: 2px solid var(--dbd, rgba(255,255,255,0.1));
    border-top-color: var(--dt2, #aaa);
    animation: spin 0.8s linear infinite;
  }
  .int-spinner--sm { width: 14px; height: 14px; border-width: 1.5px; }
  @keyframes spin { to { transform: rotate(360deg); } }

  /* ─── Service Toolbar ──────────────────────────────────────────────────── */
  .svc-toolbar {
    display: flex; align-items: center; justify-content: space-between;
    gap: 12px; padding: 0 24px 12px;
  }
  .svc-search {
    display: flex; align-items: center; gap: 8px;
    padding: 6px 12px; border-radius: 8px;
    background: var(--dbg2, #141414); border: 1px solid var(--dbd, rgba(255,255,255,0.08));
    flex: 1; max-width: 320px;
    color: var(--dt3, #777);
  }
  .svc-search:focus-within { border-color: rgba(255,255,255,0.15); }
  .svc-search-input {
    background: none; border: none; outline: none; flex: 1; min-width: 0;
    font-size: 13px; color: var(--dt, #fff);
  }
  .svc-search-input::placeholder { color: var(--dt4, #555); }
  .svc-search-clear {
    background: none; border: none; cursor: pointer; padding: 2px;
    color: var(--dt4, #555); display: flex;
  }
  .svc-search-clear:hover { color: var(--dt2, #aaa); }
  .svc-summary { font-size: 12px; color: var(--dt3, #777); white-space: nowrap; }
  .svc-summary-count { font-weight: 600; color: var(--dt2, #aaa); }

  /* ─── Category Filter Pills ──────────────────────────────────────────── */
  .svc-filters {
    display: flex; gap: 6px; padding: 0 24px 16px;
    overflow-x: auto; flex-wrap: wrap;
  }
  .svc-pill {
    display: inline-flex; align-items: center; gap: 4px;
    padding: 4px 12px; border-radius: 9999px; border: 1px solid var(--dbd, rgba(255,255,255,0.08));
    background: transparent; color: var(--dt3, #777); font-size: 12px; font-weight: 500;
    cursor: pointer; transition: all 150ms; white-space: nowrap;
  }
  .svc-pill:hover { background: var(--dbg2, rgba(255,255,255,0.04)); color: var(--dt2, #aaa); }
  .svc-pill--active {
    background: rgba(255, 255, 255, 0.08); color: var(--dt, #fff);
    border-color: rgba(255, 255, 255, 0.15);
  }
  .svc-pill-count {
    font-size: 10px; padding: 0 5px; border-radius: 9999px;
    background: var(--dbg3, rgba(255,255,255,0.06)); color: var(--dt4, #555);
  }
  .svc-pill--active .svc-pill-count {
    background: rgba(255, 255, 255, 0.12); color: var(--dt2, #aaa);
  }

  /* ─── Category Groups ────────────────────────────────────────────────── */
  .svc-category { margin-bottom: 24px; }
  .svc-category-header {
    display: flex; align-items: center; justify-content: space-between;
    padding: 0 24px 10px; gap: 8px;
  }
  .svc-category-title {
    font-size: 13px; font-weight: 600; color: var(--dt2, #aaa);
    text-transform: uppercase; letter-spacing: 0.5px; margin: 0;
  }
  .svc-category-stat {
    font-size: 11px; color: var(--dt4, #555);
  }

  /* ─── Service Grid ───────────────────────────────────────────────────── */
  .svc-grid {
    display: grid; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
    gap: 12px; padding: 0 24px;
  }

  /* ─── Service Card ───────────────────────────────────────────────────── */
  .svc-card {
    display: flex; flex-direction: column; gap: 10px;
    padding: 16px; border-radius: 12px;
    background: var(--dbg2, #141414);
    border: 1px solid var(--dbd, rgba(255,255,255,0.06));
    transition: border-color 200ms, box-shadow 200ms;
  }
  .svc-card:hover { border-color: rgba(255, 255, 255, 0.1); }
  .svc-card--connected { border-color: rgba(255, 255, 255, 0.1); }
  .svc-card--error { border-color: rgba(239, 68, 68, 0.25); }

  .svc-card-top { display: flex; align-items: flex-start; justify-content: space-between; gap: 8px; }
  .svc-card-identity { display: flex; align-items: center; gap: 10px; }
  .svc-card-icon {
    width: 36px; height: 36px; border-radius: 8px; flex-shrink: 0;
    display: flex; align-items: center; justify-content: center;
    background: var(--dbg3, rgba(255,255,255,0.04));
    border: 1px solid var(--dbd, rgba(255,255,255,0.06));
    color: var(--dt3, #777); font-weight: 600; font-size: 15px;
  }
  .svc-card-icon--connected {
    background: rgba(255, 255, 255, 0.06);
    border-color: rgba(255, 255, 255, 0.1);
    color: var(--dt, #fff);
  }
  .svc-card-icon img { border-radius: 4px; }
  .svc-card-initial { line-height: 1; }
  .svc-card-meta { display: flex; flex-direction: column; gap: 1px; }
  .svc-card-name { font-size: 14px; font-weight: 600; color: var(--dt, #fff); }
  .svc-card-provider { font-size: 11px; color: var(--dt4, #555); text-transform: capitalize; }

  .svc-status {
    display: inline-flex; align-items: center; gap: 5px;
    font-size: 11px; padding: 3px 10px; border-radius: 9999px;
    white-space: nowrap; flex-shrink: 0; font-weight: 500;
  }
  .svc-status--connected {
    background: rgba(255, 255, 255, 0.06); color: rgba(255, 255, 255, 0.7);
    border: 1px solid rgba(255, 255, 255, 0.08);
  }
  .svc-status--disconnected {
    background: transparent; color: var(--dt4, #555);
    border: 1px solid var(--dbd, rgba(255,255,255,0.06));
  }
  .svc-status--error {
    background: rgba(239, 68, 68, 0.12); color: #fca5a5;
    border: 1px solid rgba(239, 68, 68, 0.2);
  }
  .svc-status-dot {
    width: 6px; height: 6px; border-radius: 50%;
  }
  .svc-status-dot--connected {
    background: #4ade80;
    box-shadow: 0 0 4px rgba(74, 222, 128, 0.4);
  }
  .svc-status-dot--error { background: #f87171; }

  .svc-card-desc {
    font-size: 12px; line-height: 1.55; color: var(--dt3, #777);
    margin: 0; display: -webkit-box; -webkit-line-clamp: 3;
    -webkit-box-orient: vertical; overflow: hidden;
  }

  .svc-card-features {
    display: flex; flex-wrap: wrap; gap: 4px;
  }
  .svc-feature-tag {
    font-size: 10px; padding: 2px 7px; border-radius: 4px;
    background: var(--dbg3, rgba(255,255,255,0.04));
    color: var(--dt3, #777);
    border: 1px solid var(--dbd, rgba(255,255,255,0.04));
  }

  .svc-card-footer {
    display: flex; align-items: center; gap: 8px;
    margin-top: auto; padding-top: 4px;
  }
  .svc-btn {
    padding: 5px 14px; border-radius: 9999px; font-size: 12px; font-weight: 500;
    cursor: pointer; border: none; transition: all 150ms;
  }
  .svc-btn--connect {
    background: rgba(255, 255, 255, 0.08); color: rgba(255, 255, 255, 0.6);
    border: 1px solid rgba(255, 255, 255, 0.1);
  }
  .svc-btn--connect:hover {
    background: rgba(255, 255, 255, 0.12); color: rgba(255, 255, 255, 0.8);
  }
  .svc-btn--disconnect {
    background: transparent; color: var(--dt3, #777);
    border: 1px solid var(--dbd, rgba(255,255,255,0.08));
  }
  .svc-btn--disconnect:hover {
    background: rgba(239, 68, 68, 0.08); color: #fca5a5;
    border-color: rgba(239, 68, 68, 0.2);
  }
  .svc-card-sync { font-size: 10px; color: var(--dt4, #555); }
  .svc-docs-link {
    display: inline-flex; align-items: center; gap: 3px;
    font-size: 11px; color: var(--dt4, #555); text-decoration: none;
    margin-left: auto; transition: color 150ms;
  }
  .svc-docs-link:hover { color: var(--dt2, #aaa); }

  /* ─── OSA Connected Banner ──────────────────────────────────────────────── */
  .osa-connected {
    display: flex; align-items: center; justify-content: space-between;
    padding: 12px 16px; margin: 0 24px 16px; border-radius: 10px;
    background: var(--dbg2, #141414);
    border: 1px solid rgba(255, 255, 255, 0.1);
  }
  .osa-connected-left { display: flex; align-items: center; gap: 8px; }
  .osa-dot {
    width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0;
    background: var(--dt4, #555);
  }
  .osa-dot--live {
    background: #4ade80;
    box-shadow: 0 0 6px rgba(74, 222, 128, 0.5);
    animation: osa-pulse 2s ease-in-out infinite;
  }
  @keyframes osa-pulse {
    0%, 100% { box-shadow: 0 0 6px rgba(74, 222, 128, 0.5); }
    50% { box-shadow: 0 0 12px rgba(74, 222, 128, 0.8); }
  }
  .osa-label { font-size: 13px; color: var(--dt, #fff); font-weight: 600; }
  .osa-ver { font-size: 12px; color: var(--dt3, #777); }
  .osa-port { font-size: 11px; color: var(--dt4, #555); font-family: monospace; }
  .osa-badge-running {
    font-size: 11px; padding: 2px 10px; border-radius: 9999px; font-weight: 500;
    background: rgba(255, 255, 255, 0.08); color: rgba(255, 255, 255, 0.6);
    border: 1px solid rgba(255, 255, 255, 0.1);
  }

  /* ─── OSA Setup Card ────────────────────────────────────────────────────── */
  .osa-setup {
    margin: 0 24px 16px; padding: 20px; border-radius: 12px;
    background: var(--dbg2, #141414);
    border: 1px solid rgba(255, 255, 255, 0.08);
    backdrop-filter: blur(8px);
  }
  .osa-setup-top { margin-bottom: 16px; }
  .osa-setup-title { font-size: 15px; color: var(--dt, #fff); display: block; margin-bottom: 4px; }
  .osa-setup-desc { font-size: 13px; color: var(--dt3, #777); margin: 0; }
  .osa-setup-actions { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
  .osa-hint { font-size: 12px; color: var(--dt4, #555); margin: 0; }
  .osa-hint code {
    font-size: 11px; padding: 2px 6px; border-radius: 4px;
    background: var(--dbg3, rgba(255,255,255,0.06)); color: var(--dt2, #aaa);
  }

  /* ─── OSA Setup Steps ───────────────────────────────────────────────────── */
  .osa-steps { display: flex; flex-direction: column; gap: 6px; margin-bottom: 16px; }
  .osa-step {
    display: flex; align-items: center; gap: 8px;
    font-size: 12px; color: var(--dt3, #777);
  }
  .osa-step-icon { font-size: 13px; width: 16px; text-align: center; flex-shrink: 0; }
  .osa-step--ok .osa-step-icon { color: #4ade80; }
  .osa-step--fail .osa-step-icon { color: #f87171; }
  .osa-step-label {
    font-weight: 600; text-transform: uppercase; font-size: 10px; letter-spacing: 0.5px;
    width: 48px; flex-shrink: 0; color: var(--dt4, #555);
  }
  .osa-step-msg { color: var(--dt2, #aaa); }
</style>
