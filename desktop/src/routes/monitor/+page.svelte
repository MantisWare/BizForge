<!-- src/routes/monitor/+page.svelte -->
<!-- Headless stats dashboard — workspace selector → information-dense dark-theme monitoring -->
<script lang="ts">
  import WorkspaceHeader from '$lib/components/monitor/WorkspaceHeader.svelte';
  import SystemHealth from '$lib/components/monitor/SystemHealth.svelte';
  import AgentActivity from '$lib/components/monitor/AgentActivity.svelte';
  import TaskFlow from '$lib/components/monitor/TaskFlow.svelte';
  import TokenBurn from '$lib/components/monitor/TokenBurn.svelte';
  import BudgetGauge from '$lib/components/monitor/BudgetGauge.svelte';
  import HeartbeatTimeline from '$lib/components/monitor/HeartbeatTimeline.svelte';
  import LogStream from '$lib/components/monitor/LogStream.svelte';
  import AlertPanel from '$lib/components/monitor/AlertPanel.svelte';
  import QuickActions from '$lib/components/monitor/QuickActions.svelte';
  import { monitorStore } from '$lib/stores/monitor.svelte';
  import type { Workspace } from '$api/types';

  function handleKeydown(e: KeyboardEvent): void {
    if (e.target instanceof HTMLInputElement) return;
    if (monitorStore.selectingWorkspace) return;
    switch (e.key) {
      case 'p':
        monitorStore.pauseAll();
        break;
      case 'r':
        monitorStore.resumeAll();
        break;
      case 'Escape':
        monitorStore.backToSelector();
        break;
    }
  }

  function selectWorkspace(ws: Workspace): void {
    monitorStore.selectWorkspace(ws);
  }
</script>

<svelte:window on:keydown={handleKeydown} />

{#if monitorStore.selectingWorkspace}
  <!-- Workspace selector screen -->
  <div class="selector-screen">
    <div class="selector-card">
      <div class="selector-logo">BF</div>
      <h1 class="selector-title">Bizforge Monitor</h1>
      <p class="selector-subtitle">Select a workspace to monitor</p>

      <div class="workspace-list">
        {#if monitorStore.availableWorkspaces.length === 0}
          <div class="ws-empty">
            <span class="ws-empty-icon">\u2014</span>
            <span>No workspaces found.</span>
            <span class="ws-empty-hint">Create a workspace in the Command Center first.</span>
          </div>
        {:else}
          {#each monitorStore.availableWorkspaces as ws (ws.id)}
            <button class="ws-option" onclick={() => selectWorkspace(ws)}>
              <div class="ws-option-left">
                <span class="ws-option-name">{ws.name}</span>
                <span class="ws-option-path">{ws.path ?? ws.id}</span>
              </div>
              <div class="ws-option-right">
                <span class="ws-option-status" class:active={ws.status === 'active'}>
                  {ws.status ?? 'unknown'}
                </span>
                <span class="ws-option-arrow">\u2192</span>
              </div>
            </button>
          {/each}
        {/if}
      </div>
    </div>
  </div>
{:else}
  <!-- Dashboard -->
  <div class="monitor-dashboard">
    <WorkspaceHeader />

    <div class="monitor-grid">
      <div class="monitor-panel panel-health">
        <SystemHealth />
      </div>

      <div class="monitor-panel panel-agents">
        <AgentActivity />
      </div>

      <div class="monitor-panel panel-tasks">
        <TaskFlow />
      </div>

      <div class="monitor-panel panel-burn">
        <TokenBurn />
      </div>

      <div class="monitor-panel panel-budget">
        <BudgetGauge />
      </div>

      <div class="monitor-panel panel-actions">
        <QuickActions />
      </div>

      <div class="monitor-panel panel-timeline">
        <HeartbeatTimeline />
      </div>

      <div class="monitor-panel panel-logs">
        <LogStream />
      </div>

      <div class="monitor-panel panel-alerts">
        <AlertPanel />
      </div>
    </div>
  </div>
{/if}

<style>
  /* ── Workspace selector ────────────────────────────────────────── */
  .selector-screen {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    padding-top: 36px;
  }

  .selector-card {
    display: flex;
    flex-direction: column;
    align-items: center;
    width: 100%;
    max-width: 480px;
    padding: 32px;
  }

  .selector-logo {
    width: 48px;
    height: 48px;
    border-radius: 10px;
    background: linear-gradient(135deg, #f26522, #e04b18);
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: 800;
    font-size: 18px;
    color: #fff;
    margin-bottom: 16px;
  }

  .selector-title {
    font-size: 22px;
    font-weight: 700;
    color: #f1f5f9;
    margin: 0 0 4px;
  }

  .selector-subtitle {
    font-size: 13px;
    color: #64748b;
    margin: 0 0 24px;
  }

  .workspace-list {
    width: 100%;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .ws-empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 8px;
    padding: 32px 16px;
    color: #475569;
    font-size: 13px;
  }

  .ws-empty-icon { font-size: 20px; opacity: 0.5; }
  .ws-empty-hint { font-size: 11px; color: #334155; }

  .ws-option {
    display: flex;
    align-items: center;
    justify-content: space-between;
    width: 100%;
    padding: 12px 16px;
    background: #111827;
    border: 1px solid #1e293b;
    border-radius: 8px;
    color: #e2e8f0;
    cursor: pointer;
    transition: background 0.15s, border-color 0.15s;
    text-align: left;
  }

  .ws-option:hover {
    background: #1e293b;
    border-color: #334155;
  }

  .ws-option-left {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }

  .ws-option-name {
    font-size: 14px;
    font-weight: 600;
    color: #f1f5f9;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .ws-option-path {
    font-size: 11px;
    color: #64748b;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .ws-option-right {
    display: flex;
    align-items: center;
    gap: 10px;
    flex-shrink: 0;
  }

  .ws-option-status {
    font-size: 10px;
    font-weight: 600;
    text-transform: uppercase;
    color: #64748b;
    background: #64748b15;
    padding: 2px 8px;
    border-radius: 4px;
  }

  .ws-option-status.active {
    color: #22c55e;
    background: #22c55e15;
  }

  .ws-option-arrow {
    font-size: 16px;
    color: #475569;
    transition: transform 0.15s;
  }

  .ws-option:hover .ws-option-arrow {
    transform: translateX(2px);
    color: #f26522;
  }

  /* ── Dashboard ─────────────────────────────────────────────────── */
  .monitor-dashboard {
    flex: 1;
    display: flex;
    flex-direction: column;
    padding: 8px 12px 12px;
    gap: 8px;
    overflow: hidden;
    padding-top: 36px;
  }

  .monitor-grid {
    flex: 1;
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    grid-template-rows: auto 1fr 1fr;
    gap: 8px;
    min-height: 0;
  }

  .monitor-panel {
    background: #111827;
    border: 1px solid #1e293b;
    border-radius: 8px;
    padding: 12px;
    overflow: hidden;
    display: flex;
    flex-direction: column;
  }

  .panel-health { grid-column: 1; grid-row: 1; }
  .panel-agents { grid-column: 2; grid-row: 1; }
  .panel-tasks { grid-column: 3; grid-row: 1; }
  .panel-burn { grid-column: 4; grid-row: 1; }

  .panel-budget { grid-column: 1; grid-row: 2; }
  .panel-actions { grid-column: 1; grid-row: 3; }
  .panel-timeline { grid-column: 2 / 4; grid-row: 2 / 4; }
  .panel-logs { grid-column: 4; grid-row: 2; }
  .panel-alerts { grid-column: 4; grid-row: 3; }
</style>
