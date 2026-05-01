<!-- src/lib/components/layout/AppFooter.svelte
     Unified app footer: connection status (left) + system health (right) -->
<script lang="ts">
  import StatusDot from '$lib/components/shared/StatusDot.svelte';
  import { connectionStore } from '$lib/stores/connection.svelte';
  import { dashboardStore } from '$lib/stores/dashboard.svelte';
  import { isMockEnabled } from '$api/client';

  const STATUS_CONFIG = {
    connected:    { label: 'Connected',      cls: 'dot-connected' },
    mock:         { label: 'Offline Mode',   cls: 'dot-mock' },
    connecting:   { label: 'Connecting\u2026', cls: 'dot-connecting' },
    reconnecting: { label: 'Reconnecting',   cls: 'dot-reconnecting' },
    disconnected: { label: 'Disconnected',   cls: 'dot-disconnected' },
  } as const;

  type BackendStatus = 'ok' | 'degraded' | 'error' | string;
  type GatewayStatus = 'healthy' | 'degraded' | 'down' | string;

  function backendToDot(status: BackendStatus): 'online' | 'busy' | 'error' {
    if (status === 'ok')       return 'online';
    if (status === 'degraded') return 'busy';
    return 'error';
  }

  function gatewayToDot(status: GatewayStatus): 'online' | 'busy' | 'error' {
    if (status === 'healthy')  return 'online';
    if (status === 'degraded') return 'busy';
    return 'error';
  }

  const status     = $derived(connectionStore.status);
  const attempts   = $derived(connectionStore.reconnectAttempts);
  const queueSize  = $derived(connectionStore.offlineQueueSize);
  const connHealth = $derived(connectionStore.health);
  const config     = $derived(STATUS_CONFIG[status]);

  const versionLabel = $derived(
    connHealth?.version ? `v${connHealth.version}` : null
  );

  const health        = $derived(dashboardStore.systemHealth);
  const memoryWarning = $derived(health !== null && health.memory_mb > 500);
  const cpuWarning    = $derived(health !== null && health.cpu_pct > 80);
  const backendDot    = $derived(health ? backendToDot(health.backend) : 'idle' as const);
  const gatewayDot    = $derived(health ? gatewayToDot(health.gateway_status) : 'idle' as const);
  const gatewayName   = $derived(health?.primary_gateway ?? 'No gateway');

  function retryNow() {
    void connectionStore.check();
  }
</script>

<footer class="af-bar" role="status" aria-live="polite">
  <!-- LEFT: connection status -->
  <div class="af-section">
    <span class="af-dot {config.cls}" aria-hidden="true"></span>
    <span class="af-label">{config.label}</span>

    {#if status === 'reconnecting' && attempts > 0}
      <span class="af-detail">attempt {attempts}</span>
    {/if}
    {#if status === 'connected' && connHealth?.status === 'degraded'}
      <span class="af-warn">degraded</span>
    {/if}
    {#if status === 'mock'}
      <span class="af-detail">no backend</span>
    {/if}
    {#if queueSize > 0}
      <span class="af-detail">{queueSize} queued</span>
    {/if}
    {#if status === 'connected' && connHealth?.agents_active !== undefined}
      <span class="af-detail">{connHealth.agents_active} agent{connHealth.agents_active === 1 ? '' : 's'}</span>
    {/if}
    {#if versionLabel}
      <span class="af-version">{versionLabel}</span>
    {/if}
    {#if status === 'disconnected'}
      <button class="af-retry" onclick={retryNow} aria-label="Retry connection">
        Retry
      </button>
    {/if}
  </div>

  <!-- RIGHT: system health -->
  <div class="af-section">
    {#if health}
      <StatusDot status={backendDot} size="sm" />
      <span class="af-label">
        Backend<span class="af-hide-sm">:</span>
      </span>

      <span class="af-sep" aria-hidden="true"></span>

      <StatusDot status={gatewayDot} size="sm" />
      <span class="af-label af-hide-sm">{gatewayName}</span>

      <span class="af-sep" aria-hidden="true"></span>

      <svg class="af-icon" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
        <rect x="2" y="6" width="20" height="12" rx="2" />
        <path d="M6 12h.01M10 12h.01M14 12h.01M18 12h.01" />
      </svg>
      <span class="af-label" class:af-label--warn={memoryWarning}>
        {health.memory_mb} MB
      </span>

      <span class="af-sep" aria-hidden="true"></span>

      <svg class="af-icon" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
        <rect x="4" y="4" width="16" height="16" rx="2" />
        <rect x="9" y="9" width="6" height="6" />
        <path d="M9 2v2M15 2v2M9 20v2M15 20v2M2 9h2M2 15h2M20 9h2M20 15h2" />
      </svg>
      <span class="af-label" class:af-label--warn={cpuWarning}>
        {health.cpu_pct}%
      </span>
    {:else}
      <span class="af-detail">Cache savings: %</span>
    {/if}
  </div>
</footer>

<style>
  .af-bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 6px;
    padding: 2px 12px;
    font-size: 11px;
    line-height: 1;
    color: var(--text-tertiary, rgba(255,255,255,0.45));
    border-top: 1px solid rgba(255,255,255,0.05);
    background: var(--bg-primary, #0d1117);
    flex-shrink: 0;
    height: 22px;
    box-sizing: border-box;
  }

  .af-section {
    display: flex;
    align-items: center;
    gap: 6px;
    min-width: 0;
  }

  .af-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    flex-shrink: 0;
  }

  .af-label {
    color: var(--text-tertiary, rgba(255,255,255,0.45));
    white-space: nowrap;
  }

  .af-label--warn {
    color: var(--accent-warning, #eab308);
  }

  .af-detail {
    color: var(--text-muted, rgba(255,255,255,0.25));
    white-space: nowrap;
  }

  .af-warn {
    color: #eab308;
    font-weight: 500;
  }

  .af-version {
    color: var(--text-muted, rgba(255,255,255,0.25));
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 10px;
  }

  .af-sep {
    width: 1px;
    height: 12px;
    background: rgba(255,255,255,0.08);
    flex-shrink: 0;
  }

  .af-icon {
    flex-shrink: 0;
    color: var(--text-tertiary, rgba(255,255,255,0.45));
  }

  .af-retry {
    padding: 1px 6px;
    border: 1px solid rgba(255,255,255,0.12);
    border-radius: 4px;
    background: rgba(255,255,255,0.05);
    color: rgba(255,255,255,0.5);
    font-size: 10px;
    cursor: pointer;
    transition: all 120ms ease;
  }

  .af-retry:hover {
    background: rgba(255,255,255,0.1);
    color: rgba(255,255,255,0.8);
    border-color: rgba(255,255,255,0.2);
  }

  .dot-connected    { background: #22c55e; }
  .dot-mock         { background: #f97316; animation: af-pulse 2s ease-in-out infinite; }
  .dot-connecting   { background: #3b82f6; animation: af-pulse 1.4s ease-in-out infinite; }
  .dot-reconnecting { background: #eab308; animation: af-pulse 1s ease-in-out infinite; }
  .dot-disconnected { background: #ef4444; }

  @keyframes af-pulse {
    0%, 100% { opacity: 1; }
    50%      { opacity: 0.3; }
  }

  @media (max-width: 640px) {
    .af-hide-sm { display: none; }
  }
</style>
