<!-- Active chat sessions bar — multi-tab conversation switching -->
<script lang="ts">
  import { chatRunsStore } from '$lib/stores/chatRuns.svelte';

  interface Props {
    onNewChat?: () => void;
  }

  let { onNewChat }: Props = $props();
</script>

<div class="asb" role="tablist" aria-label="Active chat sessions">
  {#each chatRunsStore.runs as run (run.runId)}
    <button
      class="asb-tab"
      class:asb-tab--active={chatRunsStore.activeRunId === run.runId}
      class:asb-tab--loading={run.loading}
      role="tab"
      aria-selected={chatRunsStore.activeRunId === run.runId}
      onclick={() => chatRunsStore.setActive(run.runId)}
    >
      {#if run.loading}
        <span class="asb-spinner" aria-hidden="true"></span>
      {/if}
      <span class="asb-title">{run.title}</span>
      <span
        class="asb-close"
        role="button"
        tabindex="0"
        aria-label="Close tab"
        onclick={(e) => { e.stopPropagation(); chatRunsStore.closeRun(run.runId); }}
        onkeydown={(e) => {
          if (e.key === 'Enter' || e.key === ' ') {
            e.stopPropagation();
            e.preventDefault();
            chatRunsStore.closeRun(run.runId);
          }
        }}
      >×</span>
    </button>
  {/each}
  {#if onNewChat}
    <button class="asb-new" onclick={onNewChat} aria-label="New chat">+</button>
  {/if}
</div>

<style>
  .asb {
    display: flex;
    align-items: center;
    gap: 4px;
    padding: 6px 12px;
    border-bottom: 1px solid var(--border-default);
    background: var(--bg-secondary);
    overflow-x: auto;
    flex-shrink: 0;
  }
  .asb-tab {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 5px 10px;
    border-radius: var(--radius-sm);
    border: 1px solid var(--border-default);
    background: var(--bg-surface);
    color: var(--text-secondary);
    font-size: 12px;
    cursor: pointer;
    max-width: 180px;
    transition: background var(--transition-fast), border-color var(--transition-fast);
  }
  .asb-tab--active {
    background: var(--bg-elevated);
    border-color: var(--accent-primary);
    color: var(--text-primary);
  }
  .asb-tab--loading .asb-title {
    opacity: 0.8;
  }
  .asb-title {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .asb-close {
    opacity: 0.5;
    font-size: 14px;
    line-height: 1;
    padding: 0 2px;
  }
  .asb-close:hover {
    opacity: 1;
    color: var(--accent-error);
  }
  .asb-spinner {
    width: 10px;
    height: 10px;
    border: 1.5px solid var(--border-default);
    border-top-color: var(--accent-primary);
    border-radius: 50%;
    animation: spin 0.7s linear infinite;
    flex-shrink: 0;
  }
  .asb-new {
    padding: 5px 10px;
    border-radius: var(--radius-sm);
    border: 1px dashed var(--border-default);
    background: transparent;
    color: var(--text-tertiary);
    cursor: pointer;
    font-size: 14px;
    flex-shrink: 0;
  }
  .asb-new:hover {
    border-color: var(--accent-primary);
    color: var(--accent-primary);
  }
</style>
