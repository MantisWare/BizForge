<!-- src/routes/app/settings/tabs/IntegrationsSettings.svelte -->
<script lang="ts">
  import { onMount, tick } from 'svelte';
  import { integrationsStore } from '$lib/stores/integrations.svelte';
  import IntegrationConnectModal from '$lib/components/integrations/IntegrationConnectModal.svelte';

  interface Props {
    highlightProvider?: string | null;
  }

  let { highlightProvider = null }: Props = $props();

  interface ProviderDef {
    name: string;
    provider: string;
    desc: string;
    icon: string;
    category: string;
  }

  const PROVIDERS: ProviderDef[] = [
    { name: 'GitHub', provider: 'github', desc: 'Push commits, open PRs, manage issues.', icon: '⬡', category: 'version_control' },
    { name: 'Linear', provider: 'linear', desc: 'Sync issues and projects bidirectionally.', icon: '◈', category: 'project_management' },
    { name: 'Slack', provider: 'slack', desc: 'Send notifications and receive commands.', icon: '◎', category: 'communication' },
    { name: 'Notion', provider: 'notion', desc: 'Read and write documents and databases.', icon: '⬢', category: 'storage' },
    { name: 'Jira', provider: 'jira', desc: 'Sync issues from Atlassian Jira projects.', icon: '◇', category: 'project_management' },
    { name: 'Datadog', provider: 'datadog', desc: 'Ingest metrics and alert events.', icon: '⬡', category: 'monitoring' },
    { name: 'Domo', provider: 'domo', desc: 'Administer Domo instances, datasets, and apps.', icon: '◉', category: 'analytics' },
    { name: 'Confluence', provider: 'confluence', desc: 'Read and publish documentation pages.', icon: '◆', category: 'storage' },
    { name: 'GitLab', provider: 'gitlab', desc: 'Push code, manage pipelines and merge requests.', icon: '⬡', category: 'version_control' },
  ];

  let modalOpen = $state(false);
  let modalProvider = $state<ProviderDef | null>(null);
  let removingId = $state<string | null>(null);
  let togglingId = $state<string | null>(null);

  const configs = $derived(integrationsStore.integrations);

  const groupedConfigs = $derived.by(() => {
    const groups: Record<string, typeof configs> = {};
    for (const cfg of configs) {
      const provider = cfg.provider.toLowerCase();
      if (groups[provider] === undefined) {
        groups[provider] = [];
      }
      groups[provider].push(cfg);
    }
    return groups;
  });

  const hasAnyConfigs = $derived(configs.length > 0);

  let providerGridEl: HTMLElement | undefined = $state(undefined);
  let providerPickerActive = $state(false);

  onMount(async () => {
    void integrationsStore.fetchIntegrations();
    if (highlightProvider !== null && highlightProvider !== '') {
      await tick();
      const target = PROVIDERS.find(p => p.provider === highlightProvider);
      if (target !== undefined) {
        openAddModal(target);
      } else {
        activateProviderPicker();
      }
    }
  });

  function activateProviderPicker() {
    providerPickerActive = true;
    tick().then(() => {
      providerGridEl?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    });
  }

  function openAddModal(provider?: ProviderDef) {
    if (provider !== undefined) {
      providerPickerActive = false;
      modalProvider = provider;
      modalOpen = true;
    } else {
      activateProviderPicker();
    }
  }

  function closeModal() {
    modalOpen = false;
    modalProvider = null;
    providerPickerActive = false;
  }

  async function handleRemove(id: string, slug: string) {
    removingId = id;
    try {
      await integrationsStore.remove(slug);
    } finally {
      removingId = null;
    }
  }

  async function handleToggle(id: string, slug: string, currentStatus: string) {
    togglingId = id;
    try {
      await integrationsStore.toggleStatus(slug, currentStatus);
    } finally {
      togglingId = null;
    }
  }

  function handleConfigure(cfg: (typeof configs)[number]) {
    const provider = PROVIDERS.find(p => p.provider === cfg.provider.toLowerCase());
    if (provider !== undefined) {
      modalProvider = provider;
      modalOpen = true;
    }
  }

  function getProviderMeta(providerKey: string): ProviderDef | undefined {
    return PROVIDERS.find(p => p.provider === providerKey.toLowerCase());
  }
</script>

<section class="stg-section">
  <div class="stg-section-header">
    <div>
      <h2 class="stg-section-title">Integration Configurations</h2>
      <p class="stg-section-desc">
        Manage global service configurations. These are available for selection by any project, team, agent, or skill.
      </p>
    </div>
    <button class="stg-add-btn" onclick={() => openAddModal()}>
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
        <path d="M12 5v14M5 12h14" />
      </svg>
      Add Configuration
    </button>
  </div>

  {#if hasAnyConfigs}
    <div class="stg-configs-registry">
      {#each Object.entries(groupedConfigs) as [providerKey, providerConfigs] (providerKey)}
        {@const meta = getProviderMeta(providerKey)}
        <div class="stg-provider-group">
          <div class="stg-provider-header">
            <span class="stg-provider-icon" aria-hidden="true">{meta?.icon ?? '◌'}</span>
            <span class="stg-provider-name">{meta?.name ?? providerKey}</span>
            <span class="stg-provider-count">{providerConfigs.length} config{providerConfigs.length !== 1 ? 's' : ''}</span>
            <button
              class="stg-provider-add"
              onclick={() => { if (meta !== undefined) openAddModal(meta); }}
              aria-label="Add another {meta?.name ?? providerKey} configuration"
            >+</button>
          </div>
          <div class="stg-config-list">
            {#each providerConfigs as cfg (cfg.id)}
              <div class="stg-config-card" class:stg-config-card--connected={cfg.status === 'connected'}>
                <div class="stg-config-body">
                  <span class="stg-config-name">{cfg.name}</span>
                  <span class="stg-config-meta">{meta?.desc ?? ''}</span>
                </div>
                <div class="stg-config-toggle-area">
                  <button
                    class="stg-toggle"
                    class:stg-toggle--on={cfg.status === 'connected'}
                    class:stg-toggle--busy={togglingId === cfg.id}
                    disabled={togglingId === cfg.id}
                    onclick={() => handleToggle(cfg.id, cfg.slug ?? cfg.provider, cfg.status)}
                    aria-label="{cfg.status === 'connected' ? 'Disconnect' : 'Connect'} {cfg.name}"
                    role="switch"
                    aria-checked={cfg.status === 'connected'}
                  >
                    <span class="stg-toggle-track">
                      <span class="stg-toggle-thumb"></span>
                    </span>
                  </button>
                  <span class="stg-config-label">{cfg.status === 'connected' ? 'Connected' : 'Disconnected'}</span>
                </div>
                <div class="stg-config-actions">
                  <button
                    class="stg-config-btn stg-config-btn--configure"
                    onclick={() => handleConfigure(cfg)}
                  >Configure</button>
                  <button
                    class="stg-config-btn stg-config-btn--remove"
                    disabled={removingId === cfg.id}
                    onclick={() => handleRemove(cfg.id, cfg.slug ?? cfg.provider)}
                  >
                    {removingId === cfg.id ? 'Removing…' : 'Remove'}
                  </button>
                </div>
              </div>
            {/each}
          </div>
        </div>
      {/each}
    </div>
  {:else}
    <div class="stg-empty-state">
      <p class="stg-empty-text">No integration configurations yet.</p>
      <p class="stg-empty-hint">
        Add a configuration to connect agents to external services like Domo, Jira, GitHub, and more.
      </p>
    </div>
  {/if}

  <div
    class="stg-providers-grid"
    class:stg-providers-grid--active={providerPickerActive}
    bind:this={providerGridEl}
  >
    <h3 class="stg-providers-heading">
      {providerPickerActive ? 'Select a provider to configure' : 'Available Providers'}
    </h3>
    <div class="stg-providers-list">
      {#each PROVIDERS as provider (provider.provider)}
        {@const existingCount = groupedConfigs[provider.provider]?.length ?? 0}
        <button
          class="stg-provider-tile"
          onclick={() => openAddModal(provider)}
          aria-label="Add {provider.name} configuration"
        >
          <span class="stg-tile-icon" aria-hidden="true">{provider.icon}</span>
          <span class="stg-tile-name">{provider.name}</span>
          {#if existingCount > 0}
            <span class="stg-tile-badge">{existingCount}</span>
          {/if}
        </button>
      {/each}
    </div>
  </div>
</section>

<IntegrationConnectModal
  open={modalOpen}
  integration={modalProvider !== null ? { name: modalProvider.name, slug: modalProvider.provider, desc: modalProvider.desc, icon: modalProvider.icon, category: modalProvider.category } : null}
  onClose={closeModal}
/>

<style>
  .stg-section { max-width: 100%; }

  .stg-section-header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 16px;
    margin-bottom: 20px;
  }

  .stg-section-title {
    font-size: 15px;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0 0 4px;
  }

  .stg-section-desc {
    font-size: 13px;
    color: var(--text-secondary);
    margin: 0;
  }

  .stg-add-btn {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 7px 14px;
    font-size: 12px;
    font-weight: 500;
    color: #fff;
    background: var(--accent-primary, #3b82f6);
    border: none;
    border-radius: var(--radius-sm);
    cursor: pointer;
    flex-shrink: 0;
    transition: background 150ms ease;
  }

  .stg-add-btn:hover { background: #2563eb; }

  /* Provider groups */
  .stg-configs-registry {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(380px, 1fr));
    gap: 16px;
    margin-bottom: 24px;
  }

  .stg-provider-group {
    border: 1px solid var(--border-default);
    border-radius: var(--radius-md);
    overflow: hidden;
  }

  .stg-provider-header {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 10px 14px;
    background: var(--bg-elevated);
    border-bottom: 1px solid var(--border-default);
  }

  .stg-provider-icon {
    font-size: 14px;
    color: var(--text-secondary);
  }

  .stg-provider-name {
    font-size: 13px;
    font-weight: 600;
    color: var(--text-primary);
    flex: 1;
  }

  .stg-provider-count {
    font-size: 11px;
    color: var(--text-tertiary);
  }

  .stg-provider-add {
    width: 22px;
    height: 22px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 14px;
    font-weight: 600;
    color: var(--accent-primary);
    background: rgba(59, 130, 246, 0.08);
    border: 1px solid rgba(59, 130, 246, 0.2);
    border-radius: var(--radius-xs);
    cursor: pointer;
    transition: background 120ms ease;
  }

  .stg-provider-add:hover { background: rgba(59, 130, 246, 0.15); }

  .stg-config-list {
    display: flex;
    flex-direction: column;
  }

  .stg-config-card {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px 14px;
    border-bottom: 1px solid var(--border-default);
    transition: background 120ms ease;
  }

  .stg-config-card:last-child { border-bottom: none; }
  .stg-config-card:hover { background: var(--bg-surface); }
  .stg-config-card--connected { border-left: 3px solid rgba(74, 222, 128, 0.4); }

  .stg-config-body {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .stg-config-name {
    font-size: 13px;
    font-weight: 500;
    color: var(--text-primary);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .stg-config-meta {
    font-size: 11px;
    color: var(--text-tertiary);
  }

  .stg-config-toggle-area {
    display: flex;
    align-items: center;
    gap: 8px;
    flex-shrink: 0;
  }

  .stg-toggle {
    position: relative;
    padding: 0;
    border: none;
    background: none;
    cursor: pointer;
    flex-shrink: 0;
  }

  .stg-toggle:disabled { cursor: not-allowed; }

  .stg-toggle-track {
    display: block;
    width: 32px;
    height: 18px;
    border-radius: 9px;
    background: var(--text-muted, #555);
    transition: background 200ms ease;
    position: relative;
  }

  .stg-toggle--on .stg-toggle-track {
    background: var(--accent-success, #4ade80);
  }

  .stg-toggle-thumb {
    position: absolute;
    top: 2px;
    left: 2px;
    width: 14px;
    height: 14px;
    border-radius: 50%;
    background: #fff;
    transition: transform 200ms ease;
    box-shadow: 0 1px 2px rgba(0, 0, 0, 0.25);
  }

  .stg-toggle--on .stg-toggle-thumb {
    transform: translateX(14px);
  }

  .stg-toggle--busy .stg-toggle-track {
    opacity: 0.5;
  }

  .stg-config-label {
    font-size: 11px;
    color: var(--text-tertiary);
  }

  .stg-config-actions {
    display: flex;
    gap: 6px;
    flex-shrink: 0;
  }

  .stg-config-btn {
    padding: 4px 10px;
    font-size: 11px;
    font-weight: 500;
    border-radius: var(--radius-xs);
    cursor: pointer;
    border: 1px solid;
    transition: background 120ms ease, opacity 120ms ease;
  }

  .stg-config-btn:disabled { opacity: 0.5; cursor: not-allowed; }

  .stg-config-btn--configure {
    color: var(--text-secondary);
    background: var(--bg-elevated);
    border-color: var(--border-default);
  }

  .stg-config-btn--configure:hover:not(:disabled) {
    background: var(--bg-tertiary, rgba(255, 255, 255, 0.06));
  }

  .stg-config-btn--remove {
    color: var(--accent-error, #ef4444);
    background: rgba(239, 68, 68, 0.06);
    border-color: rgba(239, 68, 68, 0.15);
  }

  .stg-config-btn--remove:hover:not(:disabled) { background: rgba(239, 68, 68, 0.12); }

  /* Empty state */
  .stg-empty-state {
    text-align: center;
    padding: 32px 16px;
    margin-bottom: 24px;
    border: 1px dashed var(--border-default);
    border-radius: var(--radius-md);
  }

  .stg-empty-text {
    font-size: 13px;
    color: var(--text-secondary);
    margin: 0 0 4px;
  }

  .stg-empty-hint {
    font-size: 12px;
    color: var(--text-tertiary);
    margin: 0;
  }

  /* Available providers grid */
  .stg-providers-grid {
    margin-top: 24px;
  }

  .stg-providers-grid--active {
    padding: 16px;
    border: 2px solid var(--accent-primary, #3b82f6);
    border-radius: var(--radius-md, 8px);
    background: rgba(59, 130, 246, 0.03);
    animation: pulse-border 1.5s ease-in-out;
  }

  @keyframes pulse-border {
    0%, 100% { border-color: var(--accent-primary, #3b82f6); }
    50% { border-color: rgba(59, 130, 246, 0.4); }
  }

  .stg-providers-grid--active .stg-providers-heading {
    color: var(--accent-primary, #3b82f6);
  }

  .stg-providers-heading {
    font-size: 13px;
    font-weight: 600;
    color: var(--text-secondary);
    margin: 0 0 10px;
  }

  .stg-providers-list {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(100px, 1fr));
    gap: 8px;
  }

  .stg-provider-tile {
    position: relative;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 6px;
    padding: 14px 8px;
    background: var(--bg-surface);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-sm);
    cursor: pointer;
    transition: border-color 120ms ease, background 120ms ease;
  }

  .stg-provider-tile:hover {
    border-color: var(--accent-primary, #3b82f6);
    background: var(--bg-elevated);
  }

  .stg-tile-icon {
    font-size: 18px;
    color: var(--text-secondary);
  }

  .stg-tile-name {
    font-size: 11px;
    font-weight: 500;
    color: var(--text-primary);
    text-align: center;
  }

  .stg-tile-badge {
    position: absolute;
    top: 6px;
    right: 6px;
    min-width: 16px;
    height: 16px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 10px;
    font-weight: 600;
    color: #fff;
    background: var(--accent-primary, #3b82f6);
    border-radius: 8px;
    padding: 0 4px;
  }
</style>
