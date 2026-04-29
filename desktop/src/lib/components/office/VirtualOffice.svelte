<!-- src/lib/components/office/VirtualOffice.svelte -->
<!-- Container: switches Pixel / 3D mode, renders detail panel -->
<script lang="ts">
  import type { BizforgeAgent } from '$api/types';
  import PixelOffice from './pixel/PixelOffice.svelte';
  import Office3D from './Office3D.svelte';
  import OfficeDetailPanel from './OfficeDetailPanel.svelte';

  interface Props {
    agents: BizforgeAgent[];
    viewMode?: '2d' | '3d';
    onViewModeChange?: (mode: '2d' | '3d') => void;
  }

  let { agents, viewMode = '2d', onViewModeChange }: Props = $props();
  let selectedAgent = $state<BizforgeAgent | null>(null);

  function handleAgentClick(agent: BizforgeAgent) {
    selectedAgent = selectedAgent?.id === agent.id ? null : agent;
  }

  function handleClosePanel() {
    selectedAgent = null;
  }

  function toggleMode() {
    const next = viewMode === '2d' ? '3d' : '2d';
    onViewModeChange?.(next);
  }
</script>

<div class="vo-container" class:vo-panel-open={selectedAgent !== null}>
  {#if viewMode === '2d'}
    <!-- Pixel Art office — has its own toolbar, sidebar, minimap -->
    <div class="vo-pixel-wrap">
      <PixelOffice
        {agents}
        selectedAgentId={selectedAgent?.id ?? null}
        onAgentClick={handleAgentClick}
      />
      <!-- Floating mode toggle -->
      <div class="vo-mode-float">
        <button class="vo-mode-btn vo-mode-btn--active" onclick={toggleMode}>Pixel</button>
        <button class="vo-mode-btn" onclick={toggleMode}>3D</button>
      </div>
    </div>
  {:else}
    <!-- 3D mode with outer toolbar -->
    <div class="vo-toolbar">
      <div class="vo-stats">
        <span class="vo-stat">
          <span class="vo-dot vo-dot--active"></span>
          {agents.filter(a => a.status === 'running' || a.status === 'idle').length} active
        </span>
        <span class="vo-stat">
          {agents.length} total
        </span>
      </div>
      <div class="vo-mode-toggle" role="group" aria-label="View mode">
        <button class="vo-mode-btn" onclick={toggleMode}>Pixel</button>
        <button class="vo-mode-btn vo-mode-btn--active" onclick={toggleMode}>3D</button>
      </div>
    </div>
    <div class="vo-canvas">
      <Office3D
        {agents}
        selectedAgentId={selectedAgent?.id ?? null}
        onAgentClick={handleAgentClick}
      />
    </div>
  {/if}

  {#if selectedAgent}
    <OfficeDetailPanel agent={selectedAgent} onclose={handleClosePanel} />
  {/if}
</div>

<style>
  .vo-container {
    display: flex;
    flex-direction: column;
    height: 100%;
    position: relative;
    overflow: hidden;
  }
  .vo-pixel-wrap {
    flex: 1;
    min-height: 0;
    position: relative;
  }
  .vo-mode-float {
    position: absolute;
    top: 6px;
    right: 50%;
    transform: translateX(50%);
    display: flex;
    gap: 2px;
    background: var(--glass-bg, rgba(22, 27, 38, 0.82));
    border-radius: 8px;
    padding: 2px;
    z-index: 20;
    border: 1px solid var(--border-default, rgba(148, 163, 184, 0.12));
    backdrop-filter: blur(12px);
  }
  .vo-toolbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 8px 16px;
    border-bottom: 1px solid var(--border-default);
    background: var(--bg-secondary);
    flex-shrink: 0;
  }
  .vo-stats {
    display: flex;
    gap: 16px;
    font-size: 12px;
    color: var(--text-tertiary);
  }
  .vo-stat {
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .vo-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: #6b7a8d;
  }
  .vo-dot--active { background: #6ee7b7; }
  .vo-mode-toggle {
    display: flex;
    gap: 2px;
    background: var(--bg-elevated);
    border-radius: 8px;
    padding: 2px;
  }
  .vo-mode-btn {
    padding: 4px 12px;
    border: none;
    border-radius: 6px;
    font-size: 11px;
    font-weight: 600;
    background: transparent;
    color: var(--text-tertiary);
    cursor: pointer;
    transition: all 120ms ease;
  }
  .vo-mode-btn--active {
    background: var(--accent-primary, #a78bfa);
    color: white;
  }
  .vo-mode-btn:hover:not(.vo-mode-btn--active) {
    color: var(--text-secondary);
  }
  .vo-canvas {
    flex: 1;
    min-height: 0;
    background: var(--bg-primary, #0f1117);
  }
  .vo-panel-open .vo-canvas,
  .vo-panel-open .vo-pixel-wrap {
    margin-right: 320px;
  }
</style>
