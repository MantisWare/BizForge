// 3D Character state management — walking, wandering, pathfinding
// Mirrors the 2D PixelOffice character logic for the 3D Threlte view

import type { BizforgeAgent, AgentStatus } from '$api/types';

// ─── Types ────────────────────────────────────────────────────

export type CharState3D = 'idle' | 'walk' | 'type' | 'sleep';

export interface Character3D {
  id: string;
  worldX: number;
  worldZ: number;
  targetX: number;
  targetZ: number;
  state: CharState3D;
  path: [number, number][];
  moveProgress: number;
  seatX: number;
  seatZ: number;
  facingAngle: number;
  animTimer: number;
}

export interface SeatDef3D {
  pos: [number, number, number];
  deskType: 'desk' | 'conference';
  facingZ: number;
}

export interface ZoneDef3D {
  id: string;
  x: number;
  z: number;
  w: number;
  d: number;
}

// ─── Grid mapping ─────────────────────────────────────────────
// Map 3D world coords to a discrete grid for BFS pathfinding.
// The 3D world spans roughly x:[-11, 14] z:[-8, 10].
// Use 1-unit grid cells.

const GRID_ORIGIN_X = -11;
const GRID_ORIGIN_Z = -8;
const GRID_COLS = 26;
const GRID_ROWS = 19;
const CELL_SIZE = 1;

function worldToGrid(wx: number, wz: number): [number, number] {
  const gx = Math.round((wx - GRID_ORIGIN_X) / CELL_SIZE);
  const gz = Math.round((wz - GRID_ORIGIN_Z) / CELL_SIZE);
  return [
    Math.max(0, Math.min(GRID_COLS - 1, gx)),
    Math.max(0, Math.min(GRID_ROWS - 1, gz)),
  ];
}

function gridToWorld(gx: number, gz: number): [number, number] {
  return [
    GRID_ORIGIN_X + gx * CELL_SIZE,
    GRID_ORIGIN_Z + gz * CELL_SIZE,
  ];
}

// ─── Walkability ──────────────────────────────────────────────

export function buildWalkableGrid(
  zones: readonly ZoneDef3D[],
  corridorHRange: [number, number],
  corridorVRange: [number, number],
): boolean[][] {
  const grid: boolean[][] = [];
  for (let gz = 0; gz < GRID_ROWS; gz++) {
    grid[gz] = [];
    for (let gx = 0; gx < GRID_COLS; gx++) {
      grid[gz][gx] = false;
    }
  }

  // Mark zone interiors as walkable
  for (const zone of zones) {
    const [x1] = worldToGrid(zone.x, zone.z);
    const [, z1] = worldToGrid(zone.x, zone.z);
    const [x2] = worldToGrid(zone.x + zone.w, zone.z + zone.d);
    const [, z2] = worldToGrid(zone.x + zone.w, zone.z + zone.d);
    for (let gz = Math.min(z1, z2); gz <= Math.max(z1, z2); gz++) {
      for (let gx = Math.min(x1, x2); gx <= Math.max(x1, x2); gx++) {
        if (gx >= 0 && gx < GRID_COLS && gz >= 0 && gz < GRID_ROWS) {
          grid[gz][gx] = true;
        }
      }
    }
  }

  // Mark corridors as walkable (horizontal and vertical bands)
  const [hzStart, hzEnd] = corridorHRange;
  const [vxStart, vxEnd] = corridorVRange;

  for (let gx = 0; gx < GRID_COLS; gx++) {
    for (let gz = hzStart; gz <= hzEnd; gz++) {
      if (gz >= 0 && gz < GRID_ROWS) grid[gz][gx] = true;
    }
  }
  for (let gz = 0; gz < GRID_ROWS; gz++) {
    for (let gx = vxStart; gx <= vxEnd; gx++) {
      if (gx >= 0 && gx < GRID_COLS) grid[gz][gx] = true;
    }
  }

  return grid;
}

// ─── BFS pathfinding ──────────────────────────────────────────

function findPath3D(
  walkable: boolean[][],
  startGX: number,
  startGZ: number,
  endGX: number,
  endGZ: number,
): [number, number][] {
  if (startGX === endGX && startGZ === endGZ) return [];
  if (endGZ < 0 || endGZ >= GRID_ROWS || endGX < 0 || endGX >= GRID_COLS) return [];
  if (!walkable[endGZ]?.[endGX]) return [];

  const visited = new Set<string>();
  const queue: { x: number; z: number; path: [number, number][] }[] = [
    { x: startGX, z: startGZ, path: [] },
  ];
  visited.add(`${startGX},${startGZ}`);

  const dirs: [number, number][] = [[0, -1], [1, 0], [0, 1], [-1, 0]];

  while (queue.length > 0) {
    const curr = queue.shift()!;

    for (const [dx, dz] of dirs) {
      const nx = curr.x + dx;
      const nz = curr.z + dz;
      const key = `${nx},${nz}`;

      if (nx < 0 || nx >= GRID_COLS || nz < 0 || nz >= GRID_ROWS) continue;
      if (visited.has(key)) continue;
      if (!walkable[nz][nx]) continue;

      const newPath: [number, number][] = [...curr.path, [nx, nz]];
      if (nx === endGX && nz === endGZ) return newPath;

      visited.add(key);
      queue.push({ x: nx, z: nz, path: newPath });
    }
  }

  return [];
}

// ─── Status mapping ───────────────────────────────────────────

function statusToState(status: AgentStatus | string): CharState3D {
  switch (status) {
    case 'running': return 'type';
    case 'sleeping': return 'sleep';
    default: return 'idle';
  }
}

// ─── Sync agents to 3D characters ─────────────────────────────

export function syncAgentsToCharacters3D(
  agents: BizforgeAgent[],
  existingChars: Character3D[],
  seats: { pos: [number, number, number]; facingZ: number }[],
  walkable: boolean[][],
): Character3D[] {
  const existingMap = new Map(existingChars.map(c => [c.id, c]));
  const result: Character3D[] = [];

  agents.forEach((agent, i) => {
    const seat = seats[i % seats.length];
    const seatX = seat.pos[0];
    const seatZ = seat.pos[2];
    const newState = statusToState(agent.status);
    const existing = existingMap.get(agent.id);

    if (existing !== undefined) {
      const prevState = existing.state;
      existing.state = newState;

      // If agent became active, walk to seat
      if (newState === 'type' && prevState !== 'type') {
        const [startGX, startGZ] = worldToGrid(existing.worldX, existing.worldZ);
        const [endGX, endGZ] = worldToGrid(seatX, seatZ);

        if (startGX !== endGX || startGZ !== endGZ) {
          const path = findPath3D(walkable, startGX, startGZ, endGX, endGZ);
          if (path.length > 0) {
            existing.path = path;
            existing.state = 'walk';
            existing.moveProgress = 0;
          }
        }
      }

      // If agent finished working, walk toward lounge area
      if ((newState === 'idle' || newState === 'sleep') && prevState === 'type') {
        const loungeX = 11;
        const loungeZ = 6.5;
        const [startGX, startGZ] = worldToGrid(existing.worldX, existing.worldZ);
        const [endGX, endGZ] = worldToGrid(loungeX, loungeZ);
        const path = findPath3D(walkable, startGX, startGZ, endGX, endGZ);
        if (path.length > 0) {
          existing.path = path;
          existing.state = 'walk';
          existing.moveProgress = 0;
        }
      }
      result.push(existing);
    } else {
      const facingAngle = seat.facingZ > 0 ? 0 : Math.PI;
      result.push({
        id: agent.id,
        worldX: seatX,
        worldZ: seatZ,
        targetX: seatX,
        targetZ: seatZ,
        state: newState,
        path: [],
        moveProgress: 0,
        seatX,
        seatZ,
        facingAngle,
        animTimer: 0,
      });
    }
  });

  return result;
}

// ─── Tick: advance movement + idle wandering ──────────────────

const WALK_SPEED_3D = 2.5; // world units per second

export function tick3D(
  characters: Character3D[],
  dt: number,
  walkable: boolean[][],
  agents: BizforgeAgent[],
): void {
  for (const char of characters) {
    char.animTimer += dt;

    // Movement along path
    if (char.path.length > 0) {
      char.state = 'walk';
      const [nextGX, nextGZ] = char.path[0];
      const [nextWX, nextWZ] = gridToWorld(nextGX, nextGZ);
      char.targetX = nextWX;
      char.targetZ = nextWZ;

      // Compute facing angle toward target
      const dx = nextWX - char.worldX;
      const dz = nextWZ - char.worldZ;
      if (Math.abs(dx) > 0.01 || Math.abs(dz) > 0.01) {
        char.facingAngle = Math.atan2(dx, dz);
      }

      char.moveProgress += WALK_SPEED_3D * dt / CELL_SIZE;

      if (char.moveProgress >= 1) {
        char.worldX = nextWX;
        char.worldZ = nextWZ;
        char.moveProgress = 0;
        char.path.shift();

        if (char.path.length === 0) {
          const agent = agents.find(a => a.id === char.id);
          if (agent !== undefined) {
            char.state = statusToState(agent.status);
          } else {
            char.state = 'idle';
          }
          // Snap facing toward seat direction
          const dxSeat = char.seatX - char.worldX;
          const dzSeat = char.seatZ - char.worldZ;
          if (Math.abs(dxSeat) < 0.1 && Math.abs(dzSeat) < 0.1) {
            // Already at seat; keep facing angle
          }
        }
      }
    }

    // Idle wandering
    if (char.state === 'idle' && char.path.length === 0) {
      if (Math.random() < 0.0008) {
        const [curGX, curGZ] = worldToGrid(char.worldX, char.worldZ);
        const rx = curGX + Math.floor(Math.random() * 5) - 2;
        const rz = curGZ + Math.floor(Math.random() * 5) - 2;
        if (rx >= 0 && rx < GRID_COLS && rz >= 0 && rz < GRID_ROWS && walkable[rz]?.[rx]) {
          const pathOut = findPath3D(walkable, curGX, curGZ, rx, rz);
          if (pathOut.length > 0 && pathOut.length < 8) {
            const [seatGX, seatGZ] = worldToGrid(char.seatX, char.seatZ);
            const pathBack = findPath3D(walkable, rx, rz, seatGX, seatGZ);
            if (pathBack.length > 0) {
              char.path = [...pathOut, ...pathBack];
              char.moveProgress = 0;
            }
          }
        }
      }
    }
  }
}

// ─── Interpolated position for rendering ──────────────────────

export function getInterpolatedPos(char: Character3D): [number, number] {
  if (char.path.length > 0 && char.moveProgress > 0 && char.moveProgress < 1) {
    const [nextGX, nextGZ] = char.path[0];
    const [nextWX, nextWZ] = gridToWorld(nextGX, nextGZ);
    return [
      char.worldX + (nextWX - char.worldX) * char.moveProgress,
      char.worldZ + (nextWZ - char.worldZ) * char.moveProgress,
    ];
  }
  return [char.worldX, char.worldZ];
}
