<!-- src/lib/components/office/VirtualOffice.svelte -->
<!-- Container: switches Pixel / 3D mode, renders detail panel -->
<script lang="ts">
  import type { BizforgeAgent } from '$api/types';
  import type { AgentOrgInfo } from '$lib/utils/orgColors';
  import PixelOffice from './pixel/PixelOffice.svelte';
  import Office3D from './Office3D.svelte';
  import OfficeDetailPanel from './OfficeDetailPanel.svelte';
  import OfficeChatModal from './OfficeChatModal.svelte';

  const CEO_STORAGE_KEY = 'bizforge:office:ceo';

  function readStoredCeo(): string | null {
    try {
      return localStorage.getItem(CEO_STORAGE_KEY);
    } catch {
      return null;
    }
  }

  interface Props {
    agents: BizforgeAgent[];
    viewMode?: '2d' | '3d';
    agentOrgMap?: Map<string, AgentOrgInfo>;
    onViewModeChange?: (mode: '2d' | '3d') => void;
  }

  let { agents, viewMode = '2d', agentOrgMap = new Map(), onViewModeChange }: Props = $props();
  let selectedAgent = $state<BizforgeAgent | null>(null);
  let legendOpen = $state(false);
  let chatOpen = $state(false);
  let ceoId = $state<string | null>(readStoredCeo());

  function setCeo(id: string | null): void {
    ceoId = id;
    try {
      if (id) localStorage.setItem(CEO_STORAGE_KEY, id);
      else localStorage.removeItem(CEO_STORAGE_KEY);
    } catch {
      /* localStorage unavailable */
    }
  }

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

  interface LegendTeam { id: string; name: string; color: string; count: number }
  interface LegendDivision { id: string; name: string; color: string; teams: LegendTeam[] }

  const legendData = $derived.by((): { divisions: LegendDivision[]; unassigned: number } => {
    const divMap = new Map<string, LegendDivision>();
    let unassigned = 0;

    for (const a of agents) {
      const info = agentOrgMap.get(a.id);
      if (info === undefined || info.teamId === null) {
        unassigned++;
        continue;
      }
      const divId = info.divisionId ?? '_none';
      let div = divMap.get(divId);
      if (div === undefined) {
        div = { id: divId, name: info.divisionName ?? 'Unknown', color: info.divisionColor ?? '#4a4a5a', teams: [] };
        divMap.set(divId, div);
      }
      let team = div.teams.find(t => t.id === info.teamId);
      if (team === undefined) {
        team = { id: info.teamId!, name: info.teamName ?? 'Unknown', color: info.teamColor ?? '#4a4a5a', count: 0 };
        div.teams.push(team);
      }
      team.count++;
    }

    return { divisions: [...divMap.values()], unassigned };
  });
</script>

<div class="vo-container" class:vo-panel-open={selectedAgent !== null}>
  {#if viewMode === '2d'}
    <!-- Pixel Art office — has its own toolbar, sidebar, minimap -->
    <div class="vo-pixel-wrap">
      <PixelOffice
        {agents}
        {agentOrgMap}
        selectedAgentId={selectedAgent?.id ?? null}
        onAgentClick={handleAgentClick}
      />
      <!-- Floating mode toggle -->
      <div class="vo-mode-float">
        <button class="vo-mode-btn vo-mode-btn--active" onclick={toggleMode}>Pixel</button>
        <button class="vo-mode-btn" onclick={toggleMode}>3D</button>
        <button class="vo-chat-btn" onclick={() => { chatOpen = true; }} title="Office Chat">Chat</button>
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
        <button class="vo-chat-btn" onclick={() => { chatOpen = true; }} title="Office Chat">Chat</button>
      </div>
    </div>
    <div class="vo-canvas">
      <Office3D
        {agents}
        {agentOrgMap}
        selectedAgentId={selectedAgent?.id ?? null}
        onAgentClick={handleAgentClick}
      />
    </div>
  {/if}

  {#if selectedAgent}
    <OfficeDetailPanel
      agent={selectedAgent}
      {agentOrgMap}
      ceoId={ceoId}
      onMakeCeo={() => setCeo(selectedAgent?.id ?? null)}
      onclose={handleClosePanel}
    />
  {/if}

  <OfficeChatModal open={chatOpen} {agents} onClose={() => { chatOpen = false; }} />

  <!-- Team / Division legend overlay -->
  {#if legendData.divisions.length > 0 || legendData.unassigned > 0}
    <div class="vo-legend" class:vo-legend--open={legendOpen}>
      <button class="vo-legend-toggle" onclick={() => { legendOpen = !legendOpen; }} aria-label="Toggle team legend">
        <svg width="14" height="14" viewBox="0 0 16 16" fill="none" aria-hidden="true">
          <rect x="1" y="1" width="5" height="5" rx="1" stroke="currentColor" stroke-width="1.4"/>
          <rect x="10" y="1" width="5" height="5" rx="1" stroke="currentColor" stroke-width="1.4"/>
          <rect x="1" y="10" width="5" height="5" rx="1" stroke="currentColor" stroke-width="1.4"/>
          <rect x="10" y="10" width="5" height="5" rx="1" stroke="currentColor" stroke-width="1.4"/>
        </svg>
        Teams
        <svg class="vo-legend-caret" class:vo-legend-caret--up={legendOpen} width="10" height="10" viewBox="0 0 10 10" fill="none" aria-hidden="true">
          <path d="M2 4L5 7L8 4" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>
      </button>
      {#if legendOpen}
        <div class="vo-legend-body">
          {#each legendData.divisions as div (div.id)}
            <div class="vo-legend-division">
              <div class="vo-legend-div-header">
                <span class="vo-legend-pip" style="background: {div.color};"></span>
                <span class="vo-legend-div-name">{div.name}</span>
              </div>
              {#each div.teams as team (team.id)}
                <div class="vo-legend-team">
                  <span class="vo-legend-swatch" style="background: {team.color};"></span>
                  <span class="vo-legend-team-name">{team.name}</span>
                  <span class="vo-legend-count">{team.count}</span>
                </div>
              {/each}
            </div>
          {/each}
          {#if legendData.unassigned > 0}
            <div class="vo-legend-team vo-legend-team--unassigned">
              <span class="vo-legend-swatch" style="background: #4a4a5a;"></span>
              <span class="vo-legend-team-name">Unassigned</span>
              <span class="vo-legend-count">{legendData.unassigned}</span>
            </div>
          {/if}
        </div>
      {/if}
    </div>
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
    background: var(--accent-primary, #fb923c);
    color: white;
  }
  .vo-mode-btn:hover:not(.vo-mode-btn--active) {
    color: var(--text-secondary);
  }
  .vo-chat-btn {
    padding: 4px 12px;
    border: none;
    border-radius: 6px;
    font-size: 11px;
    font-weight: 600;
    background: var(--bg-elevated);
    color: var(--accent-primary);
    cursor: pointer;
    margin-left: 4px;
    transition: all 120ms ease;
  }
  .vo-chat-btn:hover {
    background: var(--accent-primary);
    color: #fff;
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

  /* ── Legend overlay ──────────────────────────── */
  .vo-legend {
    position: absolute;
    bottom: 12px;
    left: 12px;
    z-index: 18;
    background: var(--glass-bg, rgba(15, 17, 23, 0.88));
    backdrop-filter: blur(12px);
    border: 1px solid var(--border-default, rgba(148, 163, 184, 0.12));
    border-radius: 10px;
    min-width: 140px;
    max-width: 220px;
    overflow: hidden;
    transition: box-shadow 200ms ease;
  }
  .vo-legend--open {
    box-shadow: 0 4px 24px rgba(0, 0, 0, 0.35);
  }
  .vo-legend-toggle {
    display: flex;
    align-items: center;
    gap: 6px;
    width: 100%;
    padding: 7px 12px;
    border: none;
    background: transparent;
    color: var(--text-tertiary, #8a94a8);
    font-size: 11px;
    font-weight: 600;
    cursor: pointer;
    transition: color 100ms ease;
  }
  .vo-legend-toggle:hover { color: var(--text-secondary, #c8c0d8); }
  .vo-legend-caret {
    margin-left: auto;
    transition: transform 150ms ease;
  }
  .vo-legend-caret--up { transform: rotate(180deg); }
  .vo-legend-body {
    padding: 0 10px 10px;
    display: flex;
    flex-direction: column;
    gap: 6px;
    max-height: 240px;
    overflow-y: auto;
  }
  .vo-legend-body::-webkit-scrollbar { width: 3px; }
  .vo-legend-body::-webkit-scrollbar-thumb { background: #2a2848; border-radius: 2px; }
  .vo-legend-division {
    display: flex;
    flex-direction: column;
    gap: 3px;
  }
  .vo-legend-div-header {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 2px 0;
  }
  .vo-legend-pip {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    flex-shrink: 0;
  }
  .vo-legend-div-name {
    font-size: 10px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    color: var(--text-tertiary, #6a6a8a);
  }
  .vo-legend-team {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 2px 0 2px 14px;
  }
  .vo-legend-team--unassigned {
    padding-left: 0;
    margin-top: 2px;
    border-top: 1px solid rgba(148, 163, 184, 0.08);
    padding-top: 6px;
  }
  .vo-legend-swatch {
    width: 10px;
    height: 3px;
    border-radius: 1.5px;
    flex-shrink: 0;
  }
  .vo-legend-team-name {
    font-size: 11px;
    color: var(--text-secondary, #c8c0d8);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    flex: 1;
  }
  .vo-legend-count {
    font-size: 10px;
    color: var(--text-tertiary, #6a6a8a);
    font-variant-numeric: tabular-nums;
    flex-shrink: 0;
  }
</style>
