<script lang="ts">
  import { browser } from '$app/environment';
  import { goto, beforeNavigate, afterNavigate } from '$app/navigation';
  import { onMount } from 'svelte';
import Sidebar from '$lib/components/layout/Sidebar.svelte';
  import AppFooter from '$lib/components/layout/AppFooter.svelte';
  import LogPanel from '$lib/components/layout/LogPanel.svelte';
  import ToastContainer from '$lib/components/layout/ToastContainer.svelte';
  import { connectionStore } from '$lib/stores/connection.svelte';
  import { themeStore } from '$lib/stores/theme.svelte';
  import { paletteStore } from '$lib/stores/palette.svelte';
  import { workspaceStore } from '$lib/stores/workspace.svelte';
  import { agentsStore } from '$lib/stores/agents.svelte';
  import { projectsStore } from '$lib/stores/projects.svelte';
  import { settingsStore } from '$lib/stores/settings.svelte';
  import CommandPalette from '$lib/components/layout/CommandPalette.svelte';
  import ActivityWidget from '$lib/components/activity/ActivityWidget.svelte';
  import LlmInspectorPanel from '$lib/components/inspector/LlmInspectorPanel.svelte';
  import WorkspaceWizard from '$lib/components/wizard/WorkspaceWizard.svelte';
  import { activityStore } from '$lib/stores/activity.svelte';
  import { llmInspectorStore, bindAgentsStore } from '$lib/stores/llmInspector.svelte';
  import { sessionsStore } from '$lib/stores/sessions.svelte';
  import { organizationsStore } from '$lib/stores/organizations.svelte';
  import { approvalsStore } from '$lib/stores/approvals.svelte';
  import { hierarchyStore } from '$lib/stores/hierarchy.svelte';
  import { providersStore } from '$lib/stores/providers.svelte';
  import { isTauri, isMacOS } from '$lib/utils/platform';
  import { initializeAuth, getToken, saveSessionToStore, logInfo, logWarn, logError } from '$api/client';
  import { wizardStore } from '$lib/stores/wizard.svelte';

  let { children } = $props();

  bindAgentsStore(agentsStore);

  // ─── Navigation timing ─────────────────────────────────────────────────
  let _navStart = 0;
  beforeNavigate(({ from, to, type }) => {
    _navStart = performance.now();
    logInfo('boot', `Navigation started: ${from?.url.pathname ?? '?'} → ${to?.url.pathname ?? '?'} (${type})`);
  });
  afterNavigate(({ from, to, type }) => {
    const elapsed = Math.round(performance.now() - _navStart);
    logInfo('boot', `Navigation complete: ${to?.url.pathname ?? '?'} (${type}, ${elapsed}ms)`);
    if (elapsed > 1000) {
      logWarn('boot', `Slow navigation detected: ${elapsed}ms for ${to?.url.pathname ?? '?'}`);
    }
  });

  // ─── Onboarding guard ────────────────────────────────────────────────────
  // NOTE: This guard runs inside initializeAuth().then() (see the second
  // onMount below) so that _token is already set before we check it.
  // A separate early-mount guard here would fire before auth resolves and
  // always see an empty token, causing spurious redirects to /onboarding.

  // Initialize theme
  $effect(() => { void themeStore.resolved; });

  // Forward session-related activity events to the sessions store so the
  // session list stays current during live execution without a full refetch.
  let _lastForwardedActivityId = $state<string | null>(null);
  $effect(() => {
    const latest = activityStore.events[0];
    if (!latest || latest.id === _lastForwardedActivityId) return;
    _lastForwardedActivityId = latest.id;
    sessionsStore.handleActivityEvent(latest);
  });

  // Sidebar collapsed state — persisted to localStorage
  let sidebarCollapsed = $state(false);
  $effect(() => {
    if (!browser) return;
    const stored = localStorage.getItem('bizforge-sidebar-collapsed');
    if (stored !== null) sidebarCollapsed = stored === 'true';
  });

  function toggleSidebar() {
    sidebarCollapsed = !sidebarCollapsed;
    if (browser) localStorage.setItem('bizforge-sidebar-collapsed', String(sidebarCollapsed));
  }

  // Nav routes for ⌘1–⌘3 (Core section)
  const NAV_ROUTES = ['/app', '/app/inbox', '/app/office'];

  onMount(() => {
    let stopPolling: (() => void) | null = null;
    const bootStart = performance.now();
    const bootMs = () => Math.round(performance.now() - bootStart);

    logInfo('boot', `Layout onMount — loading workspace context from localStorage`);
    workspaceStore.fetchWorkspaces();
    logInfo('boot', `Workspace context loaded (wsId: ${workspaceStore.activeWorkspaceId ?? 'none'}) [${bootMs()}ms]`);

    logInfo('boot', `Calling initializeAuth()... [${bootMs()}ms]`);
    initializeAuth().then(async () => {
      logInfo('boot', `initializeAuth() resolved — token: ${getToken() !== null ? 'present' : 'absent'} [${bootMs()}ms]`);

      if (getToken()) {
        localStorage.setItem('bizforge-onboarding-complete', 'true');
        localStorage.setItem('bizforge-onboarding', JSON.stringify({ completed: true }));
        void saveSessionToStore();
      } else {
        const raw = localStorage.getItem('bizforge-onboarding');
        const completed = raw
          ? (JSON.parse(raw) as { completed?: boolean }).completed
          : false;
        if (!completed) {
          const legacy = localStorage.getItem('bizforge-onboarding-complete');
          if (legacy !== 'true') {
            logInfo('boot', `No token, onboarding incomplete — redirecting to /onboarding [${bootMs()}ms]`);
            goto('/onboarding');
            return;
          }
        }
      }

      const canFetch = getToken() !== null;
      stopPolling = connectionStore.startPolling(30_000);

      if (!canFetch) {
        logWarn('boot', `No auth token — redirecting to /auth [${bootMs()}ms]`);
        goto('/auth', { replaceState: true });
        return;
      }

      activityStore.subscribe();

      const wsId = workspaceStore.activeWorkspaceId ?? undefined;
      const ws = workspaceStore.activeWorkspace;
      logInfo('boot', `Firing concurrent data fetches (wsId: ${wsId ?? 'none'}, ws: ${ws?.name ?? 'none'}) [${bootMs()}ms]`);

      void workspaceStore.syncFromBackend().catch(() => {});
      void organizationsStore.ensureDefault().then(() => {
        if (organizationsStore.current) {
          void hierarchyStore.fetchTree(organizationsStore.current.id);
          void hierarchyStore.fetchDivisions(organizationsStore.current.id);
          void hierarchyStore.fetchDepartments();
          void hierarchyStore.fetchTeams();
        }
      });

      void approvalsStore.fetchApprovals(wsId);
      void providersStore.fetch();
      void projectsStore.fetchProjects(wsId);

      if (ws) {
        workspaceStore.scanAndLoadAgents(ws.path).then(() => {
          workspaceStore.watchActive();
          if (agentsStore.agents.length === 0) {
            void agentsStore.fetchAgents(wsId);
          }
          logInfo('boot', `Agent scan complete [${bootMs()}ms]`);
        });
      } else {
        void agentsStore.fetchAgents(wsId);
      }
      logInfo('boot', `All data fetches dispatched [${bootMs()}ms]`);
    }).catch((err) => {
      logError('boot', `Boot sequence failed: ${(err as Error).message}`);
    });

    // Load adapter choice and miosaCloud setting from Tauri secure store
    // (written during onboarding; no-op in browser dev mode)
    void settingsStore.loadFromTauriStore();

    paletteStore.registerBuiltins(goto, {
      newWorkspace: () => { wizardStore.reset(); wizardStore.open(); },
    });
    return () => {
      stopPolling?.();
      activityStore.unsubscribe();
    };
  });

  // Keyboard shortcuts
  onMount(() => {
    function handleKeyDown(e: KeyboardEvent) {
      const meta = e.metaKey || e.ctrlKey;
      if (meta && (e.key === 'k' || e.key === 'K')) { e.preventDefault(); paletteStore.toggle(); return; }
      if (!meta) return;
      if (e.key === '\\') { e.preventDefault(); toggleSidebar(); return; }
      if (e.key === ',') { e.preventDefault(); goto('/app/settings'); return; }
      if (e.key === 't' || e.key === 'T') { e.preventDefault(); goto('/app/terminal'); return; }
      if (e.shiftKey && (e.key === 'i' || e.key === 'I')) { e.preventDefault(); llmInspectorStore.toggle(); return; }
      const idx = ['1', '2', '3'].indexOf(e.key);
      if (idx !== -1) { e.preventDefault(); goto(NAV_ROUTES[idx]); }
    }
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  });

  // Log panel state
  let logPanelOpen = $state(false);
  function toggleLogPanel(): void {
    logPanelOpen = !logPanelOpen;
  }

  // Wire user display name from onboarding
  let userName = $state<string | null>(null);
  $effect(() => {
    if (!browser) return;
    const name = localStorage.getItem('bizforge-display-name');
    if (name) userName = name;
  });
  const user = $derived(userName ? { name: userName, email: '' } : null);

  // Backend disconnection banner
  const connStatus = $derived(connectionStore.status);
  const showDisconnectedBanner = $derived(
    connStatus === 'disconnected' || connStatus === 'reconnecting'
  );
  const bannerConfig = $derived.by(() => {
    if (connStatus === 'reconnecting') return {
      cls: 'disc-banner--reconnecting',
      icon: 'reconnecting',
      title: 'Reconnecting to Backend…',
      desc: `Attempt ${connectionStore.reconnectAttempts} — your data will refresh automatically when the connection is restored.`,
    };
    return {
      cls: 'disc-banner--disconnected',
      icon: 'disconnected',
      title: 'Backend Disconnected',
      desc: 'Cannot reach the server. Check that the backend is running and try again.',
    };
  });
  let bannerDismissed = $state(false);
  $effect(() => { if (connStatus === 'connected') bannerDismissed = false; });
</script>

<!-- App shell with sidebar + main content -->
<div class="app-shell" class:has-titlebar={isTauri() && isMacOS()}>
  {#if showDisconnectedBanner && !bannerDismissed}
    <div class="disc-banner {bannerConfig.cls}" role="alert">
      <div class="disc-banner-content">
        <div class="disc-banner-icon">
          {#if bannerConfig.icon === 'reconnecting'}
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" class="disc-spin">
              <path d="M21 12a9 9 0 11-6.219-8.56"/>
            </svg>
          {:else}
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <path d="M18.364 5.636a9 9 0 010 12.728M5.636 18.364a9 9 0 010-12.728"/>
              <line x1="2" y1="2" x2="22" y2="22"/>
            </svg>
          {/if}
        </div>
        <div class="disc-banner-text">
          <strong>{bannerConfig.title}</strong>
          <span class="disc-banner-desc">{bannerConfig.desc}</span>
        </div>
      </div>
      <div class="disc-banner-actions">
        {#if connStatus === 'disconnected' || connStatus === 'mock'}
          <button class="disc-banner-btn" onclick={() => void connectionStore.check()}>Retry Now</button>
        {/if}
        <button class="disc-banner-dismiss" onclick={() => { bannerDismissed = true; }} aria-label="Dismiss">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
          </svg>
        </button>
      </div>
    </div>
  {/if}
  <div class="app-body">
    <Sidebar bind:isCollapsed={sidebarCollapsed} onToggle={toggleSidebar} {user} />
    <main class="main-content" id="main-content">
      {@render children()}
    </main>
    <LlmInspectorPanel />
  </div>
  {#if logPanelOpen}
    <LogPanel onClose={() => { logPanelOpen = false; }} />
  {/if}
  <AppFooter {logPanelOpen} onToggleLogs={toggleLogPanel} />
</div>

<!-- Global overlays -->
<CommandPalette />
<ToastContainer />
<ActivityWidget />
<WorkspaceWizard />

<style>
  .app-shell {
    width: 100vw; height: 100dvh;
    display: flex; flex-direction: column;
    overflow: hidden;
    background: var(--bg-primary); position: relative;
    background-image: radial-gradient(ellipse at 20% 0%, rgba(255,255,255,0.015) 0%, transparent 60%);
  }
  .app-shell.has-titlebar {
    padding-top: 28px;
  }
  .app-body {
    flex: 1; display: flex; min-height: 0; overflow: hidden;
  }
  .main-content {
    flex: 1; display: flex; flex-direction: column;
    min-width: 0; overflow: hidden; background: var(--bg-secondary);
    box-shadow: inset 1px 0 0 rgba(255,255,255,0.04); position: relative;
  }

  /* ── Backend disconnected banner ───────────────────────────────────── */
  .disc-banner {
    display: flex; align-items: center; justify-content: space-between;
    gap: 12px; padding: 10px 20px; flex-shrink: 0;
    animation: disc-slide-down 0.25s ease-out;
  }
  @keyframes disc-slide-down {
    from { transform: translateY(-100%); opacity: 0; }
    to   { transform: translateY(0); opacity: 1; }
  }
  .disc-banner--reconnecting {
    background: linear-gradient(90deg, rgba(234,179,8,0.15), rgba(234,179,8,0.08));
    border-bottom: 1px solid rgba(234,179,8,0.25);
    color: #fde047;
  }
  .disc-banner--disconnected {
    background: linear-gradient(90deg, rgba(239,68,68,0.15), rgba(239,68,68,0.08));
    border-bottom: 1px solid rgba(239,68,68,0.25);
    color: #fca5a5;
  }
  .disc-banner-content {
    display: flex; align-items: center; gap: 10px; flex: 1; min-width: 0;
  }
  .disc-banner-icon { flex-shrink: 0; display: flex; }
  .disc-banner-text {
    display: flex; align-items: baseline; gap: 8px; flex-wrap: wrap;
    font-size: 13px; line-height: 1.4;
  }
  .disc-banner-text strong { font-weight: 600; }
  .disc-banner-desc {
    font-weight: 400; opacity: 0.75; font-size: 12px;
  }
  .disc-banner-actions {
    display: flex; align-items: center; gap: 8px; flex-shrink: 0;
  }
  .disc-banner-btn {
    padding: 4px 12px; border-radius: 6px; font-size: 12px; font-weight: 500;
    background: rgba(255,255,255,0.12); border: 1px solid rgba(255,255,255,0.15);
    color: inherit; cursor: pointer; transition: all 0.15s; white-space: nowrap;
  }
  .disc-banner-btn:hover {
    background: rgba(255,255,255,0.2); border-color: rgba(255,255,255,0.25);
  }
  .disc-banner-dismiss {
    background: none; border: none; color: inherit; cursor: pointer;
    padding: 2px; border-radius: 4px; opacity: 0.5; transition: opacity 0.15s;
  }
  .disc-banner-dismiss:hover { opacity: 1; }
  .disc-spin { animation: disc-spin-anim 1s linear infinite; }
  @keyframes disc-spin-anim { to { transform: rotate(360deg); } }
</style>
