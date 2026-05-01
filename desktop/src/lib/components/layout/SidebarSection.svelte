<!-- src/lib/components/layout/SidebarSection.svelte -->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import { slide } from 'svelte/transition';

  interface Props {
    label: string;
    badge?: number;
    defaultOpen?: boolean;
    description?: string;
    children: Snippet;
  }

  let { label, badge, defaultOpen = false, description, children }: Props = $props();

  let isOpen = $state(defaultOpen);
  let showTooltip = $state(false);
  let infoEl: HTMLSpanElement | undefined = $state(undefined);
  let tooltipX = $state(0);
  let tooltipY = $state(0);

  function positionTooltip(): void {
    if (infoEl === undefined) return;
    const rect = infoEl.getBoundingClientRect();
    tooltipX = rect.right + 10;
    tooltipY = rect.top + rect.height / 2;
  }

  function showInfo(): void {
    positionTooltip();
    showTooltip = true;
  }
</script>

<div class="ss-section">
  <button
    class="ss-header"
    onclick={() => { isOpen = !isOpen; }}
    aria-expanded={isOpen}
    aria-label="Toggle {label} section"
  >
    <span class="ss-chevron" class:open={isOpen} aria-hidden="true">
      <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
        <path d="M9 18l6-6-6-6" />
      </svg>
    </span>
    <span class="ss-label">{label}</span>
    {#if badge !== undefined && badge > 0}
      <span class="ss-badge">{badge}</span>
    {/if}
    {#if description}
      <!-- svelte-ignore a11y_no_static_element_interactions -->
      <span
        class="ss-info"
        bind:this={infoEl}
        onmouseenter={showInfo}
        onmouseleave={() => { showTooltip = false; }}
        onclick={(e: MouseEvent) => { e.stopPropagation(); if (showTooltip) { showTooltip = false; } else { showInfo(); } }}
        role="note"
        aria-label="{label} info"
      >
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <circle cx="12" cy="12" r="10" />
          <path d="M12 16v-4" />
          <path d="M12 8h.01" />
        </svg>
      </span>
    {/if}
  </button>

  {#if showTooltip && description}
    <div
      class="ss-tooltip"
      style="left: {tooltipX}px; top: {tooltipY}px;"
      role="tooltip"
    >
      {description}
    </div>
  {/if}

  {#if isOpen}
    <div class="ss-content" transition:slide={{ duration: 160 }}>
      {@render children()}
    </div>
  {/if}
</div>

<style>
  .ss-section {
    display: flex;
    flex-direction: column;
  }

  .ss-header {
    display: flex;
    align-items: center;
    gap: 6px;
    height: 26px;
    padding: 0 8px;
    border: none;
    background: transparent;
    cursor: pointer;
    text-align: left;
    border-radius: var(--radius-xs);
    transition: background 100ms ease;
  }

  .ss-header:hover {
    background: var(--bg-surface);
  }

  .ss-label {
    flex: 1;
    font-size: 10px;
    font-weight: 600;
    letter-spacing: 1px;
    text-transform: uppercase;
    color: var(--text-muted);
  }

  .ss-badge {
    font-size: 10px;
    color: var(--text-tertiary);
  }

  .ss-chevron {
    flex-shrink: 0;
    color: var(--text-muted);
    display: flex;
    transition: transform 160ms ease;
  }

  .ss-chevron.open {
    transform: rotate(90deg);
  }

  .ss-info {
    position: relative;
    flex-shrink: 0;
    display: flex;
    align-items: center;
    color: var(--text-muted);
    opacity: 0;
    transition: opacity 0.15s, color 0.15s;
    cursor: help;
  }

  .ss-header:hover .ss-info {
    opacity: 1;
  }

  .ss-info:hover {
    color: var(--text-secondary);
  }

  .ss-tooltip {
    position: fixed;
    transform: translateY(-50%);
    width: 230px;
    padding: 10px 12px;
    background: #1e2433;
    border: 1px solid #2e3650;
    border-radius: 8px;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.55);
    font-size: 12px;
    font-weight: 400;
    line-height: 1.55;
    color: #c8cdd8;
    text-transform: none;
    letter-spacing: normal;
    white-space: normal;
    z-index: 9999;
    pointer-events: none;
  }

  .ss-content {
    display: flex;
    flex-direction: column;
    gap: 1px;
    overflow: hidden;
  }
</style>
