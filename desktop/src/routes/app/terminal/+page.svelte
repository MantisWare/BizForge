<!-- src/routes/app/terminal/+page.svelte -->
<script lang="ts">
  import { onMount } from 'svelte';
  import PageShell from '$lib/components/layout/PageShell.svelte';
  import { terminalStore } from '$lib/stores/terminal.svelte';

  let terminalComponent: typeof import('$lib/components/terminal/EmbeddedTerminal.svelte').default | undefined = $state();

  onMount(() => {
    if (terminalStore.tabs.length === 0) {
      terminalStore.createTab();
    }

    import('$lib/components/terminal/EmbeddedTerminal.svelte').then((mod) => {
      terminalComponent = mod.default;
    });
  });

  function addTab(): void {
    terminalStore.createTab();
  }

  function closeTab(id: string): void {
    terminalStore.closeTab(id);
  }
</script>

<PageShell title="Terminal" subtitle="Embedded shell" noPadding>
  {#snippet actions()}
    <button class="trm-btn" onclick={addTab} title="New terminal tab">
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <path d="M12 4.5v15m7.5-7.5h-15" />
      </svg>
      New
    </button>
  {/snippet}

  <div class="trm-root">
    {#if terminalStore.tabs.length > 1}
      <div class="trm-tabs" role="tablist" aria-label="Terminal tabs">
        {#each terminalStore.tabs as tab (tab.id)}
          <div
            class="trm-tab"
            class:trm-tab--active={tab.id === terminalStore.activeTabId}
            role="tab"
            tabindex="0"
            aria-selected={tab.id === terminalStore.activeTabId}
            onclick={() => terminalStore.switchTab(tab.id)}
            onkeydown={(e) => { if (e.key === 'Enter' || e.key === ' ') terminalStore.switchTab(tab.id); }}
          >
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <path d="M6.75 7.5l3 2.25-3 2.25m4.5 0h3m-9 8.25h13.5A2.25 2.25 0 0021 18V6a2.25 2.25 0 00-2.25-2.25H5.25A2.25 2.25 0 003 6v12a2.25 2.25 0 002.25 2.25z" />
            </svg>
            <span class="trm-tab-label">{tab.label}</span>
            <button
              class="trm-tab-close"
              onclick={(e) => { e.stopPropagation(); closeTab(tab.id); }}
              aria-label="Close {tab.label}"
              title="Close tab"
            >
              <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <path d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
        {/each}
      </div>
    {/if}

    <div class="trm-pane">
      {#if terminalComponent !== undefined && terminalStore.activeTabId !== null}
        {#key terminalStore.activeTabId}
          <svelte:component this={terminalComponent} tabId={terminalStore.activeTabId} />
        {/key}
      {:else}
        <div class="trm-loading">
          <span class="trm-loading-dot"></span>
          <span class="trm-loading-dot"></span>
          <span class="trm-loading-dot"></span>
        </div>
      {/if}
    </div>
  </div>
</PageShell>

<style>
  .trm-root {
    display: flex;
    flex-direction: column;
    flex: 1;
    min-height: 0;
    background: #0d1117;
  }

  .trm-btn {
    display: flex;
    align-items: center;
    gap: 5px;
    padding: 4px 10px;
    border: 1px solid var(--border-default);
    background: var(--bg-surface);
    color: var(--text-secondary);
    border-radius: 6px;
    font-size: 12px;
    cursor: pointer;
    transition: background 120ms ease, border-color 120ms ease;
  }

  .trm-btn:hover {
    background: var(--bg-elevated);
    border-color: var(--border-hover);
    color: var(--text-primary);
  }

  .trm-tabs {
    display: flex;
    align-items: center;
    gap: 1px;
    padding: 4px 8px 0;
    background: #0d1117;
    border-bottom: 1px solid rgba(255, 255, 255, 0.06);
    overflow-x: auto;
    flex-shrink: 0;
  }

  .trm-tabs::-webkit-scrollbar {
    height: 2px;
  }
  .trm-tabs::-webkit-scrollbar-thumb {
    background: rgba(255, 255, 255, 0.1);
  }

  .trm-tab {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 6px 10px;
    border: none;
    background: transparent;
    color: rgba(255, 255, 255, 0.4);
    font-size: 12px;
    cursor: pointer;
    border-radius: 6px 6px 0 0;
    transition: background 120ms ease, color 120ms ease;
    white-space: nowrap;
    font-family: inherit;
  }

  .trm-tab:hover {
    background: rgba(255, 255, 255, 0.05);
    color: rgba(255, 255, 255, 0.6);
  }

  .trm-tab--active {
    background: rgba(255, 255, 255, 0.08);
    color: rgba(255, 255, 255, 0.85);
  }

  .trm-tab-label {
    max-width: 120px;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .trm-tab-close {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 16px;
    height: 16px;
    border: none;
    background: transparent;
    color: inherit;
    border-radius: 3px;
    cursor: pointer;
    opacity: 0;
    transition: opacity 120ms ease, background 120ms ease;
    padding: 0;
  }

  .trm-tab:hover .trm-tab-close {
    opacity: 0.6;
  }

  .trm-tab-close:hover {
    opacity: 1;
    background: rgba(255, 255, 255, 0.1);
  }

  .trm-pane {
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
  }

  .trm-loading {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
  }

  .trm-loading-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: rgba(255, 255, 255, 0.3);
    animation: trm-pulse 1.4s ease-in-out infinite both;
  }

  .trm-loading-dot:nth-child(1) { animation-delay: -0.32s; }
  .trm-loading-dot:nth-child(2) { animation-delay: -0.16s; }

  @keyframes trm-pulse {
    0%, 80%, 100% { transform: scale(0); opacity: 0.3; }
    40% { transform: scale(1); opacity: 1; }
  }
</style>
