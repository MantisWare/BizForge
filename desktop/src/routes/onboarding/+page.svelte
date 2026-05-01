<script lang="ts">
  import { goto } from '$app/navigation';
  import { onMount } from 'svelte';
  import { onboardingStore } from '$lib/stores/onboarding.svelte';
  import type { AdapterType, TeamTemplate, AgentTemplateData } from '$lib/stores/onboarding.svelte';
  import { initializeAuth, getToken, isMockEnabled } from '$api/client';
  import { isTauri } from '$lib/utils/platform';
  import { workspaceStore, type LocalWorkspace } from '$lib/stores/workspace.svelte';
  import { connectionStore } from '$lib/stores/connection.svelte';
  import ConnectionStatusBar from '$lib/components/layout/ConnectionStatusBar.svelte';
  import Welcome from './steps/Welcome.svelte';
  import Provider from './steps/Provider.svelte';
  import Adapter from './steps/Adapter.svelte';
  import Workspace from './steps/Workspace.svelte';
  import Team from './steps/Team.svelte';
  import MiosaCloud from './steps/MiosaCloud.svelte';
  import Review from './steps/Review.svelte';

  onMount(() => {
    console.log('[bizforge:onboarding] Mounted — initializing auth and connection check');
    initializeAuth().then(() => {
      console.log(`[bizforge:onboarding] Auth initialized — mock=${isMockEnabled()}, token=${getToken() !== null}`);
      void connectionStore.check();
    });
    const stopPolling = connectionStore.startPolling(30_000);
    return () => stopPolling();
  });

  // ─── Registration data (pre-filled from /auth if the user just registered) ──
  //
  // When a user registers, /auth stores:
  //   bizforge-registered-name           → user's full name
  //   bizforge-registered-workspace-id   → backend workspace UUID
  //   bizforge-registered-workspace-name → workspace display name
  //
  // We use these to seed the onboarding form so the user doesn't have to
  // re-enter information they already provided.

  const registeredName = typeof localStorage !== 'undefined'
    ? (localStorage.getItem('bizforge-registered-name') ?? '')
    : '';
  const registeredWorkspaceId = typeof localStorage !== 'undefined'
    ? (localStorage.getItem('bizforge-registered-workspace-id') ?? '')
    : '';
  const registeredWorkspaceName = typeof localStorage !== 'undefined'
    ? (localStorage.getItem('bizforge-registered-workspace-name') ?? '')
    : '';

  // ─── Shared state ─────────────────────────────────────────────────────────

  // When coming directly from registration the user already entered their name.
  // Auto-advance past the Welcome step (step 0) to avoid asking again.
  const _initialStep = onboardingStore.currentStep === 0 && registeredName
    ? 1
    : onboardingStore.currentStep;

  let step = $state(_initialStep);

  // Pre-fill display name from registration; fall back to store/empty.
  let displayName        = $state(
    onboardingStore.data.displayName ||
    registeredName ||
    (typeof localStorage !== 'undefined' ? (localStorage.getItem('bizforge-display-name') ?? '') : '')
  );
  let selectedProviderSlug = $state(onboardingStore.data.provider?.slug ?? '');
  let providerKeys       = $state<Record<string, string>>({});
  let selectedProviders  = $state<import('./steps/Provider.svelte').ProviderSetup[]>(
    onboardingStore.data.provider
      ? [{ slug: onboardingStore.data.provider.slug, apiKey: onboardingStore.data.provider.apiKey }]
      : [],
  );
  let selectedAdapter    = $state<AdapterType>(onboardingStore.data.adapter);
  let workspacePath      = $state(onboardingStore.data.workspace?.path ?? '~/.bizforge');
  // Pre-fill workspace name from registration response when available.
  let workspaceName      = $state(
    onboardingStore.data.workspace?.name ||
    registeredWorkspaceName ||
    'My Workspace'
  );
  let workspaceDesc      = $state(onboardingStore.data.workspace?.description ?? '');
  let teamTemplate       = $state<TeamTemplate>(onboardingStore.data.teamTemplate ?? 'dev-team');
  let miosaCloud         = $state(onboardingStore.data.miosaCloud);
  let isLaunching        = $state(false);

  // Sync selectedProviders back to legacy single-provider fields for review/launch
  $effect(() => {
    if (onboardingStore.data.provider) {
      providerKeys[onboardingStore.data.provider.slug] = onboardingStore.data.provider.apiKey;
    }
    if (selectedProviders.length > 0) {
      selectedProviderSlug = selectedProviders[0].slug;
      for (const sp of selectedProviders) {
        if (sp.apiKey) providerKeys[sp.slug] = sp.apiKey;
      }
    }
  });

  // ─── Template data ────────────────────────────────────────────────────────

  const TEMPLATE_AGENTS: Record<TeamTemplate, AgentTemplateData[]> = {
    solo: [
      { id: 'main-agent', name: 'Main Agent', emoji: 'robot', role: 'engineer', adapter: 'osa', skills: ['code', 'debug', 'test'], system_prompt: 'You are a skilled software engineer...' },
    ],
    'dev-team': [
      { id: 'orchestrator',    name: 'Orchestrator',    emoji: 'light-bulb', role: 'orchestrator', adapter: 'osa', skills: ['delegate', 'plan'],      system_prompt: 'You coordinate a development team...' },
      { id: 'code-worker',     name: 'Code Worker',     emoji: 'code-bracket', role: 'developer',    adapter: 'osa', skills: ['code', 'debug'],          system_prompt: 'You are a focused code implementation specialist...' },
      { id: 'research-worker', name: 'Research Worker', emoji: 'magnifying', role: 'researcher',   adapter: 'osa', skills: ['web_search', 'analyze'],  system_prompt: 'You research solutions, APIs, and best practices...' },
      { id: 'qa-agent',        name: 'QA Agent',        emoji: 'shield-check', role: 'engineer',     adapter: 'osa', skills: ['test', 'validate'],       system_prompt: 'You ensure code quality through testing...' },
    ],
    research: [
      { id: 'lead-researcher', name: 'Lead Researcher', emoji: 'magnifying', role: 'researcher', adapter: 'osa', skills: ['web_search', 'analyze', 'summarize'], system_prompt: 'You lead research investigations...' },
      { id: 'data-analyst',    name: 'Data Analyst',    emoji: 'chart-bar',  role: 'researcher', adapter: 'osa', skills: ['analyze', 'visualize'],              system_prompt: 'You analyze data and produce insights...' },
      { id: 'writer',          name: 'Writer',          emoji: 'document-text', role: 'writer',     adapter: 'osa', skills: ['write', 'edit', 'format'],            system_prompt: 'You produce clear, well-structured written content...' },
    ],
    'content-studio': [
      { id: 'content-strategist', name: 'Content Strategist', emoji: 'flag', role: 'strategist', adapter: 'osa', skills: ['plan', 'analyze', 'schedule'],     system_prompt: 'You develop content strategies, editorial calendars, and campaign plans...' },
      { id: 'copywriter',         name: 'Copywriter',         emoji: 'document-text', role: 'writer',     adapter: 'osa', skills: ['write', 'edit', 'seo'],            system_prompt: 'You write compelling copy for blogs, emails, landing pages, and social media...' },
      { id: 'designer',           name: 'Visual Designer',    emoji: 'paint-brush', role: 'designer',  adapter: 'osa', skills: ['design', 'brand', 'format'],       system_prompt: 'You create visual assets, design briefs, and brand-consistent materials...' },
    ],
    'ops-center': [
      { id: 'infra-engineer',  name: 'Infra Engineer',  emoji: 'cog',  role: 'engineer',    adapter: 'osa', skills: ['deploy', 'monitor', 'provision'], system_prompt: 'You manage infrastructure, CI/CD pipelines, and cloud resources...' },
      { id: 'sre-agent',       name: 'SRE Agent',       emoji: 'shield-check',  role: 'engineer',    adapter: 'osa', skills: ['monitor', 'alert', 'diagnose'],   system_prompt: 'You ensure reliability, respond to incidents, and manage SLOs...' },
      { id: 'security-agent',  name: 'Security Agent',  emoji: 'lock-closed',    role: 'engineer',    adapter: 'osa', skills: ['audit', 'scan', 'remediate'],     system_prompt: 'You perform security audits, vulnerability scanning, and compliance checks...' },
    ],
    'sales-engine': [
      { id: 'prospector',      name: 'Prospector',      emoji: 'magnifying',  role: 'researcher',  adapter: 'osa', skills: ['web_search', 'analyze', 'enrich'], system_prompt: 'You find and qualify potential leads, enrich contact data, and score prospects...' },
      { id: 'outreach-agent',  name: 'Outreach Agent',  emoji: 'envelope',    role: 'writer',      adapter: 'osa', skills: ['write', 'personalize', 'sequence'], system_prompt: 'You craft personalized outreach emails, follow-up sequences, and messaging...' },
      { id: 'deal-analyst',    name: 'Deal Analyst',    emoji: 'chart-bar',   role: 'analyst',     adapter: 'osa', skills: ['analyze', 'forecast', 'report'],   system_prompt: 'You analyze pipeline health, forecast revenue, and identify deal risks...' },
    ],
    'data-science': [
      { id: 'ml-engineer',     name: 'ML Engineer',     emoji: 'light-bulb',   role: 'engineer',    adapter: 'osa', skills: ['code', 'train', 'evaluate'],       system_prompt: 'You build, train, and evaluate machine learning models...' },
      { id: 'data-engineer',   name: 'Data Engineer',   emoji: 'circle-stack', role: 'engineer',   adapter: 'osa', skills: ['pipeline', 'transform', 'query'],  system_prompt: 'You build data pipelines, ETL processes, and manage data infrastructure...' },
      { id: 'analyst',         name: 'Analyst',         emoji: 'chart-bar',   role: 'analyst',     adapter: 'osa', skills: ['analyze', 'visualize', 'report'],  system_prompt: 'You perform exploratory data analysis, create visualizations, and generate reports...' },
    ],
    custom: [],
  };

  // ─── Derived ──────────────────────────────────────────────────────────────

  const teamAgents = $derived(TEMPLATE_AGENTS[teamTemplate]);

  // $derived evaluates to a boolean directly so Svelte tracks every reactive
  // read (step, selectedProviderSlug, providerKeys, workspacePath) and
  // recomputes whenever any of them change.
  const canContinue = $derived((() => {
    if (step === 1) {
      if (selectedProviders.length === 0) return false;
      return selectedProviders.every((sp) => {
        if (sp.slug === 'local') return true;
        const noKeySlugs = ['local'];
        if (noKeySlugs.includes(sp.slug)) return true;
        return (sp.apiKey ?? '').trim().length > 0;
      });
    }
    if (step === 3) return workspacePath.trim().length > 0;
    return true;
  })());

  // ─── Navigation ───────────────────────────────────────────────────────────

  function next() {
    if (!canContinue) return;
    syncToStore();
    onboardingStore.nextStep();
    step = onboardingStore.currentStep;
  }

  function prev() {
    onboardingStore.prevStep();
    step = onboardingStore.currentStep;
  }

  function syncToStore() {
    const primarySlug = selectedProviders.length > 0 ? selectedProviders[0].slug : selectedProviderSlug;
    const primaryKey = selectedProviders.length > 0
      ? selectedProviders[0].apiKey
      : (providerKeys[selectedProviderSlug] ?? '');
    onboardingStore.updateData({
      displayName,
      provider: primarySlug
        ? { slug: primarySlug, apiKey: primaryKey, verified: false }
        : null,
      adapter: selectedAdapter,
      workspace: { path: workspacePath, name: workspaceName, description: workspaceDesc },
      teamTemplate,
      agents: TEMPLATE_AGENTS[teamTemplate],
      miosaCloud,
    });
  }

  // ─── Import callback from Welcome step ────────────────────────────────────

  function handleImport(result: {
    workspacePath: string;
    workspaceName: string;
    adapter: AdapterType;
    teamTemplate: TeamTemplate;
    agents: AgentTemplateData[];
    jumpToStep: number;
  }) {
    if (result.workspacePath) workspacePath = result.workspacePath;
    if (result.workspaceName) workspaceName = result.workspaceName;
    selectedAdapter = result.adapter;
    teamTemplate = result.teamTemplate;
    if (result.agents.length > 0) {
      onboardingStore.updateData({ agents: result.agents });
    }
    onboardingStore.updateData({
      displayName,
      workspace: { path: workspacePath, name: workspaceName, description: workspaceDesc },
      adapter: selectedAdapter,
      teamTemplate,
    });
    step = result.jumpToStep;
    onboardingStore.goToStep(result.jumpToStep);
  }

  // ─── Open recent workspace ──────────────────────────────────────────

  async function handleOpenRecent(ws: LocalWorkspace) {
    workspaceStore.fetchWorkspaces();
    await workspaceStore.setActiveWorkspace(ws.id);

    if (displayName) {
      localStorage.setItem('bizforge-display-name', displayName);
    }

    onboardingStore.complete();
    if (typeof localStorage !== 'undefined') {
      localStorage.setItem('bizforge-onboarding-complete', 'true');
      localStorage.setItem('bizforge-onboarding', JSON.stringify({ completed: true }));
    }

    const needsLogin = !isMockEnabled() && getToken() === null;
    goto(needsLogin ? '/auth' : '/app');
  }

  // ─── Launch ───────────────────────────────────────────────────────────────

  function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
    return Promise.race([
      promise,
      new Promise<never>((_, reject) =>
        setTimeout(() => reject(new Error(`Timed out after ${ms}ms`)), ms),
      ),
    ]);
  }

  async function launch() {
    if (isLaunching) return;
    isLaunching = true;
    syncToStore();

    try {
      // Ensure auth gate is open before any API calls
      await withTimeout(initializeAuth(), 5000);
    } catch {
      console.warn('Auth init timed out — proceeding with launch');
    }

    try {
      if (isTauri() && workspacePath.trim()) {
        const { invoke } = await import('@tauri-apps/api/core');
        const agents = TEMPLATE_AGENTS[teamTemplate].map(a => ({
          id: a.id,
          name: a.name,
          emoji: a.emoji,
          role: a.role,
          adapter: a.adapter,
          model: a.model ?? null,
          skills: a.skills,
          system_prompt: a.system_prompt ?? null,
        }));

        try {
          await withTimeout(invoke('scaffold_bizforge_dir', {
            path: workspacePath,
            name: workspaceName,
            description: workspaceDesc || null,
            agents,
          }), 10000);
        } catch (e) {
          console.warn('Scaffold warning:', e);
        }

        const { workspaceStore } = await import('$lib/stores/workspace.svelte');

        const hasAuth = getToken() !== null || isMockEnabled();
        let wsId = registeredWorkspaceId || '';

        if (!wsId && hasAuth) {
          try {
            const { workspaces: workspacesApi } = await import('$api/client');
            const created = await withTimeout(
              workspacesApi.create({
                name: workspaceName,
                path: workspacePath,
              }),
              5000,
            );
            if (created?.id) wsId = created.id;
          } catch (e) {
            console.warn('Backend workspace creation failed:', e);
          }
        }

        if (!wsId) wsId = crypto.randomUUID();

        const wsEntry = {
          id: wsId,
          path: workspacePath,
          name: workspaceName,
          description: workspaceDesc,
          addedAt: new Date().toISOString(),
        };
        workspaceStore.addWorkspace(wsEntry);

        if (hasAuth) {
          try {
            await withTimeout(workspaceStore.setActiveWorkspace(wsEntry.id), 8000);
          } catch (e) {
            console.warn('Workspace activation timed out:', e);
          }
        } else {
          workspaceStore.activeWorkspaceId = wsEntry.id;
          if (typeof localStorage !== 'undefined') {
            localStorage.setItem('bizforge-active-workspace', wsEntry.id);
          }
        }

        if (registeredWorkspaceId && hasAuth) {
          try {
            const { workspaces: workspacesApi } = await import('$api/client');
            await withTimeout(workspacesApi.update(registeredWorkspaceId, {
              name: workspaceName,
              path: workspacePath,
              description: workspaceDesc || undefined,
            }), 5000);
          } catch {
            // Non-fatal
          }
        }
      }

      const hasAuth = getToken() !== null || isMockEnabled();
      if (hasAuth) {
        try {
          const { organizations } = await import('$api/client');
          const { organizationsStore } = await import('$lib/stores/organizations.svelte');
          const orgName = workspaceName || 'My Organization';
          const orgSlug = orgName
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, '-')
            .replace(/^-|-$/g, '');
          const org = await withTimeout(
            organizations.create({ name: orgName, slug: orgSlug }),
            5000,
          );
          if (org) organizationsStore.setCurrent(org);
        } catch (e) {
          console.warn('Org creation skipped:', e);
        }
      }

      onboardingStore.complete();

      // Persist providers via API
      if (selectedProviders.length > 0) {
        const hasAuth = getToken() !== null || isMockEnabled();
        if (hasAuth) {
          try {
            const { providers: providersApi } = await import('$api/client');
            for (let i = 0; i < selectedProviders.length; i++) {
              const sp = selectedProviders[i];
              const { findProvider } = await import('$lib/data/provider-catalog');
              const catalogEntry = findProvider(sp.slug);
              await withTimeout(providersApi.create({
                slug: sp.slug,
                name: catalogEntry?.name ?? sp.slug,
                category: sp.slug === 'local' ? 'local' : 'cloud',
                api_key: sp.apiKey || undefined,
                endpoint: sp.endpoint ?? catalogEntry?.defaultEndpoint ?? undefined,
                config: sp.localRuntime ? { local_runtime: sp.localRuntime, local_endpoint: sp.endpoint } : {},
                models: catalogEntry?.defaultModels ?? [],
                is_default: i === 0,
              }), 5000);
            }
          } catch (e) {
            console.warn('Provider persistence failed:', e);
          }
        }
      }

      if (typeof localStorage !== 'undefined') {
        localStorage.setItem('bizforge-onboarding-complete', 'true');
        localStorage.setItem(
          'bizforge-onboarding',
          JSON.stringify({ completed: true }),
        );
        localStorage.setItem('bizforge-display-name', displayName);
        localStorage.setItem('bizforge-default-adapter', selectedAdapter);
        if (selectedProviderSlug) {
          localStorage.setItem('bizforge-provider-slug', selectedProviderSlug);
          const key = providerKeys[selectedProviderSlug];
          if (key) localStorage.setItem(`bizforge-provider-${selectedProviderSlug}`, key);
        }
        localStorage.removeItem('bizforge-registered-name');
        localStorage.removeItem('bizforge-registered-workspace-id');
        localStorage.removeItem('bizforge-registered-workspace-name');
      }

      if (isTauri() && selectedProviderSlug) {
        try {
          const { Store } = await import('@tauri-apps/plugin-store');
          const credStore = await Store.load('credentials.json');
          await credStore.set('provider', {
            slug: selectedProviderSlug,
            apiKey: providerKeys[selectedProviderSlug] ?? '',
          });
          await credStore.save();
        } catch (e) {
          console.warn('Credential save failed:', e);
        }
      }

      if (isTauri()) {
        try {
          const { Store } = await import('@tauri-apps/plugin-store');
          const settStore = await Store.load('settings.json');
          await settStore.set('default_adapter', selectedAdapter);
          await settStore.set('miosa_cloud', miosaCloud);
          await settStore.save();
        } catch (e) {
          console.warn('Settings save failed:', e);
        }
      }

      const needsLogin = !isMockEnabled() && getToken() === null;
      goto(needsLogin ? '/auth' : '/app');
    } catch (e) {
      console.error('Launch failed:', e);
      isLaunching = false;
    }
  }

  async function skip() {
    syncToStore();
    onboardingStore.complete();

    // Persist providers via API (same as launch)
    if (selectedProviders.length > 0) {
      const hasAuth = getToken() !== null || isMockEnabled();
      if (hasAuth) {
        try {
          const { providers: providersApi } = await import('$api/client');
          for (let i = 0; i < selectedProviders.length; i++) {
            const sp = selectedProviders[i];
            const { findProvider } = await import('$lib/data/provider-catalog');
            const catalogEntry = findProvider(sp.slug);
            await providersApi.create({
              slug: sp.slug,
              name: catalogEntry?.name ?? sp.slug,
              category: sp.slug === 'local' ? 'local' : 'cloud',
              api_key: sp.apiKey || undefined,
              endpoint: sp.endpoint ?? catalogEntry?.defaultEndpoint ?? undefined,
              config: sp.localRuntime ? { local_runtime: sp.localRuntime, local_endpoint: sp.endpoint } : {},
              models: catalogEntry?.defaultModels ?? [],
              is_default: i === 0,
            });
          }
        } catch (e) {
          console.warn('Skip: provider persistence failed:', e);
        }
      }
    }

    if (typeof localStorage !== 'undefined') {
      localStorage.setItem('bizforge-onboarding-complete', 'true');
      localStorage.setItem(
        'bizforge-onboarding',
        JSON.stringify({ completed: true }),
      );
      if (displayName) localStorage.setItem('bizforge-display-name', displayName);
      localStorage.setItem('bizforge-default-adapter', selectedAdapter);
      if (selectedProviderSlug) {
        localStorage.setItem('bizforge-provider-slug', selectedProviderSlug);
        const key = providerKeys[selectedProviderSlug];
        if (key) localStorage.setItem(`bizforge-provider-${selectedProviderSlug}`, key);
      }
      localStorage.removeItem('bizforge-registered-name');
      localStorage.removeItem('bizforge-registered-workspace-id');
      localStorage.removeItem('bizforge-registered-workspace-name');
    }

    if (isTauri() && selectedProviderSlug) {
      try {
        const { Store } = await import('@tauri-apps/plugin-store');
        const credStore = await Store.load('credentials.json');
        await credStore.set('provider', {
          slug: selectedProviderSlug,
          apiKey: providerKeys[selectedProviderSlug] ?? '',
        });
        await credStore.save();
      } catch (e) {
        console.warn('Skip: credential save failed:', e);
      }
    }

    if (isTauri()) {
      try {
        const { Store } = await import('@tauri-apps/plugin-store');
        const settStore = await Store.load('settings.json');
        await settStore.set('default_adapter', selectedAdapter);
        await settStore.set('miosa_cloud', miosaCloud);
        await settStore.save();
      } catch (e) {
        console.warn('Skip: settings save failed:', e);
      }
    }

    const needsLogin = !isMockEnabled() && getToken() === null;
    goto(needsLogin ? '/auth' : '/app');
  }
</script>

<div class="ob-root">
  <!-- Progress dots -->
  <div class="ob-dots">
    {#each { length: 7 } as _, i}
      <button
        class="ob-dot"
        class:ob-dot--active={i === step}
        class:ob-dot--done={i < step}
        onclick={() => { if (i <= step) { step = i; onboardingStore.goToStep(i); } }}
        aria-label="Step {i + 1}"
      ></button>
    {/each}
  </div>

  <!-- Step content card -->
  <div class="ob-card">
    {#if step === 0}
      <Welcome bind:displayName onImport={handleImport} onOpenRecent={handleOpenRecent} />
    {:else if step === 1}
      <Provider bind:selectedProviders />
    {:else if step === 2}
      <Adapter bind:selectedAdapter />
    {:else if step === 3}
      <Workspace bind:workspacePath bind:workspaceName bind:workspaceDesc />
    {:else if step === 4}
      <Team bind:teamTemplate />
    {:else if step === 5}
      <MiosaCloud bind:miosaCloud />
    {:else if step === 6}
      <Review
        {displayName}
        {selectedProviderSlug}
        {selectedProviders}
        {selectedAdapter}
        {workspacePath}
        {teamTemplate}
        {teamAgents}
        {miosaCloud}
        {isLaunching}
        onLaunch={launch}
        onSkip={skip}
      />
    {/if}
  </div>

  <!-- Navigation -->
  {#if step < 6}
    <div class="ob-nav" class:ob-nav--center={step === 0}>
      {#if step > 0}
        <button
          class="ob-btn ob-btn--secondary"
          onclick={prev}
          aria-label="Go back"
        >
          <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" width="14" height="14"><path d="M10 4L6 8l4 4"/></svg>
          Back
        </button>
      {/if}
      <button
        class="ob-btn ob-btn--primary"
        onclick={next}
        disabled={!canContinue}
        aria-label="Continue to next step"
      >
        {step === 0 ? 'Get Started' : 'Continue'}
        <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" width="14" height="14"><path d="M6 4l4 4-4 4"/></svg>
      </button>
    </div>
  {:else}
    <div class="ob-nav ob-nav--center">
      <button
        class="ob-btn ob-btn--secondary"
        onclick={prev}
        aria-label="Go back"
      >
        <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" width="14" height="14"><path d="M10 4L6 8l4 4"/></svg>
        Back
      </button>
    </div>
  {/if}
</div>

<div class="ob-footer">
  <ConnectionStatusBar alwaysShow={true} />
</div>

<style>
  /* ─── Root & layout ─────────────────────────────────────────────────── */

  .ob-root {
    min-height: calc(100vh - 24px);
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 2rem 1rem;
    background: #0a0a0a;
    color: #f0f0f0;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
  }

  .ob-footer {
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    background: rgba(10, 10, 10, 0.9);
    backdrop-filter: blur(8px);
    -webkit-backdrop-filter: blur(8px);
    border-top: 1px solid rgba(255, 255, 255, 0.06);
    z-index: 50;
  }

  /* ─── Progress dots ──────────────────────────────────────────────────── */

  .ob-dots {
    display: flex;
    gap: 6px;
    margin-bottom: 1.5rem;
  }

  .ob-dot {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: rgba(255, 255, 255, 0.15);
    border: none;
    padding: 0;
    cursor: pointer;
    transition: background 200ms ease, transform 200ms ease;
  }

  .ob-dot--active {
    background: #f26522;
    transform: scale(1.3);
  }

  .ob-dot--done {
    background: rgba(242, 101, 34, 0.45);
  }

  /* ─── Card ───────────────────────────────────────────────────────────── */

  .ob-card {
    width: 100%;
    max-width: 560px;
    background: rgba(255, 255, 255, 0.06);
    backdrop-filter: blur(24px);
    -webkit-backdrop-filter: blur(24px);
    border: 1px solid rgba(255, 255, 255, 0.08);
    border-radius: 20px;
    box-shadow:
      0 8px 32px rgba(0, 0, 0, 0.12),
      0 2px 8px rgba(0, 0, 0, 0.08),
      inset 0 1px 0 rgba(255, 255, 255, 0.1);
    padding: 2rem;
    min-height: 340px;
    display: flex;
    flex-direction: column;
  }

  /* ─── Navigation ─────────────────────────────────────────────────────── */

  .ob-nav {
    display: flex;
    align-items: center;
    justify-content: space-between;
    width: 100%;
    max-width: 560px;
    margin-top: 1rem;
  }

  .ob-nav--center {
    justify-content: center;
  }

  /* ─── Buttons ────────────────────────────────────────────────────────── */

  .ob-btn {
    display: inline-flex;
    align-items: center;
    gap: 0.375rem;
    border-radius: 9999px;
    font-size: 0.875rem;
    font-weight: 500;
    cursor: pointer;
    border: none;
    padding: 0.625rem 1.25rem;
    transition: background 150ms ease, opacity 150ms ease, transform 150ms ease, box-shadow 150ms ease;
  }

  .ob-btn:disabled {
    opacity: 0.35;
    cursor: not-allowed;
  }

  .ob-btn--primary {
    background: #f26522;
    color: #ffffff;
    border: 1px solid rgba(242, 101, 34, 0.6);
    box-shadow: none;
  }

  .ob-btn--primary:not(:disabled):hover {
    background: #e05a1a;
    border-color: rgba(224, 90, 26, 0.7);
  }

  .ob-btn--primary:not(:disabled):active {
    background: #cc5016;
  }

  .ob-btn--secondary {
    background: rgba(255, 255, 255, 0.06);
    color: #a1a1a6;
    border: 1px solid rgba(255, 255, 255, 0.1);
    box-shadow: none;
  }

  .ob-btn--secondary:not(:disabled):hover {
    background: rgba(255, 255, 255, 0.1);
    border-color: rgba(255, 255, 255, 0.15);
  }
</style>
