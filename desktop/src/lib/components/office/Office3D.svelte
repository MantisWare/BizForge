<!-- src/lib/components/office/Office3D.svelte -->
<!-- 3D Virtual Office with Threlte (Three.js for Svelte) -->
<script lang="ts">
  import { Canvas } from '@threlte/core';
  import type { BizforgeAgent } from '$api/types';
  import type { AgentOrgInfo } from '$lib/utils/orgColors';
  import Scene3D from './Scene3D.svelte';

  interface Props {
    agents: BizforgeAgent[];
    agentOrgMap?: Map<string, AgentOrgInfo>;
    selectedAgentId?: string | null;
    onAgentClick?: (agent: BizforgeAgent) => void;
  }

  let { agents, agentOrgMap = new Map(), selectedAgentId = null, onAgentClick }: Props = $props();
</script>

<div class="o3d-container">
  <Canvas>
    <Scene3D {agents} {agentOrgMap} {selectedAgentId} {onAgentClick} />
  </Canvas>
</div>

<style>
  .o3d-container {
    width: 100%;
    height: 100%;
    min-height: 500px;
    background: #1a1828;
  }
</style>
