<!-- Pixel Art Virtual Office — Canvas 2D game-style renderer -->
<!-- Renders agents as pixel art characters in a tile-based office with rooms, furniture, and animations -->
<script lang="ts">
  import { onMount, untrack } from 'svelte';
  import type { BizforgeAgent } from '$api/types';
  import type { AgentOrgInfo } from '$lib/utils/orgColors';
  import type { Camera, OfficeCharacter, TimeOfDay } from './types';
  import { CharacterState } from './types';
  import { createDefaultLayout, findPath, SEATS } from './layout';
  import { renderOffice, renderMinimap, hitTestCharacter } from './renderer';
  import { clearSpriteCache } from './sprites';

  interface Props {
    agents: BizforgeAgent[];
    agentOrgMap?: Map<string, AgentOrgInfo>;
    selectedAgentId?: string | null;
    onAgentClick?: (agent: BizforgeAgent) => void;
  }

  let { agents, agentOrgMap = new Map(), selectedAgentId = null, onAgentClick }: Props = $props();

  let canvasEl: HTMLCanvasElement | undefined = $state();
  let minimapEl: HTMLCanvasElement | undefined = $state();
  let containerEl: HTMLDivElement | undefined = $state();
  let width = $state(800);
  let height = $state(600);
  let timeOfDay = $state<TimeOfDay>('day');
  let hoveredCharId = $state<string | null>(null);
  let showMinimap = $state(true);
  let showEvents = $state(true);
  let showSidebar = $state(true);
  let events = $state<{ time: string; text: string; color: string }[]>([]);

  const layout = createDefaultLayout();
  const WALK_SPEED = 48; // pixels per second
  const ANIM_SPEED = 4; // frames per second

  // Camera state
  let camera: Camera = {
    x: layout.cols * layout.tileSize / 2,
    y: layout.rows * layout.tileSize / 2,
    zoom: 3,
    targetX: layout.cols * layout.tileSize / 2,
    targetY: layout.rows * layout.tileSize / 2,
    targetZoom: 3,
    isDragging: false,
    dragStartX: 0,
    dragStartY: 0,
    dragStartCamX: 0,
    dragStartCamY: 0,
  };

  // Characters map
  let characters: OfficeCharacter[] = $state([]);

  // ─── Agent → Character sync ─────────────────────────────
  function statusToColor(status: string): string {
    switch (status) {
      case 'running': return '#6ee7b7';
      case 'idle': return '#fb923c';
      case 'sleeping': return '#6b7a8d';
      case 'paused': return '#fcd34d';
      case 'terminated': case 'error': return '#fca5a5';
      default: return '#8a94a8';
    }
  }

  function statusToCharState(status: string): CharacterState {
    switch (status) {
      case 'running': return CharacterState.TYPE;
      case 'idle': return CharacterState.IDLE;
      case 'sleeping': return CharacterState.SLEEP;
      case 'paused': return CharacterState.IDLE;
      default: return CharacterState.IDLE;
    }
  }

  // Sync agents to characters whenever agents change
  // NOTE: We untrack `characters` to avoid an infinite loop — the effect
  // reads characters (to preserve positions) and writes characters, which
  // would re-trigger itself endlessly without untrack.
  $effect(() => {
    // Track agents (this is the real dependency)
    const _agents = agents;

    // Read existing characters WITHOUT tracking — prevents infinite loop
    const existingChars = untrack(() => characters);
    const existingMap = new Map(existingChars.map(c => [c.id, c]));

    const newChars: OfficeCharacter[] = [];

    _agents.forEach((agent, i) => {
      const existing = existingMap.get(agent.id);
      const seat = SEATS[i % SEATS.length];
      const newState = statusToCharState(agent.status);

      if (existing) {
        const prevState = existing.state;
        const orgInfo = agentOrgMap.get(agent.id);
        existing.state = newState;
        existing.statusColor = statusToColor(agent.status);
        existing.teamColor = orgInfo?.teamColor ?? undefined;
        existing.divisionColor = orgInfo?.divisionColor ?? undefined;
        existing.currentTask = agent.current_task ?? undefined;
        existing.name = agent.display_name ?? agent.name;

        // If agent became active, walk to seat
        if (newState === CharacterState.TYPE && prevState !== CharacterState.TYPE) {
          if (existing.gridX !== seat.gridX || existing.gridY !== seat.gridY) {
            const path = findPath(layout.walkable, existing.gridX, existing.gridY, seat.gridX, seat.gridY, layout.cols, layout.rows);
            if (path.length > 0) {
              existing.path = path;
              existing.state = CharacterState.WALK;
            }
          }
        }
        newChars.push(existing);
      } else {
        // Create new character at seat
        const orgInfo = agentOrgMap.get(agent.id);
        newChars.push({
          id: agent.id,
          name: agent.display_name ?? agent.name,
          color: '',
          skinTone: '',
          hairColor: '',
          state: newState,
          facing: seat.facing,
          gridX: seat.gridX,
          gridY: seat.gridY,
          targetX: seat.gridX,
          targetY: seat.gridY,
          moveProgress: 0,
          path: [],
          seatX: seat.gridX,
          seatY: seat.gridY,
          seatFacing: seat.facing,
          animFrame: 0,
          animTimer: 0,
          statusColor: statusToColor(agent.status),
          teamColor: orgInfo?.teamColor ?? undefined,
          divisionColor: orgInfo?.divisionColor ?? undefined,
          currentTask: agent.current_task ?? undefined,
          bubbleTimer: 3,
        });

        // Add spawn event
        untrack(() => addEvent(`${agent.display_name ?? agent.name} joined the office`, '#fb923c'));
      }
    });

    characters = newChars;
  });

  // ─── Events ─────────────────────────────────────────────
  function addEvent(text: string, color: string) {
    const time = new Date().toLocaleTimeString('en-US', { hour12: false, hour: '2-digit', minute: '2-digit' });
    events = [{ time, text, color }, ...events.slice(0, 19)];
  }

  // ─── Game loop ──────────────────────────────────────────
  let rafId = 0;
  let lastTime = 0;

  function gameLoop(timestamp: number) {
    const dt = Math.min((timestamp - lastTime) / 1000, 0.1); // cap at 100ms
    lastTime = timestamp;

    // Update characters
    for (const char of characters) {
      // Animation timer
      char.animTimer += dt;
      if (char.animTimer >= 1 / ANIM_SPEED) {
        char.animTimer = 0;
        char.animFrame++;
      }

      // Bubble timer decay
      if (char.bubbleTimer > 0) {
        char.bubbleTimer -= dt;
      }

      // Movement
      if (char.path.length > 0) {
        char.state = CharacterState.WALK;
        const [nextX, nextY] = char.path[0];
        char.targetX = nextX;
        char.targetY = nextY;

        // Direction
        if (nextX > char.gridX) char.facing = 'right';
        else if (nextX < char.gridX) char.facing = 'left';
        else if (nextY > char.gridY) char.facing = 'down';
        else if (nextY < char.gridY) char.facing = 'up';

        char.moveProgress += (WALK_SPEED * dt) / layout.tileSize;

        if (char.moveProgress >= 1) {
          char.gridX = nextX;
          char.gridY = nextY;
          char.moveProgress = 0;
          char.path.shift();

          // Arrived at seat?
          if (char.path.length === 0) {
            char.facing = char.seatFacing;
            // Restore intended state
            const agent = agents.find(a => a.id === char.id);
            if (agent) {
              char.state = statusToCharState(agent.status);
            } else {
              char.state = CharacterState.IDLE;
            }
          }
        }
      }

      // Idle wandering (if idle and at seat for a while)
      if (char.state === CharacterState.IDLE && char.path.length === 0) {
        // Random chance to wander
        if (Math.random() < 0.001) {
          const rx = char.gridX + Math.floor(Math.random() * 5) - 2;
          const ry = char.gridY + Math.floor(Math.random() * 5) - 2;
          if (rx >= 0 && rx < layout.cols && ry >= 0 && ry < layout.rows && layout.walkable[ry]?.[rx]) {
            const path = findPath(layout.walkable, char.gridX, char.gridY, rx, ry, layout.cols, layout.rows);
            if (path.length > 0 && path.length < 8) {
              char.path = [...path, ...findPath(layout.walkable, rx, ry, char.seatX, char.seatY, layout.cols, layout.rows)];
            }
          }
        }
      }
    }

    // Smooth camera
    camera.x += (camera.targetX - camera.x) * 0.1;
    camera.y += (camera.targetY - camera.y) * 0.1;
    camera.zoom += (camera.targetZoom - camera.zoom) * 0.15;

    // Render
    if (canvasEl) {
      const ctx = canvasEl.getContext('2d');
      if (ctx) {
        renderOffice(
          ctx, width, height, layout, camera, characters,
          timeOfDay, selectedAgentId, hoveredCharId, timestamp,
        );
      }
    }

    // Render minimap
    if (minimapEl && showMinimap) {
      const mCtx = minimapEl.getContext('2d');
      if (mCtx) {
        renderMinimap(mCtx, layout, characters, camera, width, height, 160, 110);
      }
    }

    rafId = requestAnimationFrame(gameLoop);
  }

  // ─── Input handlers ─────────────────────────────────────
  function handleMouseDown(e: MouseEvent) {
    if (e.button === 1 || (e.button === 0 && e.altKey)) {
      // Middle click or Alt+Click = pan
      camera.isDragging = true;
      camera.dragStartX = e.clientX;
      camera.dragStartY = e.clientY;
      camera.dragStartCamX = camera.targetX;
      camera.dragStartCamY = camera.targetY;
      e.preventDefault();
    } else if (e.button === 0) {
      // Left click = select agent
      const rect = canvasEl!.getBoundingClientRect();
      const cx = e.clientX - rect.left;
      const cy = e.clientY - rect.top;
      const hit = hitTestCharacter(cx, cy, camera, width, height, characters, layout.tileSize);
      if (hit) {
        const agent = agents.find(a => a.id === hit.id);
        if (agent) onAgentClick?.(agent);
      }
    }
  }

  function handleMouseMove(e: MouseEvent) {
    if (camera.isDragging) {
      const dx = (e.clientX - camera.dragStartX) / camera.zoom;
      const dy = (e.clientY - camera.dragStartY) / camera.zoom;
      camera.targetX = camera.dragStartCamX - dx;
      camera.targetY = camera.dragStartCamY - dy;
    } else {
      // Hover detection
      const rect = canvasEl!.getBoundingClientRect();
      const cx = e.clientX - rect.left;
      const cy = e.clientY - rect.top;
      const hit = hitTestCharacter(cx, cy, camera, width, height, characters, layout.tileSize);
      hoveredCharId = hit?.id ?? null;

      if (canvasEl) {
        canvasEl.style.cursor = hit ? 'pointer' : 'default';
      }
    }
  }

  function handleMouseUp() {
    camera.isDragging = false;
  }

  function handleWheel(e: WheelEvent) {
    e.preventDefault();
    const delta = e.deltaY > 0 ? -0.5 : 0.5;
    camera.targetZoom = Math.max(1, Math.min(8, camera.targetZoom + delta));
  }

  function handleResize() {
    if (containerEl) {
      width = containerEl.clientWidth;
      height = containerEl.clientHeight;
      if (canvasEl) {
        canvasEl.width = width;
        canvasEl.height = height;
      }
    }
  }

  // ─── Zoom controls ──────────────────────────────────────
  function zoomIn() { camera.targetZoom = Math.min(8, camera.targetZoom + 1); }
  function zoomOut() { camera.targetZoom = Math.max(1, camera.targetZoom - 1); }
  function resetView() {
    camera.targetX = layout.cols * layout.tileSize / 2;
    camera.targetY = layout.rows * layout.tileSize / 2;
    camera.targetZoom = 3;
  }

  // Center on selected agent
  $effect(() => {
    if (selectedAgentId) {
      const char = characters.find(c => c.id === selectedAgentId);
      if (char) {
        camera.targetX = char.gridX * layout.tileSize + layout.tileSize / 2;
        camera.targetY = char.gridY * layout.tileSize + layout.tileSize / 2;
      }
    }
  });

  onMount(() => {
    handleResize();
    const ro = new ResizeObserver(handleResize);
    if (containerEl) ro.observe(containerEl);

    lastTime = performance.now();
    rafId = requestAnimationFrame(gameLoop);

    return () => {
      cancelAnimationFrame(rafId);
      ro.disconnect();
    };
  });

  // Stats
  const activeCount = $derived(agents.filter(a => a.status === 'running' || a.status === 'idle').length);
  const awayCount = $derived(agents.length - activeCount);
  const zoomPct = $derived(Math.round(camera.targetZoom * 100 / 3));
</script>

<div class="po-root">
  <!-- Agent sidebar -->
  {#if showSidebar}
    <div class="po-sidebar">
      <div class="po-sidebar-header">
        <span class="po-team-name">BIZFORGE</span>
        <span class="po-team-count">{agents.length} agents</span>
      </div>
      <div class="po-sidebar-tabs">
        <button class="po-tab po-tab--active">All</button>
        <button class="po-tab">Working</button>
        <button class="po-tab">Idle</button>
      </div>
      <div class="po-sidebar-list">
        {#each agents as agent (agent.id)}
          <button
            class="po-agent-row"
            class:po-agent-row--selected={selectedAgentId === agent.id}
            onclick={() => onAgentClick?.(agent)}
          >
            <div class="po-agent-avatar" style="background-color: {statusToColor(agent.status)}">
              {(agent.display_name || agent.name).charAt(0).toUpperCase()}
            </div>
            <div class="po-agent-info">
              <span class="po-agent-name">{agent.display_name || agent.name}</span>
              <span class="po-agent-role">{agent.role || 'agent'}</span>
            </div>
            <div class="po-agent-status">
              <span class="po-status-dot" style="background: {statusToColor(agent.status)}"></span>
              <span class="po-status-text">{agent.status}</span>
            </div>
          </button>
        {/each}
        {#if agents.length === 0}
          <div class="po-empty">No agents yet. Click a room/desk or run an action.</div>
        {/if}
      </div>
    </div>
  {/if}

  <!-- Main canvas area -->
  <div class="po-main" bind:this={containerEl}>
    <!-- Top toolbar -->
    <div class="po-toolbar">
      <div class="po-toolbar-left">
        <button class="po-tool-btn" onclick={() => showSidebar = !showSidebar}>
          {showSidebar ? 'Hide Sidebar' : 'Show Sidebar'}
        </button>
        <button class="po-tool-btn" onclick={() => showMinimap = !showMinimap}>
          {showMinimap ? 'Hide Minimap' : 'Show Minimap'}
        </button>
        <button class="po-tool-btn" onclick={() => showEvents = !showEvents}>
          {showEvents ? 'Hide Events' : 'Show Events'}
        </button>
        <button class="po-tool-btn" onclick={resetView}>Reset Layout</button>
      </div>
      <div class="po-toolbar-right">
        <span class="po-stat">
          <span class="po-dot po-dot--active"></span>
          {activeCount} active
        </span>
        <span class="po-stat">
          <span class="po-dot po-dot--away"></span>
          {awayCount} away
        </span>
      </div>
    </div>

    <!-- Canvas -->
    <canvas
      bind:this={canvasEl}
      width={width}
      height={height}
      onmousedown={handleMouseDown}
      onmousemove={handleMouseMove}
      onmouseup={handleMouseUp}
      onmouseleave={handleMouseUp}
      onwheel={handleWheel}
    ></canvas>

    <!-- Zoom controls (top-left) -->
    <div class="po-zoom">
      <span class="po-zoom-pct">{zoomPct}%</span>
      <button class="po-zoom-btn" onclick={zoomIn}>+</button>
      <button class="po-zoom-btn" onclick={resetView}>R</button>
      <button class="po-zoom-btn" onclick={zoomOut}>-</button>
    </div>

    <!-- Time of day controls (top-right) -->
    <div class="po-time">
      {#each (['dawn', 'day', 'dusk', 'night'] as const) as tod}
        <button
          class="po-time-btn"
          class:po-time-btn--active={timeOfDay === tod}
          onclick={() => { timeOfDay = tod; clearSpriteCache(); }}
        >
          {tod.toUpperCase()}
        </button>
      {/each}
    </div>

    <!-- Minimap (bottom-right) -->
    {#if showMinimap}
      <div class="po-minimap">
        <div class="po-minimap-label">MINIMAP</div>
        <canvas bind:this={minimapEl} width={160} height={110}></canvas>
      </div>
    {/if}

    <!-- Events panel (bottom) -->
    {#if showEvents}
      <div class="po-events">
        <div class="po-events-header">
          <span class="po-dot po-dot--active"></span>
          <span>Busy: {agents.filter(a => a.status === 'running').length}</span>
          <span class="po-dot po-dot--idle"></span>
          <span>Idle: {agents.filter(a => a.status === 'idle').length}</span>
          <span class="po-dot po-dot--away"></span>
          <span>Other: {agents.filter(a => a.status !== 'running' && a.status !== 'idle').length}</span>
        </div>
        <div class="po-events-list">
          {#if events.length === 0}
            <span class="po-events-empty">No events yet. Click a room/desk or run an action.</span>
          {:else}
            {#each events as ev}
              <div class="po-event">
                <span class="po-event-time">{ev.time}</span>
                <span class="po-event-dot" style="background: {ev.color}"></span>
                <span class="po-event-text">{ev.text}</span>
              </div>
            {/each}
          {/if}
        </div>
      </div>
    {/if}
  </div>
</div>

<style>
  .po-root {
    display: flex;
    width: 100%;
    height: 100%;
    background: var(--bg-primary, #0f1117);
    position: relative;
    overflow: hidden;
  }

  /* ─── Sidebar ─── */
  .po-sidebar {
    width: 220px;
    background: var(--bg-secondary, #161b26);
    border-right: 1px solid var(--border-default, rgba(148, 163, 184, 0.12));
    display: flex;
    flex-direction: column;
    flex-shrink: 0;
  }
  .po-sidebar-header {
    padding: 12px 14px;
    border-bottom: 1px solid var(--border-default, rgba(148, 163, 184, 0.12));
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .po-team-name {
    font-size: 14px;
    font-weight: 700;
    color: var(--text-primary, #f0f2f5);
    letter-spacing: 1px;
  }
  .po-team-count {
    font-size: 11px;
    color: var(--text-tertiary, #6b7a8d);
  }
  .po-sidebar-tabs {
    display: flex;
    padding: 8px 10px;
    gap: 4px;
    border-bottom: 1px solid var(--border-default, rgba(148, 163, 184, 0.12));
  }
  .po-tab {
    padding: 4px 10px;
    border: none;
    border-radius: 6px;
    font-size: 11px;
    font-weight: 600;
    background: transparent;
    color: var(--text-tertiary, #6b7a8d);
    cursor: pointer;
  }
  .po-tab--active {
    background: var(--bg-elevated, rgba(148, 163, 184, 0.08));
    color: var(--accent-primary, #fb923c);
  }
  .po-sidebar-list {
    flex: 1;
    overflow-y: auto;
    padding: 4px 0;
  }
  .po-agent-row {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 8px 12px;
    width: 100%;
    border: none;
    background: transparent;
    cursor: pointer;
    text-align: left;
    transition: background 100ms;
  }
  .po-agent-row:hover { background: var(--bg-elevated, rgba(148, 163, 184, 0.08)); }
  .po-agent-row--selected { background: rgba(251, 146, 60, 0.10); }
  .po-agent-avatar {
    width: 28px;
    height: 28px;
    border-radius: 8px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 12px;
    font-weight: 700;
    color: white;
    flex-shrink: 0;
  }
  .po-agent-info {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
  }
  .po-agent-name {
    font-size: 12px;
    font-weight: 600;
    color: var(--text-primary, #f0f2f5);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .po-agent-role {
    font-size: 10px;
    color: var(--text-tertiary, #6b7a8d);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .po-agent-status {
    display: flex;
    align-items: center;
    gap: 4px;
    flex-shrink: 0;
  }
  .po-status-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
  }
  .po-status-text {
    font-size: 10px;
    color: var(--text-secondary, #c8d1dc);
  }
  .po-empty {
    padding: 16px;
    color: var(--text-secondary, #c8d1dc);
    font-size: 11px;
    text-align: center;
  }

  /* ─── Main area ─── */
  .po-main {
    flex: 1;
    position: relative;
    overflow: hidden;
  }
  canvas {
    display: block;
    width: 100%;
    height: 100%;
    image-rendering: pixelated;
    image-rendering: crisp-edges;
  }

  /* ─── Toolbar ─── */
  .po-toolbar {
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 6px 12px;
    background: var(--glass-bg, rgba(22, 27, 38, 0.82));
    backdrop-filter: blur(12px);
    z-index: 10;
    border-bottom: 1px solid var(--border-default, rgba(148, 163, 184, 0.12));
  }
  .po-toolbar-left, .po-toolbar-right {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .po-tool-btn {
    padding: 4px 10px;
    border: 1px solid var(--border-default, rgba(148, 163, 184, 0.12));
    border-radius: 6px;
    background: var(--bg-elevated, rgba(148, 163, 184, 0.08));
    color: var(--text-secondary, #a8b2c1);
    font-size: 11px;
    cursor: pointer;
    transition: all 100ms;
  }
  .po-tool-btn:hover {
    background: rgba(251, 146, 60, 0.12);
    color: var(--accent-primary, #fb923c);
    border-color: rgba(251, 146, 60, 0.20);
  }
  .po-stat {
    display: flex;
    align-items: center;
    gap: 4px;
    font-size: 11px;
    color: var(--text-secondary, #c8d1dc);
  }
  .po-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
  }
  .po-dot--active { background: #6ee7b7; }
  .po-dot--idle { background: #fb923c; }
  .po-dot--away { background: #6b7a8d; }

  /* ─── Zoom ─── */
  .po-zoom {
    position: absolute;
    top: 44px;
    left: 12px;
    display: flex;
    align-items: center;
    gap: 4px;
    z-index: 10;
  }
  .po-zoom-pct {
    font-size: 11px;
    color: var(--text-tertiary, #6b7a8d);
    min-width: 36px;
    text-align: center;
  }
  .po-zoom-btn {
    width: 24px;
    height: 24px;
    border: 1px solid var(--border-default, rgba(148, 163, 184, 0.12));
    border-radius: 6px;
    background: var(--glass-bg, rgba(22, 27, 38, 0.82));
    color: var(--text-secondary, #a8b2c1);
    font-size: 12px;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
  }
  .po-zoom-btn:hover {
    background: rgba(251, 146, 60, 0.15);
    color: var(--accent-primary, #fb923c);
  }

  /* ─── Time of day ─── */
  .po-time {
    position: absolute;
    top: 44px;
    right: 12px;
    display: flex;
    gap: 2px;
    background: var(--glass-bg, rgba(22, 27, 38, 0.82));
    border-radius: 8px;
    padding: 2px;
    z-index: 10;
    border: 1px solid var(--border-default, rgba(148, 163, 184, 0.12));
  }
  .po-time-btn {
    padding: 3px 8px;
    border: none;
    border-radius: 6px;
    font-size: 10px;
    font-weight: 600;
    background: transparent;
    color: var(--text-secondary, #c8d1dc);
    cursor: pointer;
    letter-spacing: 0.5px;
  }
  .po-time-btn--active {
    background: var(--accent-primary, #fb923c);
    color: white;
  }
  .po-time-btn:hover:not(.po-time-btn--active) {
    color: var(--text-primary, #e2e8f0);
  }

  /* ─── Minimap ─── */
  .po-minimap {
    position: absolute;
    bottom: 12px;
    right: 12px;
    z-index: 10;
    border-radius: 10px;
    overflow: hidden;
    border: 2px solid var(--border-default, rgba(148, 163, 184, 0.12));
    background: var(--glass-bg, rgba(22, 27, 38, 0.82));
  }
  .po-minimap-label {
    font-size: 9px;
    font-weight: 700;
    color: var(--text-secondary, #c8d1dc);
    letter-spacing: 1px;
    padding: 3px 6px;
    background: var(--bg-primary, #0f1117);
    text-align: center;
    border-bottom: 1px solid var(--border-default, rgba(148, 163, 184, 0.12));
  }
  .po-minimap canvas {
    display: block;
    width: 160px;
    height: 110px;
  }

  /* ─── Events panel ─── */
  .po-events {
    position: absolute;
    bottom: 12px;
    left: 12px;
    right: 190px;
    z-index: 10;
    max-height: 100px;
    background: var(--glass-bg, rgba(22, 27, 38, 0.82));
    backdrop-filter: blur(12px);
    border: 1px solid var(--border-default, rgba(148, 163, 184, 0.12));
    border-radius: 10px;
    overflow: hidden;
  }
  .po-events-header {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 5px 10px;
    font-size: 10px;
    color: var(--text-secondary, #c8d1dc);
    border-bottom: 1px solid var(--border-default, rgba(148, 163, 184, 0.12));
  }
  .po-events-list {
    overflow-y: auto;
    max-height: 60px;
    padding: 4px 8px;
  }
  .po-events-empty {
    font-size: 11px;
    color: var(--text-secondary, #c8d1dc);
    padding: 4px;
  }
  .po-event {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 2px 0;
  }
  .po-event-time {
    font-size: 10px;
    color: var(--text-tertiary, #94a3b8);
    font-family: monospace;
  }
  .po-event-dot {
    width: 5px;
    height: 5px;
    border-radius: 50%;
    flex-shrink: 0;
  }
  .po-event-text {
    font-size: 11px;
    color: var(--text-primary, #e2e8f0);
  }
</style>
