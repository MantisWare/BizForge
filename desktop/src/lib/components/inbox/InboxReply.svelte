<!-- src/lib/components/inbox/InboxReply.svelte -->
<!-- Reply composer for inbox items with a source_channel -->
<script lang="ts">
  import type { InboxItem } from '$api/types';
  import { inboxStore } from '$lib/stores/inbox.svelte';

  interface Props {
    item: InboxItem;
    onClose?: () => void;
  }

  let { item, onClose }: Props = $props();

  let replyText = $state('');
  let sending = $state(false);

  const channelLabel = $derived(
    item.source_channel === 'slack' ? 'Slack'
    : item.source_channel === 'email' ? 'Email'
    : item.source_channel ?? 'channel'
  );

  async function handleSend() {
    const trimmed = replyText.trim();
    if (trimmed === '' || sending) return;

    sending = true;
    const ok = await inboxStore.replyToItem(item.id, trimmed);
    sending = false;

    if (ok) {
      replyText = '';
      onClose?.();
    }
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
      e.preventDefault();
      handleSend();
    }
    if (e.key === 'Escape') {
      onClose?.();
    }
  }
</script>

<div class="ir-container" role="region" aria-label="Reply to {channelLabel}">
  <div class="ir-header">
    <span class="ir-label">Reply via {channelLabel}</span>
    {#if onClose}
      <button class="ir-close" onclick={onClose} aria-label="Close reply" type="button">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <path d="M18 6L6 18M6 6l12 12" />
        </svg>
      </button>
    {/if}
  </div>

  <textarea
    class="ir-textarea"
    bind:value={replyText}
    onkeydown={handleKeydown}
    placeholder="Type your reply... (Cmd+Enter to send)"
    rows="3"
    disabled={sending}
    aria-label="Reply message"
  ></textarea>

  <div class="ir-footer">
    <span class="ir-hint">Cmd+Enter to send</span>
    <button
      class="ir-send-btn"
      onclick={handleSend}
      disabled={replyText.trim() === '' || sending}
      type="button"
    >
      {#if sending}
        Sending...
      {:else}
        Send Reply
      {/if}
    </button>
  </div>
</div>

<style>
  .ir-container {
    border-top: 1px solid var(--border-default);
    padding: 10px 14px;
    display: flex;
    flex-direction: column;
    gap: 8px;
    background: rgba(255, 255, 255, 0.02);
  }

  .ir-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .ir-label {
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--text-muted);
  }

  .ir-close {
    background: none;
    border: none;
    color: var(--text-muted);
    cursor: pointer;
    padding: 2px;
    border-radius: var(--radius-xs);
    display: flex;
    align-items: center;
    justify-content: center;
  }
  .ir-close:hover {
    color: var(--text-primary);
    background: rgba(255, 255, 255, 0.06);
  }

  .ir-textarea {
    width: 100%;
    min-height: 60px;
    max-height: 150px;
    resize: vertical;
    background: rgba(0, 0, 0, 0.2);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-sm);
    padding: 8px 10px;
    font-size: 13px;
    font-family: inherit;
    color: var(--text-primary);
    line-height: 1.5;
  }
  .ir-textarea:focus {
    outline: none;
    border-color: var(--accent-primary);
  }
  .ir-textarea::placeholder {
    color: var(--text-muted);
  }
  .ir-textarea:disabled {
    opacity: 0.5;
  }

  .ir-footer {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .ir-hint {
    font-size: 11px;
    color: var(--text-muted);
  }

  .ir-send-btn {
    font-size: 12px;
    font-weight: 600;
    font-family: inherit;
    padding: 5px 14px;
    border-radius: var(--radius-sm);
    border: none;
    background: var(--accent-primary);
    color: #fff;
    cursor: pointer;
    transition: opacity 100ms ease;
  }
  .ir-send-btn:hover:not(:disabled) {
    opacity: 0.85;
  }
  .ir-send-btn:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }
</style>
