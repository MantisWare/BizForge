<!-- Queued messages shown while agent is generating -->
<script lang="ts">
  interface QueuedItem {
    id: string;
    text: string;
  }

  interface Props {
    items: QueuedItem[];
    onRemove?: (id: string) => void;
  }

  let { items, onRemove }: Props = $props();
</script>

{#if items.length > 0}
  <div class="qm" aria-label="Queued messages">
    <span class="qm-label">Queued ({items.length})</span>
    {#each items as item (item.id)}
      <div class="qm-item">
        <span class="qm-text">{item.text}</span>
        {#if onRemove}
          <button class="qm-remove" onclick={() => onRemove?.(item.id)} aria-label="Remove queued message">×</button>
        {/if}
      </div>
    {/each}
  </div>
{/if}

<style>
  .qm {
    padding: 8px 12px;
    border-top: 1px solid var(--border-default);
    background: var(--bg-surface);
    display: flex;
    flex-direction: column;
    gap: 4px;
  }
  .qm-label {
    font-size: 10px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--text-muted);
  }
  .qm-item {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 8px;
    background: var(--bg-secondary);
    border-radius: var(--radius-xs);
    font-size: 12px;
    color: var(--text-secondary);
  }
  .qm-text {
    flex: 1;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .qm-remove {
    background: none;
    border: none;
    color: var(--text-muted);
    cursor: pointer;
    font-size: 14px;
    padding: 0 4px;
  }
</style>
