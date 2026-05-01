<!-- src/lib/components/layout/ConnectionStatusBar.svelte -->
<script lang="ts">
  import { connectionStore } from '$lib/stores/connection.svelte';
  import { isMockEnabled } from '$api/client';

  interface Props {
    alwaysShow?: boolean;
  }

  let { alwaysShow = false }: Props = $props();

  const STATUS_CONFIG = {
    connected:    { label: 'Connected',     cls: 'dot-connected',    icon: 'check' },
    mock:         { label: 'Offline Mode',  cls: 'dot-mock',         icon: 'mock' },
    connecting:   { label: 'Connecting\u2026', cls: 'dot-connecting', icon: 'loading' },
    reconnecting: { label: 'Reconnecting',  cls: 'dot-reconnecting', icon: 'loading' },
    disconnected: { label: 'Disconnected',  cls: 'dot-disconnected', icon: 'x' },
  } as const;

  let status    = $derived(connectionStore.status);
  let attempts  = $derived(connectionStore.reconnectAttempts);
  let queueSize = $derived(connectionStore.offlineQueueSize);
  let healthData = $derived(connectionStore.health);

  let showBar = $derived(
    alwaysShow ||
    status === 'connecting' ||
    status === 'reconnecting' ||
    status === 'disconnected'
  );

  let config = $derived(STATUS_CONFIG[status]);

  let versionLabel = $derived(
    healthData?.version
      ? `v${healthData.version}`
      : null
  );

  function retryNow() {
    void connectionStore.check();
  }
</script>

{#if showBar}
  <footer class="csb-bar" role="status" aria-live="polite">
    <div class="csb-left">
      <span class="csb-dot {config.cls}" aria-hidden="true"></span>
      <span class="csb-label">{config.label}</span>

      {#if status === 'reconnecting' && attempts > 0}
        <span class="csb-detail">attempt {attempts}</span>
      {/if}
      {#if status === 'connected' && healthData?.status === 'degraded'}
        <span class="csb-warn">degraded</span>
      {/if}
      {#if status === 'mock'}
        <span class="csb-detail">no backend</span>
      {/if}
    </div>

    <div class="csb-right">
      {#if queueSize > 0}
        <span class="csb-queue">{queueSize} queued</span>
      {/if}
      {#if status === 'connected' && healthData?.agents_active !== undefined}
        <span class="csb-detail">{healthData.agents_active} agent{healthData.agents_active === 1 ? '' : 's'}</span>
      {/if}
      {#if versionLabel}
        <span class="csb-version">{versionLabel}</span>
      {/if}
      {#if status === 'disconnected'}
        <button class="csb-retry" onclick={retryNow} aria-label="Retry connection">
          Retry
        </button>
      {/if}
    </div>
  </footer>
{/if}

<style>
  .csb-bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 6px;
    padding: 4px 12px;
    font-size: 11px;
    color: var(--text-tertiary, rgba(255,255,255,0.45));
    border-top: 1px solid rgba(255,255,255,0.05);
    flex-shrink: 0;
  }

  .csb-left, .csb-right {
    display: flex;
    align-items: center;
    gap: 6px;
  }

  .csb-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    flex-shrink: 0;
  }

  .csb-label {
    color: var(--text-tertiary, rgba(255,255,255,0.45));
  }

  .csb-detail,
  .csb-queue,
  .csb-version {
    color: var(--text-muted, rgba(255,255,255,0.25));
  }

  .csb-warn {
    color: #eab308;
    font-weight: 500;
  }

  .csb-version {
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 10px;
  }

  .dot-connected {
    background: #22c55e;
  }

  .dot-mock {
    background: #f97316;
    animation: csb-pulse 2s ease-in-out infinite;
  }

  .dot-connecting {
    background: #3b82f6;
    animation: csb-pulse 1.4s ease-in-out infinite;
  }

  .dot-reconnecting {
    background: #eab308;
    animation: csb-pulse 1s ease-in-out infinite;
  }

  .dot-disconnected {
    background: #ef4444;
  }

  .csb-retry {
    padding: 1px 6px;
    border: 1px solid rgba(255,255,255,0.12);
    border-radius: 4px;
    background: rgba(255,255,255,0.05);
    color: rgba(255,255,255,0.5);
    font-size: 10px;
    cursor: pointer;
    transition: all 120ms ease;
  }

  .csb-retry:hover {
    background: rgba(255,255,255,0.1);
    color: rgba(255,255,255,0.8);
    border-color: rgba(255,255,255,0.2);
  }

  @keyframes csb-pulse {
    0%, 100% { opacity: 1; }
    50%       { opacity: 0.3; }
  }
</style>
