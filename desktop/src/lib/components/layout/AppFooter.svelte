<!-- src/lib/components/layout/AppFooter.svelte
     Unified app footer: connection status (left) + OSA + system health (right) -->
<script lang="ts">
  import StatusDot from '$lib/components/shared/StatusDot.svelte';
  import ResourceMonitor from '$lib/components/layout/ResourceMonitor.svelte';
  import { connectionStore } from '$lib/stores/connection.svelte';
  import { dashboardStore } from '$lib/stores/dashboard.svelte';
  import { checkOsaHealth, setupOsa, stopOsa, restartOsa, type OsaHealth } from '$lib/services/osa';

  interface Props {
    logPanelOpen?: boolean;
    onToggleLogs?: () => void;
  }

  let { logPanelOpen = false, onToggleLogs }: Props = $props();

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
  const healthMemMb   = $derived(health?.memory_mb ?? 0);
  const healthCpuPct  = $derived(health?.cpu_pct ?? 0);
  const memoryWarning = $derived(health !== null && healthMemMb > 500);
  const cpuWarning    = $derived(health !== null && healthCpuPct > 80);
  const backendDot    = $derived(health !== null ? backendToDot(health.backend ?? 'error') : 'idle' as const);
  const gatewayDot    = $derived(health !== null ? gatewayToDot(health.gateway_status ?? 'down') : 'idle' as const);
  const gatewayName   = $derived(health?.primary_gateway ?? 'No gateway');

  // OSA runtime state
  let osaHealth = $state<OsaHealth | null>(null);
  let osaLoading = $state(false);
  let osaDropdownOpen = $state(false);
  let osaDropdownEl = $state<HTMLElement | null>(null);

  const osaRunning = $derived(osaHealth !== null);
  const osaDot = $derived<'online' | 'error'>(osaRunning ? 'online' : 'error');

  // Resource Monitor
  let showResourceMonitor = $state(false);

  // ─── UI Zoom ───────────────────────────────────────────────────────────────
  const ZOOM_MIN = 50;
  const ZOOM_MAX = 150;
  const ZOOM_STEP = 5;
  const ZOOM_PRESETS = [75, 90, 100, 110, 125] as const;
  const ZOOM_KEY = 'bizforge-ui-zoom';

  let zoomPct = $state(
    typeof localStorage !== 'undefined'
      ? parseInt(localStorage.getItem(ZOOM_KEY) ?? '100', 10)
      : 100
  );
  let zoomOpen = $state(false);
  let zoomDropdownEl = $state<HTMLElement | null>(null);
  let zoomInputValue = $state(String(zoomPct));

  function clampZoom(v: number): number {
    return Math.max(ZOOM_MIN, Math.min(ZOOM_MAX, Math.round(v)));
  }

  function applyZoom(pct: number): void {
    const clamped = clampZoom(pct);
    zoomPct = clamped;
    zoomInputValue = String(clamped);
    if (typeof localStorage !== 'undefined') {
      localStorage.setItem(ZOOM_KEY, String(clamped));
    }
    if (typeof document !== 'undefined') {
      document.documentElement.style.zoom = `${clamped}%`;
    }
  }

  function zoomIn(): void { applyZoom(zoomPct + ZOOM_STEP); }
  function zoomOut(): void { applyZoom(zoomPct - ZOOM_STEP); }
  function resetZoom(): void { applyZoom(100); }

  function handleZoomInputBlur(): void {
    const parsed = parseInt(zoomInputValue, 10);
    if (Number.isNaN(parsed)) {
      zoomInputValue = String(zoomPct);
      return;
    }
    applyZoom(parsed);
  }

  function handleZoomInputKey(e: KeyboardEvent): void {
    if (e.key === 'Enter') {
      (e.target as HTMLInputElement).blur();
    }
  }

  // Apply persisted zoom on mount
  $effect(() => {
    if (typeof document !== 'undefined' && zoomPct !== 100) {
      document.documentElement.style.zoom = `${zoomPct}%`;
    }
  });

  // Close zoom dropdown on outside click
  function handleZoomDocClick(e: MouseEvent) {
    if (zoomDropdownEl !== null && !zoomDropdownEl.contains(e.target as Node)) {
      zoomOpen = false;
    }
  }

  $effect(() => {
    if (zoomOpen) {
      document.addEventListener('click', handleZoomDocClick, true);
      return () => document.removeEventListener('click', handleZoomDocClick, true);
    }
  });

  async function pollOsa(): Promise<void> {
    osaHealth = await checkOsaHealth();
  }

  $effect(() => {
    void pollOsa();
    const timer = setInterval(() => void pollOsa(), 15_000);
    return () => clearInterval(timer);
  });

  // Close OSA dropdown on outside click
  function handleDocClick(e: MouseEvent) {
    if (osaDropdownEl !== null && !osaDropdownEl.contains(e.target as Node)) {
      osaDropdownOpen = false;
    }
  }

  $effect(() => {
    if (osaDropdownOpen) {
      document.addEventListener('click', handleDocClick, true);
      return () => document.removeEventListener('click', handleDocClick, true);
    }
  });

  async function handleOsaStart(): Promise<void> {
    osaLoading = true;
    try {
      await setupOsa();
      await pollOsa();
    } finally {
      osaLoading = false;
    }
  }

  async function handleOsaStop(): Promise<void> {
    osaLoading = true;
    try {
      await stopOsa();
      await pollOsa();
    } finally {
      osaLoading = false;
    }
  }

  async function handleOsaRestart(): Promise<void> {
    osaLoading = true;
    try {
      await restartOsa();
      await pollOsa();
    } finally {
      osaLoading = false;
    }
  }

  const isOffline = $derived(status === 'mock' || status === 'disconnected');
  const isChecking = $derived(connectionStore.isChecking);
  let reconnecting = $state(false);

  async function reconnectBackend(): Promise<void> {
    if (reconnecting) return;
    reconnecting = true;
    try {
      await connectionStore.check();
      if (connectionStore.status === 'connected') {
        await dashboardStore.fetch();
      }
    } finally {
      reconnecting = false;
    }
  }

  function retryNow() {
    void reconnectBackend();
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
    {#if isOffline}
      <button
        class="af-reconnect"
        class:af-reconnect--busy={reconnecting || isChecking}
        onclick={retryNow}
        disabled={reconnecting || isChecking}
        aria-label="Reconnect to backend"
      >
        <svg
          class="af-reconnect-icon"
          class:af-reconnect-icon--spin={reconnecting || isChecking}
          width="10"
          height="10"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2.5"
          aria-hidden="true"
        >
          <path d="M23 4v6h-6" />
          <path d="M1 20v-6h6" />
          <path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10" />
          <path d="M20.49 15a9 9 0 0 1-14.85 3.36L1 14" />
        </svg>
        {reconnecting || isChecking ? 'Checking\u2026' : 'Reconnect'}
      </button>
    {/if}

    <span class="af-sep" aria-hidden="true"></span>

    <button
      class="af-log-btn"
      class:af-log-btn--active={logPanelOpen}
      onclick={onToggleLogs}
      aria-label={logPanelOpen ? 'Hide system logs' : 'Show system logs'}
      title="System Logs"
    >
      <svg class="af-icon" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
        <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
        <polyline points="14 2 14 8 20 8" />
        <line x1="16" y1="13" x2="8" y2="13" />
        <line x1="16" y1="17" x2="8" y2="17" />
      </svg>
      <span class="af-label">Logs</span>
    </button>
  </div>

  <!-- RIGHT: system health -->
  <div class="af-section">
    <StatusDot status={backendDot} size="sm" />
      <span class="af-label" class:af-label--degraded={health === null}>
        Backend{#if health !== null}<span class="af-hide-sm">:</span>{:else}<span class="af-hide-sm">: --</span>{/if}
      </span>

      <span class="af-sep" aria-hidden="true"></span>

      <!-- OSA indicator (polls independently, always available) -->
      <span class="af-osa-wrap" bind:this={osaDropdownEl}>
        <button
          class="af-osa-btn"
          onclick={() => osaDropdownOpen = !osaDropdownOpen}
          aria-label="OSA runtime status"
          title={osaRunning ? `OSA running${osaHealth?.version !== undefined ? ` v${osaHealth.version}` : ''}` : 'OSA not running'}
        >
          <StatusDot status={osaDot} size="sm" />
          <span class="af-label">OSA</span>
        </button>

        {#if osaDropdownOpen}
          <div class="af-osa-dropdown" role="menu">
            <div class="af-osa-header">
              <span class="af-osa-title">OSA Runtime</span>
              <span class="af-osa-status" class:af-osa-status--running={osaRunning}>
                {osaRunning ? 'Running' : 'Stopped'}
              </span>
            </div>
            {#if osaHealth !== null}
              {#if osaHealth.version !== undefined}
                <div class="af-osa-detail">Version: {osaHealth.version}</div>
              {/if}
              {#if osaHealth.model !== undefined}
                <div class="af-osa-detail">Model: {osaHealth.model}</div>
              {/if}
            {/if}
            <div class="af-osa-actions">
              {#if osaRunning}
                <button class="af-osa-action" onclick={handleOsaRestart} disabled={osaLoading}>
                  {osaLoading ? 'Restarting...' : 'Restart'}
                </button>
                <button class="af-osa-action af-osa-action--danger" onclick={handleOsaStop} disabled={osaLoading}>
                  {osaLoading ? 'Stopping...' : 'Stop'}
                </button>
              {:else}
                <button class="af-osa-action af-osa-action--primary" onclick={handleOsaStart} disabled={osaLoading}>
                  {osaLoading ? 'Starting...' : 'Start'}
                </button>
              {/if}
            </div>
          </div>
        {/if}
      </span>

      <span class="af-sep" aria-hidden="true"></span>

      <StatusDot status={gatewayDot} size="sm" />
      <span class="af-label af-hide-sm" class:af-label--degraded={health === null}>
        {health !== null ? gatewayName : '--'}
      </span>

      <span class="af-sep" aria-hidden="true"></span>

      <!-- Clickable memory: opens Resource Monitor -->
      <button class="af-mem-btn" onclick={() => showResourceMonitor = !showResourceMonitor} aria-label="Open resource monitor">
        <svg class="af-icon" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <rect x="2" y="6" width="20" height="12" rx="2" />
          <path d="M6 12h.01M10 12h.01M14 12h.01M18 12h.01" />
        </svg>
        <span class="af-label" class:af-label--warn={memoryWarning} class:af-label--degraded={health === null}>
          {health !== null ? `${healthMemMb} MB` : '-- MB'}
        </span>
      </button>

      <span class="af-sep" aria-hidden="true"></span>

      <svg class="af-icon" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
        <rect x="4" y="4" width="16" height="16" rx="2" />
        <rect x="9" y="9" width="6" height="6" />
        <path d="M9 2v2M15 2v2M9 20v2M15 20v2M2 9h2M2 15h2M20 9h2M20 15h2" />
      </svg>
      <span class="af-label" class:af-label--warn={cpuWarning} class:af-label--degraded={health === null}>
        {health !== null ? `${healthCpuPct}%` : '--%'}
      </span>

    <span class="af-sep" aria-hidden="true"></span>

    <!-- UI Zoom control -->
    <span class="af-zoom-wrap" bind:this={zoomDropdownEl}>
      <button
        class="af-zoom-btn"
        onclick={() => zoomOpen = !zoomOpen}
        aria-label="UI Zoom: {zoomPct}%"
        title="UI Zoom: {zoomPct}%"
      >
        <svg class="af-icon" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <circle cx="11" cy="11" r="7" />
          <path d="M21 21l-4.35-4.35" />
          <path d="M8 11h6M11 8v6" />
        </svg>
        <span class="af-label">{zoomPct}%</span>
      </button>

      {#if zoomOpen}
        <div class="af-zoom-dropdown" role="dialog" aria-label="UI Zoom">
          <div class="af-zoom-header">
            <span class="af-zoom-title">UI Zoom</span>
            <button class="af-zoom-reset" onclick={resetZoom}>Reset</button>
          </div>

          <div class="af-zoom-slider-row">
            <span class="af-zoom-bound">{ZOOM_MIN}%</span>
            <input
              type="range"
              class="af-zoom-slider"
              min={ZOOM_MIN}
              max={ZOOM_MAX}
              step={ZOOM_STEP}
              value={zoomPct}
              oninput={(e) => applyZoom(parseInt((e.target as HTMLInputElement).value, 10))}
              aria-label="Zoom slider"
            />
            <span class="af-zoom-bound">{ZOOM_MAX}%</span>
          </div>

          <div class="af-zoom-input-row">
            <button class="af-zoom-step-btn" onclick={zoomOut} disabled={zoomPct <= ZOOM_MIN} aria-label="Zoom out">−</button>
            <div class="af-zoom-input-wrap">
              <input
                type="text"
                class="af-zoom-input"
                bind:value={zoomInputValue}
                onblur={handleZoomInputBlur}
                onkeydown={handleZoomInputKey}
                aria-label="Zoom percentage"
              />
              <span class="af-zoom-input-suffix">%</span>
            </div>
            <button class="af-zoom-step-btn" onclick={zoomIn} disabled={zoomPct >= ZOOM_MAX} aria-label="Zoom in">+</button>
          </div>

          <div class="af-zoom-presets">
            {#each ZOOM_PRESETS as preset}
              <button
                class="af-zoom-preset"
                class:af-zoom-preset--active={zoomPct === preset}
                onclick={() => applyZoom(preset)}
              >
                {preset}%
              </button>
            {/each}
          </div>
        </div>
      {/if}
    </span>
  </div>
</footer>

{#if showResourceMonitor}
  <ResourceMonitor onClose={() => showResourceMonitor = false} />
{/if}

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

  .af-reconnect {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    padding: 1px 8px 1px 5px;
    border: 1px solid rgba(59, 130, 246, 0.25);
    border-radius: 4px;
    background: rgba(59, 130, 246, 0.08);
    color: rgba(59, 130, 246, 0.85);
    font-size: 10px;
    font-weight: 500;
    font-family: inherit;
    cursor: pointer;
    transition: all 150ms ease;
    animation: af-reconnect-attention 3s ease-in-out 2s 2;
  }

  .af-reconnect:hover:not(:disabled) {
    background: rgba(59, 130, 246, 0.15);
    color: #93bbfc;
    border-color: rgba(59, 130, 246, 0.4);
  }

  .af-reconnect:disabled {
    cursor: wait;
    opacity: 0.7;
  }

  .af-reconnect--busy {
    border-color: rgba(59, 130, 246, 0.15);
    animation: none;
  }

  .af-reconnect-icon {
    flex-shrink: 0;
  }

  .af-reconnect-icon--spin {
    animation: af-spin 800ms linear infinite;
  }

  @keyframes af-spin {
    from { transform: rotate(0deg); }
    to   { transform: rotate(360deg); }
  }

  @keyframes af-reconnect-attention {
    0%, 100% { border-color: rgba(59, 130, 246, 0.25); }
    50%      { border-color: rgba(59, 130, 246, 0.55); box-shadow: 0 0 6px rgba(59, 130, 246, 0.15); }
  }

  .af-label--degraded {
    color: var(--text-muted, rgba(255,255,255,0.2));
    font-style: italic;
  }

  /* Log button */
  .af-log-btn {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    padding: 0 4px;
    border: none;
    background: none;
    cursor: pointer;
    font-size: inherit;
    font-family: inherit;
    line-height: inherit;
    color: inherit;
    border-radius: 3px;
    transition: all 120ms ease;
  }

  .af-log-btn:hover {
    background: rgba(255,255,255,0.06);
    color: rgba(255,255,255,0.8);
  }

  .af-log-btn--active {
    background: rgba(59, 130, 246, 0.12);
    color: #60a5fa;
  }

  .af-log-btn--active:hover {
    background: rgba(59, 130, 246, 0.18);
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

  /* Memory button — looks inline but clickable */
  .af-mem-btn {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    padding: 0;
    border: none;
    background: none;
    cursor: pointer;
    font-size: inherit;
    font-family: inherit;
    line-height: inherit;
    color: inherit;
    border-radius: 3px;
    transition: background 120ms ease;
  }

  .af-mem-btn:hover {
    background: rgba(255,255,255,0.06);
  }

  /* OSA indicator */
  .af-osa-wrap {
    position: relative;
    display: inline-flex;
    align-items: center;
  }

  .af-osa-btn {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    padding: 0 2px;
    border: none;
    background: none;
    cursor: pointer;
    font-size: inherit;
    font-family: inherit;
    line-height: inherit;
    color: inherit;
    border-radius: 3px;
    transition: background 120ms ease;
  }

  .af-osa-btn:hover {
    background: rgba(255,255,255,0.06);
  }

  .af-osa-dropdown {
    position: absolute;
    bottom: calc(100% + 8px);
    left: 50%;
    transform: translateX(-50%);
    width: 200px;
    padding: 10px;
    border-radius: 8px;
    background: rgba(13, 17, 23, 0.97);
    border: 1px solid rgba(255,255,255,0.1);
    box-shadow: 0 8px 24px rgba(0,0,0,0.4);
    backdrop-filter: blur(12px);
    display: flex;
    flex-direction: column;
    gap: 8px;
    z-index: 10000;
  }

  .af-osa-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .af-osa-title {
    font-size: 11px;
    font-weight: 600;
    color: #e0e0e0;
  }

  .af-osa-status {
    font-size: 10px;
    font-weight: 500;
    padding: 1px 6px;
    border-radius: 3px;
    background: rgba(239, 68, 68, 0.12);
    color: rgba(239, 68, 68, 0.8);
  }

  .af-osa-status--running {
    background: rgba(34, 197, 94, 0.12);
    color: rgba(34, 197, 94, 0.8);
  }

  .af-osa-detail {
    font-size: 10px;
    color: rgba(255,255,255,0.4);
  }

  .af-osa-actions {
    display: flex;
    gap: 4px;
  }

  .af-osa-action {
    flex: 1;
    padding: 4px 8px;
    border: 1px solid rgba(255,255,255,0.1);
    border-radius: 4px;
    background: rgba(255,255,255,0.05);
    color: rgba(255,255,255,0.6);
    font-size: 10px;
    font-weight: 500;
    cursor: pointer;
    transition: all 120ms ease;
  }

  .af-osa-action:hover:not(:disabled) {
    background: rgba(255,255,255,0.1);
    color: rgba(255,255,255,0.9);
  }

  .af-osa-action:disabled {
    opacity: 0.5;
    cursor: wait;
  }

  .af-osa-action--primary {
    background: rgba(34, 197, 94, 0.1);
    border-color: rgba(34, 197, 94, 0.2);
    color: rgba(34, 197, 94, 0.8);
  }

  .af-osa-action--primary:hover:not(:disabled) {
    background: rgba(34, 197, 94, 0.2);
  }

  .af-osa-action--danger {
    background: rgba(239, 68, 68, 0.08);
    border-color: rgba(239, 68, 68, 0.15);
    color: rgba(239, 68, 68, 0.7);
  }

  .af-osa-action--danger:hover:not(:disabled) {
    background: rgba(239, 68, 68, 0.15);
  }

  /* ── Zoom control ─────────────────────────────────────────────────── */
  .af-zoom-wrap {
    position: relative;
    display: inline-flex;
    align-items: center;
  }

  .af-zoom-btn {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    padding: 0 4px;
    border: none;
    background: none;
    cursor: pointer;
    font-size: inherit;
    font-family: inherit;
    line-height: inherit;
    color: inherit;
    border-radius: 3px;
    transition: background 120ms ease;
  }

  .af-zoom-btn:hover {
    background: rgba(255,255,255,0.06);
  }

  .af-zoom-dropdown {
    position: absolute;
    bottom: calc(100% + 10px);
    right: 0;
    width: 260px;
    padding: 14px;
    border-radius: 10px;
    background: rgba(13, 17, 23, 0.97);
    border: 1px solid rgba(255,255,255,0.1);
    box-shadow: 0 12px 36px rgba(0,0,0,0.5);
    backdrop-filter: blur(16px);
    display: flex;
    flex-direction: column;
    gap: 12px;
    z-index: 10000;
    animation: af-zoom-in 150ms ease;
  }

  @keyframes af-zoom-in {
    from { opacity: 0; transform: translateY(6px); }
    to   { opacity: 1; transform: translateY(0); }
  }

  .af-zoom-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .af-zoom-title {
    font-size: 13px;
    font-weight: 600;
    color: #e0e0e0;
  }

  .af-zoom-reset {
    padding: 3px 10px;
    border: 1px solid rgba(255,255,255,0.12);
    border-radius: 5px;
    background: rgba(255,255,255,0.05);
    color: rgba(255,255,255,0.6);
    font-size: 11px;
    font-weight: 500;
    cursor: pointer;
    transition: all 120ms ease;
  }

  .af-zoom-reset:hover {
    background: rgba(255,255,255,0.1);
    color: rgba(255,255,255,0.9);
    border-color: rgba(255,255,255,0.2);
  }

  /* Slider row */
  .af-zoom-slider-row {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .af-zoom-bound {
    font-size: 10px;
    color: rgba(255,255,255,0.3);
    white-space: nowrap;
    min-width: 28px;
    text-align: center;
  }

  .af-zoom-slider {
    flex: 1;
    -webkit-appearance: none;
    appearance: none;
    height: 4px;
    border-radius: 2px;
    background: rgba(255,255,255,0.1);
    outline: none;
    cursor: pointer;
  }

  .af-zoom-slider::-webkit-slider-thumb {
    -webkit-appearance: none;
    appearance: none;
    width: 14px;
    height: 14px;
    border-radius: 50%;
    background: #3b82f6;
    border: 2px solid #1e3a5f;
    cursor: pointer;
    box-shadow: 0 1px 4px rgba(0,0,0,0.4);
    transition: transform 100ms ease;
  }

  .af-zoom-slider::-webkit-slider-thumb:hover {
    transform: scale(1.15);
  }

  .af-zoom-slider::-moz-range-thumb {
    width: 14px;
    height: 14px;
    border-radius: 50%;
    background: #3b82f6;
    border: 2px solid #1e3a5f;
    cursor: pointer;
  }

  /* +/- input row */
  .af-zoom-input-row {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .af-zoom-step-btn {
    width: 30px;
    height: 30px;
    display: flex;
    align-items: center;
    justify-content: center;
    border: 1px solid rgba(255,255,255,0.1);
    border-radius: 6px;
    background: rgba(255,255,255,0.04);
    color: rgba(255,255,255,0.6);
    font-size: 16px;
    font-weight: 500;
    cursor: pointer;
    transition: all 120ms ease;
    flex-shrink: 0;
  }

  .af-zoom-step-btn:hover:not(:disabled) {
    background: rgba(255,255,255,0.1);
    color: rgba(255,255,255,0.9);
    border-color: rgba(255,255,255,0.2);
  }

  .af-zoom-step-btn:disabled {
    opacity: 0.3;
    cursor: not-allowed;
  }

  .af-zoom-input-wrap {
    flex: 1;
    position: relative;
    display: flex;
    align-items: center;
  }

  .af-zoom-input {
    width: 100%;
    padding: 5px 24px 5px 10px;
    border: 1px solid rgba(255,255,255,0.1);
    border-radius: 6px;
    background: rgba(255,255,255,0.04);
    color: #e0e0e0;
    font-size: 16px;
    font-weight: 600;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    text-align: center;
    outline: none;
    transition: border-color 120ms ease;
  }

  .af-zoom-input:focus {
    border-color: rgba(59, 130, 246, 0.5);
  }

  .af-zoom-input-suffix {
    position: absolute;
    right: 10px;
    font-size: 12px;
    color: rgba(255,255,255,0.3);
    pointer-events: none;
  }

  /* Preset buttons row */
  .af-zoom-presets {
    display: flex;
    gap: 4px;
  }

  .af-zoom-preset {
    flex: 1;
    padding: 5px 0;
    border: 1px solid rgba(255,255,255,0.08);
    border-radius: 6px;
    background: rgba(255,255,255,0.03);
    color: rgba(255,255,255,0.5);
    font-size: 11px;
    font-weight: 500;
    cursor: pointer;
    transition: all 120ms ease;
  }

  .af-zoom-preset:hover {
    background: rgba(255,255,255,0.08);
    color: rgba(255,255,255,0.8);
    border-color: rgba(255,255,255,0.15);
  }

  .af-zoom-preset--active {
    background: rgba(59, 130, 246, 0.15);
    border-color: rgba(59, 130, 246, 0.3);
    color: #60a5fa;
    font-weight: 600;
  }

  .af-zoom-preset--active:hover {
    background: rgba(59, 130, 246, 0.2);
    color: #93bbfc;
  }

  @media (max-width: 640px) {
    .af-hide-sm { display: none; }
  }
</style>
