<!-- src/lib/components/office/AgentDesk3D.svelte -->
<!-- Individual agent desk + character in 3D space -->
<script lang="ts">
  import { T, useTask } from '@threlte/core';
  import { Text, Float } from '@threlte/extras';
  import type { BizforgeAgent } from '$api/types';

  interface Props {
    agent: BizforgeAgent;
    position: [number, number, number];
    selected: boolean;
    emissive: string;
    zoneColor?: string;
    teamColor?: string;
    divisionColor?: string;
    deskType?: 'desk' | 'conference';
    facingZ?: number;
    onclick: () => void;
  }

  let { agent, position, selected, emissive, zoneColor = '#8888a0', teamColor, divisionColor, deskType = 'desk', facingZ = 1, onclick }: Props = $props();

  const isConference = $derived(deskType === 'conference');

  // Deterministic color from agent id
  function agentColor(id: string): string {
    let hash = 5381;
    for (let i = 0; i < id.length; i++) {
      hash = ((hash << 5) - hash + id.charCodeAt(i)) >>> 0;
    }
    const hue = hash % 360;
    return `hsl(${hue}, 55%, 50%)`;
  }

  // Breathing / working animation
  let bobY = $state(0);
  const isActive = $derived(agent.status === 'running' || agent.status === 'idle');

  useTask(() => {
    if (isActive) {
      bobY = Math.sin(Date.now() * 0.003) * 0.05;
    } else {
      bobY = 0;
    }
  });

  const color = agentColor(agent.id);
  const label = agent.display_name ?? agent.name;
  const shortLabel = label.length > 10 ? label.slice(0, 10) + '...' : label;
</script>

<T.Group position.x={position[0]} position.y={position[1]} position.z={position[2]}>
  {#if !isConference}
    <!-- ═══ STANDARD DESK LAYOUT ═══ -->
    <!-- Desk surface — warm birch wood -->
    <T.Mesh position.y={0.45} castShadow>
      <T.BoxGeometry args={[1.8, 0.08, 0.9]} />
      <T.MeshStandardMaterial color="#8a7b6a" roughness={0.7} metalness={0.1} />
    </T.Mesh>

    <!-- Desk legs -->
    {#each [[-0.8, 0.22, -0.35], [0.8, 0.22, -0.35], [-0.8, 0.22, 0.35], [0.8, 0.22, 0.35]] as leg}
      <T.Mesh position={leg as [number, number, number]}>
        <T.CylinderGeometry args={[0.03, 0.03, 0.44, 6]} />
        <T.MeshStandardMaterial color="#605545" />
      </T.Mesh>
    {/each}

    <!-- Monitor on desk -->
    <T.Mesh position={[0, 0.72, -0.25]}>
      <T.BoxGeometry args={[0.65, 0.42, 0.03]} />
      <T.MeshStandardMaterial
        color={agent.status === 'running' ? '#0f1828' : '#121520'}
        emissive={agent.status === 'running' ? emissive : '#000000'}
        emissiveIntensity={agent.status === 'running' ? 0.4 : 0}
      />
    </T.Mesh>
    <!-- Monitor bezel -->
    <T.Mesh position={[0, 0.72, -0.26]}>
      <T.BoxGeometry args={[0.7, 0.47, 0.02]} />
      <T.MeshStandardMaterial color="#3a3555" roughness={0.5} metalness={0.3} />
    </T.Mesh>
    <!-- Monitor stand -->
    <T.Mesh position={[0, 0.52, -0.25]}>
      <T.CylinderGeometry args={[0.04, 0.06, 0.06, 8]} />
      <T.MeshStandardMaterial color="#3a3555" metalness={0.3} />
    </T.Mesh>
    <!-- Monitor base -->
    <T.Mesh position={[0, 0.485, -0.25]}>
      <T.CylinderGeometry args={[0.12, 0.12, 0.02, 12]} />
      <T.MeshStandardMaterial color="#3a3555" metalness={0.3} />
    </T.Mesh>
  {:else}
    <!-- ═══ CONFERENCE TABLE SEAT — laptop on shared table ═══ -->
    <!-- Laptop base (keyboard half, flat on table) -->
    <T.Mesh position={[0, 0.52, -0.15 * facingZ]} castShadow>
      <T.BoxGeometry args={[0.4, 0.02, 0.28]} />
      <T.MeshStandardMaterial color="#3a3555" roughness={0.5} metalness={0.3} />
    </T.Mesh>
    <!-- Laptop screen (angled upward) -->
    <T.Mesh position={[0, 0.62, -0.28 * facingZ]} rotation.x={-0.25 * facingZ}>
      <T.BoxGeometry args={[0.38, 0.26, 0.015]} />
      <T.MeshStandardMaterial
        color={agent.status === 'running' ? '#0f1828' : '#121520'}
        emissive={agent.status === 'running' ? emissive : '#000000'}
        emissiveIntensity={agent.status === 'running' ? 0.5 : 0}
      />
    </T.Mesh>
    <!-- Laptop screen bezel -->
    <T.Mesh position={[0, 0.62, (-0.28 - 0.008 * facingZ) * (facingZ > 0 ? 1 : -1 / facingZ)]} rotation.x={-0.25 * facingZ}>
      <T.BoxGeometry args={[0.42, 0.29, 0.01]} />
      <T.MeshStandardMaterial color="#2a2845" roughness={0.5} metalness={0.3} />
    </T.Mesh>
    <!-- Keyboard keys hint on laptop base -->
    <T.Mesh position={[0, 0.535, -0.08 * facingZ]}>
      <T.BoxGeometry args={[0.32, 0.005, 0.16]} />
      <T.MeshStandardMaterial color="#2e2c45" roughness={0.8} />
    </T.Mesh>
  {/if}

  <!-- Chair seat — soft upholstery (both modes) -->
  <T.Mesh position={[0, 0.35, 0.6 * facingZ]}>
    <T.BoxGeometry args={[0.5, 0.07, 0.5]} />
    <T.MeshStandardMaterial color="#5a5578" roughness={0.9} />
  </T.Mesh>
  <!-- Chair back -->
  <T.Mesh position={[0, 0.62, 0.82 * facingZ]}>
    <T.BoxGeometry args={[0.5, 0.48, 0.06]} />
    <T.MeshStandardMaterial color="#4a4568" roughness={0.9} />
  </T.Mesh>
  <!-- Chair legs -->
  {#each [[-0.2, 0.17, 0.4 * facingZ], [0.2, 0.17, 0.4 * facingZ], [-0.2, 0.17, 0.75 * facingZ], [0.2, 0.17, 0.75 * facingZ]] as chairLeg}
    <T.Mesh position={chairLeg as [number, number, number]}>
      <T.CylinderGeometry args={[0.02, 0.02, 0.34, 6]} />
      <T.MeshStandardMaterial color="#3a3558" metalness={0.4} />
    </T.Mesh>
  {/each}

  <!-- Agent character (stylized capsule) -->
  <T.Group position={[0, 0.9 + bobY, 0.6 * facingZ]}>
    <!-- Body -->
    <T.Mesh castShadow onclick={onclick}>
      <T.CapsuleGeometry args={[0.18, 0.35, 4, 12]} />
      <T.MeshStandardMaterial
        {color}
        roughness={0.6}
        metalness={0.1}
        emissive={selected ? '#f97316' : emissive}
        emissiveIntensity={selected ? 0.5 : (agent.status === 'running' ? 0.3 : 0.05)}
      />
    </T.Mesh>

    <!-- Head -->
    <T.Mesh position.y={0.38} castShadow onclick={onclick}>
      <T.SphereGeometry args={[0.15, 16, 12]} />
      <T.MeshStandardMaterial
        color="#e8d5c4"
        roughness={0.8}
        emissive={selected ? '#f97316' : '#000000'}
        emissiveIntensity={selected ? 0.3 : 0}
      />
    </T.Mesh>

    <!-- Status ring (glowing torus around the agent) -->
    {#if agent.status === 'running' || selected}
      <T.Mesh position.y={-0.1} rotation.x={Math.PI / 2}>
        <T.TorusGeometry args={[0.35, 0.02, 8, 32]} />
        <T.MeshBasicMaterial
          color={selected ? '#f97316' : emissive}
          transparent
          opacity={0.6}
        />
      </T.Mesh>
    {/if}

    <!-- Selection glow -->
    {#if selected}
      <T.PointLight position.y={0.5} intensity={1} color="#f97316" distance={3} decay={2} />
    {/if}
  </T.Group>

  <!-- Agent name label floating above with team-colored backdrop -->
  <T.Group position={[0, 1.85, 0.6 * facingZ]}>
    {#if teamColor !== undefined}
      <T.Mesh position.z={-0.01}>
        <T.PlaneGeometry args={[shortLabel.length * 0.1 + 0.3, 0.22]} />
        <T.MeshBasicMaterial color={teamColor} transparent opacity={0.3} />
      </T.Mesh>
      <T.Mesh position={[0, -0.1, -0.005]}>
        <T.PlaneGeometry args={[shortLabel.length * 0.1 + 0.3, 0.03]} />
        <T.MeshBasicMaterial color={teamColor} transparent opacity={0.85} />
      </T.Mesh>
    {/if}
    <Float speed={2} floatIntensity={0.12}>
      <Text
        text={shortLabel}
        fontSize={0.15}
        color={selected ? '#fdba74' : '#c8c0d8'}
        anchorX="center"
        anchorY="middle"
      />
    </Float>
  </T.Group>

  <!-- Status label -->
  <T.Group position={[0, 1.65, 0.6 * facingZ]}>
    <Text
      text={agent.status}
      fontSize={0.1}
      color={emissive}
      anchorX="center"
      anchorY="middle"
    />
  </T.Group>

  <!-- Division pip -->
  <T.Mesh position={[-0.5, 1.85, 0.6 * facingZ]}>
    <T.SphereGeometry args={[0.04, 8, 8]} />
    <T.MeshBasicMaterial color={divisionColor ?? zoneColor} />
  </T.Mesh>

  <!-- Current task speech bubble (if running) -->
  {#if agent.status === 'running' && agent.current_task !== undefined && agent.current_task !== null}
    <T.Group position={[0, 2.15, 0.6 * facingZ]}>
      <Float speed={3} floatIntensity={0.15}>
        <Text
          text={agent.current_task.slice(0, 30)}
          fontSize={0.08}
          color="#6ee7b7"
          anchorX="center"
          anchorY="middle"
        />
      </Float>
    </T.Group>
  {/if}

  <!-- Screen glow when running -->
  {#if agent.status === 'running'}
    <T.PointLight
      position={[0, isConference ? 0.6 : 0.55, isConference ? -0.2 * facingZ : -0.1]}
      intensity={isConference ? 0.15 : 0.25}
      color={emissive}
      distance={isConference ? 1.0 : 1.5}
      decay={2}
    />
  {/if}
</T.Group>
