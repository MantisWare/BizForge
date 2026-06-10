<!-- src/routes/app/projects/[id]/+page.svelte -->
<script lang="ts">
  import { page } from '$app/state';
  import { goto } from '$app/navigation';
  import PageShell from '$lib/components/layout/PageShell.svelte';
  import PhaseHierarchy from '$lib/components/phases/PhaseHierarchy.svelte';
  import TaskList from '$lib/components/tasks/TaskList.svelte';
  import AgentCard from '$lib/components/agents/AgentCard.svelte';
  import AgentIcon from '$lib/components/shared/AgentIcon.svelte';
  import DocumentViewer from '$lib/components/documents/DocumentViewer.svelte';
  import GenerateDocModal from '$lib/components/documents/GenerateDocModal.svelte';
  import GeneratePhasesTasksModal from '$lib/components/tasks/GeneratePhasesTasksModal.svelte';
  import AutomatedTaskPipeline from '$lib/components/tasks/AutomatedTaskPipeline.svelte';
  import { projectsStore } from '$lib/stores/projects.svelte';
  import { phasesStore } from '$lib/stores/phases.svelte';
  import { tasksStore } from '$lib/stores/tasks.svelte';
  import { agentsStore } from '$lib/stores/agents.svelte';
  import { sessionsStore } from '$lib/stores/sessions.svelte';
  import { costsStore } from '$lib/stores/costs.svelte';
  import { documentsStore } from '$lib/stores/documents.svelte';
  import { workspaceStore } from '$lib/stores/workspace.svelte';
  import { integrationsStore } from '$lib/stores/integrations.svelte';
  import { integrationBindings as bindingsApi } from '$api/client';
  import IntegrationBindingSelector from '$lib/components/integrations/IntegrationBindingSelector.svelte';
  import { SKILLS } from '$api/mock/library/skills';
  import type { Project, Document, IntegrationBinding, SkillIntegrationRequirement, DocumentFormat, DeliveryReport, DeliveryReadiness, DeliveryCheck } from '$api/types';
  import { projects as projectsApi } from '$api/client';
  import { isTauri } from '$lib/utils/platform';
  import { onMount, onDestroy } from 'svelte';

  // ── Route params ────────────────────────────────────────────────────────────
  const id = $derived(page.params.id ?? '');

  // ── Tab state — URL-persisted via ?tab= ─────────────────────────────────────
  type ProjectTab = 'overview' | 'docs' | 'phases' | 'tasks' | 'agents' | 'sessions' | 'costs' | 'delivery';
  const TABS: { id: ProjectTab; label: string }[] = [
    { id: 'overview',  label: 'Overview'  },
    { id: 'docs',      label: 'Docs'      },
    { id: 'phases',    label: 'Phases'    },
    { id: 'tasks',     label: 'Tasks'     },
    { id: 'agents',    label: 'Agents'    },
    { id: 'sessions',  label: 'Sessions'  },
    { id: 'costs',     label: 'Costs'     },
    { id: 'delivery',  label: 'Delivery'  },
  ];

  const activeTab = $derived.by<ProjectTab>(() => {
    const t = page.url.searchParams.get('tab');
    if (t === 'docs' || t === 'phases' || t === 'tasks' || t === 'agents' || t === 'sessions' || t === 'costs' || t === 'delivery') {
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

  // Overview needs docs + phases to render the conditional CTA, so pre-fetch them.
  $effect(() => {
    if (!id) return;
    if (!loadedTabs.has('docs')) {
      loadedTabs = new Set([...loadedTabs, 'docs']);
      void documentsStore.fetchByProject(id);
    }
    if (!loadedTabs.has('phases')) {
      loadedTabs = new Set([...loadedTabs, 'phases']);
      void phasesStore.fetchPhases(id);
    }
    if (!loadedTabs.has('tasks')) {
      loadedTabs = new Set([...loadedTabs, 'tasks']);
      void tasksStore.fetchTasks(workspaceStore.activeWorkspaceId ?? undefined);
    }
  });

  $effect(() => {
    const tab = activeTab;
    if (!id || loadedTabs.has(tab)) return;

    if (tab === 'phases') {
      loadedTabs = new Set([...loadedTabs, 'phases']);
      void phasesStore.fetchPhases(id);
    } else if (tab === 'docs') {
      loadedTabs = new Set([...loadedTabs, 'docs']);
      void documentsStore.fetchByProject(id);
    } else if (tab === 'tasks') {
      loadedTabs = new Set([...loadedTabs, 'tasks']);
      void tasksStore.fetchTasks(workspaceStore.activeWorkspaceId ?? undefined);
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
  const projectTasks = $derived(
    tasksStore.tasks.filter((t) => t.project_id === id),
  );
  const openTaskCount = $derived(
    projectTasks.filter((t) => t.status !== 'done').length,
  );

  // Sessions: Session type has no project_id — filter by agents assigned to project.
  // Since agents also don't carry project_id we show all sessions (most useful fallback).
  const projectSessions = $derived(sessionsStore.sessions);

  // Cost breakdown: show agents with cost (workspace-scoped, no project_id on breakdown)
  const projectAgentCosts = $derived(costsStore.agentBreakdown);

  // ── Overview: recent activity (last 5 tasks + phases combined, by updated_at) ──
  const recentActivity = $derived.by(() => {
    type ActivityItem = { kind: 'task' | 'phase'; id: string; title: string; updated_at: string; status: string };
    const items: ActivityItem[] = [
      ...projectTasks.map((i) => ({ kind: 'task' as const, id: i.id, title: i.title, updated_at: i.updated_at, status: i.status })),
      ...phasesStore.flatPhases.map((g) => ({ kind: 'phase' as const, id: g.id, title: g.title, updated_at: g.updated_at, status: g.status })),
    ];
    return items
      .sort((a, b) => new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime())
      .slice(0, 5);
  });

  // ── Phases progress (overview KPI) ────────────────────────────────────────────
  const phasesTotal = $derived(phasesStore.totalCount);
  const phasesCompleted = $derived(phasesStore.completedCount);
  const phasesProgress = $derived(phasesTotal > 0 ? Math.round((phasesCompleted / phasesTotal) * 100) : 0);

  // ── Docs tab state ──────────────────────────────────────────────────────────
  let selectedDoc = $state<Document | null>(null);
  let showDocForm = $state(false);
  let docFormPath = $state('');
  let docFormContent = $state('');
  let docCreating = $state(false);
  let showGenerateDocModal = $state(false);
  let showGenerateTasksModal = $state(false);
  let showPipelineModal = $state(false);

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

  // ── Upload files dialog ───────────────────────────────────────────────────────
  let showUploadDialog = $state(false);
  let uploadFiles = $state<{ id: string; name: string; content: string; format: DocumentFormat; size: number }[]>([]);
  let uploadDragOver = $state(false);
  let uploading = $state(false);
  let uploadError = $state<string | null>(null);

  const UPLOAD_ACCEPTED_EXTENSIONS: Record<string, DocumentFormat> = {
    '.md': 'markdown', '.txt': 'text', '.json': 'json', '.yaml': 'yaml',
    '.yml': 'yaml', '.csv': 'text', '.dbml': 'text', '.sql': 'sql',
    '.pdf': 'pdf', '.doc': 'binary', '.docx': 'binary',
    '.xls': 'binary', '.xlsx': 'binary',
  };
  const UPLOAD_BINARY_EXTENSIONS = new Set(['.pdf', '.doc', '.docx', '.xls', '.xlsx']);
  const UPLOAD_ACCEPT_STRING = Object.keys(UPLOAD_ACCEPTED_EXTENSIONS).join(',');

  function getUploadExt(name: string): string { return name.slice(name.lastIndexOf('.')).toLowerCase(); }
  function getUploadFormat(name: string): DocumentFormat { return UPLOAD_ACCEPTED_EXTENSIONS[getUploadExt(name)] ?? 'markdown'; }
  function isUploadAccepted(name: string): boolean { return getUploadExt(name) in UPLOAD_ACCEPTED_EXTENSIONS; }
  function uploadFormatSize(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }

  async function handleUploadFileInput(files: FileList | null): Promise<void> {
    if (files === null) return;
    for (const file of Array.from(files)) {
      if (!isUploadAccepted(file.name)) continue;
      const ext = getUploadExt(file.name);
      let content: string;
      if (UPLOAD_BINARY_EXTENSIONS.has(ext)) {
        const label = ext.replace('.', '').toUpperCase();
        content = `[${label} Document: ${file.name}] — ${uploadFormatSize(file.size)}`;
      } else {
        content = await file.text();
      }
      uploadFiles = [...uploadFiles, {
        id: crypto.randomUUID(),
        name: file.name,
        content,
        format: getUploadFormat(file.name),
        size: file.size,
      }];
    }
  }

  async function handleUploadTauriPaths(paths: string[]): Promise<void> {
    const fs = await import('@tauri-apps/plugin-fs');
    for (const filePath of paths) {
      const name = filePath.split('/').pop() ?? filePath;
      if (!isUploadAccepted(name)) continue;
      const ext = getUploadExt(name);
      try {
        let content: string;
        let size: number;
        if (UPLOAD_BINARY_EXTENSIONS.has(ext)) {
          const bytes = await fs.readFile(filePath);
          size = bytes.byteLength;
          const label = ext.replace('.', '').toUpperCase();
          content = `[${label} Document: ${name}] — ${uploadFormatSize(size)}`;
        } else {
          content = await fs.readTextFile(filePath);
          size = new TextEncoder().encode(content).byteLength;
        }
        uploadFiles = [...uploadFiles, {
          id: crypto.randomUUID(),
          name,
          content,
          format: getUploadFormat(name),
          size,
        }];
      } catch (err) {
        console.error(`[Upload] Failed to read dropped file "${filePath}":`, err);
      }
    }
  }

  function removeUploadFile(fileId: string): void {
    uploadFiles = uploadFiles.filter((f) => f.id !== fileId);
  }

  async function handleUploadSubmit(): Promise<void> {
    if (uploadFiles.length === 0 || project === undefined) return;
    uploading = true;
    uploadError = null;
    let successCount = 0;
    try {
      for (const file of uploadFiles) {
        await documentsStore.createDocument({
          title: file.name,
          path: `docs/${file.name}`,
          content: file.content,
          format: file.format,
          project_id: project.id,
          output_path: project.output_path,
          disk_subdir: 'docs',
        });
        successCount++;
      }
      showUploadDialog = false;
      uploadFiles = [];
    } catch (err) {
      uploadError = `Uploaded ${successCount}/${uploadFiles.length} files. Error: ${(err as Error).message}`;
    } finally {
      uploading = false;
    }
  }

  function cancelUpload(): void {
    showUploadDialog = false;
    uploadFiles = [];
    uploadError = null;
  }

  let unlistenUploadDrag: (() => void) | undefined;
  onMount(() => {
    if (!isTauri()) return;
    (async () => {
      const { getCurrentWebview } = await import('@tauri-apps/api/webview');
      unlistenUploadDrag = await getCurrentWebview().onDragDropEvent((event) => {
        if (!showUploadDialog) return;
        const { type } = event.payload;
        if (type === 'enter' || type === 'over') { uploadDragOver = true; }
        else if (type === 'leave' || type === 'cancel') { uploadDragOver = false; }
        else if (type === 'drop') {
          uploadDragOver = false;
          const payload = event.payload as { type: 'drop'; paths: string[] };
          void handleUploadTauriPaths(payload.paths);
        }
      });
    })();
  });
  onDestroy(() => { unlistenUploadDrag?.(); });

  // ── Delivery gate state ──────────────────────────────────────────────────────
  let deliveryReadiness = $state<DeliveryReadiness | null>(null);
  let deliveryLastReport = $state<DeliveryReport | null>(null);
  let deliveryRunning = $state(false);
  let deliveryError = $state<string | null>(null);

  // Editable delivery checks (local form state)
  let deliveryChecks = $state<DeliveryCheck[]>([]);
  let deliveryCwd = $state('code');

  $effect(() => {
    if (project !== null && activeTab === 'delivery') {
      void fetchDeliveryStatus();
      const existingConfig = project.config?.delivery;
      if (existingConfig !== undefined) {
        deliveryChecks = existingConfig.checks?.map(c => ({ ...c })) ?? [];
        deliveryCwd = existingConfig.cwd ?? 'code';
      } else if (deliveryChecks.length === 0) {
        deliveryChecks = [];
        deliveryCwd = 'code';
      }
    }
  });

  async function fetchDeliveryStatus() {
    if (!id) return;
    try {
      const data = await projectsApi.deliveryStatus(id);
      deliveryReadiness = data.readiness;
      deliveryLastReport = data.last_report ?? null;
    } catch {
      deliveryReadiness = null;
      deliveryLastReport = null;
    }
  }

  async function runDeliveryGate() {
    if (!id || !project) return;
    deliveryRunning = true;
    deliveryError = null;
    try {
      await saveDeliveryConfig();
      const result = await projectsApi.deliver(id);
      deliveryLastReport = result.report;
      await fetchDeliveryStatus();
      if (result.report.overall_pass) {
        await projectsStore.fetchProject(id);
      }
    } catch (err) {
      deliveryError = (err as Error).message;
    } finally {
      deliveryRunning = false;
    }
  }

  async function saveDeliveryConfig() {
    if (!project) return;
    const config = { ...(project.config ?? {}), delivery: { cwd: deliveryCwd, require_all_tasks_done: true, checks: deliveryChecks } };
    await projectsStore.updateProject(project.id, { config } as Partial<Project>);
  }

  function addDeliveryCheck() {
    deliveryChecks = [...deliveryChecks, { name: '', command: '', timeout_ms: 120000, required: true }];
  }

  function removeDeliveryCheck(index: number) {
    deliveryChecks = deliveryChecks.filter((_, i) => i !== index);
  }

  function prefillHelloWorld() {
    deliveryCwd = 'code';
    deliveryChecks = [
      { name: 'install', command: 'npm install', timeout_ms: 120000, required: true },
      { name: 'build', command: 'npm run build', timeout_ms: 120000, required: true },
    ];
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
            {#if tab.id === 'tasks' && openTaskCount > 0}
              <span class="pj-tab-badge" aria-label="{openTaskCount} open tasks">
                {openTaskCount}
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
              <span class="pj-kpi-value">{project.phase_count}</span>
              <span class="pj-kpi-label">Phases</span>
            </div>
            <div class="pj-kpi" role="listitem">
              <span class="pj-kpi-value">{openTaskCount}</span>
              <span class="pj-kpi-label">Open Tasks</span>
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

          <!-- Doc-driven onboarding CTA -->
          {#if projectDocsCount === 0}
            <div class="pj-cta-card">
              <div class="pj-cta-icon" aria-hidden="true">
                <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.25">
                  <path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8zM14 2v6h6M16 13H8M16 17H8M10 9H8" />
                </svg>
              </div>
              <h3 class="pj-cta-title">Get started with documentation</h3>
              <p class="pj-cta-desc">Add project documentation to unlock AI-powered phase and task generation.</p>
              <button
                class="pj-btn-primary pj-cta-btn"
                type="button"
                onclick={() => setTab('docs')}
                aria-label="Navigate to Docs tab to create a document"
              >
                Create a Document
              </button>
            </div>
          {:else if phasesTotal === 0 && projectTasks.length === 0}
            <div class="pj-cta-card">
              <div class="pj-cta-icon" aria-hidden="true">
                <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.25">
                  <path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5" />
                </svg>
              </div>
              <h3 class="pj-cta-title">Ready to plan your project</h3>
              <p class="pj-cta-desc">You have {projectDocsCount} document{projectDocsCount === 1 ? '' : 's'}. Use AI to generate implementation phases and tasks.</p>
              <button
                class="pj-btn-accent pj-cta-btn"
                type="button"
                onclick={() => { showGenerateTasksModal = true; }}
                aria-label="Decompose documents into phases and tasks"
                title="Analyze your project documents and break them down into implementation phases and individual tasks"
              >
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                  <path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5" />
                </svg>
                Decompose Docs into Phases &amp; Tasks
              </button>
            </div>
          {/if}

          <!-- Phases progress -->
          {#if phasesTotal > 0}
            <div class="pj-card">
              <div class="pj-card-header">
                <h2 class="pj-card-title">Phases Progress</h2>
                <span class="pj-card-meta">{phasesCompleted} / {phasesTotal} completed</span>
              </div>
              <div class="pj-progress-track" role="progressbar" aria-valuenow={phasesProgress} aria-valuemin={0} aria-valuemax={100} aria-label="Phases completion progress">
                <div class="pj-progress-fill" style="width: {phasesProgress}%"></div>
              </div>
              <p class="pj-progress-label">{phasesProgress}% complete</p>
            </div>
          {/if}

          <!-- Recent activity -->
          <div class="pj-card">
            <div class="pj-card-header">
              <h2 class="pj-card-title">Recent Activity</h2>
            </div>
            {#if recentActivity.length === 0}
              <p class="pj-empty-hint">No recent activity. Create a phase or task to get started.</p>
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

        <!-- ── Phases ─────────────────────────────────────────────────────────── -->
        {:else if activeTab === 'phases'}
          <div class="pj-tab-toolbar">
            <h2 class="pj-tab-heading">Phases</h2>
            <button
              class="pj-btn-primary"
              type="button"
              onclick={() => void goto(`/app/phases?new=1&project=${id}`)}
              aria-label="Create phase in this project"
            >
              + Create Phase
            </button>
          </div>

          {#if phasesStore.loading}
            <div class="pj-loading" role="status" aria-live="polite">
              <div class="pj-spinner" aria-hidden="true"></div>
              <span>Loading phases…</span>
            </div>
          {:else if phasesStore.phases.length === 0}
            <div class="pj-empty-tab">
              <p class="pj-empty-hint">No phases yet for this project.</p>
            </div>
          {:else}
            <PhaseHierarchy nodes={phasesStore.phases} />
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
                  onclick={() => { showGenerateTasksModal = true; }}
                  aria-label="Analyze documents and decompose into phases and tasks"
                  title="Analyze your project documents and break them down into implementation phases and individual tasks"
                >
                  <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                    <path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5" />
                  </svg>
                  Decompose Docs
                </button>
              {/if}
              <button
                class="pj-btn-ghost"
                type="button"
                onclick={() => { showGenerateDocModal = true; }}
                aria-label="Generate a project document using AI"
                title="Create a new document (PRD, technical spec, architecture, etc.) generated by AI from your project description"
              >
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                  <path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z" /><path d="M14 2v6h6" /><path d="M12 18v-6M9 15l3-3 3 3" />
                </svg>
                Generate Document
              </button>
              <button
                class="pj-btn-ghost"
                type="button"
                onclick={() => { showUploadDialog = true; }}
                aria-label="Upload document files"
              >
                Upload Files
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
                  title="Create a new document (PRD, technical spec, architecture, etc.) generated by AI from your project description"
                >
                  Generate Document
                </button>
                <button
                  class="pj-btn-ghost"
                  type="button"
                  onclick={() => { showUploadDialog = true; }}
                >
                  Upload Files
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
                    aria-current={selectedDoc?.id === doc.id ? 'true' : undefined}
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

        <!-- ── Tasks ──────────────────────────────────────────────────────────── -->
        {:else if activeTab === 'tasks'}
          <div class="pj-tab-toolbar">
            <h2 class="pj-tab-heading">
              Tasks
              {#if openTaskCount > 0}
                <span class="pj-count-badge">{openTaskCount} open</span>
              {/if}
            </h2>
            <div class="pj-tab-toolbar-actions">
              <button
                class="pj-btn-accent"
                type="button"
                onclick={() => { showPipelineModal = true; }}
                aria-label="Run automated task generation pipeline"
                title="Run the full automated pipeline: detect codebase, select stack, and generate tasks with AI"
              >
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                  <path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5" />
                </svg>
                Auto-Generate Tasks
              </button>
              {#if projectDocsCount > 0}
                <button
                  class="pj-btn-ghost"
                  type="button"
                  onclick={() => { showGenerateTasksModal = true; }}
                  aria-label="Decompose documents into phases and tasks"
                  title="Analyze your uploaded documents and decompose them into implementation phases and tasks"
                >
                  Decompose Docs
                </button>
              {/if}
              <button
                class="pj-btn-primary"
                type="button"
                onclick={() => void goto(`/app/tasks?new=1&project=${id}`)}
                aria-label="Create task in this project"
              >
                + Create Task
              </button>
            </div>
          </div>

          {#if tasksStore.loading}
            <div class="pj-loading" role="status" aria-live="polite">
              <div class="pj-spinner" aria-hidden="true"></div>
              <span>Loading tasks…</span>
            </div>
          {:else if projectTasks.length === 0}
            <div class="pj-empty-tab">
              <p class="pj-empty-hint">No tasks for this project.</p>
            </div>
          {:else}
            <TaskList tasks={projectTasks} />
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

        <!-- ── Delivery ────────────────────────────────────────────────────────── -->
        {:else if activeTab === 'delivery'}
          <div class="pj-tab-toolbar">
            <h2 class="pj-tab-heading">Delivery Gate</h2>
            <div class="pj-tab-toolbar-actions">
              <button
                class="pj-btn-ghost"
                type="button"
                onclick={prefillHelloWorld}
                aria-label="Prefill with Node.js project checks"
              >
                Node.js Preset
              </button>
              <button
                class="pj-btn-primary"
                type="button"
                onclick={runDeliveryGate}
                disabled={deliveryRunning || deliveryChecks.length === 0}
                aria-label="Run delivery gate checks"
              >
                {deliveryRunning ? 'Running…' : 'Run Delivery Gate'}
              </button>
            </div>
          </div>

          {#if deliveryError}
            <div class="pj-delivery-error" role="alert">{deliveryError}</div>
          {/if}

          <!-- Readiness -->
          {#if deliveryReadiness}
            <div class="pj-card">
              <div class="pj-card-header">
                <h2 class="pj-card-title">Readiness</h2>
                <span class="pj-delivery-badge" class:pj-delivery-badge--pass={deliveryReadiness.ready} class:pj-delivery-badge--fail={!deliveryReadiness.ready}>
                  {deliveryReadiness.ready ? 'Ready' : 'Not Ready'}
                </span>
              </div>
              {#if deliveryReadiness.reasons.length > 0}
                <ul class="pj-delivery-reasons">
                  {#each deliveryReadiness.reasons as reason}
                    <li>{reason}</li>
                  {/each}
                </ul>
              {/if}
            </div>
          {/if}

          <!-- Check configuration -->
          <div class="pj-card">
            <div class="pj-card-header">
              <h2 class="pj-card-title">Delivery Checks</h2>
            </div>

            <div class="pj-field" style="margin-bottom: 12px;">
              <label class="pj-field-label" for="delivery-cwd">Working directory (relative to output_path)</label>
              <input
                id="delivery-cwd"
                class="pj-field-input"
                type="text"
                placeholder="code"
                bind:value={deliveryCwd}
              />
            </div>

            {#if deliveryChecks.length === 0}
              <p class="pj-empty-hint">No checks configured. Add a check or use a preset.</p>
            {:else}
              <div class="pj-delivery-checks">
                {#each deliveryChecks as check, i (i)}
                  <div class="pj-delivery-check-row">
                    <input
                      class="pj-field-input pj-delivery-check-name"
                      type="text"
                      placeholder="Check name"
                      bind:value={check.name}
                    />
                    <input
                      class="pj-field-input pj-delivery-check-cmd"
                      type="text"
                      placeholder="Command (e.g. npm run build)"
                      bind:value={check.command}
                    />
                    <label class="pj-delivery-check-req">
                      <input type="checkbox" bind:checked={check.required} />
                      Req
                    </label>
                    <button
                      class="pj-delivery-check-remove"
                      type="button"
                      onclick={() => removeDeliveryCheck(i)}
                      aria-label="Remove check"
                    >
                      ×
                    </button>
                  </div>
                {/each}
              </div>
            {/if}

            <button
              class="pj-btn-ghost"
              type="button"
              style="margin-top: 8px;"
              onclick={addDeliveryCheck}
            >
              + Add Check
            </button>

            <div style="margin-top: 12px; display: flex; justify-content: flex-end;">
              <button
                class="pj-btn-ghost"
                type="button"
                onclick={saveDeliveryConfig}
              >
                Save Config
              </button>
            </div>
          </div>

          <!-- Last report -->
          {#if deliveryLastReport}
            <div class="pj-card">
              <div class="pj-card-header">
                <h2 class="pj-card-title">Last Delivery Report</h2>
                <span class="pj-delivery-badge" class:pj-delivery-badge--pass={deliveryLastReport.overall_pass} class:pj-delivery-badge--fail={!deliveryLastReport.overall_pass}>
                  {deliveryLastReport.overall_pass ? 'PASS' : 'FAIL'}
                </span>
              </div>
              <p class="pj-delivery-timestamp">
                Run at {new Date(deliveryLastReport.timestamp).toLocaleString()}
                {#if !deliveryLastReport.all_tasks_done}
                  — <span class="pj-delivery-warn">Not all tasks are done</span>
                {/if}
              </p>
              {#if deliveryLastReport.checks.length > 0}
                <table class="pj-session-table" aria-label="Delivery check results">
                  <thead>
                    <tr>
                      <th class="pj-th">Check</th>
                      <th class="pj-th">Command</th>
                      <th class="pj-th">Result</th>
                      <th class="pj-th pj-th--num">Exit</th>
                      <th class="pj-th pj-th--num">Time</th>
                    </tr>
                  </thead>
                  <tbody>
                    {#each deliveryLastReport.checks as cr (cr.name)}
                      <tr class="pj-cost-row">
                        <td class="pj-td">{cr.name}{cr.required ? '' : ' (optional)'}</td>
                        <td class="pj-td pj-meta-mono" style="max-width:200px;overflow:hidden;text-overflow:ellipsis;">{cr.command}</td>
                        <td class="pj-td">
                          <span class="pj-delivery-badge" class:pj-delivery-badge--pass={cr.pass} class:pj-delivery-badge--fail={!cr.pass}>
                            {cr.pass ? 'PASS' : 'FAIL'}
                          </span>
                        </td>
                        <td class="pj-td pj-td--num">{cr.exit_code}</td>
                        <td class="pj-td pj-td--num">{(cr.elapsed_ms / 1000).toFixed(1)}s</td>
                      </tr>
                    {/each}
                  </tbody>
                </table>
              {/if}
            </div>
          {/if}

        {/if}

      </div><!-- /pj-tab-content -->
    </div><!-- /pj-page -->
  {/if}
</PageShell>

<!-- Create document dialog -->
{#if showDocForm}
  <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
  <div
    class="pj-overlay"
    role="dialog"
    aria-modal="true"
    aria-label="Create document"
    tabindex="-1"
    onclick={(e) => { if (e.target === e.currentTarget) cancelDocForm(); }}
    onkeydown={(e) => { if (e.key === 'Escape') cancelDocForm(); }}
  >
    <div class="pj-dialog">
      <h2 class="pj-dialog-title">New Document</h2>
      <div class="pj-field">
        <label class="pj-field-label" for="pj-doc-path">Path</label>
        <!-- svelte-ignore a11y_autofocus -->
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

<!-- Upload files dialog -->
{#if showUploadDialog}
  <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
  <div
    class="pj-overlay"
    role="dialog"
    aria-modal="true"
    aria-label="Upload documents"
    tabindex="-1"
    onclick={(e) => { if (e.target === e.currentTarget) cancelUpload(); }}
    onkeydown={(e) => { if (e.key === 'Escape') cancelUpload(); }}
  >
    <div class="pj-dialog pj-dialog--wide">
      <h2 class="pj-dialog-title">Upload Documents</h2>
      <p class="pj-dialog-subtitle">
        Drag and drop files or use the browse button. Supported formats: .md, .txt, .json, .yaml, .yml, .csv, .sql, .pdf, .doc, .docx, .xls, .xlsx
      </p>

      <div
        class="pj-upload-zone"
        class:pj-upload-zone--active={uploadDragOver}
        role="region"
        aria-label="File drop zone"
        ondragover={(e) => { e.preventDefault(); uploadDragOver = true; }}
        ondragleave={() => { uploadDragOver = false; }}
        ondrop={(e) => {
          e.preventDefault();
          uploadDragOver = false;
          void handleUploadFileInput(e.dataTransfer?.files ?? null);
        }}
      >
        <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true">
          <path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M17 8l-5-5-5 5M12 3v12" />
        </svg>
        <span class="pj-upload-hint">
          {uploadDragOver ? 'Drop files here…' : 'Drag files here or'}
        </span>
        {#if !uploadDragOver}
          <label class="pj-upload-browse">
            browse
            <input
              type="file"
              accept={UPLOAD_ACCEPT_STRING}
              multiple
              hidden
              onchange={(e) => { void handleUploadFileInput((e.target as HTMLInputElement).files); (e.target as HTMLInputElement).value = ''; }}
            />
          </label>
        {/if}
      </div>

      {#if uploadFiles.length > 0}
        <div class="pj-upload-list" role="list" aria-label="Files to upload">
          {#each uploadFiles as file (file.id)}
            <div class="pj-upload-item" role="listitem">
              <div class="pj-upload-item-info">
                <span class="pj-upload-item-name">{file.name}</span>
                <span class="pj-upload-item-meta">{file.format} · {uploadFormatSize(file.size)}</span>
              </div>
              <button
                class="pj-upload-item-remove"
                type="button"
                onclick={() => removeUploadFile(file.id)}
                aria-label="Remove {file.name}"
              >
                ×
              </button>
            </div>
          {/each}
        </div>
      {/if}

      {#if uploadError}
        <div class="pj-upload-error" role="alert">{uploadError}</div>
      {/if}

      <div class="pj-dialog-footer">
        <button class="pj-btn-ghost" onclick={cancelUpload} disabled={uploading}>Cancel</button>
        <button
          class="pj-btn-primary"
          onclick={handleUploadSubmit}
          disabled={uploading || uploadFiles.length === 0}
        >
          {#if uploading}
            Uploading…
          {:else}
            Upload {uploadFiles.length} {uploadFiles.length === 1 ? 'File' : 'Files'}
          {/if}
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

<!-- Generate phases & tasks from docs modal -->
{#if showGenerateTasksModal && project}
  <GeneratePhasesTasksModal
    projectId={project.id}
    projectName={project.name}
    outputPath={project.output_path}
    documents={projectDocs}
    onClose={() => { showGenerateTasksModal = false; }}
    onCreated={() => { showGenerateTasksModal = false; }}
  />
{/if}

<!-- Automated task pipeline modal -->
{#if showPipelineModal && project}
  <AutomatedTaskPipeline
    projectId={project.id}
    projectName={project.name}
    outputPath={project.output_path ?? null}
    workspaceId={workspaceStore.activeWorkspaceId ?? ''}
    documents={projectDocs}
    onClose={() => { showPipelineModal = false; }}
    onCreated={() => { showPipelineModal = false; void tasksStore.fetchTasks(workspaceStore.activeWorkspaceId ?? undefined); }}
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
    height: 100%;
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
    display: inline-flex;
    align-items: center;
    gap: 4px;
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
    white-space: nowrap;
    transition: all 120ms ease;
  }

  .pj-btn-ghost:hover {
    background: var(--bg-elevated);
    color: var(--text-primary);
  }

  .pj-btn-accent {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    height: 30px;
    padding: 0 12px;
    border-radius: var(--radius-sm, 6px);
    border: 1px solid rgba(99, 102, 241, 0.35);
    background: rgba(99, 102, 241, 0.1);
    color: #a5b4fc;
    font-size: 12px;
    font-weight: 500;
    font-family: var(--font-sans);
    cursor: pointer;
    white-space: nowrap;
    transition: all 120ms ease;
  }

  .pj-btn-accent:hover {
    background: rgba(99, 102, 241, 0.18);
    border-color: rgba(99, 102, 241, 0.5);
  }

  .pj-btn-primary {
    display: inline-flex;
    align-items: center;
    gap: 4px;
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
    white-space: nowrap;
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
    flex: 1;
    min-height: 0;
    overflow-y: auto;
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

  .pj-activity-kind--task { background: rgba(239, 68, 68, 0.1); color: #fca5a5; }
  .pj-activity-kind--phase  { background: rgba(249, 115, 22, 0.1); color: #fdba74; }

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
    flex: 1;
    min-height: 250px;
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

  /* ── Upload dialog ──────────────────────────────────────────────────────── */
  .pj-dialog--wide {
    width: 560px;
  }

  .pj-dialog-subtitle {
    font-size: 12px;
    color: var(--text-tertiary);
    margin: -8px 0 0 0;
    line-height: 1.5;
  }

  .pj-upload-zone {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 8px;
    padding: 32px 16px;
    border: 2px dashed var(--border-default);
    border-radius: 10px;
    background: var(--bg-elevated);
    color: var(--text-tertiary);
    transition: border-color 0.15s, background 0.15s;
    cursor: pointer;
  }
  .pj-upload-zone--active {
    border-color: #f97316;
    background: rgba(249, 115, 22, 0.06);
    color: #f97316;
  }

  .pj-upload-hint {
    font-size: 13px;
  }

  .pj-upload-browse {
    font-size: 13px;
    font-weight: 500;
    color: #f97316;
    cursor: pointer;
    text-decoration: underline;
    text-underline-offset: 2px;
  }

  .pj-upload-list {
    display: flex;
    flex-direction: column;
    gap: 4px;
    max-height: 200px;
    overflow-y: auto;
  }

  .pj-upload-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    padding: 8px 10px;
    border-radius: 6px;
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
  }

  .pj-upload-item-info {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }

  .pj-upload-item-name {
    font-size: 13px;
    font-weight: 500;
    color: var(--text-primary);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .pj-upload-item-meta {
    font-size: 11px;
    color: var(--text-tertiary);
  }

  .pj-upload-item-remove {
    flex-shrink: 0;
    width: 24px;
    height: 24px;
    display: flex;
    align-items: center;
    justify-content: center;
    border: none;
    background: transparent;
    color: var(--text-tertiary);
    font-size: 16px;
    border-radius: 4px;
    cursor: pointer;
  }
  .pj-upload-item-remove:hover {
    background: rgba(239, 68, 68, 0.1);
    color: #ef4444;
  }

  /* ── CTA card (overview onboarding) ────────────────────────────────────── */
  .pj-cta-card {
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: center;
    gap: 10px;
    padding: 32px 24px;
    background: var(--bg-surface);
    border: 1px dashed var(--border-hover);
    border-radius: var(--radius-md, 8px);
    backdrop-filter: blur(8px);
    -webkit-backdrop-filter: blur(8px);
  }

  .pj-cta-icon {
    color: var(--text-muted);
    opacity: 0.5;
  }

  .pj-cta-title {
    font-size: 15px;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0;
  }

  .pj-cta-desc {
    font-size: 13px;
    color: var(--text-tertiary);
    margin: 0;
    max-width: 400px;
    line-height: 1.5;
  }

  .pj-cta-btn {
    margin-top: 6px;
    height: 34px;
    padding: 0 16px;
    font-size: 13px;
    display: inline-flex;
    align-items: center;
  }

  .pj-upload-error {
    font-size: 12px;
    color: #ef4444;
    background: rgba(239, 68, 68, 0.08);
    border: 1px solid rgba(239, 68, 68, 0.2);
    border-radius: 6px;
    padding: 8px 12px;
  }

  /* ── Delivery tab ─────────────────────────────────────────────────────── */
  .pj-delivery-error {
    font-size: 12px;
    color: #ef4444;
    background: rgba(239, 68, 68, 0.08);
    border: 1px solid rgba(239, 68, 68, 0.2);
    border-radius: 6px;
    padding: 8px 12px;
  }

  .pj-delivery-badge {
    display: inline-flex;
    align-items: center;
    height: 20px;
    padding: 0 8px;
    border-radius: 10px;
    font-size: 10px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.3px;
  }

  .pj-delivery-badge--pass {
    background: rgba(34, 197, 94, 0.1);
    border: 1px solid rgba(34, 197, 94, 0.25);
    color: #86efac;
  }

  .pj-delivery-badge--fail {
    background: rgba(239, 68, 68, 0.1);
    border: 1px solid rgba(239, 68, 68, 0.25);
    color: #fca5a5;
  }

  .pj-delivery-reasons {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 4px;
    font-size: 12px;
    color: var(--text-tertiary);
  }

  .pj-delivery-reasons li::before {
    content: '• ';
    color: var(--text-muted);
  }

  .pj-delivery-checks {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .pj-delivery-check-row {
    display: flex;
    align-items: center;
    gap: 6px;
  }

  .pj-delivery-check-name {
    width: 120px;
    flex-shrink: 0;
  }

  .pj-delivery-check-cmd {
    flex: 1;
  }

  .pj-delivery-check-req {
    display: flex;
    align-items: center;
    gap: 4px;
    font-size: 11px;
    color: var(--text-tertiary);
    white-space: nowrap;
    cursor: pointer;
  }

  .pj-delivery-check-remove {
    width: 24px;
    height: 24px;
    display: flex;
    align-items: center;
    justify-content: center;
    border: none;
    background: transparent;
    color: var(--text-tertiary);
    font-size: 16px;
    border-radius: 4px;
    cursor: pointer;
    flex-shrink: 0;
  }

  .pj-delivery-check-remove:hover {
    background: rgba(239, 68, 68, 0.1);
    color: #ef4444;
  }

  .pj-delivery-timestamp {
    font-size: 11px;
    color: var(--text-muted);
    margin: 0 0 10px;
  }

  .pj-delivery-warn {
    color: #f59e0b;
    font-weight: 500;
  }
</style>
