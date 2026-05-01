<!-- src/routes/app/settings/tabs/IntegrationsSettings.svelte -->
<script lang="ts">
  import { goto } from '$app/navigation';
  import { integrationsStore } from '$lib/stores/integrations.svelte';
  import IntegrationConnectModal from '$lib/components/integrations/IntegrationConnectModal.svelte';

  interface IntegrationDef {
    name: string;
    slug: string;
    desc: string;
    icon: string;
    category: string;
  }

  const INTEGRATIONS: IntegrationDef[] = [
    { name: 'GitHub',   slug: 'github',  desc: 'Push commits, open PRs, manage issues.',        icon: '⬡', category: 'version_control' },
    { name: 'Linear',   slug: 'linear',  desc: 'Sync issues and projects bidirectionally.',      icon: '◈', category: 'project_management' },
    { name: 'Slack',    slug: 'slack',   desc: 'Send notifications and receive commands.',       icon: '◎', category: 'communication' },
    { name: 'Notion',   slug: 'notion',  desc: 'Read and write documents and databases.',        icon: '⬢', category: 'storage' },
    { name: 'Jira',     slug: 'jira',    desc: 'Sync issues from Atlassian Jira projects.',     icon: '◇', category: 'project_management' },
    { name: 'Datadog',  slug: 'datadog', desc: 'Ingest metrics and alert events.',              icon: '⬡', category: 'monitoring' },
  ];

  let connectingSlug = $state<string | null>(null);
  let modalOpen = $state(false);
  let modalIntegration = $state<IntegrationDef | null>(null);

  function getStatus(slug: string): 'connected' | 'disconnected' | 'error' {
    const match = integrationsStore.integrations.find(
      (i) => i.provider.toLowerCase() === slug
    );
    if (match === undefined) return 'disconnected';
    return match.status;
  }

  function openConnectModal(integration: IntegrationDef) {
    modalIntegration = integration;
    modalOpen = true;
  }

  function closeModal() {
    modalOpen = false;
    modalIntegration = null;
  }

  async function handleDisconnect(slug: string) {
    connectingSlug = slug;
    try {
      await integrationsStore.disconnect(slug);
    } finally {
      connectingSlug = null;
    }
  }

  function handleConfigure(slug: string) {
    const int = INTEGRATIONS.find(i => i.slug === slug);
    if (int !== undefined) {
      modalIntegration = int;
      modalOpen = true;
    }
  }
</script>

<section class="stg-section">
  <h2 class="stg-section-title">Integrations</h2>
  <p class="stg-section-desc">Connect external services to extend agent capabilities.</p>

  <div class="stg-integration-list">
    {#each INTEGRATIONS as int (int.slug)}
      {@const status = getStatus(int.slug)}
      <div class="stg-int-card" class:stg-int-card--connected={status === 'connected'}>
        <div class="stg-int-icon" aria-hidden="true">{int.icon}</div>
        <div class="stg-int-body">
          <span class="stg-int-name">{int.name}</span>
          <span class="stg-int-desc">{int.desc}</span>
        </div>
        <div class="stg-int-status">
          <span class="stg-int-dot stg-int-dot--{status}"></span>
          <span class="stg-int-label">{status}</span>
        </div>
        {#if status === 'connected'}
          <button
            class="stg-int-btn stg-int-btn--configure"
            aria-label="Configure {int.name}"
            onclick={() => handleConfigure(int.slug)}
          >
            Configure
          </button>
          <button
            class="stg-int-btn stg-int-btn--disconnect"
            aria-label="Disconnect {int.name}"
            disabled={connectingSlug === int.slug}
            onclick={() => handleDisconnect(int.slug)}
          >
            {connectingSlug === int.slug ? 'Disconnecting…' : 'Disconnect'}
          </button>
        {:else}
          <button
            class="stg-int-btn"
            aria-label="Connect {int.name}"
            onclick={() => openConnectModal(int)}
          >
            Connect
          </button>
        {/if}
      </div>
    {/each}
  </div>

  <div class="stg-int-footer">
    <button class="stg-int-more" onclick={() => goto('/app/integrations')}>
      Manage all integrations →
    </button>
  </div>
</section>

<IntegrationConnectModal
  open={modalOpen}
  integration={modalIntegration}
  onClose={closeModal}
/>

<style>
  .stg-section { max-width: 640px; }

  .stg-section-title {
    font-size: 15px;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0 0 4px;
  }

  .stg-section-desc {
    font-size: 13px;
    color: var(--text-secondary);
    margin: 0 0 16px;
  }

  .stg-integration-list {
    display: flex;
    flex-direction: column;
    gap: 8px;
    margin-top: 16px;
  }

  .stg-int-card {
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 14px 16px;
    background: var(--bg-surface);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-md);
    transition: border-color var(--transition-fast);
  }

  .stg-int-card:hover { border-color: var(--border-hover); }
  .stg-int-card--connected { border-color: rgba(74, 222, 128, 0.2); }

  .stg-int-icon {
    font-size: 18px;
    width: 32px;
    height: 32px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-sm);
    flex-shrink: 0;
    color: var(--text-secondary);
  }

  .stg-int-body {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .stg-int-name {
    font-size: 13px;
    font-weight: 500;
    color: var(--text-primary);
  }

  .stg-int-desc {
    font-size: 12px;
    color: var(--text-tertiary);
  }

  .stg-int-status {
    display: flex;
    align-items: center;
    gap: 6px;
    flex-shrink: 0;
  }

  .stg-int-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    flex-shrink: 0;
  }

  .stg-int-dot--connected    { background: var(--accent-success, #4ade80); }
  .stg-int-dot--disconnected { background: var(--text-muted); }
  .stg-int-dot--error        { background: var(--accent-error, #ef4444); }

  .stg-int-label {
    font-size: 12px;
    color: var(--text-tertiary);
    text-transform: capitalize;
  }

  .stg-int-btn {
    padding: 5px 12px;
    font-size: 12px;
    font-weight: 500;
    color: var(--accent-primary);
    background: rgba(59, 130, 246, 0.08);
    border: 1px solid rgba(59, 130, 246, 0.2);
    border-radius: var(--radius-sm);
    cursor: pointer;
    flex-shrink: 0;
    transition: background var(--transition-fast), opacity var(--transition-fast);
  }

  .stg-int-btn:hover { background: rgba(59, 130, 246, 0.15); }
  .stg-int-btn:disabled { opacity: 0.5; cursor: not-allowed; }

  .stg-int-btn--configure {
    color: var(--text-secondary);
    background: var(--bg-elevated);
    border-color: var(--border-default);
  }

  .stg-int-btn--configure:hover {
    background: var(--bg-tertiary, rgba(255, 255, 255, 0.06));
    border-color: var(--border-hover);
  }

  .stg-int-btn--disconnect {
    color: var(--accent-error, #ef4444);
    background: rgba(239, 68, 68, 0.08);
    border-color: rgba(239, 68, 68, 0.2);
  }

  .stg-int-btn--disconnect:hover { background: rgba(239, 68, 68, 0.15); }

  .stg-int-footer {
    margin-top: 16px;
  }

  .stg-int-more {
    padding: 6px 0;
    font-size: 12px;
    font-weight: 500;
    color: var(--accent-primary);
    background: none;
    border: none;
    cursor: pointer;
    transition: opacity var(--transition-fast);
  }

  .stg-int-more:hover { opacity: 0.8; }
</style>
