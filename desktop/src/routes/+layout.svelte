<script lang="ts">
  import '../app.css';
  import { onMount } from 'svelte';
  import { isTauri, isMacOS } from '$lib/utils/platform';
  import { fontStore } from '$lib/stores/font.svelte';
  let { children } = $props();

  onMount(() => {
    void fontStore.font;
    if (!isTauri()) return;

    const isMonitorWindow = window.location.pathname.startsWith('/monitor');
    if (isMonitorWindow) return;

    const apiBase = import.meta.env.VITE_API_URL ?? 'http://127.0.0.1:9089';
    const healthUrl = `${apiBase}/api/v1/health`;
    const maxAttempts = 90;
    const pollMs = 500;

    const dismissSplash = async () => {
      const { invoke } = await import('@tauri-apps/api/core');
      for (let attempt = 0; attempt < maxAttempts; attempt++) {
        try {
          const response = await fetch(healthUrl, {
            signal: AbortSignal.timeout(2000),
          });
          if (response.ok) {
            await invoke('close_splash');
            return;
          }
        } catch {
          // Backend still starting — keep polling
        }
        await new Promise((resolve) => setTimeout(resolve, pollMs));
      }
      // Never block the user on a stuck splash; native startup also dismisses it.
      await invoke('close_splash');
    };

    void dismissSplash();
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
