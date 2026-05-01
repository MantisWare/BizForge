// Pixel Office — Office layout definition
// Defines rooms, furniture placement, and walkability

import {
  FurnitureType,
  type OfficeLayout,
  type OfficeRoom,
  type Furniture,
} from "./types";

// ─── Room definitions ──────────────────────────────────────
const ROOMS: OfficeRoom[] = [
  {
    id: "engineering",
    name: "Engineering",
    label: "ENGINEERING",
    color: "#2e2b50",
    labelColor: "#fdba74",
    x: 1,
    y: 1,
    width: 9,
    height: 7,
    floorPattern: "grid",
  },
  {
    id: "product",
    name: "Product",
    label: "PRODUCT",
    color: "#253040",
    labelColor: "#93c5fd",
    x: 14,
    y: 1,
    width: 9,
    height: 7,
    floorPattern: "checker",
  },
  {
    id: "operations",
    name: "Operations",
    label: "OPERATIONS",
    color: "#1e3038",
    labelColor: "#6ee7b7",
    x: 1,
    y: 12,
    width: 9,
    height: 6,
    floorPattern: "herringbone",
  },
  {
    id: "research",
    name: "Research",
    label: "RESEARCH",
    color: "#302535",
    labelColor: "#f9a8d4",
    x: 14,
    y: 12,
    width: 6,
    height: 6,
    floorPattern: "dot",
  },
  {
    id: "lounge",
    name: "Lounge",
    label: "LOUNGE",
    color: "#302828",
    labelColor: "#fcd6a5",
    x: 21,
    y: 12,
    width: 4,
    height: 6,
    floorPattern: "carpet",
  },
];

// ─── Furniture placement ──────────────────────────────────
const FURNITURE: Furniture[] = [
  // Engineering — 2 rows of desks with PCs
  { type: FurnitureType.DESK, x: 2, y: 2, facing: "down" },
  { type: FurnitureType.PC, x: 2, y: 2, facing: "down", state: "off" },
  { type: FurnitureType.CHAIR, x: 2, y: 3, facing: "up" },
  { type: FurnitureType.DESK, x: 4, y: 2, facing: "down" },
  { type: FurnitureType.PC, x: 4, y: 2, facing: "down", state: "off" },
  { type: FurnitureType.CHAIR, x: 4, y: 3, facing: "up" },
  { type: FurnitureType.DESK, x: 6, y: 2, facing: "down" },
  { type: FurnitureType.PC, x: 6, y: 2, facing: "down", state: "off" },
  { type: FurnitureType.CHAIR, x: 6, y: 3, facing: "up" },
  { type: FurnitureType.DESK, x: 8, y: 2, facing: "down" },
  { type: FurnitureType.PC, x: 8, y: 2, facing: "down", state: "off" },
  { type: FurnitureType.CHAIR, x: 8, y: 3, facing: "up" },

  { type: FurnitureType.DESK, x: 2, y: 5, facing: "down" },
  { type: FurnitureType.PC, x: 2, y: 5, facing: "down", state: "off" },
  { type: FurnitureType.CHAIR, x: 2, y: 6, facing: "up" },
  { type: FurnitureType.DESK, x: 4, y: 5, facing: "down" },
  { type: FurnitureType.PC, x: 4, y: 5, facing: "down", state: "off" },
  { type: FurnitureType.CHAIR, x: 4, y: 6, facing: "up" },
  { type: FurnitureType.DESK, x: 6, y: 5, facing: "down" },
  { type: FurnitureType.PC, x: 6, y: 5, facing: "down", state: "off" },
  { type: FurnitureType.CHAIR, x: 6, y: 6, facing: "up" },

  { type: FurnitureType.WHITEBOARD, x: 9, y: 1, facing: "left" },
  { type: FurnitureType.PLANT, x: 1, y: 1, facing: "down" },

  // Engineering rugs (decorative, under desk rows)
  { type: FurnitureType.RUG, x: 2, y: 3, facing: "down" },
  { type: FurnitureType.RUG, x: 4, y: 3, facing: "down" },
  { type: FurnitureType.RUG, x: 6, y: 3, facing: "down" },

  // Product — 2 rows of desks
  { type: FurnitureType.DESK, x: 15, y: 2, facing: "down" },
  { type: FurnitureType.PC, x: 15, y: 2, facing: "down", state: "off" },
  { type: FurnitureType.CHAIR, x: 15, y: 3, facing: "up" },
  { type: FurnitureType.DESK, x: 17, y: 2, facing: "down" },
  { type: FurnitureType.PC, x: 17, y: 2, facing: "down", state: "off" },
  { type: FurnitureType.CHAIR, x: 17, y: 3, facing: "up" },
  { type: FurnitureType.DESK, x: 19, y: 2, facing: "down" },
  { type: FurnitureType.PC, x: 19, y: 2, facing: "down", state: "off" },
  { type: FurnitureType.CHAIR, x: 19, y: 3, facing: "up" },
  { type: FurnitureType.DESK, x: 21, y: 2, facing: "down" },
  { type: FurnitureType.PC, x: 21, y: 2, facing: "down", state: "off" },
  { type: FurnitureType.CHAIR, x: 21, y: 3, facing: "up" },

  { type: FurnitureType.DESK, x: 15, y: 5, facing: "down" },
  { type: FurnitureType.PC, x: 15, y: 5, facing: "down", state: "off" },
  { type: FurnitureType.CHAIR, x: 15, y: 6, facing: "up" },
  { type: FurnitureType.DESK, x: 17, y: 5, facing: "down" },
  { type: FurnitureType.PC, x: 17, y: 5, facing: "down", state: "off" },
  { type: FurnitureType.CHAIR, x: 17, y: 6, facing: "up" },

  { type: FurnitureType.BOOKSHELF, x: 22, y: 1, facing: "left" },
  { type: FurnitureType.PLANT, x: 14, y: 1, facing: "down" },
  { type: FurnitureType.WALL_ART, x: 18, y: 1, facing: "down" },

  // Product rugs
  { type: FurnitureType.RUG, x: 15, y: 3, facing: "down" },
  { type: FurnitureType.RUG, x: 17, y: 3, facing: "down" },
  { type: FurnitureType.RUG, x: 19, y: 3, facing: "down" },

  // Operations — desks
  { type: FurnitureType.DESK, x: 2, y: 13, facing: "down" },
  { type: FurnitureType.PC, x: 2, y: 13, facing: "down", state: "off" },
  { type: FurnitureType.CHAIR, x: 2, y: 14, facing: "up" },
  { type: FurnitureType.DESK, x: 4, y: 13, facing: "down" },
  { type: FurnitureType.PC, x: 4, y: 13, facing: "down", state: "off" },
  { type: FurnitureType.CHAIR, x: 4, y: 14, facing: "up" },
  { type: FurnitureType.DESK, x: 6, y: 13, facing: "down" },
  { type: FurnitureType.PC, x: 6, y: 13, facing: "down", state: "off" },
  { type: FurnitureType.CHAIR, x: 6, y: 14, facing: "up" },
  { type: FurnitureType.DESK, x: 8, y: 13, facing: "down" },
  { type: FurnitureType.PC, x: 8, y: 13, facing: "down", state: "off" },
  { type: FurnitureType.CHAIR, x: 8, y: 14, facing: "up" },

  { type: FurnitureType.CABINET, x: 9, y: 12, facing: "left" },
  { type: FurnitureType.PLANT, x: 1, y: 17, facing: "down" },

  // Research — desks
  { type: FurnitureType.DESK, x: 15, y: 13, facing: "down" },
  { type: FurnitureType.PC, x: 15, y: 13, facing: "down", state: "off" },
  { type: FurnitureType.CHAIR, x: 15, y: 14, facing: "up" },
  { type: FurnitureType.DESK, x: 17, y: 13, facing: "down" },
  { type: FurnitureType.PC, x: 17, y: 13, facing: "down", state: "off" },
  { type: FurnitureType.CHAIR, x: 17, y: 14, facing: "up" },
  { type: FurnitureType.DESK, x: 15, y: 16, facing: "down" },
  { type: FurnitureType.PC, x: 15, y: 16, facing: "down", state: "off" },
  { type: FurnitureType.CHAIR, x: 15, y: 17, facing: "up" },

  { type: FurnitureType.BOOKSHELF, x: 14, y: 17, facing: "up" },
  { type: FurnitureType.WHITEBOARD, x: 19, y: 12, facing: "down" },

  // Lounge — seating area (two sofas facing each other)
  { type: FurnitureType.SOFA, x: 21, y: 13, facing: "down" },
  { type: FurnitureType.SOFA, x: 21, y: 15, facing: "down" },
  { type: FurnitureType.TABLE_ROUND, x: 22, y: 14, facing: "down" },
  { type: FurnitureType.TV, x: 22, y: 12, facing: "down" },
  // Lounge — mini kitchen (tucked along right wall)
  { type: FurnitureType.KITCHEN_COUNTER, x: 24, y: 13, facing: "left" },
  { type: FurnitureType.COFFEE_MACHINE, x: 24, y: 14, facing: "left" },
  { type: FurnitureType.FRIDGE, x: 24, y: 15, facing: "left" },
  { type: FurnitureType.PLANT, x: 24, y: 17, facing: "down" },

  // ─── Environmental decorations ──────────────────
  // Water cooler at corridor intersection
  { type: FurnitureType.WATERCOOLER, x: 13, y: 9, facing: "down" },
  // Entrance mat at corridor entrance (left)
  { type: FurnitureType.ENTRANCE_MAT, x: 0, y: 9, facing: "right" },
  // Ceiling lights in corridors
  { type: FurnitureType.CEILING_LIGHT, x: 5, y: 9, facing: "down" },
  { type: FurnitureType.CEILING_LIGHT, x: 18, y: 9, facing: "down" },
  { type: FurnitureType.CEILING_LIGHT, x: 12, y: 4, facing: "down" },
  { type: FurnitureType.CEILING_LIGHT, x: 12, y: 15, facing: "down" },
];

// ─── Seat assignments (chair positions for agents) ────────
export interface Seat {
  gridX: number;
  gridY: number;
  facing: "up" | "down" | "left" | "right";
  room: string;
  deskX: number;
  deskY: number;
}

export const SEATS: Seat[] = [
  // Engineering seats (at chairs, facing desk)
  { gridX: 2, gridY: 3, facing: "up", room: "engineering", deskX: 2, deskY: 2 },
  { gridX: 4, gridY: 3, facing: "up", room: "engineering", deskX: 4, deskY: 2 },
  { gridX: 6, gridY: 3, facing: "up", room: "engineering", deskX: 6, deskY: 2 },
  { gridX: 8, gridY: 3, facing: "up", room: "engineering", deskX: 8, deskY: 2 },
  { gridX: 2, gridY: 6, facing: "up", room: "engineering", deskX: 2, deskY: 5 },
  { gridX: 4, gridY: 6, facing: "up", room: "engineering", deskX: 4, deskY: 5 },
  { gridX: 6, gridY: 6, facing: "up", room: "engineering", deskX: 6, deskY: 5 },
  // Product seats
  { gridX: 15, gridY: 3, facing: "up", room: "product", deskX: 15, deskY: 2 },
  { gridX: 17, gridY: 3, facing: "up", room: "product", deskX: 17, deskY: 2 },
  { gridX: 19, gridY: 3, facing: "up", room: "product", deskX: 19, deskY: 2 },
  { gridX: 21, gridY: 3, facing: "up", room: "product", deskX: 21, deskY: 2 },
  { gridX: 15, gridY: 6, facing: "up", room: "product", deskX: 15, deskY: 5 },
  { gridX: 17, gridY: 6, facing: "up", room: "product", deskX: 17, deskY: 5 },
  // Operations seats
  { gridX: 2, gridY: 14, facing: "up", room: "operations", deskX: 2, deskY: 13 },
  { gridX: 4, gridY: 14, facing: "up", room: "operations", deskX: 4, deskY: 13 },
  { gridX: 6, gridY: 14, facing: "up", room: "operations", deskX: 6, deskY: 13 },
  { gridX: 8, gridY: 14, facing: "up", room: "operations", deskX: 8, deskY: 13 },
  // Research seats
  { gridX: 15, gridY: 14, facing: "up", room: "research", deskX: 15, deskY: 13 },
  { gridX: 17, gridY: 14, facing: "up", room: "research", deskX: 17, deskY: 13 },
  { gridX: 15, gridY: 17, facing: "up", room: "research", deskX: 15, deskY: 16 },
  // Lounge seats (sofa)
  { gridX: 21, gridY: 14, facing: "up", room: "lounge", deskX: 21, deskY: 13 },
  { gridX: 22, gridY: 14, facing: "up", room: "lounge", deskX: 22, deskY: 13 },
];

// ─── Build layout ──────────────────────────────────────────

const COLS = 26;
const ROWS = 19;
const TILE_SIZE = 16; // pixels per tile (before zoom)

// Corridor indices (wider = 3 tiles)
export const CORRIDOR_H_START = 8;
export const CORRIDOR_H_END = 10; // y = 8, 9, 10
export const CORRIDOR_V_START = 11;
export const CORRIDOR_V_END = 13; // x = 11, 12, 13

export function createDefaultLayout(): OfficeLayout {
  // Initialize walkable grid
  const walkable: boolean[][] = [];
  for (let y = 0; y < ROWS; y++) {
    walkable[y] = [];
    for (let x = 0; x < COLS; x++) {
      walkable[y][x] = false;
    }
  }

  // Mark room floors as walkable
  for (const room of ROOMS) {
    for (let dy = 0; dy < room.height; dy++) {
      for (let dx = 0; dx < room.width; dx++) {
        const gx = room.x + dx;
        const gy = room.y + dy;
        if (gx < COLS && gy < ROWS) {
          walkable[gy][gx] = true;
        }
      }
    }
  }

  // Corridors — horizontal at y=8,9,10
  for (let x = 0; x < COLS; x++) {
    for (let cy = CORRIDOR_H_START; cy <= CORRIDOR_H_END; cy++) {
      if (cy < ROWS) walkable[cy][x] = true;
    }
  }
  // Vertical corridor at x=11,12,13
  for (let y = 0; y < ROWS; y++) {
    for (let cx = CORRIDOR_V_START; cx <= CORRIDOR_V_END; cx++) {
      if (cx < COLS) walkable[y][cx] = true;
    }
  }

  // Mark desk/furniture tiles as non-walkable
  for (const f of FURNITURE) {
    if (
      f.type === FurnitureType.DESK ||
      f.type === FurnitureType.BOOKSHELF ||
      f.type === FurnitureType.CABINET ||
      f.type === FurnitureType.WHITEBOARD ||
      f.type === FurnitureType.KITCHEN_COUNTER ||
      f.type === FurnitureType.FRIDGE ||
      f.type === FurnitureType.TV
    ) {
      if (f.y < ROWS && f.x < COLS) {
        walkable[f.y][f.x] = false;
      }
    }
  }

  return {
    cols: COLS,
    rows: ROWS,
    tileSize: TILE_SIZE,
    rooms: ROOMS,
    furniture: FURNITURE,
    walkable,
  };
}

// ─── BFS Pathfinding ──────────────────────────────────────

export function findPath(
  walkable: boolean[][],
  startX: number,
  startY: number,
  endX: number,
  endY: number,
  cols: number,
  rows: number,
): [number, number][] {
  if (startX === endX && startY === endY) return [];
  if (!walkable[endY]?.[endX]) return [];

  const visited = new Set<string>();
  const queue: { x: number; y: number; path: [number, number][] }[] = [
    { x: startX, y: startY, path: [] },
  ];
  visited.add(`${startX},${startY}`);

  const dirs: [number, number][] = [
    [0, -1],
    [1, 0],
    [0, 1],
    [-1, 0],
  ];

  while (queue.length > 0) {
    const curr = queue.shift()!;

    for (const [dx, dy] of dirs) {
      const nx = curr.x + dx;
      const ny = curr.y + dy;
      const key = `${nx},${ny}`;

      if (nx < 0 || nx >= cols || ny < 0 || ny >= rows) continue;
      if (visited.has(key)) continue;
      if (!walkable[ny][nx]) continue;

      const newPath: [number, number][] = [...curr.path, [nx, ny]];
      if (nx === endX && ny === endY) return newPath;

      visited.add(key);
      queue.push({ x: nx, y: ny, path: newPath });
    }
  }

  return []; // no path found
}
