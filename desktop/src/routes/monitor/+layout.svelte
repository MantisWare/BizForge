<!-- src/routes/monitor/+layout.svelte -->
<!-- Standalone layout for the headless stats dashboard — no sidebar, no nav, pure monitoring -->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import { onMount, onDestroy } from 'svelte';
  import { monitorStore } from '$lib/stores/monitor.svelte';
  import { browser } from '$app/environment';

  interface Props {
    children: Snippet;
  }

  let { children }: Props = $props();
  let mounted = $state(false);

  onMount(async () => {
    mounted = true;

    const params = new URLSearchParams(window.location.search);
    const workspaceParam = params.get('workspace');

    await monitorStore.loadAvailableWorkspaces();

    if (workspaceParam !== null && workspaceParam !== '') {
      const match = monitorStore.availableWorkspaces.find(
        (w) => w.id === workspaceParam || w.name === workspaceParam,
      );
      if (match !== undefined) {
        monitorStore.selectWorkspace(match);
      }
    }
  });

  onDestroy(() => {
    monitorStore.stopPolling();
  });
</script>

<div class="monitor-root" class:mounted>
  {@render children()}
</div>

<style>
  :global(body) {
    margin: 0;
    padding: 0;
    background: #0a0e17;
    color: #e2e8f0;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', sans-serif;
    overflow: hidden;
  }

  .monitor-root {
    width: 100vw;
    height: 100vh;
    display: flex;
    flex-direction: column;
    background: #0a0e17;
    opacity: 0;
    transition: opacity 0.3s ease;
  }

  .monitor-root.mounted {
    opacity: 1;
  }
</style>
