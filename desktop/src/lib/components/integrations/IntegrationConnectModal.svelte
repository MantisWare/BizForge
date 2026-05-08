<!-- src/lib/components/integrations/IntegrationConnectModal.svelte -->
<script lang="ts">
  import { integrationsStore } from '$lib/stores/integrations.svelte';
  import { toastStore } from '$lib/stores/toasts.svelte';

  interface IntegrationDef {
    name: string;
    slug: string;
    desc: string;
    icon: string;
    category: string;
  }

  interface ConfigField {
    key: string;
    label: string;
    type: 'text' | 'password' | 'url';
    placeholder: string;
    required: boolean;
    is_secret?: boolean;
    help?: string;
  }

  interface Props {
    open: boolean;
    integration: IntegrationDef | null;
    onClose: () => void;
  }

  let { open, integration, onClose }: Props = $props();

  let configName = $state('');
  let configValues = $state<Record<string, string>>({});
  let connecting = $state(false);
  let validationErrors = $state<Record<string, string>>({});

  const INTEGRATION_FIELDS: Record<string, ConfigField[]> = {
    github: [
      { key: 'access_token', label: 'Personal Access Token', type: 'password', placeholder: 'ghp_xxxxxxxxxxxx', required: true, is_secret: true, help: 'Generate from GitHub Settings → Developer settings → Personal access tokens' },
      { key: 'organization', label: 'Organization (optional)', type: 'text', placeholder: 'my-org', required: false, help: 'Leave blank to use personal repositories' },
      { key: 'webhook_url', label: 'Webhook URL (optional)', type: 'url', placeholder: 'https://your-server.com/webhooks/github', required: false },
    ],
    linear: [
      { key: 'api_key', label: 'API Key', type: 'password', placeholder: 'lin_api_xxxxxxxxxxxx', required: true, is_secret: true, help: 'Generate from Linear Settings → API → Personal API keys' },
      { key: 'team_id', label: 'Team ID (optional)', type: 'text', placeholder: 'TEAM-123', required: false, help: 'Restrict sync to a specific team' },
    ],
    slack: [
      { key: 'bot_token', label: 'Bot Token', type: 'password', placeholder: 'xoxb-xxxxxxxxxxxx', required: true, is_secret: true, help: 'From your Slack App → OAuth & Permissions → Bot User OAuth Token' },
      { key: 'signing_secret', label: 'Signing Secret', type: 'password', placeholder: 'xxxxxxxxxxxxxxxx', required: true, is_secret: true, help: 'From your Slack App → Basic Information → App Credentials' },
      { key: 'default_channel', label: 'Default Channel', type: 'text', placeholder: '#general', required: false, help: 'Channel for notifications when no specific routing is configured' },
    ],
    notion: [
      { key: 'api_key', label: 'Integration Token', type: 'password', placeholder: 'secret_xxxxxxxxxxxx', required: true, is_secret: true, help: 'Create an integration at notion.so/my-integrations' },
      { key: 'root_page_id', label: 'Root Page ID (optional)', type: 'text', placeholder: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx', required: false, help: 'Limit access to a specific page and its children' },
    ],
    jira: [
      { key: 'domain', label: 'Jira Domain', type: 'url', placeholder: 'https://your-team.atlassian.net', required: true },
      { key: 'email', label: 'Email', type: 'text', placeholder: 'you@company.com', required: true },
      { key: 'api_token', label: 'API Token', type: 'password', placeholder: 'xxxxxxxxxxxx', required: true, is_secret: true, help: 'Generate from id.atlassian.com/manage-profile/security/api-tokens' },
      { key: 'project_key', label: 'Default Project Key (optional)', type: 'text', placeholder: 'PROJ', required: false },
    ],
    datadog: [
      { key: 'api_key', label: 'API Key', type: 'password', placeholder: 'xxxxxxxxxxxx', required: true, is_secret: true, help: 'From Datadog → Organization Settings → API Keys' },
      { key: 'app_key', label: 'Application Key', type: 'password', placeholder: 'xxxxxxxxxxxx', required: true, is_secret: true, help: 'From Datadog → Organization Settings → Application Keys' },
      { key: 'site', label: 'Datadog Site', type: 'text', placeholder: 'datadoghq.com', required: false, help: 'e.g. datadoghq.eu for EU region' },
    ],
    domo: [
      { key: 'instance_url', label: 'Instance URL', type: 'url', placeholder: 'https://company.domo.com', required: true, help: 'Your Domo instance URL (e.g. https://acme.domo.com)' },
      { key: 'client_id', label: 'OAuth Client ID', type: 'password', placeholder: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx', required: true, is_secret: true, help: 'From Admin → Security → OAuth → Create client' },
      { key: 'client_secret', label: 'OAuth Client Secret', type: 'password', placeholder: 'xxxxxxxxxxxxxxxxxxxxxxxxxxxx', required: true, is_secret: true, help: 'Generated with your OAuth client' },
      { key: 'developer_token', label: 'Developer Token (optional)', type: 'password', placeholder: 'xxxxxxxxxxxx', required: false, is_secret: true, help: 'Full-admin token from Admin → Security → Access Tokens. Use only when full access is needed.' },
      { key: 'scopes', label: 'OAuth Scopes', type: 'text', placeholder: 'data user dashboard account audit', required: false, help: 'Space-separated scopes. Defaults to all if blank.' },
    ],
    confluence: [
      { key: 'domain', label: 'Confluence Domain', type: 'url', placeholder: 'https://your-team.atlassian.net/wiki', required: true },
      { key: 'email', label: 'Email', type: 'text', placeholder: 'you@company.com', required: true },
      { key: 'api_token', label: 'API Token', type: 'password', placeholder: 'xxxxxxxxxxxx', required: true, is_secret: true },
      { key: 'space_key', label: 'Space Key (optional)', type: 'text', placeholder: 'ENG', required: false },
    ],
    gitlab: [
      { key: 'access_token', label: 'Personal Access Token', type: 'password', placeholder: 'glpat-xxxxxxxxxxxx', required: true, is_secret: true, help: 'Generate from GitLab → User Settings → Access Tokens' },
      { key: 'base_url', label: 'GitLab URL', type: 'url', placeholder: 'https://gitlab.com', required: false, help: 'Leave blank for gitlab.com, or enter your self-hosted URL' },
      { key: 'group_id', label: 'Group ID (optional)', type: 'text', placeholder: '12345', required: false },
    ],
  };

  const fields = $derived<ConfigField[]>(
    integration !== null ? (INTEGRATION_FIELDS[integration.slug] ?? []) : []
  );

  $effect(() => {
    if (open && integration !== null) {
      configName = '';
      configValues = {};
      validationErrors = {};
      connecting = false;
    }
  });

  function validate(): boolean {
    const errors: Record<string, string> = {};

    if (configName.trim() === '') {
      errors['_name'] = 'Configuration name is required';
    }

    for (const field of fields) {
      if (field.required && (configValues[field.key] ?? '').trim() === '') {
        errors[field.key] = `${field.label} is required`;
      }
    }

    validationErrors = errors;
    return Object.keys(errors).length === 0;
  }

  async function handleConnect() {
    if (integration === null) return;
    if (!validate()) return;

    connecting = true;
    try {
      const config: Record<string, unknown> = {};
      for (const field of fields) {
        const val = (configValues[field.key] ?? '').trim();
        if (val !== '') {
          config[field.key] = val;
        }
      }

      const slug = `${integration.slug}-${configName.trim().toLowerCase().replace(/[^a-z0-9]+/g, '-')}`;
      await integrationsStore.connect(slug, { ...config, _name: configName.trim(), _provider: integration.slug });
      onClose();
    } catch (e) {
      toastStore.error('Connection failed', (e as Error).message);
    } finally {
      connecting = false;
    }
  }

  function handleBackdrop(e: MouseEvent) {
    if ((e.target as HTMLElement).classList.contains('icm-overlay')) onClose();
  }

  function handleWindowKeyDown(e: KeyboardEvent) {
    if (open && e.key === 'Escape') onClose();
  }
</script>

<svelte:window onkeydown={handleWindowKeyDown} />

{#if open && integration !== null}
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    class="icm-overlay"
    onclick={handleBackdrop}
    role="dialog"
    aria-modal="true"
    aria-label="Add {integration.name} Configuration"
  >
    <div class="icm-modal">
      <header class="icm-header">
        <div class="icm-header-left">
          <span class="icm-header-icon" aria-hidden="true">{integration.icon}</span>
          <div class="icm-header-text">
            <h2 class="icm-title">Add {integration.name} Configuration</h2>
            <p class="icm-subtitle">{integration.desc}</p>
          </div>
        </div>
        <button class="icm-close" onclick={onClose} aria-label="Close dialog">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <path d="M18 6 6 18M6 6l12 12" />
          </svg>
        </button>
      </header>

      <div class="icm-body">
        <form class="icm-form" onsubmit={(e) => { e.preventDefault(); handleConnect(); }}>
          <div class="icm-field icm-field--name" class:icm-field--error={validationErrors['_name'] !== undefined}>
            <label class="icm-label" for="icm-config-name">
              Configuration Name
              <span class="icm-required" aria-label="required">*</span>
            </label>
            <input
              id="icm-config-name"
              class="icm-input icm-input--name"
              type="text"
              placeholder="e.g. Acme Corp {integration.name}"
              value={configName}
              oninput={(e) => {
                configName = (e.target as HTMLInputElement).value;
                if (validationErrors['_name'] !== undefined) {
                  const { '_name': _, ...rest } = validationErrors;
                  validationErrors = rest;
                }
              }}
              autocomplete="off"
            />
            {#if validationErrors['_name'] !== undefined}
              <span class="icm-error-msg">{validationErrors['_name']}</span>
            {:else}
              <span class="icm-help">A unique label for this configuration (e.g. client name or environment).</span>
            {/if}
          </div>

          {#if fields.length > 0}
            <div class="icm-divider"></div>
            {#each fields as field (field.key)}
              <div class="icm-field" class:icm-field--error={validationErrors[field.key] !== undefined}>
                <label class="icm-label" for="icm-{field.key}">
                  {field.label}
                  {#if field.required}
                    <span class="icm-required" aria-label="required">*</span>
                  {/if}
                  {#if field.is_secret === true}
                    <span class="icm-secret-badge" title="Stored securely in vault">🔒</span>
                  {/if}
                </label>
                <input
                  id="icm-{field.key}"
                  class="icm-input"
                  type={field.type}
                  placeholder={field.placeholder}
                  value={configValues[field.key] ?? ''}
                  oninput={(e) => {
                    configValues[field.key] = (e.target as HTMLInputElement).value;
                    if (validationErrors[field.key] !== undefined) {
                      const { [field.key]: _, ...rest } = validationErrors;
                      validationErrors = rest;
                    }
                  }}
                  autocomplete="off"
                />
                {#if validationErrors[field.key] !== undefined}
                  <span class="icm-error-msg">{validationErrors[field.key]}</span>
                {:else if field.help !== undefined}
                  <span class="icm-help">{field.help}</span>
                {/if}
              </div>
            {/each}
          {:else}
            <p class="icm-no-config">This integration has no additional configuration fields.</p>
          {/if}
        </form>
      </div>

      <footer class="icm-footer">
        <button class="icm-btn icm-btn--cancel" onclick={onClose} disabled={connecting}>
          Cancel
        </button>
        <button class="icm-btn icm-btn--connect" onclick={handleConnect} disabled={connecting}>
          {#if connecting}
            <span class="icm-spinner"></span>
            Saving…
          {:else}
            Save Configuration
          {/if}
        </button>
      </footer>
    </div>
  </div>
{/if}

<style>
  .icm-overlay {
    position: fixed;
    inset: 0;
    z-index: 9999;
    display: flex;
    align-items: center;
    justify-content: center;
    background: rgba(0, 0, 0, 0.6);
    backdrop-filter: blur(4px);
    padding: 24px;
    animation: icm-fade-in 150ms ease;
  }

  @keyframes icm-fade-in {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  .icm-modal {
    width: 100%;
    max-width: 520px;
    max-height: 85vh;
    display: flex;
    flex-direction: column;
    background: var(--bg-primary);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-lg, 12px);
    box-shadow: 0 24px 48px rgba(0, 0, 0, 0.4);
    animation: icm-slide-up 200ms ease;
  }

  @keyframes icm-slide-up {
    from { transform: translateY(12px); opacity: 0; }
    to { transform: translateY(0); opacity: 1; }
  }

  .icm-header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 12px;
    padding: 20px 20px 16px;
    border-bottom: 1px solid var(--border-default);
  }

  .icm-header-left {
    display: flex;
    align-items: flex-start;
    gap: 12px;
    min-width: 0;
  }

  .icm-header-icon {
    width: 36px;
    height: 36px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 18px;
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-sm);
    flex-shrink: 0;
    color: var(--text-secondary);
  }

  .icm-header-text {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }

  .icm-title {
    font-size: 15px;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0;
  }

  .icm-subtitle {
    font-size: 12px;
    color: var(--text-tertiary);
    margin: 0;
    line-height: 1.4;
  }

  .icm-close {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 28px;
    height: 28px;
    border: none;
    background: transparent;
    color: var(--text-tertiary);
    cursor: pointer;
    border-radius: var(--radius-xs);
    flex-shrink: 0;
    transition: background 120ms ease, color 120ms ease;
  }

  .icm-close:hover {
    background: var(--bg-elevated);
    color: var(--text-primary);
  }

  .icm-body {
    flex: 1;
    overflow-y: auto;
    padding: 20px;
  }

  .icm-no-config {
    font-size: 13px;
    color: var(--text-secondary);
    margin: 0;
    text-align: center;
    padding: 20px 0;
  }

  .icm-form {
    display: flex;
    flex-direction: column;
    gap: 16px;
  }

  .icm-divider {
    height: 1px;
    background: var(--border-default);
    margin: 4px 0;
  }

  .icm-field {
    display: flex;
    flex-direction: column;
    gap: 5px;
  }

  .icm-field--name {
    padding-bottom: 4px;
  }

  .icm-label {
    font-size: 13px;
    font-weight: 500;
    color: var(--text-primary);
    display: flex;
    align-items: center;
    gap: 4px;
  }

  .icm-required {
    color: var(--accent-error, #ef4444);
    font-size: 14px;
  }

  .icm-secret-badge {
    font-size: 11px;
    margin-left: 2px;
  }

  .icm-input {
    width: 100%;
    padding: 8px 12px;
    font-size: 13px;
    font-family: var(--font-mono, monospace);
    color: var(--text-primary);
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-sm);
    outline: none;
    transition: border-color 150ms ease;
  }

  .icm-input--name {
    font-family: var(--font-sans, inherit);
    font-weight: 500;
  }

  .icm-input:focus {
    border-color: var(--accent-primary, #3b82f6);
  }

  .icm-input::placeholder {
    color: var(--text-muted);
    font-family: var(--font-mono, monospace);
  }

  .icm-input--name::placeholder {
    font-family: var(--font-sans, inherit);
    font-weight: 400;
  }

  .icm-field--error .icm-input {
    border-color: var(--accent-error, #ef4444);
  }

  .icm-help {
    font-size: 11px;
    color: var(--text-muted);
    line-height: 1.4;
  }

  .icm-error-msg {
    font-size: 11px;
    color: var(--accent-error, #ef4444);
  }

  .icm-footer {
    display: flex;
    align-items: center;
    justify-content: flex-end;
    gap: 8px;
    padding: 16px 20px;
    border-top: 1px solid var(--border-default);
  }

  .icm-btn {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 7px 16px;
    font-size: 13px;
    font-weight: 500;
    border-radius: var(--radius-sm);
    cursor: pointer;
    border: 1px solid;
    transition: background 150ms ease, border-color 150ms ease, opacity 150ms ease;
  }

  .icm-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .icm-btn--cancel {
    color: var(--text-secondary);
    background: var(--bg-elevated);
    border-color: var(--border-default);
  }

  .icm-btn--cancel:hover:not(:disabled) {
    background: var(--bg-tertiary, rgba(255, 255, 255, 0.06));
    border-color: var(--border-hover);
  }

  .icm-btn--connect {
    color: #fff;
    background: var(--accent-primary, #3b82f6);
    border-color: var(--accent-primary, #3b82f6);
  }

  .icm-btn--connect:hover:not(:disabled) {
    background: #2563eb;
    border-color: #2563eb;
  }

  .icm-spinner {
    width: 14px;
    height: 14px;
    border-radius: 50%;
    border: 2px solid rgba(255, 255, 255, 0.3);
    border-top-color: #fff;
    animation: icm-spin 0.6s linear infinite;
  }

  @keyframes icm-spin {
    to { transform: rotate(360deg); }
  }
</style>
