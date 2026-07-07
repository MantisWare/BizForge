<!-- In-office quick chat modal (OneChat equivalent) -->
<script lang="ts">
  import { fly, fade } from 'svelte/transition';
  import type { BizforgeAgent } from '$api/types';
  import { conversationsStore } from '$lib/stores/conversations.svelte';
  import AgentIcon from '$lib/components/shared/AgentIcon.svelte';
  import Button from '$lib/components/ui/Button.svelte';

  interface Props {
    open: boolean;
    agents: BizforgeAgent[];
    onClose: () => void;
  }

  let { open, agents, onClose }: Props = $props();

  let selectedAgentId = $state<string | null>(null);
  let messageInput = $state('');
  let sending = $state(false);

  const selectedAgent = $derived(
    agents.find((a) => a.id === selectedAgentId) ?? null,
  );

  $effect(() => {
    if (open) {
      void conversationsStore.fetchConversations();
    }
  });

  $effect(() => {
    if (open && agents.length > 0 && selectedAgentId === null) {
      selectedAgentId = agents[0]?.id ?? null;
    }
    if (!open) {
      messageInput = '';
    }
  });

  $effect(() => {
    if (!open || !selectedAgentId) return;
    const conv = conversationsStore.conversations.find(
      (c) => c.agent_id === selectedAgentId && c.status === 'active',
    );
    if (conv) {
      conversationsStore.setActiveConversation(conv);
      void conversationsStore.fetchConversation(conv.id);
    } else {
      conversationsStore.setActiveConversation(null);
      conversationsStore.messages = [];
    }
  });

  async function handleSend(): Promise<void> {
    const text = messageInput.trim();
    if (!text || !selectedAgentId || sending) return;
    sending = true;
    messageInput = '';
    try {
      let conv = conversationsStore.conversations.find(
        (c) => c.agent_id === selectedAgentId && c.status === 'active',
      );
      if (!conv) {
        const agent = agents.find((a) => a.id === selectedAgentId);
        const title = agent ? `Office chat — ${agent.display_name ?? agent.name}` : 'Office chat';
        conv = await conversationsStore.createConversation(selectedAgentId, title);
      }
      if (conv) {
        conversationsStore.setActiveConversation(conv);
        await conversationsStore.sendMessage(conv.id, text);
      }
    } finally {
      sending = false;
    }
  }

  function handleKeyDown(e: KeyboardEvent): void {
    if (e.key === 'Escape') onClose();
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      void handleSend();
    }
  }
</script>

<svelte:window onkeydown={handleKeyDown} />

{#if open}
  <div class="ocm-backdrop" transition:fade={{ duration: 150 }} onclick={onClose} role="presentation">
    <div
      class="ocm-modal"
      transition:fly={{ y: 20, duration: 200 }}
      onclick={(e) => e.stopPropagation()}
      role="dialog"
      aria-label="Office chat"
    >
      <header class="ocm-header">
        <h2 class="ocm-title">Office Chat</h2>
        <button class="ocm-close" onclick={onClose} aria-label="Close">×</button>
      </header>

      <div class="ocm-agents" role="tablist" aria-label="Select agent">
        {#each agents as agent (agent.id)}
          <button
            class="ocm-agent"
            class:ocm-agent--active={selectedAgentId === agent.id}
            onclick={() => { selectedAgentId = agent.id; }}
            role="tab"
            aria-selected={selectedAgentId === agent.id}
          >
            <AgentIcon value={agent.avatar} size={20} />
            <span>{agent.display_name ?? agent.name}</span>
          </button>
        {/each}
      </div>

      <div class="ocm-messages">
        {#if conversationsStore.messages.length === 0}
          <p class="ocm-empty">Start a conversation with {selectedAgent?.display_name ?? selectedAgent?.name ?? 'an agent'}</p>
        {:else}
          {#each conversationsStore.messages as msg (msg.id)}
            <div class="ocm-msg ocm-msg--{msg.role}">
              <span class="ocm-msg-role">{msg.role === 'user' ? 'You' : 'Agent'}</span>
              <p>{msg.content}</p>
            </div>
          {/each}
        {/if}
      </div>

      <footer class="ocm-footer">
        <input
          class="ds-input"
          type="text"
          placeholder="Message {selectedAgent?.display_name ?? selectedAgent?.name ?? 'agent'}…"
          bind:value={messageInput}
          disabled={sending || !selectedAgentId}
        />
        <Button variant="primary" disabled={sending || !messageInput.trim()} onclick={() => void handleSend()}>
          Send
        </Button>
      </footer>
    </div>
  </div>
{/if}

<style>
  .ocm-backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.5);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 8000;
  }
  .ocm-modal {
    width: min(480px, calc(100vw - 32px));
    max-height: 70vh;
    background: var(--bg-secondary);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-lg);
    display: flex;
    flex-direction: column;
    overflow: hidden;
    box-shadow: var(--shadow-lg);
  }
  .ocm-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 14px 16px;
    border-bottom: 1px solid var(--border-default);
  }
  .ocm-title {
    margin: 0;
    font-size: 14px;
    font-weight: 600;
    color: var(--text-primary);
  }
  .ocm-close {
    background: none;
    border: none;
    color: var(--text-muted);
    font-size: 20px;
    cursor: pointer;
    line-height: 1;
  }
  .ocm-agents {
    display: flex;
    gap: 4px;
    padding: 8px 12px;
    overflow-x: auto;
    border-bottom: 1px solid var(--border-default);
  }
  .ocm-agent {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 4px 10px;
    border-radius: var(--radius-sm);
    border: 1px solid var(--border-default);
    background: var(--bg-surface);
    color: var(--text-secondary);
    font-size: 12px;
    cursor: pointer;
    white-space: nowrap;
  }
  .ocm-agent--active {
    border-color: var(--accent-primary);
    color: var(--text-primary);
  }
  .ocm-messages {
    flex: 1;
    overflow-y: auto;
    padding: 12px 16px;
    display: flex;
    flex-direction: column;
    gap: 10px;
    min-height: 160px;
  }
  .ocm-empty {
    color: var(--text-muted);
    font-size: 13px;
    text-align: center;
    margin: auto;
  }
  .ocm-msg {
    font-size: 13px;
    color: var(--text-primary);
  }
  .ocm-msg-role {
    font-size: 10px;
    font-weight: 600;
    text-transform: uppercase;
    color: var(--text-muted);
    display: block;
    margin-bottom: 2px;
  }
  .ocm-msg--user {
    align-self: flex-end;
    max-width: 85%;
    background: var(--bg-elevated);
    padding: 8px 10px;
    border-radius: var(--radius-sm);
  }
  .ocm-footer {
    display: flex;
    gap: 8px;
    padding: 12px 16px;
    border-top: 1px solid var(--border-default);
  }
</style>
