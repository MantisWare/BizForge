<!-- src/lib/components/office/Scene3D.svelte -->
<!-- The 3D scene: floor zones, walls, corridor, desks, agent characters, lighting -->
<script lang="ts">
  import { T } from '@threlte/core';
  import { OrbitControls, Text } from '@threlte/extras';
  import type { BizforgeAgent } from '$api/types';
  import type { AgentOrgInfo } from '$lib/utils/orgColors';
  import AgentDesk3D from './AgentDesk3D.svelte';

  interface Props {
    agents: BizforgeAgent[];
    agentOrgMap?: Map<string, AgentOrgInfo>;
    selectedAgentId?: string | null;
    onAgentClick?: (agent: BizforgeAgent) => void;
  }

  let { agents, agentOrgMap = new Map(), selectedAgentId = null, onAgentClick }: Props = $props();

  // ─── Zone definitions matching pixel office layout ───────
  const ZONES = [
    { id: 'engineering', label: 'ENGINEERING', color: '#3a3665', labelColor: '#fdba74', glowColor: '#ffdd88', neonColor: '#ff9020', x: -7.5, z: -5, w: 7, d: 5.5, seats: 7 },
    { id: 'product', label: 'PRODUCT', color: '#2d3a50', labelColor: '#93c5fd', glowColor: '#90d0ff', neonColor: '#40a0ff', x: 4.5, z: -5, w: 7, d: 5.5, seats: 6 },
    { id: 'operations', label: 'OPERATIONS', color: '#283840', labelColor: '#6ee7b7', glowColor: '#60ffb0', neonColor: '#20e080', x: -7.5, z: 4, w: 7, d: 5, seats: 4 },
    { id: 'research', label: 'RESEARCH', color: '#3a2d40', labelColor: '#f9a8d4', glowColor: '#ff90c0', neonColor: '#ff50a0', x: 4.5, z: 4, w: 5, d: 5, seats: 3 },
    { id: 'lounge', label: 'LOUNGE', color: '#3a3030', labelColor: '#fcd6a5', glowColor: '#ffcc70', neonColor: '#ffa030', x: 10, z: 4, w: 3.5, d: 5, seats: 2 },
  ] as const;

  // Conference table definitions — center of each zone (except research/lounge)
  const CONF_TABLES: readonly { zoneId: string; cx: number; cz: number; w: number; d: number }[] = [
    { zoneId: 'engineering', cx: -4, cz: -2.5, w: 4.5, d: 1.4 },
    { zoneId: 'product',     cx: 8,  cz: -2.5, w: 4.5, d: 1.4 },
    { zoneId: 'operations',  cx: -4, cz: 6.5,  w: 4.5, d: 1.4 },
  ] as const;

  type SeatDef = { pos: [number, number, number]; deskType: 'desk' | 'conference'; facingZ: number };

  // Seat positions per zone — conference seats around the table, desk seats along perimeter
  const ZONE_SEATS: Record<string, SeatDef[]> = {
    engineering: [
      // 3 seats on the near side (facing table, facingZ = -1 → face toward -z)
      { pos: [-5.5, 0, -1.3], deskType: 'conference', facingZ: -1 },
      { pos: [-4,   0, -1.3], deskType: 'conference', facingZ: -1 },
      { pos: [-2.5, 0, -1.3], deskType: 'conference', facingZ: -1 },
      // 3 seats on the far side (facing table, facingZ = 1 → face toward +z)
      { pos: [-5.5, 0, -3.7], deskType: 'conference', facingZ: 1 },
      { pos: [-4,   0, -3.7], deskType: 'conference', facingZ: 1 },
      { pos: [-2.5, 0, -3.7], deskType: 'conference', facingZ: 1 },
      // 1 perimeter desk (wall)
      { pos: [-7,   0, -4.2], deskType: 'desk', facingZ: 1 },
    ],
    product: [
      { pos: [6.5, 0, -1.3], deskType: 'conference', facingZ: -1 },
      { pos: [8,   0, -1.3], deskType: 'conference', facingZ: -1 },
      { pos: [9.5, 0, -1.3], deskType: 'conference', facingZ: -1 },
      { pos: [6.5, 0, -3.7], deskType: 'conference', facingZ: 1 },
      { pos: [8,   0, -3.7], deskType: 'conference', facingZ: 1 },
      { pos: [9.5, 0, -3.7], deskType: 'conference', facingZ: 1 },
    ],
    operations: [
      { pos: [-5.5, 0, 5.7], deskType: 'conference', facingZ: 1 },
      { pos: [-4,   0, 5.7], deskType: 'conference', facingZ: 1 },
      { pos: [-5.5, 0, 7.3], deskType: 'conference', facingZ: -1 },
      { pos: [-4,   0, 7.3], deskType: 'conference', facingZ: -1 },
    ],
    research: [
      { pos: [6.5, 0, 6.5], deskType: 'desk', facingZ: 1 },
      { pos: [8.5, 0, 6.0], deskType: 'desk', facingZ: 1 },
      { pos: [8.5, 0, 8.5], deskType: 'desk', facingZ: -1 },
    ],
    lounge: [
      { pos: [11, 0, 5.0], deskType: 'desk', facingZ: 1 },
      { pos: [11, 0, 8.0], deskType: 'desk', facingZ: -1 },
    ],
  };

  // Map each agent to a zone and specific seat
  function agentPosition(agent: BizforgeAgent, index: number): { pos: [number, number, number]; zoneId: string; deskType: 'desk' | 'conference'; facingZ: number } {
    let accumulated = 0;
    for (const zone of ZONES) {
      const seats = ZONE_SEATS[zone.id] ?? [];
      if (index < accumulated + seats.length) {
        const seat = seats[index - accumulated];
        return { pos: seat.pos, zoneId: zone.id, deskType: seat.deskType, facingZ: seat.facingZ };
      }
      accumulated += seats.length;
    }
    // Overflow: place as standard desk in operations
    const zone = ZONES[2];
    const x = zone.x + 1.5 + (index % 3) * 2.2;
    const z = zone.z + 1.5 + Math.floor(index / 3) * 2.5;
    return { pos: [x, 0, z], zoneId: zone.id, deskType: 'desk', facingZ: 1 };
  }

  // Status to emissive color
  function statusEmissive(status: string): string {
    switch (status) {
      case 'running': return '#22c55e';
      case 'idle': return '#f97316';
      case 'sleeping': return '#475569';
      case 'paused': return '#f59e0b';
      case 'terminated': return '#ef4444';
      default: return '#64748b';
    }
  }

  // Corridor dimensions
  const CORRIDOR_WIDTH = 2.5;
  const FLOOR_W = 24;
  const FLOOR_D = 18;
</script>

<!-- Camera -->
<T.PerspectiveCamera makeDefault position={[16, 14, 16]} fov={50}>
  <OrbitControls
    enableDamping
    dampingFactor={0.08}
    target={[1, 0, 1]}
    maxPolarAngle={Math.PI / 2.2}
    minDistance={5}
    maxDistance={35}
  />
</T.PerspectiveCamera>

<!-- Lighting — brighter and warmer -->
<T.AmbientLight intensity={0.5} color="#c8c0e0" />
<T.DirectionalLight position={[10, 15, 8]} intensity={0.9} color="#fff8f0" castShadow />
<T.DirectionalLight position={[-8, 10, -6]} intensity={0.35} color="#fbb98a" />
<T.PointLight position={[1, 8, 1]} intensity={0.6} color="#fb923c" distance={25} decay={2} />
<T.HemisphereLight args={['#c8d8f0', '#2a2840', 0.4]} />

<!-- Base floor (outdoor/courtyard ground) -->
<T.Mesh rotation.x={-Math.PI / 2} position={[1, -0.02, 1]} receiveShadow>
  <T.PlaneGeometry args={[FLOOR_W + 6, FLOOR_D + 6]} />
  <T.MeshStandardMaterial color="#4a4858" roughness={0.95} metalness={0.05} />
</T.Mesh>

<!-- ─── Department floor zones ──────────────────────── -->
{#each ZONES as zone}
  <T.Mesh rotation.x={-Math.PI / 2} position={[zone.x + zone.w / 2, 0.005, zone.z + zone.d / 2]} receiveShadow>
    <T.PlaneGeometry args={[zone.w, zone.d]} />
    <T.MeshStandardMaterial color={zone.color} roughness={0.85} metalness={0.08} />
  </T.Mesh>

  <!-- Zone border outline (thin raised edge) -->
  <!-- North edge -->
  <T.Mesh position={[zone.x + zone.w / 2, 0.04, zone.z]}>
    <T.BoxGeometry args={[zone.w, 0.08, 0.06]} />
    <T.MeshStandardMaterial color={zone.labelColor} transparent opacity={0.35} />
  </T.Mesh>
  <!-- South edge -->
  <T.Mesh position={[zone.x + zone.w / 2, 0.04, zone.z + zone.d]}>
    <T.BoxGeometry args={[zone.w, 0.08, 0.06]} />
    <T.MeshStandardMaterial color={zone.labelColor} transparent opacity={0.25} />
  </T.Mesh>
  <!-- West edge -->
  <T.Mesh position={[zone.x, 0.04, zone.z + zone.d / 2]}>
    <T.BoxGeometry args={[0.06, 0.08, zone.d]} />
    <T.MeshStandardMaterial color={zone.labelColor} transparent opacity={0.35} />
  </T.Mesh>
  <!-- East edge -->
  <T.Mesh position={[zone.x + zone.w, 0.04, zone.z + zone.d / 2]}>
    <T.BoxGeometry args={[0.06, 0.08, zone.d]} />
    <T.MeshStandardMaterial color={zone.labelColor} transparent opacity={0.25} />
  </T.Mesh>

  <!-- Zone label — neon sign -->
  <T.Group position={[zone.x + zone.w / 2, 3.2, zone.z + 0.3]}>
      <!-- Dark backing plate (thin box so it's solid from both sides) -->
      <T.Mesh>
        <T.BoxGeometry args={[zone.label.length * 0.24 + 0.8, 0.55, 0.04]} />
        <T.MeshBasicMaterial color="#080810" />
      </T.Mesh>
      <!-- Neon border frame (slightly larger box behind the plate) -->
      <T.Mesh>
        <T.BoxGeometry args={[zone.label.length * 0.24 + 0.9, 0.65, 0.03]} />
        <T.MeshBasicMaterial color={zone.neonColor} transparent opacity={0.5} />
      </T.Mesh>
      <!-- Label text — front face -->
      <Text
        text={zone.label}
        fontSize={0.3}
        color={zone.glowColor}
        anchorX="center"
        anchorY="middle"
        outlineWidth={0.012}
        outlineColor={zone.neonColor}
        position.z={0.025}
      />
      <!-- Label text — back face -->
      <Text
        text={zone.label}
        fontSize={0.3}
        color={zone.glowColor}
        anchorX="center"
        anchorY="middle"
        outlineWidth={0.012}
        outlineColor={zone.neonColor}
        position.z={-0.025}
        rotation.y={Math.PI}
      />
      <!-- Neon glow light -->
      <T.PointLight
        intensity={1.5}
        color={zone.neonColor}
        distance={5}
        decay={2}
      />
  </T.Group>

  <!-- Accent spot light per zone -->
  <T.PointLight
    position={[zone.x + zone.w / 2, 4, zone.z + zone.d / 2]}
    intensity={0.3}
    color={zone.labelColor}
    distance={zone.w + 2}
    decay={2}
  />
{/each}

<!-- ─── Corridors (raised path between zones) ──────── -->
<!-- Horizontal corridor -->
<T.Mesh rotation.x={-Math.PI / 2} position={[1, 0.008, 1.5]} receiveShadow>
  <T.PlaneGeometry args={[FLOOR_W, CORRIDOR_WIDTH]} />
  <T.MeshStandardMaterial color="#3a3550" roughness={0.8} metalness={0.1} />
</T.Mesh>
<!-- Corridor center runner -->
<T.Mesh rotation.x={-Math.PI / 2} position={[1, 0.012, 1.5]}>
  <T.PlaneGeometry args={[FLOOR_W - 1, 0.8]} />
  <T.MeshStandardMaterial color="#484060" roughness={0.75} metalness={0.15} />
</T.Mesh>

<!-- Vertical corridor -->
<T.Mesh rotation.x={-Math.PI / 2} position={[1, 0.008, 1]} receiveShadow>
  <T.PlaneGeometry args={[CORRIDOR_WIDTH, FLOOR_D]} />
  <T.MeshStandardMaterial color="#3a3550" roughness={0.8} metalness={0.1} />
</T.Mesh>
<!-- Corridor center runner (vertical) -->
<T.Mesh rotation.x={-Math.PI / 2} position={[1, 0.012, 1]}>
  <T.PlaneGeometry args={[0.8, FLOOR_D - 1]} />
  <T.MeshStandardMaterial color="#484060" roughness={0.75} metalness={0.15} />
</T.Mesh>

<!-- ─── Floor grid lines (subtle) ──────────────────── -->
{#each Array(25) as _, i}
  <T.Mesh rotation.x={-Math.PI / 2} position={[-11 + i, 0.003, 1]}>
    <T.PlaneGeometry args={[0.015, FLOOR_D + 4]} />
    <T.MeshBasicMaterial color="#5a5570" transparent opacity={0.15} />
  </T.Mesh>
{/each}
{#each Array(19) as _, i}
  <T.Mesh rotation.x={-Math.PI / 2} position={[1, 0.003, -8 + i]}>
    <T.PlaneGeometry args={[FLOOR_W + 4, 0.015]} />
    <T.MeshBasicMaterial color="#5a5570" transparent opacity={0.15} />
  </T.Mesh>
{/each}

<!-- ─── Outer walls ────────────────────────────────── -->
<!-- Back wall -->
<T.Mesh position={[1, 1.5, -8]}>
  <T.BoxGeometry args={[FLOOR_W + 2, 3, 0.15]} />
  <T.MeshStandardMaterial color="#2a2845" roughness={0.8} metalness={0.05} />
</T.Mesh>
<!-- Left wall -->
<T.Mesh position={[-11, 1.5, 1]}>
  <T.BoxGeometry args={[0.15, 3, FLOOR_D + 2]} />
  <T.MeshStandardMaterial color="#2a2845" roughness={0.8} metalness={0.05} />
</T.Mesh>
<!-- Right wall -->
<T.Mesh position={[14, 1.5, 1]}>
  <T.BoxGeometry args={[0.15, 3, FLOOR_D + 2]} />
  <T.MeshStandardMaterial color="#2a2845" roughness={0.8} metalness={0.05} />
</T.Mesh>
<!-- Front wall removed for visibility -->

<!-- ─── Zone furniture & props ─────────────────────── -->

<!-- Meeting table (research zone) -->
<T.Mesh position={[8.5, 0.42, 7.5]} castShadow>
  <T.CylinderGeometry args={[1, 1, 0.1, 24]} />
  <T.MeshStandardMaterial color="#4a3860" roughness={0.6} metalness={0.2} />
</T.Mesh>
<T.Mesh position={[8.5, 0.2, 7.5]}>
  <T.CylinderGeometry args={[0.06, 0.06, 0.4, 8]} />
  <T.MeshStandardMaterial color="#3a3050" />
</T.Mesh>

<!-- Lounge sofa 1 -->
<T.Mesh position={[11, 0.35, 5.5]} castShadow>
  <T.BoxGeometry args={[2, 0.65, 0.85]} />
  <T.MeshStandardMaterial color="#5a3880" roughness={0.85} />
</T.Mesh>
<T.Mesh position={[11, 0.72, 5.85]}>
  <T.BoxGeometry args={[2, 0.45, 0.2]} />
  <T.MeshStandardMaterial color="#6a4890" roughness={0.85} />
</T.Mesh>

<!-- Lounge sofa 2 (facing first sofa) -->
<T.Mesh position={[11, 0.35, 7.4]} castShadow>
  <T.BoxGeometry args={[2, 0.65, 0.85]} />
  <T.MeshStandardMaterial color="#5a3880" roughness={0.85} />
</T.Mesh>
<T.Mesh position={[11, 0.72, 7.05]}>
  <T.BoxGeometry args={[2, 0.45, 0.2]} />
  <T.MeshStandardMaterial color="#6a4890" roughness={0.85} />
</T.Mesh>

<!-- Coffee table between sofas -->
<T.Mesh position={[11, 0.25, 6.45]} castShadow>
  <T.BoxGeometry args={[1.2, 0.08, 0.5]} />
  <T.MeshStandardMaterial color="#5a4a40" roughness={0.7} metalness={0.15} />
</T.Mesh>
<T.Mesh position={[10.5, 0.12, 6.45]}>
  <T.CylinderGeometry args={[0.03, 0.03, 0.22, 6]} />
  <T.MeshStandardMaterial color="#4a3a30" />
</T.Mesh>
<T.Mesh position={[11.5, 0.12, 6.45]}>
  <T.CylinderGeometry args={[0.03, 0.03, 0.22, 6]} />
  <T.MeshStandardMaterial color="#4a3a30" />
</T.Mesh>

<!-- TV on wall above sofas -->
<T.Mesh position={[11, 1.8, 4.3]}>
  <T.BoxGeometry args={[1.8, 1.1, 0.06]} />
  <T.MeshStandardMaterial color="#1a1828" roughness={0.3} metalness={0.4} />
</T.Mesh>
<T.Mesh position={[11, 1.8, 4.27]}>
  <T.BoxGeometry args={[1.6, 0.9, 0.02]} />
  <T.MeshStandardMaterial color="#0f1828" emissive="#254868" emissiveIntensity={0.3} />
</T.Mesh>
<T.PointLight position={[11, 1.8, 4.5]} intensity={0.2} color="#4080b0" distance={3} decay={2} />

<!-- ─── Mini kitchen (back wall of lounge) ──────── -->
<!-- Kitchen counter along back wall -->
<T.Mesh position={[12.8, 0.5, 8.6]} castShadow>
  <T.BoxGeometry args={[1.8, 0.95, 0.6]} />
  <T.MeshStandardMaterial color="#5a5060" roughness={0.7} metalness={0.1} />
</T.Mesh>
<T.Mesh position={[12.8, 0.98, 8.6]}>
  <T.BoxGeometry args={[1.85, 0.04, 0.65]} />
  <T.MeshStandardMaterial color="#808090" roughness={0.4} metalness={0.2} />
</T.Mesh>

<!-- Coffee machine on counter -->
<T.Mesh position={[12.2, 1.15, 8.6]} castShadow>
  <T.BoxGeometry args={[0.3, 0.3, 0.28]} />
  <T.MeshStandardMaterial color="#4a4048" roughness={0.7} />
</T.Mesh>
<T.Mesh position={[12.2, 1.05, 8.6]}>
  <T.CylinderGeometry args={[0.05, 0.05, 0.06, 8]} />
  <T.MeshStandardMaterial color="#8a6040" roughness={0.6} />
</T.Mesh>
<T.Mesh position={[12.2, 1.2, 8.43]}>
  <T.SphereGeometry args={[0.02, 8, 8]} />
  <T.MeshBasicMaterial color="#f87171" />
</T.Mesh>

<!-- Fridge (tall, beside counter) -->
<T.Mesh position={[12.8, 0.85, 4.6]} castShadow>
  <T.BoxGeometry args={[0.7, 1.7, 0.7]} />
  <T.MeshStandardMaterial color="#d8d8e0" roughness={0.3} metalness={0.3} />
</T.Mesh>
<T.Mesh position={[12.8, 1.1, 4.25]}>
  <T.BoxGeometry args={[0.03, 0.35, 0.05]} />
  <T.MeshStandardMaterial color="#b8b8c0" metalness={0.5} />
</T.Mesh>
<T.Mesh position={[12.8, 0.5, 4.6]}>
  <T.BoxGeometry args={[0.72, 0.02, 0.72]} />
  <T.MeshStandardMaterial color="#c0c0c8" />
</T.Mesh>

<!-- Whiteboard (engineering wall) -->
<T.Mesh position={[-4.2, 1.5, -4.8]}>
  <T.BoxGeometry args={[1.8, 1.2, 0.06]} />
  <T.MeshStandardMaterial color="#e8e4f0" roughness={0.4} metalness={0.05} />
</T.Mesh>
<T.Mesh position={[-4.2, 1.5, -4.83]}>
  <T.BoxGeometry args={[2, 1.4, 0.04]} />
  <T.MeshStandardMaterial color="#5a5070" roughness={0.7} />
</T.Mesh>

<!-- Whiteboard (research wall) -->
<T.Mesh position={[9, 1.5, 4.2]}>
  <T.BoxGeometry args={[1.4, 1, 0.06]} />
  <T.MeshStandardMaterial color="#e8e4f0" roughness={0.4} metalness={0.05} />
</T.Mesh>
<T.Mesh position={[9, 1.5, 4.17]}>
  <T.BoxGeometry args={[1.6, 1.2, 0.04]} />
  <T.MeshStandardMaterial color="#5a5070" roughness={0.7} />
</T.Mesh>

<!-- Bookshelf (product zone) -->
<T.Mesh position={[11, 0.7, -4.8]} castShadow>
  <T.BoxGeometry args={[0.8, 1.4, 0.5]} />
  <T.MeshStandardMaterial color="#6a5848" roughness={0.8} />
</T.Mesh>
<!-- Book spines -->
{#each [[-0.25, 0.3], [0, 0.3], [0.25, 0.3], [-0.2, -0.1], [0.1, -0.1]] as bookPos}
  <T.Mesh position={[11 + bookPos[0] * 0.8, 0.7 + bookPos[1], -4.55]}>
    <T.BoxGeometry args={[0.12, 0.25, 0.05]} />
    <T.MeshStandardMaterial
      color={['#f87171', '#93c5fd', '#6ee7b7', '#fcd34d', '#fdba74'][Math.floor(Math.abs(bookPos[0] * 10 + bookPos[1] * 7) % 5)]}
      roughness={0.7}
    />
  </T.Mesh>
{/each}

<!-- Plants -->
{#each [[-7, 0.35, -4.5], [4.5, 0.35, -4.5], [-7, 0.35, 8.5], [13.2, 0.35, 4.5]] as plantPos}
  <!-- Pot -->
  <T.Mesh position={[plantPos[0], 0.2, plantPos[2]]} castShadow>
    <T.CylinderGeometry args={[0.2, 0.15, 0.3, 12]} />
    <T.MeshStandardMaterial color="#8a7560" roughness={0.85} />
  </T.Mesh>
  <!-- Foliage -->
  <T.Mesh position={[plantPos[0], 0.5, plantPos[2]]} castShadow>
    <T.SphereGeometry args={[0.3, 8, 8]} />
    <T.MeshStandardMaterial color="#4ec87a" roughness={0.9} />
  </T.Mesh>
  <T.Mesh position={[plantPos[0] + 0.1, 0.6, plantPos[2] - 0.1]}>
    <T.SphereGeometry args={[0.2, 8, 8]} />
    <T.MeshStandardMaterial color="#6ee7b7" roughness={0.9} />
  </T.Mesh>
{/each}

<!-- Water cooler (corridor intersection) -->
<T.Mesh position={[2.5, 0.45, 1.5]} castShadow>
  <T.CylinderGeometry args={[0.18, 0.15, 0.6, 12]} />
  <T.MeshStandardMaterial color="#d0d0d8" roughness={0.4} metalness={0.3} />
</T.Mesh>
<T.Mesh position={[2.5, 0.8, 1.5]}>
  <T.CylinderGeometry args={[0.15, 0.18, 0.15, 12]} />
  <T.MeshStandardMaterial color="#88c8e8" roughness={0.3} metalness={0.1} transparent opacity={0.7} />
</T.Mesh>

<!-- ─── Conference tables (Engineering, Product, Operations) ─── -->
{#each CONF_TABLES as ct}
  <T.Group position={[ct.cx, 0, ct.cz]}>
    <!-- Table top — warm walnut -->
    <T.Mesh position.y={0.5} castShadow>
      <T.BoxGeometry args={[ct.w, 0.1, ct.d]} />
      <T.MeshStandardMaterial color="#6a5a4a" roughness={0.6} metalness={0.12} />
    </T.Mesh>
    <!-- Table edge trim (slightly inset, darker) -->
    <T.Mesh position.y={0.495}>
      <T.BoxGeometry args={[ct.w + 0.04, 0.04, ct.d + 0.04]} />
      <T.MeshStandardMaterial color="#5a4a3a" roughness={0.7} metalness={0.1} />
    </T.Mesh>
    <!-- Metal legs (4 corners) -->
    {#each [[-1, -1], [1, -1], [-1, 1], [1, 1]] as corner}
      <T.Mesh position={[(ct.w / 2 - 0.15) * corner[0], 0.225, (ct.d / 2 - 0.1) * corner[1]]}>
        <T.CylinderGeometry args={[0.04, 0.04, 0.45, 8]} />
        <T.MeshStandardMaterial color="#808090" roughness={0.3} metalness={0.6} />
      </T.Mesh>
    {/each}
    <!-- Subtle overhead light for the table -->
    <T.PointLight position.y={2.5} intensity={0.2} color="#ffe8c0" distance={4} decay={2} />
  </T.Group>
{/each}

<!-- ─── Agents at desks / conference seats ─────────── -->
{#each agents as agent, i (agent.id)}
  {@const placement = agentPosition(agent, i)}
  {@const isSelected = selectedAgentId === agent.id}
  {@const emissive = statusEmissive(agent.status)}
  {@const zone = ZONES.find(z => z.id === placement.zoneId)}
  {@const orgInfo = agentOrgMap.get(agent.id)}
  <AgentDesk3D
    {agent}
    position={placement.pos}
    selected={isSelected}
    {emissive}
    zoneColor={zone?.labelColor ?? '#8888a0'}
    teamColor={orgInfo?.teamColor ?? undefined}
    divisionColor={orgInfo?.divisionColor ?? undefined}
    deskType={placement.deskType}
    facingZ={placement.facingZ}
    onclick={() => onAgentClick?.(agent)}
  />
{/each}

<!-- Fog — lighter, less dense -->
<T.FogExp2 color="#1a1828" density={0.02} />
