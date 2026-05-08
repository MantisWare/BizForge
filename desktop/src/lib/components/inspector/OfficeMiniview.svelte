<!-- Compact zoomed-out overview of the pixel office, embedded in the LLM Inspector panel -->
<script lang="ts">
  import { onMount, untrack } from 'svelte';
  import { agentsStore } from '$lib/stores/agents.svelte';
  import type { OfficeCharacter, Camera } from '$lib/components/office/pixel/types';
  import { CharacterState } from '$lib/components/office/pixel/types';
  import { createDefaultLayout, SEATS } from '$lib/components/office/pixel/layout';
  import { renderOffice } from '$lib/components/office/pixel/renderer';

  let canvasEl: HTMLCanvasElement | undefined = $state();
  let containerEl: HTMLDivElement | undefined = $state();
  let rafId = 0;

  let displayW = $state(400);
  let displayH = $state(260);

  const layout = createDefaultLayout();
  const worldW = layout.cols * layout.tileSize;
  const worldH = layout.rows * layout.tileSize;
  const centerX = worldW / 2;
  const centerY = worldH / 2;

  // Render at high zoom so per-pixel sprite details (tile borders, floor
  // patterns, grid lines) blend into solid fills when scaled to display size.
  const RENDER_ZOOM = 6;
  const offW = Math.round(worldW * RENDER_ZOOM * 1.04);
  const offH = Math.round(worldH * RENDER_ZOOM * 1.04);
  let offscreen: HTMLCanvasElement | undefined;

  // Throttle full re-render to ~4 fps — the miniview doesn't need 60 fps
  let lastRenderTime = 0;
  const RENDER_INTERVAL = 250;

  const renderCamera: Camera = {
    x: centerX,
    y: centerY,
    zoom: RENDER_ZOOM,
    targetX: centerX,
    targetY: centerY,
    targetZoom: RENDER_ZOOM,
    isDragging: false,
    dragStartX: 0,
    dragStartY: 0,
    dragStartCamX: 0,
    dragStartCamY: 0,
  };

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

  let characters = $state<OfficeCharacter[]>([]);

  $effect(() => {
    const _agents = agentsStore.agents;
    const existingChars = untrack(() => characters);
    const existingMap = new Map(existingChars.map(c => [c.id, c]));
    const newChars: OfficeCharacter[] = [];

    _agents.forEach((agent, i) => {
      const existing = existingMap.get(agent.id);
      const seat = SEATS[i % SEATS.length];

      if (existing !== undefined) {
        existing.state = statusToCharState(agent.status);
        existing.statusColor = statusToColor(agent.status);
        existing.name = agent.display_name ?? agent.name;
        newChars.push(existing);
      } else {
        newChars.push({
          id: agent.id,
          name: agent.display_name ?? agent.name,
          color: '',
          skinTone: '',
          hairColor: '',
          state: statusToCharState(agent.status),
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
          currentTask: agent.current_task ?? undefined,
          bubbleTimer: 0,
        });
      }
    });

    characters = newChars;
  });

  function handleResize() {
    if (containerEl === undefined) return;
    const w = containerEl.clientWidth;
    if (w < 10) return;
    const aspect = worldH / worldW;
    displayW = w;
    displayH = Math.round(w * aspect);

    if (canvasEl !== undefined) {
      canvasEl.width = displayW;
      canvasEl.height = displayH;
    }
    lastRenderTime = 0;
  }

  function render(now: number) {
    if (canvasEl === undefined || offscreen === undefined) {
      rafId = requestAnimationFrame(render);
      return;
    }

    const ctx = canvasEl.getContext('2d');
    if (ctx === null) {
      rafId = requestAnimationFrame(render);
      return;
    }

    // Only re-render the offscreen at throttled rate
    if (now - lastRenderTime > RENDER_INTERVAL) {
      lastRenderTime = now;

      const offCtx = offscreen.getContext('2d');
      if (offCtx !== null) {
        renderOffice(
          offCtx,
          offW,
          offH,
          layout,
          renderCamera,
          characters,
          'day',
          null,
          null,
          now,
        );
      }
    }

    // Scale the offscreen down to display size with smooth interpolation
    ctx.clearRect(0, 0, displayW, displayH);
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = 'high';
    ctx.drawImage(offscreen, 0, 0, offW, offH, 0, 0, displayW, displayH);

    rafId = requestAnimationFrame(render);
  }

  onMount(() => {
    offscreen = document.createElement('canvas');
    offscreen.width = offW;
    offscreen.height = offH;

    handleResize();
    const ro = new ResizeObserver(handleResize);
    if (containerEl !== undefined) ro.observe(containerEl);

    rafId = requestAnimationFrame(render);
    return () => {
      cancelAnimationFrame(rafId);
      ro.disconnect();
    };
  });

  const activeCount = $derived(
    agentsStore.agents.filter(a => a.status === 'running' || a.status === 'idle').length,
  );
</script>

<div class="omv-wrap">
  <div class="omv-header">
    <span class="omv-label">OFFICE</span>
    <span class="omv-count">
      <span class="omv-dot"></span>
      {activeCount} active
    </span>
  </div>
  <div class="omv-canvas-wrap" bind:this={containerEl}>
    <canvas
      bind:this={canvasEl}
      width={displayW}
      height={displayH}
      class="omv-canvas"
    ></canvas>
  </div>
</div>

<style>
  .omv-wrap {
    border-bottom: 1px solid var(--border-default);
    background: var(--bg-primary);
    flex-shrink: 0;
    overflow: hidden;
  }

  .omv-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 5px 12px 4px 16px;
    margin-left: var(--inspector-gutter-width, 6px);
  }

  .omv-label {
    font-size: 9px;
    font-weight: 700;
    letter-spacing: 1px;
    color: var(--text-tertiary);
  }

  .omv-count {
    display: flex;
    align-items: center;
    gap: 4px;
    font-size: 10px;
    color: var(--text-muted);
  }

  .omv-dot {
    width: 5px;
    height: 5px;
    border-radius: 50%;
    background: #6ee7b7;
  }

  .omv-canvas-wrap {
    width: 100%;
    margin-left: var(--inspector-gutter-width, 6px);
  }

  .omv-canvas {
    display: block;
    width: 100%;
    height: auto;
  }
</style>
