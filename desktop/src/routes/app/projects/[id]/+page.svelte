<!-- src/routes/app/projects/[id]/+page.svelte -->
<script lang="ts">
  import { page } from '$app/state';
  import { goto } from '$app/navigation';
  import PageShell from '$lib/components/layout/PageShell.svelte';
  import GoalHierarchy from '$lib/components/goals/GoalHierarchy.svelte';
  import IssueList from '$lib/components/issues/IssueList.svelte';
  import AgentCard from '$lib/components/agents/AgentCard.svelte';
  import AgentIcon from '$lib/components/shared/AgentIcon.svelte';
  import DocumentViewer from '$lib/components/documents/DocumentViewer.svelte';
  import GenerateDocModal from '$lib/components/documents/GenerateDocModal.svelte';
  import GenerateIssuesModal from '$lib/components/issues/GenerateIssuesModal.svelte';
  import { projectsStore } from '$lib/stores/projects.svelte';
  import { goalsStore } from '$lib/stores/goals.svelte';
  import { issuesStore } from '$lib/stores/issues.svelte';
  import { agentsStore } from '$lib/stores/agents.svelte';
  import { sessionsStore } from '$lib/stores/sessions.svelte';
  import { costsStore } from '$lib/stores/costs.svelte';
  import { documentsStore } from '$lib/stores/documents.svelte';
  import { workspaceStore } from '$lib/stores/workspace.svelte';
  import { integrationsStore } from '$lib/stores/integrations.svelte';
  import { integrationBindings as bindingsApi } from '$api/client';
  import IntegrationBindingSelector from '$lib/components/integrations/IntegrationBindingSelector.svelte';
  import { SKILLS } from '$api/mock/library/skills';
  import type { Project, Document, IntegrationBinding, SkillIntegrationRequirement } from '$api/types';

  // ── Route params ────────────────────────────────────────────────────────────
  const id = $derived(page.params.id ?? '');

  // ── Tab state — URL-persisted via ?tab= ─────────────────────────────────────
  type ProjectTab = 'overview' | 'goals' | 'docs' | 'issues' | 'agents' | 'sessions' | 'costs';
  const TABS: { id: ProjectTab; label: string }[] = [
    { id: 'overview',  label: 'Overview'  },
    { id: 'goals',     label: 'Goals'     },
    { id: 'docs',      label: 'Docs'      },
    { id: 'issues',    label: 'Issues'    },
    { id: 'agents',    label: 'Agents'    },
    { id: 'sessions',  label: 'Sessions'  },
    { id: 'costs',     label: 'Costs'     },
  ];

  const activeTab = $derived.by<ProjectTab>(() => {
    const t = page.url.searchParams.get('tab');
    if (t === 'goals' || t === 'docs' || t === 'issues' || t === 'agents' || t === 'sessions' || t === 'costs') {
      return t;
    }
    return 'overview';
  });

  function setTab(tab: ProjectTab) {
    const url = new URL(page.url);
    if (tab === 'overview') {
      url.searchParams.delete('tab');
    } else {
      url.searchParams.set('tab', tab);
    }
    void goto(url.toString(), { replaceState: true, keepFocus: true });
  }

  // ── Project load ─────────────────────────────────────────────────────────────
  let project = $state<Project | null>(null);
  let notFound = $state(false);

  $effect(() => {
    if (!id) return;
    const cached = projectsStore.projects.find((p) => p.id === id) ?? null;
    if (cached) {
      project = cached;
      notFound = false;
    } else {
      void projectsStore.fetchProject(id).then((fetched) => {
        if (fetched) {
          project = fetched;
          notFound = false;
        } else {
          notFound = true;
        }
      });
    }
  });

  // Keep project in sync with store updates (optimistic writes, etc.)
  $effect(() => {
    const updated = projectsStore.projects.find((p) => p.id === id) ?? null;
    if (updated) project = updated;
  });

  // ── Lazy-load tab data ───────────────────────────────────────────────────────
  // Track which tabs have already triggered their fetch so we don't re-fire.
  let loadedTabs = $state(new Set<ProjectTab>());

  $effect(() => {
    const tab = activeTab;
    if (!id || loadedTabs.has(tab)) return;

    if (tab === 'goals') {
      loadedTabs = new Set([...loadedTabs, 'goals']);
      void goalsStore.fetchGoals(id);
    } else if (tab === 'docs') {
      loadedTabs = new Set([...loadedTabs, 'docs']);
      void documentsStore.fetchByProject(id);
    } else if (tab === 'issues') {
      loadedTabs = new Set([...loadedTabs, 'issues']);
      void issuesStore.fetchIssues(workspaceStore.activeWorkspaceId ?? undefined);
    } else if (tab === 'agents') {
      loadedTabs = new Set([...loadedTabs, 'agents']);
      void agentsStore.fetchAgents(workspaceStore.activeWorkspaceId ?? undefined);
    } else if (tab === 'sessions') {
      loadedTabs = new Set([...loadedTabs, 'sessions']);
      void sessionsStore.fetch(workspaceStore.activeWorkspaceId ?? undefined);
    } else if (tab === 'costs') {
      loadedTabs = new Set([...loadedTabs, 'costs']);
      void costsStore.fetch(workspaceStore.activeWorkspaceId ?? undefined);
    }
  });

  // Reset loaded-tabs tracking when the project id changes (navigation between projects)
  $effect(() => {
    void id; // track reactively
    loadedTabs = new Set<ProjectTab>();
  });

  // ── Integration Bindings (project-level) ─────────────────────────────────────
  let projectBindings = $state<IntegrationBinding[]>([]);

  const projectRequiredIntegrations = $derived.by((): SkillIntegrationRequirement[] => {
    const projectAgents = agentsStore.agents.filter(a => a.project_id === id);
    const requirements: SkillIntegrationRequirement[] = [];
    const seenProviders = new Set<string>();

    for (const ag of projectAgents) {
      const agentSkillIds = ag.skills ?? [];
      for (const skillId of agentSkillIds) {
        const librarySkill = SKILLS.find(s => s.id === skillId);
        if (librarySkill === undefined) continue;
        for (const req of librarySkill.required_integrations) {
          if (!seenProviders.has(req.provider)) {
            seenProviders.add(req.provider);
            requirements.push(req);
          }
        }
      }
    }
    return requirements;
  });

  async function fetchProjectBindings() {
    if (!id) return;
    try {
      projectBindings = await bindingsApi.list('project', id);
    } catch {
      projectBindings = [];
    }
  }

  async function handleProjectBind(provider: string, integrationId: string) {
    if (!id) return;
    await bindingsApi.create({
      owner_type: 'project',
      owner_id: id,
      provider,
      integration_id: integrationId,
      config_overrides: {},
    });
    await fetchProjectBindings();
  }

  async function handleProjectUnbind(provider: string) {
    if (!id) return;
    await bindingsApi.removeByOwnerAndProvider('project', id, provider);
    await fetchProjectBindings();
  }

  $effect(() => {
    if (id) {
      void integrationsStore.fetchIntegrations();
      void fetchProjectBindings();
    }
  });

  // ── Derived: project-scoped data ─────────────────────────────────────────────
  const projectIssues = $derived(
    issuesStore.issues.filter((i) => i.project_id === id),
  );
  const openIssueCount = $derived(
    projectIssues.filter((i) => i.status !== 'done').length,
  );

  // Sessions: Session type has no project_id — filter by agents assigned to project.
  // Since agents also don't carry project_id we show all sessions (most useful fallback).
  const projectSessions = $derived(sessionsStore.sessions);

  // Cost breakdown: show agents with cost (workspace-scoped, no project_id on breakdown)
  const projectAgentCosts = $derived(costsStore.agentBreakdown);

  // ── Overview: recent activity (last 5 issues + goals combined, by updated_at) ──
  const recentActivity = $derived.by(() => {
    type ActivityItem = { kind: 'issue' | 'goal'; id: string; title: string; updated_at: string; status: string };
    const items: ActivityItem[] = [
      ...projectIssues.map((i) => ({ kind: 'issue' as const, id: i.id, title: i.title, updated_at: i.updated_at, status: i.status })),
      ...goalsStore.flatGoals.map((g) => ({ kind: 'goal' as const, id: g.id, title: g.title, updated_at: g.updated_at, status: g.status })),
    ];
    return items
      .sort((a, b) => new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime())
      .slice(0, 5);
  });

  // ── Goals progress ────────────────────────────────────────────────────────────
  const goalsTotal = $derived(goalsStore.totalCount);
  const goalsCompleted = $derived(goalsStore.completedCount);
  const goalsProgress = $derived(goalsTotal > 0 ? Math.round((goalsCompleted / goalsTotal) * 100) : 0);

  // ── Docs tab state ──────────────────────────────────────────────────────────
  let selectedDoc = $state<Document | null>(null);
  let showDocForm = $state(false);
  let docFormPath = $state('');
  let docFormContent = $state('');
  let docCreating = $state(false);
  let showGenerateDocModal = $state(false);
  let showGenerateIssuesModal = $state(false);

  const projectDocs = $derived(documentsStore.projectDocuments);
  const projectDocsCount = $derived(projectDocs.length);

  async function handleCreateDoc() {
    if (!docFormPath.trim() || !project) return;
    docCreating = true;
    try {
      await documentsStore.createDocument({
        title: docFormPath.trim().split('/').pop() ?? docFormPath.trim(),
        path: docFormPath.trim(),
        content: docFormContent,
        project_id: project.id,
        output_path: project.output_path,
        disk_subdir: 'docs',
      });
      showDocForm = false;
      docFormPath = '';
      docFormContent = '';
    } finally {
      docCreating = false;
    }
  }

  function cancelDocForm() {
    showDocForm = false;
    docFormPath = '';
    docFormContent = '';
  }

  // ── Inline-edit description ───────────────────────────────────────────────────
  let editingDesc = $state(false);
  let descDraft = $state('');

  function startEditDesc() {
    descDraft = project?.description ?? '';
    editingDesc = true;
  }

  async function saveDesc() {
    if (!project) return;
    editingDesc = false;
    await projectsStore.updateProject(project.id, { description: descDraft });
  }

  function cancelEditDesc() {
    editingDesc = false;
    descDraft = '';
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────
  function formatDate(iso: string): string {
    return new Date(iso).toLocaleDateString('en-US', {
      year: 'numeric', month: 'short', day: 'numeric',
    });
  }

  function formatDuration(startedAt: string, completedAt: string | null): string {
    const ms = completedAt
      ? new Date(completedAt).getTime() - new Date(startedAt).getTime()
      : Date.now() - new Date(startedAt).getTime();
    const s = Math.floor(ms / 1000);
    if (s < 60) return `${s}s`;
    const m = Math.floor(s / 60);
    if (m < 60) return `${m}m`;
    return `${Math.floor(m / 60)}h ${m % 60}m`;
  }

  function centsToDollars(cents: number): string {
    return `$${(cents / 100).toFixed(2)}`;
  }


</script>

<svelte:head>
  <title>{project ? `${project.name} — Projects — Bizforge` : 'Project — Bizforge'}</title>
</svelte:head>

<PageShell title={project?.name ?? 'Project'}>
  {#snippet actions()}
    {#if project}
      <nav class="pj-tab-bar" aria-label="Project sections">
        {#each TABS as tab (tab.id)}
          <button
            class="pj-tab"
            class:pj-tab--active={activeTab === tab.id}
            onclick={() => setTab(tab.id)}
            type="button"
            aria-current={activeTab === tab.id ? 'page' : undefined}
          >
            {tab.label}
            {#if tab.id === 'docs' && projectDocsCount > 0}
              <span class="pj-tab-badge" aria-label="{projectDocsCount} documents">
                {projectDocsCount}
              </span>
            {/if}
            {#if tab.id === 'issues' && openIssueCount > 0}
              <span class="pj-tab-badge" aria-label="{openIssueCount} open issues">
                {openIssueCount}
              </span>
            {/if}
          </button>
        {/each}
      </nav>
    {/if}
  {/snippet}

  <!-- ── Loading ────────────────────────────────────────────────────────────── -->
  {#if projectsStore.loading && !project}
    <div class="pj-loading" role="status" aria-live="polite">
      <div class="pj-spinner" aria-hidden="true"></div>
      <span>Loading project…</span>
    </div>

  <!-- ── Not found ──────────────────────────────────────────────────────────── -->
  {:else if notFound || (!project && !projectsStore.loading)}
    <div class="pj-empty" role="main">
      <span class="pj-empty-icon" aria-hidden="true"><AgentIcon value="folder" size={40} /></span>
      <p class="pj-empty-text">Project not found.</p>
      <button
        class="pj-btn-ghost"
        onclick={() => goto('/app/projects')}
        aria-label="Go back to projects"
      >
        ← Back to projects
      </button>
    </div>

  <!-- ── Main content ───────────────────────────────────────────────────────── -->
  {:else if project}
    <div class="pj-page">

      <!-- Breadcrumb -->
      <div class="pj-topbar">
        <button
          class="pj-back"
          onclick={() => goto('/app/projects')}
          aria-label="Back to projects list"
        >
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <path d="M19 12H5M12 19l-7-7 7-7" />
          </svg>
          Projects
        </button>
        <span class="pj-sep" aria-hidden="true">/</span>
        <span class="pj-cur">{project.name}</span>
      </div>

      <!-- Project header -->
      <div class="pj-header">
        <div class="pj-header-left">
          <span class="pj-status pj-status--{project.status}">{project.status}</span>
          <h1 class="pj-title">{project.name}</h1>

          {#if editingDesc}
            <div class="pj-desc-edit">
              <textarea
                class="pj-desc-textarea"
                bind:value={descDraft}
                rows={3}
                placeholder="Add a description…"
                aria-label="Edit project description"
              ></textarea>
              <div class="pj-desc-edit-actions">
                <button class="pj-btn-primary" onclick={saveDesc} type="button">Save</button>
                <button class="pj-btn-ghost" onclick={cancelEditDesc} type="button">Cancel</button>
              </div>
            </div>
          {:else}
            <button
              class="pj-desc-trigger"
              onclick={startEditDesc}
              type="button"
              aria-label="Edit description"
            >
              {#if project.description}
                <span class="pj-desc-text">{project.description}</span>
              {:else}
                <span class="pj-desc-placeholder">Add description…</span>
              {/if}
            </button>
          {/if}
        </div>

        <div class="pj-header-actions" role="group" aria-label="Project actions">
          <button
            class="pj-btn-ghost"
            onclick={() => void projectsStore.updateProject(project!.id, { status: 'archived' })}
            aria-label="Archive project"
          >
            Archive
          </button>
        </div>
      </div>

      <!-- Tab content -->
      <div class="pj-tab-content">

        <!-- ── Overview ──────────────────────────────────────────────────────── -->
        {#if activeTab === 'overview'}
          <!-- KPI row -->
          <div class="pj-kpi-row" role="list" aria-label="Project metrics">
            <div class="pj-kpi" role="listitem">
              <span class="pj-kpi-value">{project.goal_count}</span>
              <span class="pj-kpi-label">Goals</span>
            </div>
            <div class="pj-kpi" role="listitem">
              <span class="pj-kpi-value">{openIssueCount}</span>
              <span class="pj-kpi-label">Open Issues</span>
            </div>
            <div class="pj-kpi" role="listitem">
              <span class="pj-kpi-value">{project.agent_count}</span>
              <span class="pj-kpi-label">Agents</span>
            </div>
            <div class="pj-kpi" role="listitem">
              <span class="pj-kpi-value">{sessionsStore.sessions.length}</span>
              <span class="pj-kpi-label">Sessions</span>
            </div>
            <div class="pj-kpi" role="listitem">
              <span class="pj-kpi-value">{centsToDollars(costsStore.summary.month_cents)}</span>
              <span class="pj-kpi-label">Month Cost</span>
            </div>
          </div>

          <!-- Goals progress -->
          {#if goalsTotal > 0}
            <div class="pj-card">
              <div class="pj-card-header">
                <h2 class="pj-card-title">Goals Progress</h2>
                <span class="pj-card-meta">{goalsCompleted} / {goalsTotal} completed</span>
              </div>
              <div class="pj-progress-track" role="progressbar" aria-valuenow={goalsProgress} aria-valuemin={0} aria-valuemax={100} aria-label="Goals completion progress">
                <div class="pj-progress-fill" style="width: {goalsProgress}%"></div>
              </div>
              <p class="pj-progress-label">{goalsProgress}% complete</p>
            </div>
          {/if}

          <!-- Recent activity -->
          <div class="pj-card">
            <div class="pj-card-header">
              <h2 class="pj-card-title">Recent Activity</h2>
            </div>
            {#if recentActivity.length === 0}
              <p class="pj-empty-hint">No recent activity. Create a goal or issue to get started.</p>
            {:else}
              <ul class="pj-activity-list" aria-label="Recent activity">
                {#each recentActivity as item (item.id)}
                  <li class="pj-activity-item">
                    <span class="pj-activity-kind pj-activity-kind--{item.kind}">{item.kind}</span>
                    <span class="pj-activity-title">{item.title}</span>
                    <span class="pj-activity-status">{item.status}</span>
                    <time class="pj-activity-time" datetime={item.updated_at}>
                      {formatDate(item.updated_at)}
                    </time>
                  </li>
                {/each}
              </ul>
            {/if}
          </div>

          <!-- Service Access (project-level integration bindings) -->
          <div class="pj-card">
            <IntegrationBindingSelector
              ownerType="project"
              ownerId={project.id}
              requiredIntegrations={projectRequiredIntegrations}
              bindings={projectBindings}
              onBind={handleProjectBind}
              onUnbind={handleProjectUnbind}
            />
          </div>

          <!-- Project details sidebar info — shown inline in overview -->
          <div class="pj-card">
            <div class="pj-card-header">
              <h2 class="pj-card-title">Details</h2>
            </div>
            <dl class="pj-meta-grid">
              <div class="pj-meta-row">
                <dt class="pj-meta-label">Status</dt>
                <dd class="pj-meta-value">
                  <span class="pj-status pj-status--{project.status}">{project.status}</span>
                </dd>
              </div>
              <div class="pj-meta-row">
                <dt class="pj-meta-label">ID</dt>
                <dd class="pj-meta-value pj-meta-mono">{project.id}</dd>
              </div>
              {#if project.output_path}
                <div class="pj-meta-row">
                  <dt class="pj-meta-label">Output path</dt>
                  <dd class="pj-meta-value pj-meta-mono">{project.output_path}</dd>
                </div>
              {/if}
              <div class="pj-meta-row">
                <dt class="pj-meta-label">Created</dt>
                <dd class="pj-meta-value">{formatDate(project.created_at)}</dd>
              </div>
              <div class="pj-meta-row">
                <dt class="pj-meta-label">Updated</dt>
                <dd class="pj-meta-value">{formatDate(project.updated_at)}</dd>
              </div>
            </dl>
          </div>

        <!-- ── Goals ──────────────────────────────────────────────────────────── -->
        {:else if activeTab === 'goals'}
          <div class="pj-tab-toolbar">
            <h2 class="pj-tab-heading">Goals</h2>
            <button
              class="pj-btn-primary"
              type="button"
              onclick={() => void goalsStore.setActiveProject(id)}
              aria-label="Create goal in this project"
            >
              + Create Goal
            </button>
          </div>

          {#if goalsStore.loading}
            <div class="pj-loading" role="status" aria-live="polite">
              <div class="pj-spinner" aria-hidden="true"></div>
              <span>Loading goals…</span>
            </div>
          {:else if goalsStore.goals.length === 0}
            <div class="pj-empty-tab">
              <p class="pj-empty-hint">No goals yet for this project.</p>
            </div>
          {:else}
            <GoalHierarchy nodes={goalsStore.goals} />
          {/if}

        <!-- ── Docs ───────────────────────────────────────────────────────────── -->
        {:else if activeTab === 'docs'}
          <div class="pj-tab-toolbar">
            <h2 class="pj-tab-heading">
              Documents
              {#if projectDocsCount > 0}
                <span class="pj-count-badge">{projectDocsCount}</span>
              {/if}
            </h2>
            <div class="pj-tab-toolbar-actions">
              {#if projectDocsCount > 0}
                <button
                  class="pj-btn-ghost"
                  type="button"
                  onclick={() => { showGenerateIssuesModal = true; }}
                  aria-label="Generate issues from documentation"
                >
                  Analyze Docs
                </button>
              {/if}
              <button
                class="pj-btn-ghost"
                type="button"
                onclick={() => { showGenerateDocModal = true; }}
                aria-label="Generate documentation with AI"
              >
                Generate with AI
              </button>
              <button
                class="pj-btn-primary"
                type="button"
                onclick={() => { showDocForm = true; }}
                aria-label="Create a new document"
              >
                + New Document
              </button>
            </div>
          </div>

          {#if documentsStore.projectDocsLoading}
            <div class="pj-loading" role="status" aria-live="polite">
              <div class="pj-spinner" aria-hidden="true"></div>
              <span>Loading documents…</span>
            </div>
          {:else if projectDocsCount === 0}
            <div class="pj-empty-tab pj-docs-empty">
              <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.25" aria-hidden="true">
                <path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8zM14 2v6h6M16 13H8M16 17H8M10 9H8" />
              </svg>
              <p class="pj-empty-hint">No documents for this project yet.</p>
              <p class="pj-empty-sub">Add documentation manually or generate it with AI.</p>
              <div class="pj-empty-actions">
                <button
                  class="pj-btn-ghost"
                  type="button"
                  onclick={() => { showGenerateDocModal = true; }}
                >
                  Generate with AI
                </button>
                <button
                  class="pj-btn-primary"
                  type="button"
                  onclick={() => { showDocForm = true; }}
                >
                  + New Document
                </button>
              </div>
            </div>
          {:else}
            <div class="pj-docs-layout">
              <div class="pj-docs-list" role="list" aria-label="Project documents">
                {#each projectDocs as doc (doc.id)}
                  <button
                    class="pj-doc-row"
                    class:pj-doc-row--active={selectedDoc?.id === doc.id}
                    type="button"
                    onclick={() => { selectedDoc = doc; }}
                    aria-pressed={selectedDoc?.id === doc.id}
                    role="listitem"
                  >
                    <div class="pj-doc-info">
                      <span class="pj-doc-title">{doc.title}</span>
                      <span class="pj-doc-path">{doc.path}</span>
                    </div>
                    <div class="pj-doc-meta">
                      <span class="pj-doc-format">{doc.format}</span>
                      <time class="pj-doc-date" datetime={doc.updated_at}>
                        {formatDate(doc.updated_at)}
                      </time>
                    </div>
                  </button>
                {/each}
              </div>
              {#if selectedDoc}
                <div class="pj-docs-viewer">
                  <DocumentViewer document={selectedDoc} />
                </div>
              {:else}
                <div class="pj-docs-placeholder">
                  <p class="pj-empty-hint">Select a document to preview its contents.</p>
                </div>
              {/if}
            </div>
          {/if}

        <!-- ── Issues ─────────────────────────────────────────────────────────── -->
        {:else if activeTab === 'issues'}
          <div class="pj-tab-toolbar">
            <h2 class="pj-tab-heading">
              Issues
              {#if openIssueCount > 0}
                <span class="pj-count-badge">{openIssueCount} open</span>
              {/if}
            </h2>
            <div class="pj-tab-toolbar-actions">
              {#if projectDocsCount > 0}
                <button
                  class="pj-btn-ghost"
                  type="button"
                  onclick={() => { showGenerateIssuesModal = true; }}
                  aria-label="Generate issues from project documentation"
                >
                  Generate from Docs
                </button>
              {/if}
              <button
                class="pj-btn-primary"
                type="button"
                aria-label="Create issue in this project"
              >
                + Create Issue
              </button>
            </div>
          </div>

          {#if issuesStore.loading}
            <div class="pj-loading" role="status" aria-live="polite">
              <div class="pj-spinner" aria-hidden="true"></div>
              <span>Loading issues…</span>
            </div>
          {:else if projectIssues.length === 0}
            <div class="pj-empty-tab">
              <p class="pj-empty-hint">No issues for this project.</p>
            </div>
          {:else}
            <IssueList issues={projectIssues} />
          {/if}

        <!-- ── Agents ─────────────────────────────────────────────────────────── -->
        {:else if activeTab === 'agents'}
          <div class="pj-tab-toolbar">
            <h2 class="pj-tab-heading">Agents</h2>
            <button
              class="pj-btn-primary"
              type="button"
              aria-label="Assign agent to this project"
            >
              + Assign Agent
            </button>
          </div>

          {#if agentsStore.loading}
            <div class="pj-loading" role="status" aria-live="polite">
              <div class="pj-spinner" aria-hidden="true"></div>
              <span>Loading agents…</span>
            </div>
          {:else if agentsStore.agents.length === 0}
            <div class="pj-empty-tab">
              <p class="pj-empty-hint">No agents assigned to this project.</p>
            </div>
          {:else}
            <div class="pj-agent-grid" role="list" aria-label="Agents">
              {#each agentsStore.agents as agent (agent.id)}
                <div role="listitem">
                  <AgentCard {agent} />
                </div>
              {/each}
            </div>
          {/if}

        <!-- ── Sessions ───────────────────────────────────────────────────────── -->
        {:else if activeTab === 'sessions'}
          <div class="pj-tab-toolbar">
            <h2 class="pj-tab-heading">Sessions</h2>
          </div>

          {#if sessionsStore.loading}
            <div class="pj-loading" role="status" aria-live="polite">
              <div class="pj-spinner" aria-hidden="true"></div>
              <span>Loading sessions…</span>
            </div>
          {:else if projectSessions.length === 0}
            <div class="pj-empty-tab">
              <p class="pj-empty-hint">No sessions yet for this project.</p>
            </div>
          {:else}
            <div class="pj-session-table-wrap">
              <table class="pj-session-table" aria-label="Sessions">
                <thead>
                  <tr>
                    <th class="pj-th">Agent</th>
                    <th class="pj-th">Title</th>
                    <th class="pj-th">Status</th>
                    <th class="pj-th">Duration</th>
                    <th class="pj-th pj-th--num">Cost</th>
                    <th class="pj-th">Started</th>
                  </tr>
                </thead>
                <tbody>
                  {#each projectSessions as session (session.id)}
                    <tr
                      class="pj-session-row"
                      onclick={() => goto(`/app/sessions/${session.id}`)}
                      role="button"
                      tabindex="0"
                      onkeydown={(e) => e.key === 'Enter' && goto(`/app/sessions/${session.id}`)}
                      aria-label="Open session {session.title ?? session.id}"
                    >
                      <td class="pj-td">
                        <span class="pj-agent-name">{session.agent_name}</span>
                      </td>
                      <td class="pj-td pj-td--title">
                        {#if session.title}
                          {session.title}
                        {:else}
                          <span class="pj-muted">Untitled</span>
                        {/if}
                      </td>
                      <td class="pj-td">
                        <span class="pj-session-status pj-session-status--{session.status}">
                          {session.status}
                        </span>
                      </td>
                      <td class="pj-td">{formatDuration(session.started_at, session.completed_at)}</td>
                      <td class="pj-td pj-td--num">{centsToDollars(session.cost_cents)}</td>
                      <td class="pj-td pj-td--muted">{formatDate(session.started_at)}</td>
                    </tr>
                  {/each}
                </tbody>
              </table>
            </div>
          {/if}

        <!-- ── Costs ──────────────────────────────────────────────────────────── -->
        {:else if activeTab === 'costs'}
          <div class="pj-tab-toolbar">
            <h2 class="pj-tab-heading">Costs</h2>
          </div>

          {#if costsStore.isLoading}
            <div class="pj-loading" role="status" aria-live="polite">
              <div class="pj-spinner" aria-hidden="true"></div>
              <span>Loading cost data…</span>
            </div>
          {:else}
            <!-- Summary tiles -->
            <div class="pj-kpi-row" role="list" aria-label="Cost summary">
              <div class="pj-kpi" role="listitem">
                <span class="pj-kpi-value">{centsToDollars(costsStore.summary.today_cents)}</span>
                <span class="pj-kpi-label">Today</span>
              </div>
              <div class="pj-kpi" role="listitem">
                <span class="pj-kpi-value">{centsToDollars(costsStore.summary.week_cents)}</span>
                <span class="pj-kpi-label">This Week</span>
              </div>
              <div class="pj-kpi" role="listitem">
                <span class="pj-kpi-value">{centsToDollars(costsStore.summary.month_cents)}</span>
                <span class="pj-kpi-label">This Month</span>
              </div>
              {#if costsStore.summary.monthly_budget_cents > 0}
                <div class="pj-kpi" role="listitem">
                  <span class="pj-kpi-value">{centsToDollars(costsStore.summary.monthly_budget_cents)}</span>
                  <span class="pj-kpi-label">Monthly Budget</span>
                </div>
              {/if}
            </div>

            <!-- Budget usage bar -->
            {#if costsStore.summary.monthly_budget_cents > 0}
              <div class="pj-card">
                <div class="pj-card-header">
                  <h2 class="pj-card-title">Budget Usage</h2>
                  <span class="pj-card-meta">{Math.round(costsStore.monthlyUsagePct)}% used</span>
                </div>
                <div
                  class="pj-progress-track"
                  role="progressbar"
                  aria-valuenow={Math.round(costsStore.monthlyUsagePct)}
                  aria-valuemin={0}
                  aria-valuemax={100}
                  aria-label="Monthly budget usage"
                >
                  <div
                    class="pj-progress-fill"
                    class:pj-progress-fill--warn={costsStore.monthlyUsagePct > 75}
                    class:pj-progress-fill--danger={costsStore.monthlyUsagePct > 90}
                    style="width: {Math.min(costsStore.monthlyUsagePct, 100)}%"
                  ></div>
                </div>
              </div>
            {/if}

            <!-- Agent cost breakdown -->
            {#if projectAgentCosts.length > 0}
              <div class="pj-card">
                <div class="pj-card-header">
                  <h2 class="pj-card-title">By Agent</h2>
                </div>
                <table class="pj-cost-table" aria-label="Agent cost breakdown">
                  <thead>
                    <tr>
                      <th class="pj-th">Agent</th>
                      <th class="pj-th pj-th--num">Runs</th>
                      <th class="pj-th pj-th--num">Tokens</th>
                      <th class="pj-th pj-th--num">Cost</th>
                    </tr>
                  </thead>
                  <tbody>
                    {#each projectAgentCosts as row (row.agent_id)}
                      <tr class="pj-cost-row">
                        <td class="pj-td">
                          <div class="pj-agent-cell">
                            <span>{row.agent_name}</span>
                          </div>
                        </td>
                        <td class="pj-td pj-td--num">{row.run_count}</td>
                        <td class="pj-td pj-td--num">{(row.token_usage.input + row.token_usage.output).toLocaleString()}</td>
                        <td class="pj-td pj-td--num pj-td--cost">{centsToDollars(row.cost_cents)}</td>
                      </tr>
                    {/each}
                  </tbody>
                </table>
              </div>
            {:else}
              <div class="pj-empty-tab">
                <p class="pj-empty-hint">No cost data available yet.</p>
              </div>
            {/if}
          {/if}
        {/if}

      </div><!-- /pj-tab-content -->
    </div><!-- /pj-page -->
  {/if}
</PageShell>

<!-- Create document dialog -->
{#if showDocForm}
  <div
    class="pj-overlay"
    role="dialog"
    aria-modal="true"
    aria-label="Create document"
    onclick={(e) => { if (e.target === e.currentTarget) cancelDocForm(); }}
  >
    <div class="pj-dialog">
      <h2 class="pj-dialog-title">New Document</h2>
      <div class="pj-field">
        <label class="pj-field-label" for="pj-doc-path">Path</label>
        <input
          id="pj-doc-path"
          class="pj-field-input"
          type="text"
          placeholder="e.g. docs/requirements.md"
          bind:value={docFormPath}
          autofocus
        />
      </div>
      <div class="pj-field">
        <label class="pj-field-label" for="pj-doc-content">Content</label>
        <textarea
          id="pj-doc-content"
          class="pj-field-textarea"
          placeholder="Document content…"
          bind:value={docFormContent}
          rows={8}
        ></textarea>
      </div>
      <div class="pj-dialog-footer">
        <button class="pj-btn-ghost" onclick={cancelDocForm} disabled={docCreating}>Cancel</button>
        <button
          class="pj-btn-primary"
          onclick={handleCreateDoc}
          disabled={docCreating || !docFormPath.trim()}
        >
          {docCreating ? 'Creating…' : 'Create Document'}
        </button>
      </div>
    </div>
  </div>
{/if}

<!-- AI document generation modal -->
{#if showGenerateDocModal && project}
  <GenerateDocModal
    projectId={project.id}
    projectName={project.name}
    projectDescription={project.description}
    outputPath={project.output_path}
    onClose={() => { showGenerateDocModal = false; }}
    onSaved={() => { showGenerateDocModal = false; void documentsStore.fetchByProject(project!.id); }}
  />
{/if}

<!-- Generate issues from docs modal -->
{#if showGenerateIssuesModal && project}
  <GenerateIssuesModal
    projectId={project.id}
    projectName={project.name}
    outputPath={project.output_path}
    documents={projectDocs}
    onClose={() => { showGenerateIssuesModal = false; }}
    onCreated={() => { showGenerateIssuesModal = false; void issuesStore.fetchIssues(workspaceStore.activeWorkspaceId ?? undefined); }}
  />
{/if}

<style>
  /* ── Loading / empty states ─────────────────────────────────────────────── */
  .pj-loading {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 12px;
    height: 200px;
    color: var(--text-tertiary);
    font-size: 13px;
  }

  .pj-spinner {
    width: 22px;
    height: 22px;
    border-radius: 50%;
    border: 2px solid var(--border-default);
    border-top-color: var(--text-secondary);
    animation: pj-spin 0.8s linear infinite;
  }

  @keyframes pj-spin { to { transform: rotate(360deg); } }

  .pj-empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 12px;
    height: 100%;
    color: var(--text-tertiary);
    font-size: 13px;
  }

  .pj-empty-icon {
    display: flex;
    align-items: center;
    color: #f26522;
    opacity: 0.4;
  }
  .pj-empty-text { margin: 0; }

  .pj-empty-tab {
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 48px 24px;
  }

  .pj-empty-hint {
    font-size: 13px;
    color: var(--text-tertiary);
    margin: 0;
  }

  /* ── Tab bar ────────────────────────────────────────────────────────────── */
  .pj-tab-bar {
    display: flex;
    gap: 2px;
  }

  .pj-tab {
    display: flex;
    align-items: center;
    gap: 5px;
    height: 26px;
    padding: 0 10px;
    border-radius: 5px;
    font-size: 12px;
    font-weight: 500;
    background: transparent;
    border: 1px solid transparent;
    color: var(--text-secondary);
    cursor: pointer;
    font-family: var(--font-sans);
    transition: background 100ms ease, color 100ms ease, border-color 100ms ease;
  }

  .pj-tab:hover {
    background: var(--bg-elevated);
    color: var(--text-primary);
    border-color: var(--border-default);
  }

  .pj-tab--active {
    background: var(--bg-elevated);
    border-color: var(--border-hover);
    color: var(--text-primary);
  }

  .pj-tab-badge {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 16px;
    height: 16px;
    padding: 0 4px;
    border-radius: 8px;
    font-size: 10px;
    font-weight: 600;
    background: var(--bg-tertiary);
    color: var(--text-secondary);
  }

  /* ── Page structure ─────────────────────────────────────────────────────── */
  .pj-page {
    display: flex;
    flex-direction: column;
    min-height: 100%;
  }

  .pj-topbar {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 16px 24px 0;
  }

  .pj-back {
    display: flex;
    align-items: center;
    gap: 6px;
    height: 28px;
    padding: 0 10px;
    border-radius: var(--radius-xs, 4px);
    border: 1px solid transparent;
    background: transparent;
    color: var(--text-tertiary);
    font-size: 12px;
    font-family: var(--font-sans);
    cursor: pointer;
    transition: all 120ms ease;
  }

  .pj-back:hover {
    background: var(--bg-elevated);
    border-color: var(--border-default);
    color: var(--text-primary);
  }

  .pj-sep  { color: var(--text-muted); font-size: 12px; }
  .pj-cur  { font-size: 12px; color: var(--text-secondary); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 240px; }

  /* ── Project header ─────────────────────────────────────────────────────── */
  .pj-header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 16px;
    padding: 20px 24px 0;
  }

  .pj-header-left {
    display: flex;
    flex-direction: column;
    gap: 6px;
    min-width: 0;
  }

  .pj-title {
    font-size: 22px;
    font-weight: 700;
    color: var(--text-primary);
    margin: 0;
    line-height: 1.2;
  }

  /* Status badge */
  .pj-status {
    display: inline-flex;
    align-items: center;
    height: 20px;
    padding: 0 8px;
    border-radius: 10px;
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.2px;
    text-transform: capitalize;
    white-space: nowrap;
    width: fit-content;
  }

  .pj-status--active    { background: rgba(34, 197, 94, 0.08); border: 1px solid rgba(34, 197, 94, 0.2); color: rgba(34, 197, 94, 0.8); }
  .pj-status--completed { background: rgba(249, 115, 22, 0.12); border: 1px solid rgba(249, 115, 22, 0.25); color: #fdba74; }
  .pj-status--archived  { background: var(--bg-elevated); border: 1px solid var(--border-default); color: var(--text-muted); }

  /* Inline description editing */
  .pj-desc-trigger {
    background: transparent;
    border: 1px solid transparent;
    border-radius: var(--radius-xs, 4px);
    padding: 4px 6px;
    text-align: left;
    cursor: text;
    transition: border-color 120ms ease, background 120ms ease;
  }

  .pj-desc-trigger:hover {
    border-color: var(--border-default);
    background: var(--bg-elevated);
  }

  .pj-desc-text {
    font-size: 13px;
    line-height: 1.5;
    color: var(--text-tertiary);
  }

  .pj-desc-placeholder {
    font-size: 13px;
    color: var(--text-muted);
    font-style: italic;
  }

  .pj-desc-edit {
    display: flex;
    flex-direction: column;
    gap: 8px;
    max-width: 520px;
  }

  .pj-desc-textarea {
    padding: 8px 10px;
    border-radius: var(--radius-sm, 6px);
    border: 1px solid var(--border-focus, #f97316);
    background: var(--bg-surface);
    color: var(--text-primary);
    font-size: 13px;
    font-family: var(--font-sans);
    line-height: 1.5;
    resize: vertical;
    outline: none;
  }

  .pj-desc-edit-actions {
    display: flex;
    gap: 6px;
  }

  /* Header action buttons */
  .pj-header-actions {
    display: flex;
    gap: 6px;
    flex-shrink: 0;
    padding-top: 4px;
  }

  /* Buttons */
  .pj-btn-ghost {
    height: 30px;
    padding: 0 12px;
    border-radius: var(--radius-sm, 6px);
    border: 1px solid var(--border-default);
    background: transparent;
    color: var(--text-secondary);
    font-size: 12px;
    font-weight: 500;
    font-family: var(--font-sans);
    cursor: pointer;
    transition: all 120ms ease;
  }

  .pj-btn-ghost:hover {
    background: var(--bg-elevated);
    color: var(--text-primary);
  }

  .pj-btn-primary {
    height: 30px;
    padding: 0 12px;
    border-radius: var(--radius-sm, 6px);
    border: 1px solid rgba(249, 115, 22, 0.35);
    background: rgba(249, 115, 22, 0.1);
    color: #fdba74;
    font-size: 12px;
    font-weight: 500;
    font-family: var(--font-sans);
    cursor: pointer;
    transition: all 120ms ease;
  }

  .pj-btn-primary:hover {
    background: rgba(249, 115, 22, 0.18);
    border-color: rgba(249, 115, 22, 0.5);
    color: #fdba74;
  }

  /* ── Tab content area ───────────────────────────────────────────────────── */
  .pj-tab-content {
    padding: 20px 24px 32px;
    display: flex;
    flex-direction: column;
    gap: 16px;
    min-height: 0;
  }

  /* Tab toolbar (heading + action button) */
  .pj-tab-toolbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
  }

  .pj-tab-heading {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 14px;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0;
  }

  .pj-count-badge {
    font-size: 11px;
    font-weight: 500;
    color: var(--text-tertiary);
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    border-radius: 10px;
    padding: 0 7px;
    height: 18px;
    display: inline-flex;
    align-items: center;
  }

  /* ── KPI row ────────────────────────────────────────────────────────────── */
  .pj-kpi-row {
    display: flex;
    gap: 10px;
    flex-wrap: wrap;
  }

  .pj-kpi {
    flex: 1;
    min-width: 100px;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
    padding: 14px 8px;
    background: var(--bg-surface);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-md, 8px);
    backdrop-filter: blur(8px);
    -webkit-backdrop-filter: blur(8px);
  }

  .pj-kpi-value {
    font-size: 22px;
    font-weight: 700;
    color: var(--text-primary);
    font-variant-numeric: tabular-nums;
    line-height: 1;
  }

  .pj-kpi-label {
    font-size: 11px;
    color: var(--text-muted);
    text-align: center;
  }

  /* ── Card ───────────────────────────────────────────────────────────────── */
  .pj-card {
    background: var(--bg-surface);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-md, 8px);
    padding: 16px;
    backdrop-filter: blur(8px);
    -webkit-backdrop-filter: blur(8px);
  }

  .pj-card-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 12px;
  }

  .pj-card-title {
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    color: var(--text-tertiary);
    margin: 0;
  }

  .pj-card-meta {
    font-size: 12px;
    color: var(--text-muted);
  }

  /* ── Progress bar ───────────────────────────────────────────────────────── */
  .pj-progress-track {
    height: 6px;
    border-radius: 3px;
    background: var(--bg-elevated);
    overflow: hidden;
  }

  .pj-progress-fill {
    height: 100%;
    border-radius: 3px;
    background: #f97316;
    transition: width 300ms ease;
  }

  .pj-progress-fill--warn   { background: #f59e0b; }
  .pj-progress-fill--danger { background: #ef4444; }

  .pj-progress-label {
    font-size: 11px;
    color: var(--text-muted);
    margin: 6px 0 0;
  }

  /* ── Activity list ──────────────────────────────────────────────────────── */
  .pj-activity-list {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 1px;
  }

  .pj-activity-item {
    display: grid;
    grid-template-columns: 50px 1fr 80px 100px;
    align-items: center;
    gap: 10px;
    padding: 8px 10px;
    border-radius: var(--radius-xs, 4px);
    font-size: 12px;
  }

  .pj-activity-item:hover {
    background: var(--bg-elevated);
  }

  .pj-activity-kind {
    font-size: 10px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.3px;
    padding: 2px 6px;
    border-radius: 3px;
    text-align: center;
  }

  .pj-activity-kind--issue { background: rgba(239, 68, 68, 0.1); color: #fca5a5; }
  .pj-activity-kind--goal  { background: rgba(249, 115, 22, 0.1); color: #fdba74; }

  .pj-activity-title {
    color: var(--text-primary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .pj-activity-status { color: var(--text-muted); text-transform: capitalize; }
  .pj-activity-time   { color: var(--text-muted); text-align: right; }

  /* ── Meta grid (Details section) ───────────────────────────────────────── */
  .pj-meta-grid {
    display: flex;
    flex-direction: column;
    gap: 8px;
    margin: 0;
  }

  .pj-meta-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }

  .pj-meta-label {
    font-size: 11px;
    color: var(--text-muted);
    flex-shrink: 0;
  }

  .pj-meta-value {
    font-size: 12px;
    color: var(--text-secondary);
    text-align: right;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    max-width: 300px;
  }

  .pj-meta-mono { font-family: var(--font-mono); font-size: 11px; }

  /* ── Agent grid ─────────────────────────────────────────────────────────── */
  .pj-agent-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
    gap: 12px;
  }

  /* ── Session table ──────────────────────────────────────────────────────── */
  .pj-session-table-wrap {
    overflow-x: auto;
    border-radius: var(--radius-md, 8px);
    border: 1px solid var(--border-default);
    background: var(--bg-surface);
  }

  .pj-session-table,
  .pj-cost-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 12px;
  }

  .pj-th {
    padding: 10px 12px;
    text-align: left;
    font-size: 11px;
    font-weight: 600;
    color: var(--text-muted);
    text-transform: uppercase;
    letter-spacing: 0.4px;
    border-bottom: 1px solid var(--border-default);
    background: var(--bg-secondary);
    white-space: nowrap;
  }

  .pj-th--num { text-align: right; }

  .pj-td {
    padding: 10px 12px;
    color: var(--text-secondary);
    border-bottom: 1px solid var(--border-subtle, rgba(255,255,255,0.04));
    vertical-align: middle;
  }

  .pj-td--num    { text-align: right; font-variant-numeric: tabular-nums; }
  .pj-td--muted  { color: var(--text-muted); }
  .pj-td--title  { max-width: 240px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: var(--text-primary); }
  .pj-td--cost   { color: var(--text-primary); font-weight: 500; }

  .pj-session-row {
    cursor: pointer;
    transition: background 80ms ease;
  }

  .pj-session-row:hover .pj-td { background: var(--bg-elevated); }
  .pj-session-row:last-child .pj-td { border-bottom: none; }

  .pj-agent-name { color: var(--text-primary); font-weight: 500; }
  .pj-muted      { color: var(--text-muted); font-style: italic; }

  .pj-session-status {
    display: inline-flex;
    align-items: center;
    height: 18px;
    padding: 0 7px;
    border-radius: 9px;
    font-size: 10px;
    font-weight: 600;
    text-transform: capitalize;
  }

  .pj-session-status--active    { background: rgba(34, 197, 94, 0.1); color: #86efac; border: 1px solid rgba(34, 197, 94, 0.2); }
  .pj-session-status--completed { background: var(--bg-elevated); color: var(--text-muted); border: 1px solid var(--border-default); }
  .pj-session-status--failed    { background: rgba(239, 68, 68, 0.1); color: #fca5a5; border: 1px solid rgba(239, 68, 68, 0.2); }
  .pj-session-status--cancelled { background: var(--bg-elevated); color: var(--text-muted); border: 1px solid var(--border-default); }

  /* ── Cost table ─────────────────────────────────────────────────────────── */
  .pj-cost-table {
    border-collapse: collapse;
  }

  .pj-cost-row:last-child .pj-td { border-bottom: none; }

  .pj-agent-cell {
    display: flex;
    align-items: center;
    gap: 7px;
  }

  /* ── Docs tab ──────────────────────────────────────────────────────────── */
  .pj-tab-toolbar-actions {
    display: flex;
    align-items: center;
    gap: 6px;
  }

  .pj-docs-layout {
    display: flex;
    gap: 0;
    min-height: 300px;
    border: 1px solid var(--border-default);
    border-radius: var(--radius-md, 8px);
    overflow: hidden;
    background: var(--bg-surface);
  }

  .pj-docs-list {
    width: 280px;
    min-width: 220px;
    flex-shrink: 0;
    border-right: 1px solid var(--border-default);
    overflow-y: auto;
    display: flex;
    flex-direction: column;
  }

  .pj-docs-list::-webkit-scrollbar { width: 4px; }
  .pj-docs-list::-webkit-scrollbar-thumb { background: var(--border-default); border-radius: 2px; }

  .pj-doc-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    padding: 10px 14px;
    border: none;
    border-bottom: 1px solid var(--border-subtle, rgba(255,255,255,0.04));
    background: transparent;
    cursor: pointer;
    text-align: left;
    width: 100%;
    transition: background 80ms ease;
    font-family: inherit;
  }

  .pj-doc-row:hover { background: var(--bg-elevated); }
  .pj-doc-row--active { background: rgba(249, 115, 22, 0.06); border-left: 2px solid #f97316; }

  .pj-doc-info {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }

  .pj-doc-title {
    font-size: 13px;
    font-weight: 500;
    color: var(--text-primary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .pj-doc-path {
    font-size: 11px;
    color: var(--text-muted);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-family: var(--font-mono, monospace);
  }

  .pj-doc-meta {
    display: flex;
    flex-direction: column;
    align-items: flex-end;
    gap: 2px;
    flex-shrink: 0;
  }

  .pj-doc-format {
    font-size: 9px;
    font-weight: 500;
    text-transform: uppercase;
    padding: 1px 5px;
    border-radius: 3px;
    background: rgba(255,255,255,0.06);
    border: 1px solid var(--border-default);
    color: var(--text-tertiary);
  }

  .pj-doc-date {
    font-size: 10px;
    color: var(--text-muted);
  }

  .pj-docs-viewer {
    flex: 1;
    min-width: 0;
    overflow: hidden;
  }

  .pj-docs-placeholder {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 24px;
  }

  .pj-docs-empty {
    flex-direction: column;
    align-items: center;
    gap: 10px;
    padding: 48px 24px;
  }

  .pj-docs-empty svg { color: var(--text-muted); opacity: 0.4; }

  .pj-empty-sub {
    font-size: 12px;
    color: var(--text-muted);
    margin: 0;
  }

  .pj-empty-actions {
    display: flex;
    gap: 8px;
    margin-top: 8px;
  }

  /* ── Create doc dialog ─────────────────────────────────────────────────── */
  .pj-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0,0,0,0.5);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1000;
  }

  .pj-dialog {
    background: var(--bg-tertiary, var(--bg-surface));
    border: 1px solid var(--border-default);
    border-radius: 12px;
    padding: 24px;
    width: 480px;
    max-width: calc(100vw - 40px);
    display: flex;
    flex-direction: column;
    gap: 16px;
  }

  .pj-dialog-title {
    font-size: 16px;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0;
  }

  .pj-field {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .pj-field-label {
    font-size: 12px;
    font-weight: 500;
    color: var(--text-secondary);
  }

  .pj-field-input {
    height: 34px;
    padding: 0 10px;
    border-radius: 6px;
    font-size: 13px;
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    color: var(--text-primary);
    width: 100%;
    box-sizing: border-box;
  }
  .pj-field-input:focus { outline: none; border-color: #f97316; }

  .pj-field-textarea {
    padding: 8px 10px;
    border-radius: 6px;
    font-size: 13px;
    font-family: var(--font-mono, monospace);
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    color: var(--text-primary);
    width: 100%;
    box-sizing: border-box;
    resize: vertical;
    min-height: 120px;
    line-height: 1.5;
  }
  .pj-field-textarea:focus { outline: none; border-color: #f97316; }

  .pj-dialog-footer {
    display: flex;
    gap: 8px;
    justify-content: flex-end;
    margin-top: 4px;
  }
</style>
