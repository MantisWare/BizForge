<script lang="ts">
  import '../app.css';
  import { onMount } from 'svelte';
  import { isTauri, isMacOS } from '$lib/utils/platform';
  let { children } = $props();

  onMount(() => {
    if (!isTauri()) return;

    const dismissSplash = async () => {
      const { invoke } = await import('@tauri-apps/api/core');
      try {
        const response = await fetch('/api/v1/health');
        if (!response.ok) throw new Error('Backend not ready');
      } catch {
        await new Promise((resolve) => setTimeout(resolve, 1000));
        return dismissSplash();
      }
      await invoke('close_splash');
    };

    dismissSplash();
  });
</script>

{#if isTauri() && isMacOS()}
  <div
    class="global-drag-region"
    data-tauri-drag-region
    aria-hidden="true"
  ></div>
{/if}

{@render children()}

<style>
  .global-drag-region {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    height: 28px;
    z-index: 99999;
    -webkit-app-region: drag;
    app-region: drag;
  }
</style>
