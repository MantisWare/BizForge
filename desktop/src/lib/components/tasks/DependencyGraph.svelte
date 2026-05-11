<!-- src/lib/components/tasks/DependencyGraph.svelte -->
<!-- Simple DAG visualization of task dependencies -->
<script lang="ts">
  import type { WizardTask } from '$api/types';

  interface Props {
    tasks: WizardTask[];
    onSelect?: (taskId: string) => void;
  }

  let { tasks, onSelect }: Props = $props();

  const markerId = `dep-arrow-${Math.random().toString(36).slice(2, 8)}`;

  interface GraphNode {
    id: string;
    title: string;
    priority: string;
    taskType: string | null;
    x: number;
    y: number;
    level: number;
    selected: boolean;
  }

  interface GraphEdge {
    from: string;
    to: string;
    fromX: number;
    fromY: number;
    toX: number;
    toY: number;
  }

  const NODE_W = 180;
  const NODE_H = 40;
  const H_GAP = 40;
  const V_GAP = 60;

  const layout = $derived.by(() => {
    const idSet = new Set(tasks.map((t) => t.id));
    const levels = new Map<string, number>();

    function getLevel(id: string, visited: Set<string>): number {
      if (levels.has(id)) return levels.get(id)!;
      if (visited.has(id)) return 0;
      visited.add(id);

      const task = tasks.find((t) => t.id === id);
      if (!task) return 0;

      const deps = (task.dependsOn ?? []).filter((d) => idSet.has(d));
      if (deps.length === 0) {
        levels.set(id, 0);
        return 0;
      }

      const maxDep = Math.max(...deps.map((d) => getLevel(d, visited)));
      const level = maxDep + 1;
      levels.set(id, level);
      return level;
    }

    tasks.forEach((t) => getLevel(t.id, new Set()));

    const maxLevel = Math.max(0, ...Array.from(levels.values()));
    const byLevel = new Map<number, WizardTask[]>();

    tasks.forEach((t) => {
      const lvl = levels.get(t.id) ?? 0;
      const arr = byLevel.get(lvl) ?? [];
      arr.push(t);
      byLevel.set(lvl, arr);
    });

    const nodes: GraphNode[] = [];
    const edges: GraphEdge[] = [];

    for (let lvl = 0; lvl <= maxLevel; lvl++) {
      const group = byLevel.get(lvl) ?? [];
      const totalW = group.length * NODE_W + (group.length - 1) * H_GAP;
      const startX = -totalW / 2 + NODE_W / 2;

      group.forEach((t, idx) => {
        const x = startX + idx * (NODE_W + H_GAP);
        const y = lvl * (NODE_H + V_GAP);
        nodes.push({
          id: t.id,
          title: t.title.length > 24 ? t.title.slice(0, 22) + '…' : t.title,
          priority: t.priority,
          taskType: t.taskType,
          x,
          y,
          level: lvl,
          selected: t.selected,
        });
      });
    }

    const nodeMap = new Map(nodes.map((n) => [n.id, n]));

    tasks.forEach((t) => {
      (t.dependsOn ?? []).forEach((depId) => {
        const from = nodeMap.get(depId);
        const to = nodeMap.get(t.id);
        if (from && to) {
          edges.push({
            from: depId,
            to: t.id,
            fromX: from.x,
            fromY: from.y + NODE_H,
            toX: to.x,
            toY: to.y,
          });
        }
      });
    });

    const allX = nodes.map((n) => n.x);
    const allY = nodes.map((n) => n.y);
    const minX = Math.min(0, ...allX) - NODE_W / 2 - 20;
    const maxX = Math.max(0, ...allX) + NODE_W / 2 + 20;
    const maxY = Math.max(0, ...allY) + NODE_H + 20;

    return {
      nodes,
      edges,
      viewBox: `${minX} -10 ${maxX - minX} ${maxY + 20}`,
      width: maxX - minX,
      height: maxY + 20,
    };
  });

  const PRIORITY_COLORS: Record<string, string> = {
    critical: '#ef4444',
    high: '#f97316',
    medium: '#eab308',
    low: '#6b7280',
  };

  const TYPE_LABELS: Record<string, string> = {
    prerequisite: 'PRE',
    scaffold: 'SCF',
    feature: 'FTR',
    subtask: 'SUB',
    validation: 'VAL',
  };
</script>

<div class="dep-graph-wrap">
  {#if layout.nodes.length === 0}
    <div class="dep-graph-empty">No tasks with dependencies to visualize</div>
  {:else}
    <svg
      class="dep-graph-svg"
      viewBox={layout.viewBox}
      preserveAspectRatio="xMidYMin meet"
      role="img"
      aria-label="Task dependency graph"
    >
      <defs>
        <marker id={markerId} markerWidth="8" markerHeight="6" refX="8" refY="3" orient="auto">
          <path d="M0,0 L8,3 L0,6" fill="var(--text-muted, #666)" />
        </marker>
      </defs>

      {#each layout.edges as edge (edge.from + edge.to)}
        <path
          d="M{edge.fromX},{edge.fromY} C{edge.fromX},{edge.fromY + 25} {edge.toX},{edge.toY - 25} {edge.toX},{edge.toY}"
          fill="none"
          stroke="var(--border-default, #444)"
          stroke-width="1.5"
          marker-end="url(#{markerId})"
          opacity="0.5"
        />
      {/each}

      {#each layout.nodes as node (node.id)}
        <g
          transform="translate({node.x - NODE_W / 2}, {node.y})"
          class="dep-node"
          class:dep-node--deselected={!node.selected}
          onclick={() => onSelect?.(node.id)}
          onkeydown={(e: KeyboardEvent) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onSelect?.(node.id); } }}
          role="button"
          tabindex="0"
          aria-label={node.title}
        >
          <rect
            width={NODE_W}
            height={NODE_H}
            rx="6"
            fill="var(--bg-elevated, #2a2a2a)"
            stroke={PRIORITY_COLORS[node.priority] ?? '#666'}
            stroke-width="1.5"
          />
          <text x="8" y="16" class="dep-node-title" font-size="10" fill="var(--text-primary, #eee)">
            {node.title}
          </text>
          {#if node.taskType}
            <text x="8" y="30" font-size="8" fill="var(--text-muted, #888)" font-weight="600">
              {TYPE_LABELS[node.taskType] ?? node.taskType}
            </text>
          {/if}
          <circle cx={NODE_W - 12} cy={NODE_H / 2} r="4" fill={PRIORITY_COLORS[node.priority] ?? '#666'} />
        </g>
      {/each}
    </svg>
  {/if}
</div>

<style>
  .dep-graph-wrap {
    width: 100%;
    overflow-x: auto;
    padding: 12px 0;
  }

  .dep-graph-svg {
    width: 100%;
    min-height: 120px;
    max-height: 400px;
  }

  .dep-graph-empty {
    text-align: center;
    padding: 32px;
    color: var(--text-muted);
    font-size: 13px;
  }

  .dep-node {
    cursor: pointer;
    transition: opacity 150ms ease;
  }

  .dep-node:hover rect {
    stroke-width: 2.5;
  }

  .dep-node--deselected {
    opacity: 0.35;
  }

  .dep-node-title {
    font-family: inherit;
  }
</style>
