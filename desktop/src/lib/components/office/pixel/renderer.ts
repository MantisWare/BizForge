// Pixel Office — Canvas 2D renderer
// Draws the complete office: ground, rooms, walls, corridors, furniture, characters

import type {
  OfficeLayout,
  Camera,
  OfficeCharacter,
  TimeOfDay,
  ZDrawable,
  Furniture,
  OfficeRoom,
} from "./types";
import { CharacterState, FurnitureType } from "./types";
import {
  getCharFrames,
  resolveColor,
  agentPalette,
  checkerFloor,
  gridFloor,
  herringboneFloor,
  dotFloor,
  carpetFloor,
  groundTile,
  corridorTile,
  renderSpriteToCanvas,
  DESK_SPRITE,
  PC_ON_SPRITE,
  PC_OFF_SPRITE,
  CHAIR_SPRITE,
  PLANT_SPRITE,
  BOOKSHELF_SPRITE,
  SOFA_SPRITE,
  WHITEBOARD_SPRITE,
  RUG_SPRITE,
  WATERCOOLER_SPRITE,
  CEILING_LIGHT_SPRITE,
  WALL_ART_SPRITE,
  ENTRANCE_MAT_SPRITE,
  KITCHEN_COUNTER_SPRITE,
  MICROWAVE_SPRITE,
  COFFEE_MACHINE_SPRITE,
  FRIDGE_SPRITE,
  TV_SPRITE,
} from "./sprites";
import {
  CORRIDOR_H_START,
  CORRIDOR_H_END,
  CORRIDOR_V_START,
  CORRIDOR_V_END,
} from "./layout";

// ─── Time-of-day color schemes ────────────────────────────
const TIME_COLORS: Record<
  TimeOfDay,
  {
    ambient: string;
    overlay: string;
    overlayAlpha: number;
    wallTop: string;
    wallFace: string;
    wallShadow: string;
    groundBase: string;
    groundAlt: string;
    groundCrack: string;
    corridorEdge: string;
    corridorPath: string;
    corridorPathAlt: string;
  }
> = {
  dawn: {
    ambient: "#f5dcc0",
    overlay: "#fbb98a",
    overlayAlpha: 0.05,
    wallTop: "#a08870",
    wallFace: "#78583a",
    wallShadow: "rgba(80, 50, 30, 0.25)",
    groundBase: "#c8b8a0",
    groundAlt: "#beb098",
    groundCrack: "#a89880",
    corridorEdge: "#8a7860",
    corridorPath: "#b0a088",
    corridorPathAlt: "#a89880",
  },
  day: {
    ambient: "#f8f0e0",
    overlay: "#ffffff",
    overlayAlpha: 0.0,
    wallTop: "#8880a8",
    wallFace: "#6b6590",
    wallShadow: "rgba(40, 35, 70, 0.20)",
    groundBase: "#c8c0b0",
    groundAlt: "#beb8a8",
    groundCrack: "#a8a090",
    corridorEdge: "#7a7590",
    corridorPath: "#908898",
    corridorPathAlt: "#888090",
  },
  dusk: {
    ambient: "#d4a8a0",
    overlay: "#e08878",
    overlayAlpha: 0.06,
    wallTop: "#684870",
    wallFace: "#504068",
    wallShadow: "rgba(50, 30, 60, 0.25)",
    groundBase: "#988078",
    groundAlt: "#907870",
    groundCrack: "#786860",
    corridorEdge: "#604858",
    corridorPath: "#786070",
    corridorPathAlt: "#705868",
  },
  night: {
    ambient: "#1e2038",
    overlay: "#4040a0",
    overlayAlpha: 0.08,
    wallTop: "#383050",
    wallFace: "#2a2848",
    wallShadow: "rgba(10, 10, 30, 0.35)",
    groundBase: "#1a1828",
    groundAlt: "#181620",
    groundCrack: "#121018",
    corridorEdge: "#282040",
    corridorPath: "#242038",
    corridorPathAlt: "#201c30",
  },
};

// ─── Sprite lookup for furniture ──────────────────────────
function getFurnitureSprite(
  f: Furniture,
  activeDesks: Set<string>,
): string[][] | null {
  const key = `${f.x},${f.y}`;
  switch (f.type) {
    case FurnitureType.DESK:
      return DESK_SPRITE;
    case FurnitureType.PC:
      return activeDesks.has(key) ? PC_ON_SPRITE : PC_OFF_SPRITE;
    case FurnitureType.CHAIR:
      return CHAIR_SPRITE;
    case FurnitureType.PLANT:
    case FurnitureType.PLANT_LARGE:
      return PLANT_SPRITE;
    case FurnitureType.BOOKSHELF:
    case FurnitureType.CABINET:
      return BOOKSHELF_SPRITE;
    case FurnitureType.SOFA:
      return SOFA_SPRITE;
    case FurnitureType.WHITEBOARD:
      return WHITEBOARD_SPRITE;
    case FurnitureType.RUG:
      return RUG_SPRITE;
    case FurnitureType.WATERCOOLER:
      return WATERCOOLER_SPRITE;
    case FurnitureType.CEILING_LIGHT:
      return CEILING_LIGHT_SPRITE;
    case FurnitureType.WALL_ART:
      return WALL_ART_SPRITE;
    case FurnitureType.ENTRANCE_MAT:
      return ENTRANCE_MAT_SPRITE;
    case FurnitureType.KITCHEN_COUNTER:
      return KITCHEN_COUNTER_SPRITE;
    case FurnitureType.MICROWAVE:
      return MICROWAVE_SPRITE;
    case FurnitureType.COFFEE_MACHINE:
      return COFFEE_MACHINE_SPRITE;
    case FurnitureType.FRIDGE:
      return FRIDGE_SPRITE;
    case FurnitureType.TV:
      return TV_SPRITE;
    default:
      return null;
  }
}

// ─── Floor pattern selector ──────────────────────────────
function getRoomFloorTile(room: OfficeRoom, zoom: number): HTMLCanvasElement {
  const pattern = room.floorPattern ?? "checker";
  const c1 = room.color;
  const c2 = adjustBrightness(room.color, 1.08);
  const lineColor = adjustBrightness(room.color, 1.18);
  const dotColor = adjustBrightness(room.color, 1.25);
  const borderColor = adjustBrightness(room.color, 0.85);

  let tile: string[][];
  switch (pattern) {
    case "grid":
      tile = gridFloor(c1, lineColor);
      break;
    case "herringbone":
      tile = herringboneFloor(c1, c2);
      break;
    case "dot":
      tile = dotFloor(c1, dotColor);
      break;
    case "carpet":
      tile = carpetFloor(c1, borderColor);
      break;
    default:
      tile = checkerFloor(c1, c2);
      break;
  }
  return renderSpriteToCanvas(tile, zoom, `floor_${room.id}_${pattern}`);
}

// ─── Doorway detection ────────────────────────────────────
function roomHasDoorway(
  room: OfficeRoom,
  side: "north" | "south" | "east" | "west",
): boolean {
  const rx1 = room.x;
  const ry1 = room.y;
  const rx2 = room.x + room.width - 1;
  const ry2 = room.y + room.height - 1;

  switch (side) {
    case "north":
      return ry1 - 1 >= CORRIDOR_H_START && ry1 - 1 <= CORRIDOR_H_END;
    case "south":
      return ry2 + 1 >= CORRIDOR_H_START && ry2 + 1 <= CORRIDOR_H_END;
    case "west":
      return rx1 - 1 >= CORRIDOR_V_START && rx1 - 1 <= CORRIDOR_V_END;
    case "east":
      return rx2 + 1 >= CORRIDOR_V_START && rx2 + 1 <= CORRIDOR_V_END;
  }
}

function getDoorwayRange(
  room: OfficeRoom,
  side: "north" | "south" | "east" | "west",
): [number, number] {
  // Returns [start, end] in the parallel axis for the doorway opening
  switch (side) {
    case "north":
    case "south": {
      const overlapStart = Math.max(room.x, CORRIDOR_V_START);
      const overlapEnd = Math.min(room.x + room.width - 1, CORRIDOR_V_END);
      return [overlapStart, overlapEnd];
    }
    case "west":
    case "east": {
      const overlapStart = Math.max(room.y, CORRIDOR_H_START);
      const overlapEnd = Math.min(room.y + room.height - 1, CORRIDOR_H_END);
      return [overlapStart, overlapEnd];
    }
  }
}

// ─── Main render function ─────────────────────────────────

export function renderOffice(
  ctx: CanvasRenderingContext2D,
  canvasWidth: number,
  canvasHeight: number,
  layout: OfficeLayout,
  camera: Camera,
  characters: OfficeCharacter[],
  timeOfDay: TimeOfDay,
  selectedCharId: string | null,
  hoveredCharId: string | null,
  now: number,
): void {
  const { cols, rows, tileSize, rooms, furniture } = layout;
  const { zoom } = camera;
  const ts = tileSize * zoom;

  ctx.imageSmoothingEnabled = false;
  const tc = TIME_COLORS[timeOfDay];

  // Clear
  ctx.fillStyle = tc.groundBase;
  ctx.fillRect(0, 0, canvasWidth, canvasHeight);

  // ─── 1. Ground / outdoor paving texture ────────────────
  const camOffX = -camera.x * zoom + canvasWidth / 2;
  const camOffY = -camera.y * zoom + canvasHeight / 2;

  // Calculate visible tile range
  const startTileX = Math.floor(-camOffX / ts) - 1;
  const startTileY = Math.floor(-camOffY / ts) - 1;
  const endTileX = Math.ceil((canvasWidth - camOffX) / ts) + 1;
  const endTileY = Math.ceil((canvasHeight - camOffY) / ts) + 1;

  ctx.save();
  ctx.translate(camOffX, camOffY);

  for (let ty = startTileY; ty <= endTileY; ty++) {
    for (let tx = startTileX; tx <= endTileX; tx++) {
      const gt = groundTile(tc.groundBase, tc.groundAlt, tc.groundCrack, tx, ty);
      const gtCanvas = renderSpriteToCanvas(gt, zoom, `ground_${timeOfDay}_${((tx * 7919 + ty * 104729) >>> 0) % 1000}`);
      ctx.drawImage(gtCanvas, tx * ts, ty * ts);
    }
  }

  // ─── 2. Room floors (per-department patterns) ──────────
  for (const room of rooms) {
    const rx = room.x * ts;
    const ry = room.y * ts;

    const floorCanvas = getRoomFloorTile(room, zoom);

    for (let ty = 0; ty < room.height; ty++) {
      for (let tx = 0; tx < room.width; tx++) {
        ctx.drawImage(floorCanvas, rx + tx * ts, ry + ty * ts);
      }
    }

    // Inner floor shadow near walls (subtle darkening)
    ctx.fillStyle = tc.wallShadow;
    // Top edge shadow
    ctx.fillRect(rx, ry, room.width * ts, ts * 0.3);
    // Left edge shadow
    ctx.fillRect(rx, ry, ts * 0.3, room.height * ts);
    // Right edge shadow (lighter)
    ctx.globalAlpha = 0.5;
    ctx.fillRect(rx + room.width * ts - ts * 0.15, ry, ts * 0.15, room.height * ts);
    // Bottom edge shadow (lighter)
    ctx.fillRect(rx, ry + room.height * ts - ts * 0.15, room.width * ts, ts * 0.15);
    ctx.globalAlpha = 1.0;
  }

  // ─── 3. Corridors with carpet runner ───────────────────
  // Horizontal corridor (y = CORRIDOR_H_START to CORRIDOR_H_END)
  for (let x = 0; x < cols; x++) {
    for (let cy = CORRIDOR_H_START; cy <= CORRIDOR_H_END; cy++) {
      // Skip if inside a room
      const inRoom = rooms.some(
        (r) => x >= r.x && x < r.x + r.width && cy >= r.y && cy < r.y + r.height,
      );
      if (inRoom) continue;

      const ct = corridorTile(tc.corridorEdge, tc.corridorPath, tc.corridorPathAlt, true);
      const isMiddle = cy === CORRIDOR_H_START + 1;
      const tileKey = `corridor_h_${timeOfDay}_${isMiddle ? "mid" : "edge"}`;
      const ctCanvas = renderSpriteToCanvas(ct, zoom, tileKey);
      ctx.drawImage(ctCanvas, x * ts, cy * ts);
    }
  }

  // Vertical corridor (x = CORRIDOR_V_START to CORRIDOR_V_END)
  for (let y = 0; y < rows; y++) {
    for (let cx = CORRIDOR_V_START; cx <= CORRIDOR_V_END; cx++) {
      // Skip if inside a room or already drawn as horizontal corridor
      const inRoom = rooms.some(
        (r) => cx >= r.x && cx < r.x + r.width && y >= r.y && y < r.y + r.height,
      );
      if (inRoom) continue;
      if (y >= CORRIDOR_H_START && y <= CORRIDOR_H_END) continue;

      const ct = corridorTile(tc.corridorEdge, tc.corridorPath, tc.corridorPathAlt, false);
      const isMiddle = cx === CORRIDOR_V_START + 1;
      const tileKey = `corridor_v_${timeOfDay}_${isMiddle ? "mid" : "edge"}`;
      const ctCanvas = renderSpriteToCanvas(ct, zoom, tileKey);
      ctx.drawImage(ctCanvas, cx * ts, y * ts);
    }
  }

  // ─── 4. Thick walls with doorway cutouts ───────────────
  for (const room of rooms) {
    drawRoomWalls(ctx, room, ts, zoom, tc);
  }

  // ─── 5. Room sign plates ───────────────────────────────
  for (const room of rooms) {
    drawSignPlate(ctx, room, ts, zoom);
  }

  // ─── 6. Collect z-sorted drawables ─────────────────────
  const drawables: ZDrawable[] = [];

  // Determine which desks have active agents
  const activeDesks = new Set<string>();
  for (const char of characters) {
    if (char.state === CharacterState.TYPE) {
      activeDesks.add(`${char.seatX},${Math.max(0, char.seatY - 1)}`);
    }
  }

  // Add furniture to drawables
  for (const f of furniture) {
    const sprite = getFurnitureSprite(f, activeDesks);
    if (sprite === null) continue;

    // Decorative items rendered below furniture layer
    const isDecor =
      f.type === FurnitureType.RUG ||
      f.type === FurnitureType.CEILING_LIGHT ||
      f.type === FurnitureType.ENTRANCE_MAT;

    const spriteCanvas = renderSpriteToCanvas(
      sprite,
      zoom,
      `furn_${f.type}_${f.x}_${f.y}_${activeDesks.has(`${f.x},${f.y}`)}`,
    );
    const fx = f.x * ts;
    const fy = f.y * ts;
    const bottomY = isDecor ? fy - 1000 : fy + spriteCanvas.height;

    drawables.push({
      zY: bottomY,
      draw: (c: CanvasRenderingContext2D) => {
        const offX = (ts - spriteCanvas.width) / 2;
        const offY = ts - spriteCanvas.height;
        c.drawImage(spriteCanvas, fx + offX, fy + offY);
      },
    });
  }

  // Add characters to drawables
  for (const char of characters) {
    const palette = agentPalette(djb2(char.id));
    const frames = getCharFrames(char.facing, char.state);
    const frameIndex = Math.floor(char.animFrame) % frames.length;
    const frame = frames[frameIndex];

    const coloredSprite: string[][] = frame.map((row) =>
      row.map((key) => resolveColor(key, palette) ?? ""),
    );

    const spriteCanvas = renderSpriteToCanvas(
      coloredSprite,
      zoom,
      `char_${char.id}_${char.facing}_${char.state}_${frameIndex}`,
    );

    // Interpolated position
    let px: number, py: number;
    if (char.moveProgress < 1 && char.moveProgress > 0) {
      const prevX = char.gridX;
      const prevY = char.gridY;
      px =
        ((1 - char.moveProgress) * prevX + char.moveProgress * char.targetX) *
        ts;
      py =
        ((1 - char.moveProgress) * prevY + char.moveProgress * char.targetY) *
        ts;
    } else {
      px = char.gridX * ts;
      py = char.gridY * ts;
    }

    const charBottomY = py + spriteCanvas.height;
    const isSelected = selectedCharId === char.id;
    const isHovered = hoveredCharId === char.id;

    drawables.push({
      zY: charBottomY + 0.5,
      draw: (c: CanvasRenderingContext2D) => {
        const offX = (ts - spriteCanvas.width) / 2;
        const offY = ts - spriteCanvas.height;

        // ─── Character shadow (dark ellipse) ─────────
        c.save();
        c.fillStyle = "rgba(0, 0, 0, 0.18)";
        c.beginPath();
        c.ellipse(
          px + ts / 2,
          py + ts - 1 * zoom,
          ts * 0.35,
          ts * 0.12,
          0,
          0,
          Math.PI * 2,
        );
        c.fill();
        c.restore();

        // Selection/hover glow
        if (isSelected || isHovered) {
          c.save();
          c.shadowColor = isSelected ? "#fb923c" : "#fdba74";
          c.shadowBlur = 8 * zoom;
          c.drawImage(spriteCanvas, px + offX, py + offY);
          c.restore();
        }

        c.drawImage(spriteCanvas, px + offX, py + offY);

        // Status dot
        const dotX = px + offX + spriteCanvas.width - 2 * zoom;
        const dotY = py + offY;
        c.fillStyle = char.statusColor;
        c.beginPath();
        c.arc(dotX, dotY, 2.5 * zoom, 0, Math.PI * 2);
        c.fill();

        // Pulse ring for active agents
        if (
          char.state === CharacterState.TYPE ||
          char.state === CharacterState.WALK
        ) {
          const pulseRadius = 3 * zoom + Math.sin(now * 0.004) * 1.5 * zoom;
          c.strokeStyle = char.statusColor;
          c.lineWidth = zoom;
          c.globalAlpha = 0.5 + Math.sin(now * 0.004) * 0.3;
          c.beginPath();
          c.arc(dotX, dotY, pulseRadius, 0, Math.PI * 2);
          c.stroke();
          c.globalAlpha = 1.0;
        }

        // Name label with team underline and division pip
        const labelFontSize = Math.max(7, 8 * zoom);
        c.font = `${labelFontSize}px monospace`;
        c.textAlign = "center";

        const labelText =
          char.name.length > 12 ? char.name.slice(0, 12) + ".." : char.name;
        const labelWidth = c.measureText(labelText).width + 10 * zoom;
        const labelX = px + ts / 2;
        const labelY = py + offY - 4 * zoom;

        const labelLeft = labelX - labelWidth / 2;
        const labelTop = labelY - labelFontSize;
        const labelH = labelFontSize + 3 * zoom;
        const labelR = 3 * zoom;

        // Label background
        c.fillStyle = "rgba(15, 17, 23, 0.78)";
        c.beginPath();
        c.roundRect(labelLeft, labelTop, labelWidth, labelH, labelR);
        c.fill();

        // Team-colored underline bar at bottom of label
        const teamClr = char.teamColor;
        if (teamClr !== undefined) {
          const barH = 2 * zoom;
          c.save();
          c.beginPath();
          c.roundRect(labelLeft, labelTop, labelWidth, labelH, labelR);
          c.clip();
          c.fillStyle = teamClr;
          c.globalAlpha = 0.85;
          c.fillRect(labelLeft, labelTop + labelH - barH, labelWidth, barH);
          c.globalAlpha = 1.0;
          c.restore();
        }

        // Division color pip on the left side of label
        const divClr = char.divisionColor ?? char.statusColor;
        c.fillStyle = divClr;
        c.beginPath();
        c.arc(
          labelLeft + 4 * zoom,
          labelY - labelFontSize / 2 + 1.5 * zoom,
          2 * zoom,
          0,
          Math.PI * 2,
        );
        c.fill();

        c.fillStyle = isSelected ? "#fdba74" : "#d0d4e0";
        c.fillText(labelText, labelX + 2 * zoom, labelY - 1 * zoom);
        c.textAlign = "left";

        // Speech bubble for current task
        if (
          char.currentTask !== undefined &&
          (char.state === CharacterState.TYPE || char.bubbleTimer > 0)
        ) {
          drawSpeechBubble(
            c,
            px + ts / 2,
            py + offY - 16 * zoom,
            char.currentTask.slice(0, 30),
            zoom,
          );
        }

        // ZZZ for sleeping agents
        if (char.state === CharacterState.SLEEP) {
          const zFontSize = Math.max(6, 7 * zoom);
          c.font = `bold ${zFontSize}px monospace`;
          c.fillStyle = "#fdba74";
          const zOff = Math.sin(now * 0.002) * 3 * zoom;
          c.globalAlpha = 0.6 + Math.sin(now * 0.003) * 0.3;
          c.fillText("z", px + ts - 2 * zoom, py + offY - 2 * zoom + zOff);
          c.fillText(
            "Z",
            px + ts + 2 * zoom,
            py + offY - 8 * zoom + zOff * 0.7,
          );
          c.fillText(
            "Z",
            px + ts + 5 * zoom,
            py + offY - 14 * zoom + zOff * 0.4,
          );
          c.globalAlpha = 1.0;
        }
      },
    });
  }

  // Sort by zY and draw
  drawables.sort((a, b) => a.zY - b.zY);
  for (const d of drawables) {
    d.draw(ctx);
  }

  // ─── 7. Ambient lighting (PC glow, localized lights) ───
  drawAmbientLighting(ctx, characters, furniture, activeDesks, ts, zoom, timeOfDay, now);

  // ─── 8. Time-of-day overlay ────────────────────────────
  if (tc.overlayAlpha > 0) {
    ctx.fillStyle = tc.overlay;
    ctx.globalAlpha = tc.overlayAlpha;
    ctx.fillRect(0, 0, cols * ts, rows * ts);
    ctx.globalAlpha = 1.0;
  }

  ctx.restore();
}

// ─── Room walls with depth ───────────────────────────────

function drawRoomWalls(
  ctx: CanvasRenderingContext2D,
  room: OfficeRoom,
  ts: number,
  zoom: number,
  tc: (typeof TIME_COLORS)[TimeOfDay],
): void {
  const rx = room.x * ts;
  const ry = room.y * ts;
  const rw = room.width * ts;
  const rh = room.height * ts;
  const wallThick = Math.max(3, 4 * zoom);
  const bevelThick = Math.max(1, 1.5 * zoom);

  const sides: Array<"north" | "south" | "east" | "west"> = [
    "north",
    "south",
    "east",
    "west",
  ];

  for (const side of sides) {
    const hasDoor = roomHasDoorway(room, side);
    let doorStart = 0;
    let doorEnd = 0;
    if (hasDoor) {
      const [ds, de] = getDoorwayRange(room, side);
      doorStart = ds;
      doorEnd = de;
    }

    ctx.fillStyle = tc.wallFace;
    const topColor = tc.wallTop;

    switch (side) {
      case "north": {
        if (hasDoor) {
          // Wall left of door
          const leftEnd = doorStart * ts - rx;
          if (leftEnd > 0) {
            ctx.fillStyle = tc.wallFace;
            ctx.fillRect(rx, ry - wallThick, leftEnd, wallThick);
            ctx.fillStyle = topColor;
            ctx.fillRect(rx, ry - wallThick, leftEnd, bevelThick);
          }
          // Wall right of door
          const rightStart = (doorEnd + 1) * ts - rx;
          if (rightStart < rw) {
            ctx.fillStyle = tc.wallFace;
            ctx.fillRect(rx + rightStart, ry - wallThick, rw - rightStart, wallThick);
            ctx.fillStyle = topColor;
            ctx.fillRect(rx + rightStart, ry - wallThick, rw - rightStart, bevelThick);
          }
        } else {
          ctx.fillStyle = tc.wallFace;
          ctx.fillRect(rx, ry - wallThick, rw, wallThick);
          ctx.fillStyle = topColor;
          ctx.fillRect(rx, ry - wallThick, rw, bevelThick);
        }
        break;
      }
      case "south": {
        if (hasDoor) {
          const leftEnd = doorStart * ts - rx;
          if (leftEnd > 0) {
            ctx.fillStyle = tc.wallFace;
            ctx.fillRect(rx, ry + rh, leftEnd, wallThick);
          }
          const rightStart = (doorEnd + 1) * ts - rx;
          if (rightStart < rw) {
            ctx.fillStyle = tc.wallFace;
            ctx.fillRect(rx + rightStart, ry + rh, rw - rightStart, wallThick);
          }
        } else {
          ctx.fillStyle = tc.wallFace;
          ctx.fillRect(rx, ry + rh, rw, wallThick);
        }
        break;
      }
      case "west": {
        if (hasDoor) {
          const topEnd = doorStart * ts - ry;
          if (topEnd > 0) {
            ctx.fillStyle = tc.wallFace;
            ctx.fillRect(rx - wallThick, ry, wallThick, topEnd);
            ctx.fillStyle = topColor;
            ctx.fillRect(rx - wallThick, ry, bevelThick, topEnd);
          }
          const bottomStart = (doorEnd + 1) * ts - ry;
          if (bottomStart < rh) {
            ctx.fillStyle = tc.wallFace;
            ctx.fillRect(rx - wallThick, ry + bottomStart, wallThick, rh - bottomStart);
            ctx.fillStyle = topColor;
            ctx.fillRect(rx - wallThick, ry + bottomStart, bevelThick, rh - bottomStart);
          }
        } else {
          ctx.fillStyle = tc.wallFace;
          ctx.fillRect(rx - wallThick, ry, wallThick, rh);
          ctx.fillStyle = topColor;
          ctx.fillRect(rx - wallThick, ry, bevelThick, rh);
        }
        break;
      }
      case "east": {
        if (hasDoor) {
          const topEnd = doorStart * ts - ry;
          if (topEnd > 0) {
            ctx.fillStyle = tc.wallFace;
            ctx.fillRect(rx + rw, ry, wallThick, topEnd);
          }
          const bottomStart = (doorEnd + 1) * ts - ry;
          if (bottomStart < rh) {
            ctx.fillStyle = tc.wallFace;
            ctx.fillRect(rx + rw, ry + bottomStart, wallThick, rh - bottomStart);
          }
        } else {
          ctx.fillStyle = tc.wallFace;
          ctx.fillRect(rx + rw, ry, wallThick, rh);
        }
        break;
      }
    }
  }

  // Corner blocks
  ctx.fillStyle = tc.wallFace;
  ctx.fillRect(rx - wallThick, ry - wallThick, wallThick, wallThick);
  ctx.fillRect(rx + rw, ry - wallThick, wallThick, wallThick);
  ctx.fillRect(rx - wallThick, ry + rh, wallThick, wallThick);
  ctx.fillRect(rx + rw, ry + rh, wallThick, wallThick);
}

// ─── Sign plate ──────────────────────────────────────────

function drawSignPlate(
  ctx: CanvasRenderingContext2D,
  room: OfficeRoom,
  ts: number,
  zoom: number,
): void {
  const fontSize = Math.max(8, 9 * zoom);
  ctx.font = `bold ${fontSize}px monospace`;
  const textWidth = ctx.measureText(room.label).width;
  const padX = 6 * zoom;
  const padY = 3 * zoom;
  const plateW = textWidth + padX * 2;
  const plateH = fontSize + padY * 2;

  const rx = room.x * ts;
  const ry = room.y * ts;
  const plateX = rx + (room.width * ts) / 2 - plateW / 2;
  const plateY = ry - plateH - Math.max(3, 4 * zoom) + 1;

  // Plate background
  ctx.fillStyle = "rgba(15, 17, 23, 0.88)";
  ctx.beginPath();
  ctx.roundRect(plateX, plateY, plateW, plateH, 3 * zoom);
  ctx.fill();

  // Plate border with room accent color
  ctx.strokeStyle = room.labelColor;
  ctx.lineWidth = Math.max(1, 1.5 * zoom);
  ctx.globalAlpha = 0.6;
  ctx.beginPath();
  ctx.roundRect(plateX, plateY, plateW, plateH, 3 * zoom);
  ctx.stroke();
  ctx.globalAlpha = 1.0;

  // Text
  ctx.fillStyle = room.labelColor;
  ctx.textAlign = "center";
  ctx.fillText(room.label, rx + (room.width * ts) / 2, plateY + fontSize + padY - 1);
  ctx.textAlign = "left";
}

// ─── Ambient lighting ────────────────────────────────────

function drawAmbientLighting(
  ctx: CanvasRenderingContext2D,
  characters: OfficeCharacter[],
  furniture: Furniture[],
  activeDesks: Set<string>,
  ts: number,
  zoom: number,
  timeOfDay: TimeOfDay,
  now: number,
): void {
  // PC monitor glow for active desks
  const glowIntensity = timeOfDay === "night" ? 0.12 : timeOfDay === "dusk" ? 0.08 : 0.04;
  if (glowIntensity > 0) {
    for (const f of furniture) {
      if (f.type !== FurnitureType.PC) continue;
      if (!activeDesks.has(`${f.x},${f.y}`)) continue;

      const cx = (f.x + 0.5) * ts;
      const cy = (f.y + 1.5) * ts;
      const radius = ts * 2.5;

      const gradient = ctx.createRadialGradient(cx, cy, 0, cx, cy, radius);
      gradient.addColorStop(0, `rgba(110, 231, 183, ${glowIntensity})`);
      gradient.addColorStop(1, "rgba(110, 231, 183, 0)");

      ctx.fillStyle = gradient;
      ctx.beginPath();
      ctx.arc(cx, cy, radius, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  // Lounge warm glow (from table/lamp area)
  if (timeOfDay === "night" || timeOfDay === "dusk") {
    for (const f of furniture) {
      if (f.type !== FurnitureType.TABLE_ROUND) continue;

      const cx = (f.x + 0.5) * ts;
      const cy = (f.y + 0.5) * ts;
      const radius = ts * 3;
      const intensity = timeOfDay === "night" ? 0.10 : 0.06;
      const pulse = 1 + Math.sin(now * 0.001) * 0.02;

      const gradient = ctx.createRadialGradient(cx, cy, 0, cx, cy, radius * pulse);
      gradient.addColorStop(0, `rgba(252, 211, 77, ${intensity})`);
      gradient.addColorStop(1, "rgba(252, 211, 77, 0)");

      ctx.fillStyle = gradient;
      ctx.beginPath();
      ctx.arc(cx, cy, radius * pulse, 0, Math.PI * 2);
      ctx.fill();
    }
  }
}

// ─── Minimap renderer ─────────────────────────────────────

export function renderMinimap(
  ctx: CanvasRenderingContext2D,
  layout: OfficeLayout,
  characters: OfficeCharacter[],
  camera: Camera,
  canvasWidth: number,
  canvasHeight: number,
  minimapWidth: number,
  minimapHeight: number,
): void {
  const { cols, rows, rooms } = layout;
  const scale = Math.min(minimapWidth / cols, minimapHeight / rows);

  // Background
  ctx.fillStyle = "rgba(15, 17, 23, 0.88)";
  ctx.fillRect(0, 0, minimapWidth, minimapHeight);

  // Corridors
  ctx.fillStyle = "rgba(100, 90, 120, 0.4)";
  for (let x = 0; x < cols; x++) {
    for (let cy = CORRIDOR_H_START; cy <= CORRIDOR_H_END; cy++) {
      ctx.fillRect(x * scale, cy * scale, scale, scale);
    }
  }
  for (let y = 0; y < rows; y++) {
    for (let cx = CORRIDOR_V_START; cx <= CORRIDOR_V_END; cx++) {
      if (y >= CORRIDOR_H_START && y <= CORRIDOR_H_END) continue;
      ctx.fillRect(cx * scale, y * scale, scale, scale);
    }
  }

  // Rooms
  for (const room of rooms) {
    ctx.fillStyle = room.color;
    ctx.fillRect(
      room.x * scale,
      room.y * scale,
      room.width * scale,
      room.height * scale,
    );
    ctx.strokeStyle = "rgba(120, 110, 140, 0.5)";
    ctx.lineWidth = 1;
    ctx.strokeRect(
      room.x * scale,
      room.y * scale,
      room.width * scale,
      room.height * scale,
    );
  }

  // Characters as dots
  for (const char of characters) {
    ctx.fillStyle = char.statusColor;
    ctx.beginPath();
    ctx.arc(
      (char.gridX + 0.5) * scale,
      (char.gridY + 0.5) * scale,
      Math.max(2, scale * 0.4),
      0,
      Math.PI * 2,
    );
    ctx.fill();
  }

  // Camera viewport indicator
  const ts = layout.tileSize * camera.zoom;
  const vpX = (camera.x - canvasWidth / (2 * camera.zoom)) / layout.tileSize;
  const vpY = (camera.y - canvasHeight / (2 * camera.zoom)) / layout.tileSize;
  const vpW = canvasWidth / ts;
  const vpH = canvasHeight / ts;

  ctx.strokeStyle = "#ffffff";
  ctx.lineWidth = 1.5;
  ctx.globalAlpha = 0.6;
  ctx.strokeRect(vpX * scale, vpY * scale, vpW * scale, vpH * scale);
  ctx.globalAlpha = 1.0;

  // Border
  ctx.strokeStyle = "rgba(120, 110, 140, 0.5)";
  ctx.lineWidth = 2;
  ctx.strokeRect(0, 0, minimapWidth, minimapHeight);
}

// ─── Helper functions ─────────────────────────────────────

function drawSpeechBubble(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  text: string,
  zoom: number,
): void {
  const fontSize = Math.max(6, 7 * zoom);
  ctx.font = `${fontSize}px monospace`;
  const textWidth = ctx.measureText(text).width;
  const padX = 5 * zoom;
  const padY = 3 * zoom;
  const bubbleW = textWidth + padX * 2;
  const bubbleH = fontSize + padY * 2;
  const bubbleX = x - bubbleW / 2;
  const bubbleY = y - bubbleH;

  // Bubble background
  ctx.fillStyle = "rgba(22, 27, 38, 0.90)";
  ctx.beginPath();
  ctx.roundRect(bubbleX, bubbleY, bubbleW, bubbleH, 5 * zoom);
  ctx.fill();

  // Bubble border
  ctx.strokeStyle = "rgba(251, 146, 60, 0.35)";
  ctx.lineWidth = Math.max(1, 1.2 * zoom);
  ctx.beginPath();
  ctx.roundRect(bubbleX, bubbleY, bubbleW, bubbleH, 5 * zoom);
  ctx.stroke();

  // Tail
  ctx.fillStyle = "rgba(22, 27, 38, 0.90)";
  ctx.beginPath();
  ctx.moveTo(x - 3 * zoom, bubbleY + bubbleH);
  ctx.lineTo(x, bubbleY + bubbleH + 4 * zoom);
  ctx.lineTo(x + 3 * zoom, bubbleY + bubbleH);
  ctx.fill();

  // Text
  ctx.fillStyle = "#6ee7b7";
  ctx.textAlign = "center";
  ctx.fillText(text, x, bubbleY + fontSize + padY - 1);
  ctx.textAlign = "left";
}

function adjustBrightness(hex: string, factor: number): string {
  const r = parseInt(hex.slice(1, 3), 16);
  const g = parseInt(hex.slice(3, 5), 16);
  const b = parseInt(hex.slice(5, 7), 16);
  const nr = Math.min(255, Math.round(r * factor));
  const ng = Math.min(255, Math.round(g * factor));
  const nb = Math.min(255, Math.round(b * factor));
  return `#${nr.toString(16).padStart(2, "0")}${ng.toString(16).padStart(2, "0")}${nb.toString(16).padStart(2, "0")}`;
}

function djb2(str: string): number {
  let hash = 5381;
  for (let i = 0; i < str.length; i++) {
    hash = ((hash << 5) - hash + str.charCodeAt(i)) >>> 0;
  }
  return hash;
}

// ─── Hit testing ──────────────────────────────────────────

/** Check if a canvas point hits a character */
export function hitTestCharacter(
  canvasX: number,
  canvasY: number,
  camera: Camera,
  canvasWidth: number,
  canvasHeight: number,
  characters: OfficeCharacter[],
  tileSize: number,
): OfficeCharacter | null {
  const { zoom } = camera;

  // Convert canvas coords to world coords
  const worldX = (canvasX - canvasWidth / 2) / zoom + camera.x;
  const worldY = (canvasY - canvasHeight / 2) / zoom + camera.y;

  // Check each character (reverse order = topmost first)
  for (let i = characters.length - 1; i >= 0; i--) {
    const char = characters[i];
    const cx = char.gridX * tileSize;
    const cy = char.gridY * tileSize;
    const charW = tileSize;
    const charH = tileSize * 1.5;

    if (
      worldX >= cx &&
      worldX <= cx + charW &&
      worldY >= cy - charH * 0.3 &&
      worldY <= cy + charH
    ) {
      return char;
    }
  }

  return null;
}
