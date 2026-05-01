<!-- src/lib/components/layout/ResourceMonitor.svelte
     Floating popover showing system resources, BizForge memory, and recent AI calls.
     Triggered from the footer memory label. -->
<script lang="ts">
  import { isTauri } from '$lib/utils/platform';
  import { dashboardStore } from '$lib/stores/dashboard.svelte';
  import { dashboard } from '$api/client';
  import type { RecentAiCall, SystemHealth } from '$api/types';

  interface SystemResourceInfo {
    memory_total_gb: number;
    memory_used_gb: number;
    memory_free_gb: number;
    memory_used_pct: number;
    cpu_usage_pct: number;
    cpu_cores: number;
    cpu_brand: string;
    os_name: string;
    os_arch: string;
    hostname: string;
    pid: number;
    app_memory_mb: number;
    uptime_seconds: number;
  }

  interface Props {
    onClose: () => void;
  }

  let { onClose }: Props = $props();

  let sysInfo = $state<SystemResourceInfo | null>(null);
  let recentCalls = $state<RecentAiCall[]>([]);
  let loading = $state(true);
  let pollTimer = $state<ReturnType<typeof setInterval> | null>(null);

  const health: SystemHealth | null = $derived(dashboardStore.systemHealth);

  async function fetchSystemResources(): Promise<void> {
    if (isTauri()) {
      try {
        const { invoke } = await import('@tauri-apps/api/core');
        sysInfo = await invoke<SystemResourceInfo>('get_system_resources');
      } catch {
        sysInfo = null;
      }
    }
  }

  async function fetchRecentCalls(): Promise<void> {
    try {
      const resp = await dashboard.recentAiCalls(10);
      recentCalls = resp.data;
    } catch {
      recentCalls = [];
    }
  }

  async function refresh(): Promise<void> {
    await Promise.all([fetchSystemResources(), fetchRecentCalls()]);
    loading = false;
  }

  $effect(() => {
    void refresh();
    pollTimer = setInterval(() => void refresh(), 5000);
    return () => {
      if (pollTimer !== null) clearInterval(pollTimer);
    };
  });

  function formatUptime(seconds: number): string {
    if (seconds < 60) return `${seconds}s`;
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    return `${h}h ${m}m`;
  }

  function formatTimeAgo(isoDate: string): string {
    const diff = Date.now() - new Date(isoDate).getTime();
    const seconds = Math.floor(diff / 1000);
    if (seconds < 60) return `${seconds}s ago`;
    const minutes = Math.floor(seconds / 60);
    if (minutes < 60) return `${minutes}m ago`;
    const hours = Math.floor(minutes / 60);
    if (hours < 24) return `${hours}h ago`;
    return `${Math.floor(hours / 24)}d ago`;
  }

  function formatCost(cents: number): string {
    if (cents === 0) return '$0';
    if (cents < 1) return `$${(cents / 100).toFixed(4)}`;
    return `$${(cents / 100).toFixed(3)}`;
  }

  function handleBackdropClick(e: MouseEvent) {
    if ((e.target as HTMLElement).classList.contains('rm-backdrop')) {
      onClose();
    }
  }
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<div class="rm-backdrop" onmousedown={handleBackdropClick}>
  <div class="rm-panel" role="dialog" aria-label="Resource Monitor">
    <!-- Header -->
    <div class="rm-header">
      <div>
        <span class="rm-title">BizForge Resource Monitor</span>
        {#if sysInfo !== null}
          <span class="rm-uptime">Uptime: {formatUptime(sysInfo.uptime_seconds)}</span>
        {/if}
      </div>
      <button class="rm-close" onclick={onClose} aria-label="Close">
        <svg viewBox="0 0 16 16" fill="currentColor" width="12" height="12"><path d="M3.72 3.72a.75.75 0 0 1 1.06 0L8 6.94l3.22-3.22a.75.75 0 1 1 1.06 1.06L9.06 8l3.22 3.22a.75.75 0 1 1-1.06 1.06L8 9.06l-3.22 3.22a.75.75 0 0 1-1.06-1.06L6.94 8 3.72 4.78a.75.75 0 0 1 0-1.06Z"/></svg>
      </button>
    </div>

    {#if loading}
      <div class="rm-loading">Loading system info...</div>
    {:else}
      <!-- System Memory -->
      {#if sysInfo !== null}
        <div class="rm-section">
          <div class="rm-row">
            <span class="rm-label">System Memory</span>
            <span class="rm-value">{sysInfo.memory_used_gb} / {sysInfo.memory_total_gb} GB</span>
          </div>
          <div class="rm-bar-track">
            <div class="rm-bar-fill rm-bar--memory" style="width: {sysInfo.memory_used_pct}%"></div>
          </div>
          <span class="rm-sub">{sysInfo.memory_used_pct}% used &bull; {sysInfo.memory_free_gb} GB free</span>
        </div>
      {/if}

      <!-- BizForge Memory -->
      <div class="rm-section">
        <div class="rm-row">
          <span class="rm-label">BizForge Memory</span>
          <span class="rm-value rm-value--accent">{health?.memory_mb ?? 0} MB</span>
        </div>
        {#if health?.heap_mb !== undefined && health.heap_total_mb !== undefined}
          <div class="rm-bar-track">
            <div
              class="rm-bar-fill rm-bar--app"
              style="width: {health.heap_total_mb > 0 ? Math.min((health.heap_mb / health.heap_total_mb) * 100, 100) : 0}%"
            ></div>
          </div>
          <span class="rm-sub">Heap: {health.heap_mb} MB / {health.heap_total_mb} MB</span>
        {/if}
      </div>

      <!-- CPU Usage -->
      {#if sysInfo !== null}
        <div class="rm-section">
          <div class="rm-row">
            <span class="rm-label">CPU Usage</span>
            <span class="rm-value">{sysInfo.cpu_usage_pct}%</span>
          </div>
          <div class="rm-bar-track">
            <div class="rm-bar-fill rm-bar--cpu" style="width: {sysInfo.cpu_usage_pct}%"></div>
          </div>
          <span class="rm-sub">{sysInfo.cpu_cores} cores &bull; {sysInfo.cpu_brand}</span>
        </div>
      {/if}

      <!-- Recent AI Calls -->
      <div class="rm-section">
        <div class="rm-row">
          <span class="rm-label">
            <svg viewBox="0 0 16 16" fill="currentColor" width="12" height="12" style="vertical-align: -1px; margin-right: 3px; opacity: 0.5;"><path d="M8 0a8 8 0 1 1 0 16A8 8 0 0 1 8 0ZM1.5 8a6.5 6.5 0 1 0 13 0 6.5 6.5 0 0 0-13 0Zm7-3.25v2.992l2.028.812a.75.75 0 0 1-.557 1.392l-2.5-1A.751.751 0 0 1 7 8.25v-3.5a.75.75 0 0 1 1.5 0Z"/></svg>
            Recent AI Calls
          </span>
          <span class="rm-sub">{recentCalls.length} recent</span>
        </div>
        <div class="rm-calls">
          {#each recentCalls as call}
            <div class="rm-call-row">
              <span class="rm-call-dot" class:rm-call-dot--green={call.cost_cents < 10} class:rm-call-dot--yellow={call.cost_cents >= 10 && call.cost_cents < 100} class:rm-call-dot--red={call.cost_cents >= 100}></span>
              <div class="rm-call-info">
                <span class="rm-call-model">{call.model}</span>
                {#if call.tokens_input > 0 || call.tokens_output > 0}
                  <span class="rm-call-tokens">
                    {(call.tokens_input / 1000).toFixed(1)}K in / {(call.tokens_output / 1000).toFixed(1)}K out
                    {#if call.cost_cents > 0}
                      {formatCost(call.cost_cents)}
                    {/if}
                  </span>
                {/if}
              </div>
              <span class="rm-call-time">{formatTimeAgo(call.inserted_at)}</span>
            </div>
          {:else}
            <span class="rm-sub" style="padding: 8px 0;">No recent calls</span>
          {/each}
        </div>
      </div>

      <!-- Platform Footer -->
      {#if sysInfo !== null}
        <div class="rm-platform">
          {sysInfo.os_name} {sysInfo.os_arch} &bull; PID: {sysInfo.pid}
        </div>
      {/if}
    {/if}
  </div>
</div>

<style>
  .rm-backdrop {
    position: fixed;
    inset: 0;
    z-index: 9999;
  }

  .rm-panel {
    position: fixed;
    bottom: 28px;
    right: 12px;
    width: 380px;
    max-height: calc(100vh - 60px);
    overflow-y: auto;
    border-radius: 10px;
    background: rgba(13, 17, 23, 0.97);
    border: 1px solid rgba(255, 255, 255, 0.08);
    box-shadow: 0 12px 40px rgba(0, 0, 0, 0.5), 0 0 0 1px rgba(255, 255, 255, 0.04);
    backdrop-filter: blur(16px);
    padding: 14px;
    display: flex;
    flex-direction: column;
    gap: 12px;
    z-index: 10000;
  }

  .rm-header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 8px;
  }

  .rm-title {
    font-size: 13px;
    font-weight: 700;
    color: #e0e0e0;
    display: block;
  }

  .rm-uptime {
    font-size: 10px;
    color: rgba(255, 255, 255, 0.35);
  }

  .rm-close {
    padding: 4px;
    border: none;
    background: rgba(255, 255, 255, 0.06);
    border-radius: 4px;
    color: rgba(255, 255, 255, 0.4);
    cursor: pointer;
    transition: all 120ms ease;
    flex-shrink: 0;
  }

  .rm-close:hover {
    background: rgba(255, 255, 255, 0.12);
    color: rgba(255, 255, 255, 0.8);
  }

  .rm-loading {
    font-size: 11px;
    color: rgba(255, 255, 255, 0.35);
    padding: 20px 0;
    text-align: center;
  }

  .rm-section {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .rm-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .rm-label {
    font-size: 11px;
    font-weight: 600;
    color: rgba(255, 255, 255, 0.65);
  }

  .rm-value {
    font-size: 12px;
    font-weight: 700;
    color: #e0e0e0;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  }

  .rm-value--accent {
    color: #60a5fa;
  }

  .rm-sub {
    font-size: 10px;
    color: rgba(255, 255, 255, 0.3);
  }

  .rm-bar-track {
    height: 4px;
    border-radius: 2px;
    background: rgba(255, 255, 255, 0.06);
    overflow: hidden;
  }

  .rm-bar-fill {
    height: 100%;
    border-radius: 2px;
    transition: width 300ms ease;
  }

  .rm-bar--memory { background: #3b82f6; }
  .rm-bar--app { background: #60a5fa; }
  .rm-bar--cpu { background: #eab308; }

  .rm-calls {
    display: flex;
    flex-direction: column;
    gap: 1px;
    max-height: 240px;
    overflow-y: auto;
  }

  .rm-call-row {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 8px;
    border-radius: 5px;
    background: rgba(255, 255, 255, 0.02);
    border: 1px solid rgba(255, 255, 255, 0.04);
    transition: background 120ms ease;
  }

  .rm-call-row:hover {
    background: rgba(255, 255, 255, 0.05);
  }

  .rm-call-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    flex-shrink: 0;
  }

  .rm-call-dot--green { background: #22c55e; }
  .rm-call-dot--yellow { background: #eab308; }
  .rm-call-dot--red { background: #ef4444; }

  .rm-call-info {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 1px;
  }

  .rm-call-model {
    font-size: 11px;
    font-weight: 600;
    color: rgba(255, 255, 255, 0.7);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .rm-call-tokens {
    font-size: 9.5px;
    color: rgba(255, 255, 255, 0.3);
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  }

  .rm-call-time {
    font-size: 10px;
    color: rgba(255, 255, 255, 0.25);
    white-space: nowrap;
    flex-shrink: 0;
  }

  .rm-platform {
    font-size: 10px;
    color: rgba(255, 255, 255, 0.2);
    text-align: center;
    padding-top: 4px;
    border-top: 1px solid rgba(255, 255, 255, 0.04);
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  }
</style>
