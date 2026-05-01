<!-- src/lib/components/shared/AgentIcon.svelte -->
<!-- Renders an agent avatar as an SVG icon from the icon registry.
     Falls back to a letter initial when the value doesn't match any icon. -->
<script lang="ts">
  import { getIconPaths, DEFAULT_ICON } from '$lib/utils/agent-icons';

  interface Props {
    value: string | undefined | null;
    size?: number;
    strokeWidth?: number;
    class?: string;
  }

  let { value, size = 18, strokeWidth = 1.5, class: className = '' }: Props = $props();

  const paths = $derived(getIconPaths(value) ?? getIconPaths(DEFAULT_ICON)!);
</script>

<svg
  class="agent-icon {className}"
  width={size}
  height={size}
  viewBox="0 0 24 24"
  fill="none"
  stroke="currentColor"
  stroke-width={strokeWidth}
  stroke-linecap="round"
  stroke-linejoin="round"
  aria-hidden="true"
>
  {#each paths as d}
    <path {d} />
  {/each}
</svg>

<style>
  .agent-icon {
    flex-shrink: 0;
    display: inline-flex;
  }
</style>
