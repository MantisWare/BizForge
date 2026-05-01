<!-- src/lib/components/shared/AdapterInfoPopover.svelte
     Floating info card showing adapter capabilities, session/concurrent support, and install hint. -->
<script lang="ts">
  import { getAdapter, type AdapterDef } from '$lib/constants/adapters';

  interface Props {
    adapterId: string;
    anchor?: 'above' | 'below';
  }

  let { adapterId, anchor = 'above' }: Props = $props();

  let visible = $state(false);
  let wrapperEl = $state<HTMLElement | null>(null);

  const def: AdapterDef | undefined = $derived(getAdapter(adapterId));

  function toggle(e: MouseEvent) {
    e.stopPropagation();
    visible = !visible;
  }

  function handleClickOutside(e: MouseEvent) {
    if (wrapperEl !== null && !wrapperEl.contains(e.target as Node)) {
      visible = false;
    }
  }

  $effect(() => {
    if (visible) {
      document.addEventListener('click', handleClickOutside, true);
      return () => document.removeEventListener('click', handleClickOutside, true);
    }
  });
</script>

<span class="aip-wrap" bind:this={wrapperEl}>
  <button
    class="aip-trigger"
    onclick={toggle}
    aria-label="Adapter info"
    title="View adapter details"
  >
    <svg class="aip-icon" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true" width="13" height="13">
      <path d="M8 1a7 7 0 1 0 0 14A7 7 0 0 0 8 1Zm0 12.5a5.5 5.5 0 1 1 0-11 5.5 5.5 0 0 1 0 11ZM8 5a.75.75 0 1 1 0-1.5A.75.75 0 0 1 8 5Zm-1 2.25a.25.25 0 0 1 .25-.25h.5a.75.75 0 0 1 .75.75V11a.25.25 0 0 1-.25.25h-.5A.75.75 0 0 1 7 10.5V7.25Z"/>
    </svg>
  </button>

  {#if visible && def !== undefined}
    <div class="aip-card" class:aip-card--above={anchor === 'above'} class:aip-card--below={anchor === 'below'}>
      <div class="aip-header">
        <span class="aip-name">{def.name}</span>
        <div class="aip-flags">
          <span class="aip-flag" class:aip-flag--yes={def.supportsSession} title="Session support">
            {def.supportsSession ? 'Sessions' : 'No Sessions'}
          </span>
          <span class="aip-flag" class:aip-flag--yes={def.supportsConcurrent} title="Concurrent execution">
            {def.supportsConcurrent ? 'Concurrent' : 'Sequential'}
          </span>
        </div>
      </div>

      <p class="aip-benefits">{def.benefits}</p>

      {#if def.capabilities.length > 0}
        <div class="aip-caps">
          {#each def.capabilities as c}
            <span class="aip-cap-badge">{c.label}</span>
          {/each}
        </div>
      {/if}

      <div class="aip-install">
        <span class="aip-install-label">Install:</span>
        <code class="aip-install-code">{def.installHint}</code>
      </div>
    </div>
  {/if}
</span>

<style>
  .aip-wrap {
    position: relative;
    display: inline-flex;
    align-items: center;
  }

  .aip-trigger {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    padding: 0;
    border: none;
    background: none;
    cursor: help;
    color: rgba(255, 255, 255, 0.3);
    transition: color 150ms ease;
    flex-shrink: 0;
  }

  .aip-trigger:hover {
    color: rgba(255, 255, 255, 0.7);
  }

  .aip-icon {
    pointer-events: none;
  }

  .aip-card {
    position: absolute;
    z-index: 1000;
    left: 50%;
    transform: translateX(-50%);
    width: 260px;
    padding: 10px 12px;
    border-radius: 8px;
    background: rgba(22, 27, 34, 0.98);
    border: 1px solid rgba(255, 255, 255, 0.1);
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.4);
    display: flex;
    flex-direction: column;
    gap: 8px;
    backdrop-filter: blur(12px);
  }

  .aip-card--above {
    bottom: calc(100% + 6px);
  }

  .aip-card--below {
    top: calc(100% + 6px);
  }

  .aip-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 6px;
  }

  .aip-name {
    font-size: 12px;
    font-weight: 600;
    color: #e0e0e0;
  }

  .aip-flags {
    display: flex;
    gap: 4px;
  }

  .aip-flag {
    font-size: 9px;
    font-weight: 500;
    padding: 1px 5px;
    border-radius: 3px;
    background: rgba(239, 68, 68, 0.12);
    color: rgba(239, 68, 68, 0.7);
    border: 1px solid rgba(239, 68, 68, 0.2);
    white-space: nowrap;
  }

  .aip-flag--yes {
    background: rgba(34, 197, 94, 0.12);
    color: rgba(34, 197, 94, 0.8);
    border-color: rgba(34, 197, 94, 0.2);
  }

  .aip-benefits {
    font-size: 11px;
    color: rgba(255, 255, 255, 0.55);
    margin: 0;
    line-height: 1.45;
  }

  .aip-caps {
    display: flex;
    flex-wrap: wrap;
    gap: 3px;
  }

  .aip-cap-badge {
    font-size: 9px;
    font-weight: 500;
    padding: 1px 5px;
    border-radius: 3px;
    background: rgba(59, 130, 246, 0.1);
    color: rgba(59, 130, 246, 0.7);
    border: 1px solid rgba(59, 130, 246, 0.15);
    white-space: nowrap;
  }

  .aip-install {
    display: flex;
    align-items: baseline;
    gap: 4px;
    padding-top: 4px;
    border-top: 1px solid rgba(255, 255, 255, 0.06);
  }

  .aip-install-label {
    font-size: 9px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    color: rgba(255, 255, 255, 0.35);
    flex-shrink: 0;
  }

  .aip-install-code {
    font-size: 9.5px;
    color: rgba(255, 255, 255, 0.5);
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    word-break: break-all;
  }
</style>
