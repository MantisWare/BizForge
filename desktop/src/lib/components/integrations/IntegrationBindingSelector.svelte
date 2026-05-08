<!-- src/lib/components/integrations/IntegrationBindingSelector.svelte -->
<script lang="ts">
  import { goto } from '$app/navigation';
  import { integrationsStore } from '$lib/stores/integrations.svelte';
  import type {
    IntegrationBinding,
    IntegrationBindingOwner,
    SkillIntegrationRequirement,
  } from '$lib/api/types';

  interface Props {
    ownerType: IntegrationBindingOwner;
    /** Identifies the owner entity. Reserved for future internal fetch support. */
    ownerId: string;
    requiredIntegrations: SkillIntegrationRequirement[];
    bindings?: IntegrationBinding[];
    onBind?: (provider: string, integrationId: string, overrides?: Record<string, unknown>) => void;
    onUnbind?: (provider: string) => void;
  }

  let {
    ownerType,
    ownerId,
    requiredIntegrations,
    bindings = [],
    onBind,
    onUnbind,
  }: Props = $props();

  const integrations = $derived(integrationsStore.integrations);

  function getConfigsForProvider(provider: string) {
    return integrations.filter(
      (i) => i.provider.toLowerCase() === provider.toLowerCase()
    );
  }

  function getBoundIntegration(provider: string): IntegrationBinding | undefined {
    return bindings.find((b) => b.provider.toLowerCase() === provider.toLowerCase());
  }

  function handleSelect(provider: string, event: Event) {
    const select = event.target as HTMLSelectElement;
    const integrationId = select.value;

    if (integrationId === '') {
      onUnbind?.(provider);
    } else {
      onBind?.(provider, integrationId);
    }
  }

  function goToSettings(provider: string) {
    goto(`/app/settings?tab=integrations&provider=${provider}`);
  }
</script>

<div class="ibs-container">
  <h4 class="ibs-heading">Service Access</h4>
  <p class="ibs-desc">
    Select which configurations this {ownerType} should use for external services.
  </p>

  {#if requiredIntegrations.length === 0}
    <div class="ibs-empty">
      <span class="ibs-empty-text">No integration requirements detected.</span>
    </div>
  {:else}
    <div class="ibs-list">
      {#each requiredIntegrations as req (req.provider)}
        {@const available = getConfigsForProvider(req.provider)}
        {@const bound = getBoundIntegration(req.provider)}
        {@const hasConfigs = available.length > 0}

        <div
          class="ibs-row"
          class:ibs-row--bound={bound !== undefined}
          class:ibs-row--missing={!hasConfigs && req.optional !== true}
        >
          <div class="ibs-row-header">
            <span class="ibs-provider-name">{req.provider}</span>
            {#if req.optional === true}
              <span class="ibs-optional-badge">optional</span>
            {:else}
              <span class="ibs-required-badge">required</span>
            {/if}
            {#if bound !== undefined}
              <span class="ibs-status-dot ibs-status-dot--{bound.integration_status}"></span>
            {/if}
          </div>

          {#if hasConfigs}
            <div class="ibs-selector-row">
              <select
                class="ibs-select"
                value={bound?.integration_id ?? ''}
                onchange={(e) => handleSelect(req.provider, e)}
                aria-label="Select {req.provider} configuration"
              >
                <option value="">— Select configuration —</option>
                {#each available as cfg (cfg.id)}
                  <option value={cfg.id}>
                    {cfg.name} ({cfg.status})
                  </option>
                {/each}
              </select>

              {#if bound?.inherited_from !== null && bound?.inherited_from !== undefined}
                <span class="ibs-inherited">
                  Inherited from {bound.inherited_from.owner_type}: {bound.inherited_from.owner_name}
                </span>
              {/if}
            </div>
          {:else}
            <div class="ibs-missing-row">
              <span class="ibs-missing-text">
                No {req.provider} configuration exists yet.
              </span>
              <button
                class="ibs-settings-link"
                onclick={() => goToSettings(req.provider)}
              >
                Go to Settings to create one →
              </button>
            </div>
          {/if}
        </div>
      {/each}
    </div>
  {/if}
</div>

<style>
  .ibs-container {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .ibs-heading {
    font-size: 13px;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0;
  }

  .ibs-desc {
    font-size: 12px;
    color: var(--text-tertiary);
    margin: 0;
  }

  .ibs-empty {
    padding: 16px;
    text-align: center;
    border: 1px dashed var(--border-default);
    border-radius: var(--radius-sm);
  }

  .ibs-empty-text {
    font-size: 12px;
    color: var(--text-muted);
  }

  .ibs-list {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .ibs-row {
    padding: 12px 14px;
    background: var(--bg-surface);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-sm);
    display: flex;
    flex-direction: column;
    gap: 8px;
    transition: border-color 120ms ease;
  }

  .ibs-row--bound {
    border-color: rgba(74, 222, 128, 0.3);
  }

  .ibs-row--missing {
    border-color: rgba(239, 68, 68, 0.3);
    background: rgba(239, 68, 68, 0.02);
  }

  .ibs-row-header {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .ibs-provider-name {
    font-size: 13px;
    font-weight: 500;
    color: var(--text-primary);
    text-transform: capitalize;
  }

  .ibs-required-badge {
    font-size: 10px;
    font-weight: 600;
    color: var(--accent-error, #ef4444);
    background: rgba(239, 68, 68, 0.08);
    border: 1px solid rgba(239, 68, 68, 0.2);
    border-radius: 4px;
    padding: 1px 5px;
    text-transform: uppercase;
    letter-spacing: 0.3px;
  }

  .ibs-optional-badge {
    font-size: 10px;
    font-weight: 500;
    color: var(--text-tertiary);
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    border-radius: 4px;
    padding: 1px 5px;
    text-transform: uppercase;
    letter-spacing: 0.3px;
  }

  .ibs-status-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    margin-left: auto;
  }

  .ibs-status-dot--connected { background: var(--accent-success, #4ade80); }
  .ibs-status-dot--disconnected { background: var(--text-muted); }
  .ibs-status-dot--error { background: var(--accent-error, #ef4444); }

  .ibs-selector-row {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .ibs-select {
    width: 100%;
    padding: 7px 10px;
    font-size: 12px;
    color: var(--text-primary);
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-xs);
    outline: none;
    cursor: pointer;
    transition: border-color 120ms ease;
    appearance: auto;
  }

  .ibs-select:focus {
    border-color: var(--accent-primary, #3b82f6);
  }

  .ibs-inherited {
    font-size: 11px;
    color: var(--text-muted);
    font-style: italic;
  }

  .ibs-missing-row {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .ibs-missing-text {
    font-size: 12px;
    color: var(--text-tertiary);
  }

  .ibs-settings-link {
    display: inline-flex;
    align-items: center;
    padding: 0;
    font-size: 12px;
    font-weight: 500;
    color: var(--accent-primary, #3b82f6);
    background: none;
    border: none;
    cursor: pointer;
    text-decoration: none;
    transition: opacity 120ms ease;
  }

  .ibs-settings-link:hover {
    opacity: 0.8;
    text-decoration: underline;
  }
</style>
