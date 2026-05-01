<!-- src/lib/components/agents/hire/AgentAdapterPicker.svelte -->
<script lang="ts">
  import type { AdapterType } from '$api/types';
  import { ADAPTER_REGISTRY } from '$lib/constants/adapters';
  import AdapterInfoPopover from '$lib/components/shared/AdapterInfoPopover.svelte';

  interface Props {
    adapter: AdapterType;
    onAdapter: (v: AdapterType) => void;
  }

  let { adapter, onAdapter }: Props = $props();

  const PICKER_IDS: AdapterType[] = [
    'osa', 'claude_code', 'codex', 'openclaw', 'jidoclaw', 'hermes', 'bash', 'http', 'custom',
  ];

  const ADAPTERS = PICKER_IDS.map((id) => {
    const def = ADAPTER_REGISTRY.find(
      (a) => a.id === id || a.id.replace(/-/g, '_') === id,
    );
    return {
      value: id,
      label: def?.name ?? id,
      description: def?.description ?? '',
    };
  });
</script>

<section class="hap-section">
  <h3 class="hap-section-title">
    Adapter
    <span class="hap-info" title="The execution runtime that runs the agent on your system. The Provider gives the brain (LLM), the Adapter gives the body (how it actually executes tasks, writes files, runs commands).">
      <svg class="hap-info-icon" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
        <path d="M8 1a7 7 0 1 0 0 14A7 7 0 0 0 8 1Zm0 12.5a5.5 5.5 0 1 1 0-11 5.5 5.5 0 0 1 0 11ZM8 5a.75.75 0 1 1 0-1.5A.75.75 0 0 1 8 5Zm-1 2.25a.25.25 0 0 1 .25-.25h.5a.75.75 0 0 1 .75.75V11a.25.25 0 0 1-.25.25h-.5A.75.75 0 0 1 7 10.5V7.25Z"/>
      </svg>
    </span>
  </h3>
  <div class="hap-grid" role="radiogroup" aria-label="Select adapter">
    {#each ADAPTERS as a}
      <label
        class="hap-card"
        class:hap-card--selected={adapter === a.value}
        aria-label="{a.label}: {a.description}"
      >
        <input
          type="radio"
          name="adapter"
          value={a.value}
          checked={adapter === a.value}
          onchange={() => onAdapter(a.value)}
          class="hap-radio-hidden"
          aria-label={a.label}
        />
        <span class="hap-name-row">
          <span class="hap-name">{a.label}</span>
          <AdapterInfoPopover adapterId={a.value} anchor="below" />
        </span>
        <span class="hap-desc">{a.description}</span>
      </label>
    {/each}
  </div>
</section>

<style>
  .hap-section {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .hap-section-title {
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

  .hap-info {
    display: inline-flex;
    align-items: center;
    cursor: help;
  }

  .hap-info-icon {
    width: 13px;
    height: 13px;
    color: var(--text-muted);
    opacity: 0.6;
    transition: opacity 150ms ease, color 150ms ease;
  }

  .hap-info:hover .hap-info-icon {
    opacity: 1;
    color: var(--accent-primary);
  }

  .hap-grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 8px;
  }

  .hap-card {
    display: flex;
    flex-direction: column;
    gap: 3px;
    padding: 10px;
    border-radius: var(--radius-sm);
    border: 1px solid var(--border-default);
    background: var(--bg-surface);
    cursor: pointer;
    transition: all 120ms ease;
  }

  .hap-card:hover {
    border-color: var(--border-hover);
    background: var(--bg-elevated);
  }

  .hap-card--selected {
    border-color: rgba(59, 130, 246, 0.5);
    background: rgba(59, 130, 246, 0.1);
  }

  .hap-radio-hidden {
    position: absolute;
    opacity: 0;
    width: 0;
    height: 0;
  }

  .hap-name-row {
    display: flex;
    align-items: center;
    gap: 4px;
  }

  .hap-name {
    font-size: 12px;
    font-weight: 600;
    color: var(--text-primary);
  }

  .hap-desc {
    font-size: 10px;
    color: var(--text-muted);
    line-height: 1.3;
  }
</style>
