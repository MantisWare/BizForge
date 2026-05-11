<!-- src/routes/app/projects/+page.svelte -->
<script lang="ts">
  import { onMount } from 'svelte';
  import { fly } from 'svelte/transition';
  import { goto } from '$app/navigation';
  import PageShell from '$lib/components/layout/PageShell.svelte';
  import { projectsStore } from '$lib/stores/projects.svelte';
  import { workspaceStore } from '$lib/stores/workspace.svelte';
  import { documents as documentsApi } from '$api/client';
  import { isTauri } from '$lib/utils/platform';
  import type { ProjectStatus, DocumentFormat } from '$api/types';

  $effect(() => {
    const wsId = workspaceStore.activeWorkspaceId ?? undefined;
    void projectsStore.fetchProjects(wsId);
  });

  const STATUS_FILTERS: { value: ProjectStatus | 'all'; label: string }[] = [
    { value: 'all', label: 'All' },
    { value: 'active', label: 'Active' },
    { value: 'completed', label: 'Completed' },
    { value: 'archived', label: 'Archived' },
  ];

  // ── Wizard state ────────────────────────────────────────────────────────────
  type WizardStep = 1 | 2 | 3;
  const STEP_COUNT = 3;
  const STEP_TITLES: Record<WizardStep, string> = { 1: 'Project Details', 2: 'Project Directory', 3: 'Documentation' };
  const STEP_SUBTITLES: Record<WizardStep, string> = {
    1: 'Give your project a name and description.',
    2: 'Choose an existing directory with source code or create a new one.',
    3: 'Upload any additional documentation or context for this project.',
  };

  let showForm = $state(false);
  let wizStep = $state<WizardStep>(1);
  let wizDirection = $state<'forward' | 'back'>('forward');

  // Step 1
  let formName = $state('');
  let formDescription = $state('');
  let formStatus = $state<ProjectStatus>('active');

  // Step 2
  let formOutputPath = $state('');
  let dirExists = $state<boolean | null>(null);

  // Step 3
  interface UploadedFile { id: string; name: string; content: string; format: DocumentFormat; size: number; }
  let uploadedFiles = $state<UploadedFile[]>([]);
  let dragOver = $state(false);
  let contextText = $state('');

  let creating = $state(false);
  let createError = $state<string | null>(null);

  const ACCEPTED_EXTENSIONS: Record<string, DocumentFormat> = {
    '.md': 'markdown', '.txt': 'markdown', '.json': 'json', '.yaml': 'yaml',
    '.yml': 'yaml', '.csv': 'markdown', '.dbml': 'markdown', '.sql': 'markdown',
    '.pdf': 'markdown', '.doc': 'markdown', '.docx': 'markdown',
    '.xls': 'markdown', '.xlsx': 'markdown',
  };
  const BINARY_EXTENSIONS = new Set(['.pdf', '.doc', '.docx', '.xls', '.xlsx']);
  const ACCEPT_STRING = Object.keys(ACCEPTED_EXTENSIONS).join(',');

  function getExt(name: string): string { return name.slice(name.lastIndexOf('.')).toLowerCase(); }
  function getFormat(name: string): DocumentFormat { return ACCEPTED_EXTENSIONS[getExt(name)] ?? 'markdown'; }
  function isAccepted(name: string): boolean { return getExt(name) in ACCEPTED_EXTENSIONS; }

  function formatSize(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }

  // Validation per step
  const canProceed = $derived.by((): boolean => {
    if (wizStep === 1) return formName.trim().length > 0;
    return true;
  });

  // ── Navigation ──────────────────────────────────────────────────────────────
  function goNext(): void {
    if (wizStep < STEP_COUNT) {
      wizDirection = 'forward';
      wizStep = (wizStep + 1) as WizardStep;
    }
  }
  function goBack(): void {
    if (wizStep > 1) {
      wizDirection = 'back';
      wizStep = (wizStep - 1) as WizardStep;
    }
  }
  function goToStep(step: WizardStep): void {
    if (step < wizStep) {
      wizDirection = 'back';
      wizStep = step;
    }
  }

  // ── Directory picker ────────────────────────────────────────────────────────
  async function pickOutputDirectory(): Promise<void> {
    if (!isTauri()) return;
    try {
      const { open } = await import('@tauri-apps/plugin-dialog');
      const selected = await open({ directory: true, multiple: false, title: 'Choose Project Directory' });
      if (selected !== null && typeof selected === 'string') {
        formOutputPath = selected;
        await checkDirExists(selected);
      }
    } catch { /* dialog cancelled */ }
  }

  async function checkDirExists(path: string): Promise<void> {
    if (!path.trim() || !isTauri()) { dirExists = null; return; }
    try {
      const fs = await import('@tauri-apps/plugin-fs');
      dirExists = await fs.exists(path.trim());
    } catch { dirExists = null; }
  }

  // ── File upload ─────────────────────────────────────────────────────────────
  async function handleFileInput(files: FileList | null): Promise<void> {
    if (files === null) return;
    for (const file of Array.from(files)) {
      if (!isAccepted(file.name)) continue;
      const ext = getExt(file.name);
      let content: string;
      if (BINARY_EXTENSIONS.has(ext)) {
        const label = ext.replace('.', '').toUpperCase();
        content = `[${label} Document: ${file.name}] — ${formatSize(file.size)}`;
      } else {
        content = await file.text();
      }
      uploadedFiles = [...uploadedFiles, {
        id: crypto.randomUUID(),
        name: file.name,
        content,
        format: getFormat(file.name),
        size: file.size,
      }];
    }
  }

  async function handleTauriDroppedPaths(paths: string[]): Promise<void> {
    const fs = await import('@tauri-apps/plugin-fs');
    for (const filePath of paths) {
      const name = filePath.split('/').pop() ?? filePath;
      if (!isAccepted(name)) continue;
      const ext = getExt(name);
      try {
        let content: string;
        let size: number;
        if (BINARY_EXTENSIONS.has(ext)) {
          const bytes = await fs.readFile(filePath);
          size = bytes.byteLength;
          const label = ext.replace('.', '').toUpperCase();
          content = `[${label} Document: ${name}] — ${formatSize(size)}`;
        } else {
          content = await fs.readTextFile(filePath);
          size = new TextEncoder().encode(content).byteLength;
        }
        uploadedFiles = [...uploadedFiles, {
          id: crypto.randomUUID(),
          name,
          content,
          format: getFormat(name),
          size,
        }];
      } catch (err) {
        console.error(`[Project] Failed to read dropped file "${filePath}":`, err);
      }
    }
  }

  function removeFile(id: string): void {
    uploadedFiles = uploadedFiles.filter((f) => f.id !== id);
  }

  onMount(() => {
    if (!isTauri()) return;
    let unlisten: (() => void) | undefined;
    (async () => {
      const { getCurrentWebview } = await import('@tauri-apps/api/webview');
      unlisten = await getCurrentWebview().onDragDropEvent((event) => {
        if (!showForm || wizStep !== 3) return;
        const { type } = event.payload;
        if (type === 'enter' || type === 'over') { dragOver = true; }
        else if (type === 'leave' || type === 'cancel') { dragOver = false; }
        else if (type === 'drop') {
          dragOver = false;
          const payload = event.payload as { type: 'drop'; paths: string[] };
          void handleTauriDroppedPaths(payload.paths);
        }
      });
    })();
    return () => { unlisten?.(); };
  });

  // ── Create ──────────────────────────────────────────────────────────────────
  async function handleCreate(): Promise<void> {
    if (!formName.trim()) return;
    creating = true;
    createError = null;
    try {
      const created = await projectsStore.createProject({
        name: formName.trim(),
        description: formDescription.trim() || null,
        status: formStatus,
        output_path: formOutputPath.trim() || null,
        workspace_id: workspaceStore.activeWorkspaceId ?? undefined,
      });
      if (created === null) {
        createError = projectsStore.error ?? 'Failed to create project. Please try again.';
        return;
      }
      for (const file of uploadedFiles) {
        try {
          await documentsApi.create({
            title: file.name.replace(/\.[^.]+$/, ''),
            path: `projects/${created.id}/${file.name}`,
            content: file.content,
            format: file.format,
            project_id: created.id,
          });
        } catch (docErr) {
          console.warn('[Project] Failed to attach document:', file.name, docErr);
        }
      }
      if (contextText.trim()) {
        try {
          await documentsApi.create({
            title: 'Project Context',
            path: `projects/${created.id}/context.md`,
            content: contextText.trim(),
            format: 'markdown',
            project_id: created.id,
          });
        } catch { /* best-effort */ }
      }
      resetForm();
    } catch (err) {
      createError = (err as Error).message ?? 'An unexpected error occurred.';
    } finally {
      creating = false;
    }
  }

  function resetForm(): void {
    showForm = false;
    wizStep = 1;
    wizDirection = 'forward';
    formName = '';
    formDescription = '';
    formOutputPath = '';
    formStatus = 'active';
    dirExists = null;
    uploadedFiles = [];
    contextText = '';
    dragOver = false;
    createError = null;
  }

  function handleKeyDown(e: KeyboardEvent): void {
    if (e.key === 'Escape') { e.preventDefault(); resetForm(); }
  }
</script>

<PageShell
  title="Projects"
  subtitle="{projectsStore.activeCount} active"
  badge={projectsStore.totalCount > 0 ? projectsStore.totalCount : undefined}
>
  {#snippet actions()}
    <div class="proj-filter-group" role="group" aria-label="Filter by status">
      {#each STATUS_FILTERS as opt (opt.value)}
        <button
          class="proj-filter-btn"
          class:proj-filter-btn--active={projectsStore.filterStatus === opt.value}
          onclick={() => projectsStore.filterStatus = opt.value}
          aria-pressed={projectsStore.filterStatus === opt.value}
        >
          {opt.label}
        </button>
      {/each}
    </div>
    <input
      class="proj-search"
      type="search"
      placeholder="Search projects…"
      value={projectsStore.searchQuery}
      oninput={(e) => projectsStore.searchQuery = (e.target as HTMLInputElement).value}
      aria-label="Search projects"
    />
    <button
      class="proj-btn"
      onclick={() => showForm = true}
      type="button"
      aria-label="New project"
    >
      + New Project
    </button>
  {/snippet}

  {#if projectsStore.loading && projectsStore.projects.length === 0}
    <div class="proj-loading" role="status" aria-live="polite">
      <div class="proj-spinner" aria-hidden="true"></div>
      <span>Loading projects…</span>
    </div>
  {:else if projectsStore.error && projectsStore.projects.length === 0}
    <div class="proj-error" role="alert">
      <p>Failed to load projects: {projectsStore.error}</p>
      <button onclick={() => void projectsStore.fetchProjects(workspaceStore.activeWorkspaceId ?? undefined)}>Retry</button>
    </div>
  {:else if projectsStore.filteredProjects.length === 0}
    <div class="proj-empty" role="status">
      <p>No projects yet. Create your first project to get started.</p>
    </div>
  {:else}
    <div class="proj-grid" role="list" aria-label="Projects">
      {#each projectsStore.filteredProjects as project (project.id)}
        <div
          class="proj-card"
          class:proj-card--selected={projectsStore.selected?.id === project.id}
          role="listitem"
        >
          <button
            class="proj-card-btn"
            onclick={() => { projectsStore.selectProject(project); goto(`/app/projects/${project.id}`); }}
            aria-pressed={projectsStore.selected?.id === project.id}
            aria-label="Select project {project.name}"
          >
            <div class="proj-header">
              <span class="proj-name">{project.name}</span>
              <span class="proj-status proj-status--{project.status}">{project.status}</span>
            </div>
            {#if project.description}
              <p class="proj-desc">{project.description}</p>
            {/if}
            <div class="proj-meta">
              <span class="proj-stat">{project.phase_count} phases</span>
              <span class="proj-stat">{project.task_count} tasks</span>
              <span class="proj-stat">{project.agent_count} agents</span>
            </div>
          </button>
        </div>
      {/each}
    </div>
  {/if}
</PageShell>

<!-- Create project wizard dialog -->
{#if showForm}
  <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
  <div
    class="pw-overlay"
    role="dialog"
    aria-modal="true"
    aria-label="Create project"
    onclick={(e) => { if (e.target === e.currentTarget) resetForm(); }}
    onkeydown={handleKeyDown}
    transition:fly={{ y: 20, duration: 200 }}
  >
    <div class="pw-modal" onclick={(e) => e.stopPropagation()}>
      <!-- Header -->
      <div class="pw-header">
        <div class="pw-header-top">
          <h2 class="pw-title">New Project</h2>
          <button class="pw-close" onclick={resetForm} aria-label="Close">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <line x1="18" y1="6" x2="6" y2="18" /><line x1="6" y1="6" x2="18" y2="18" />
            </svg>
          </button>
        </div>

        <!-- Step indicator -->
        <div class="pw-steps" role="tablist" aria-label="Wizard steps">
          {#each [1, 2, 3] as step (step)}
            {@const isCurrent = wizStep === step}
            {@const isCompleted = wizStep > step}
            <button
              class="pw-step"
              class:pw-step--active={isCurrent}
              class:pw-step--done={isCompleted}
              role="tab"
              aria-selected={isCurrent}
              aria-label="Step {step}: {STEP_TITLES[step as WizardStep]}"
              disabled={!isCompleted}
              onclick={() => goToStep(step as WizardStep)}
            >
              <span class="pw-step-dot">
                {#if isCompleted}
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="20 6 9 17 4 12"/></svg>
                {:else}
                  {step}
                {/if}
              </span>
              <span class="pw-step-label">{STEP_TITLES[step as WizardStep]}</span>
            </button>
            {#if step < STEP_COUNT}
              <div class="pw-step-line" class:pw-step-line--done={wizStep > step}></div>
            {/if}
          {/each}
        </div>
      </div>

      <!-- Body -->
      <div class="pw-body">
        {#key wizStep}
          <div
            class="pw-step-content"
            in:fly={{ x: wizDirection === 'forward' ? 60 : -60, duration: 200, delay: 50 }}
            out:fly={{ x: wizDirection === 'forward' ? -60 : 60, duration: 150 }}
          >
            {#if wizStep === 1}
              <!-- Step 1: Details -->
              <h3 class="pw-section-title">{STEP_TITLES[1]}</h3>
              <p class="pw-section-desc">{STEP_SUBTITLES[1]}</p>

              <div class="pw-field">
                <label class="pw-label" for="pw-name">Name <span class="pw-required">*</span></label>
                <input
                  id="pw-name"
                  class="pw-input"
                  type="text"
                  placeholder="My Awesome Project"
                  bind:value={formName}
                  autofocus
                />
              </div>

              <div class="pw-field">
                <label class="pw-label" for="pw-desc">Description</label>
                <textarea
                  id="pw-desc"
                  class="pw-textarea"
                  placeholder="What is this project about? Goals, tech stack, constraints…"
                  rows="4"
                  bind:value={formDescription}
                ></textarea>
              </div>

              <div class="pw-field">
                <label class="pw-label" for="pw-status">Status</label>
                <select id="pw-status" class="pw-select" bind:value={formStatus}>
                  <option value="active">Active</option>
                  <option value="completed">Completed</option>
                  <option value="archived">Archived</option>
                </select>
              </div>

            {:else if wizStep === 2}
              <!-- Step 2: Directory -->
              <h3 class="pw-section-title">{STEP_TITLES[2]}</h3>
              <p class="pw-section-desc">{STEP_SUBTITLES[2]}</p>

              <div class="pw-field">
                <label class="pw-label" for="pw-dir">Project Directory</label>
                <div class="pw-path-row">
                  <input
                    id="pw-dir"
                    class="pw-input pw-input--path"
                    type="text"
                    placeholder="/path/to/project"
                    bind:value={formOutputPath}
                    oninput={() => void checkDirExists(formOutputPath)}
                  />
                  {#if isTauri()}
                    <button class="pw-btn-browse" type="button" onclick={pickOutputDirectory} aria-label="Browse for directory">
                      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                        <path d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z"/>
                      </svg>
                      Browse
                    </button>
                  {/if}
                </div>
              </div>

              {#if formOutputPath.trim()}
                <div class="pw-dir-status">
                  {#if dirExists === true}
                    <div class="pw-dir-badge pw-dir-badge--exists">
                      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                        <path d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z"/>
                      </svg>
                      <span>Existing directory — existing source code will be preserved</span>
                    </div>
                  {:else if dirExists === false}
                    <div class="pw-dir-badge pw-dir-badge--new">
                      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                        <path d="M12 5v14m-7-7h14"/>
                      </svg>
                      <span>New directory — will be created when the project is set up</span>
                    </div>
                  {:else}
                    <div class="pw-dir-badge pw-dir-badge--unknown">
                      <span>Type a path or browse to select a directory</span>
                    </div>
                  {/if}
                </div>
              {/if}

              <div class="pw-dir-hint">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                  <path d="M11.25 11.25l.041-.02a.75.75 0 011.063.852l-.708 2.836a.75.75 0 001.063.853l.041-.021M21 12a9 9 0 11-18 0 9 9 0 0118 0zm-9-3.75h.008v.008H12V8.25z"/>
                </svg>
                <span>This is where generated code, docs, and artifacts will be written. You can point to an existing repo with source code already in it.</span>
              </div>

            {:else if wizStep === 3}
              <!-- Step 3: Documentation -->
              <h3 class="pw-section-title">{STEP_TITLES[3]}</h3>
              <p class="pw-section-desc">{STEP_SUBTITLES[3]}</p>

              <!-- Drop zone -->
              <div
                class="pw-drop"
                class:pw-drop--active={dragOver}
                role="region"
                aria-label="Drop files here or click to upload"
              >
                <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" class="pw-drop-icon">
                  <path d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5m-13.5-9L12 3m0 0l4.5 4.5M12 3v13.5"/>
                </svg>
                <p class="pw-drop-text">Drag & drop files here</p>
                <p class="pw-drop-hint">.md, .txt, .pdf, .doc, .docx, .xls, .xlsx, .json, .yaml, .csv, .sql, .dbml</p>
                <label class="pw-drop-browse">
                  Choose Files
                  <input type="file" multiple accept={ACCEPT_STRING} onchange={(e) => handleFileInput((e.target as HTMLInputElement).files)} hidden />
                </label>
              </div>

              <!-- Uploaded files -->
              {#if uploadedFiles.length > 0}
                <div class="pw-files">
                  <span class="pw-files-count">{uploadedFiles.length} file{uploadedFiles.length !== 1 ? 's' : ''} attached</span>
                  <div class="pw-file-list">
                    {#each uploadedFiles as file (file.id)}
                      <div class="pw-file-item">
                        <svg class="pw-file-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true">
                          <path d="M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m2.25 0H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z"/>
                        </svg>
                        <span class="pw-file-name">{file.name}</span>
                        <span class="pw-file-size">{formatSize(file.size)}</span>
                        <button class="pw-file-remove" onclick={() => removeFile(file.id)} aria-label="Remove {file.name}">
                          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                            <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
                          </svg>
                        </button>
                      </div>
                    {/each}
                  </div>
                </div>
              {/if}

              <!-- Context textarea -->
              <div class="pw-field" style="margin-top: 16px">
                <label class="pw-label" for="pw-context">
                  Additional Context
                  <span class="pw-label-hint">Describe project goals, constraints, domain knowledge, or anything that helps agents understand the project.</span>
                </label>
                <textarea
                  id="pw-context"
                  class="pw-textarea"
                  rows="4"
                  placeholder="e.g. We're building a multi-tenant SaaS platform. The backend is Elixir/Phoenix with PostgreSQL. Key constraints: HIPAA compliance, real-time updates via WebSocket…"
                  bind:value={contextText}
                ></textarea>
              </div>
            {/if}
          </div>
        {/key}
      </div>

      <!-- Footer -->
      {#if createError !== null}
        <div class="pw-error-bar" role="alert">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/>
          </svg>
          <span>{createError}</span>
          <button class="pw-error-dismiss" onclick={() => { createError = null; }} aria-label="Dismiss error">
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
              <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
            </svg>
          </button>
        </div>
      {/if}
      <div class="pw-footer">
        <button
          class="pw-btn pw-btn--secondary"
          onclick={wizStep === 1 ? resetForm : goBack}
          disabled={creating}
        >
          {wizStep === 1 ? 'Cancel' : 'Back'}
        </button>
        <div class="pw-footer-spacer"></div>
        {#if wizStep < STEP_COUNT}
          <button class="pw-btn pw-btn--skip" onclick={goNext}>Skip</button>
          <button class="pw-btn pw-btn--primary" onclick={goNext} disabled={!canProceed}>
            {wizStep === 1 ? 'Next: Directory' : 'Next: Documentation'}
          </button>
        {:else}
          <button
            class="pw-btn pw-btn--create"
            onclick={handleCreate}
            disabled={creating || !formName.trim()}
          >
            {#if creating}
              <span class="pw-btn-spinner"></span> Creating…
            {:else}
              Create Project
            {/if}
          </button>
        {/if}
      </div>
    </div>
  </div>
{/if}

<style>
  /* ── List page toolbar ─────────────────────────────────────────────────── */
  .proj-filter-group {
    display: flex; align-items: center; gap: 2px;
    background: var(--dbg2); border: 1px solid var(--dbd); border-radius: 8px; padding: 2px;
  }
  .proj-filter-btn {
    background: none; border: none; border-radius: 6px; color: var(--dt3);
    font-size: 12px; font-weight: 500; padding: 3px 10px; cursor: pointer;
    transition: background 120ms ease, color 120ms ease;
  }
  .proj-filter-btn:hover { color: var(--dt2); background: rgba(255,255,255,0.05); }
  .proj-filter-btn--active { background: var(--dbg3); color: var(--dt); border: 1px solid var(--dbd); }
  .proj-search {
    height: 28px; padding: 0 10px; border-radius: 6px; font-size: 12px;
    background: var(--dbg2); border: 1px solid var(--dbd); color: var(--dt); min-width: 180px;
  }
  .proj-search:focus { outline: none; border-color: #f97316; }
  .proj-btn {
    height: 28px; padding: 0 12px; border-radius: 6px; font-size: 12px; font-weight: 500;
    background: #f97316; border: none; color: white; cursor: pointer; transition: background 120ms ease;
  }
  .proj-btn:hover { background: #ea580c; }
  .proj-loading, .proj-empty, .proj-error {
    display: flex; flex-direction: column; align-items: center;
    justify-content: center; gap: 12px; height: 200px;
    color: var(--dt3); font-size: 13px;
  }
  .proj-spinner {
    width: 24px; height: 24px; border-radius: 50%;
    border: 2px solid var(--dbd); border-top-color: var(--dt2);
    animation: spin 0.8s linear infinite;
  }
  @keyframes spin { to { transform: rotate(360deg); } }
  .proj-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 12px; padding: 24px; }
  .proj-card {
    background: var(--dbg2); border: 1px solid var(--dbd); border-radius: 10px;
    transition: border-color 120ms ease;
  }
  .proj-card--selected { border-color: #f97316; background: color-mix(in srgb, #f97316 6%, var(--dbg2)); }
  .proj-card:hover { border-color: var(--dbd2); }
  .proj-card-btn { width: 100%; padding: 16px; text-align: left; background: none; border: none; cursor: pointer; }
  .proj-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px; }
  .proj-name { font-size: 15px; font-weight: 600; color: var(--dt); }
  .proj-status { font-size: 10px; padding: 2px 6px; border-radius: 4px; text-transform: uppercase; font-weight: 500; }
  .proj-status--active { background: rgba(34, 197, 94, 0.1); color: rgba(34, 197, 94, 0.65); }
  .proj-status--archived { background: var(--dbg3); color: var(--dt4); }
  .proj-status--planning { background: color-mix(in srgb, #f97316 15%, transparent); color: #fdba74; }
  .proj-desc { font-size: 12px; color: var(--dt3); margin: 0 0 10px; line-height: 1.5; }
  .proj-meta { display: flex; gap: 12px; }
  .proj-stat { font-size: 11px; color: var(--dt4); }

  /* ── Project wizard overlay ────────────────────────────────────────────── */
  .pw-overlay {
    position: fixed; inset: 0; z-index: 9000;
    background: rgba(0,0,0,0.6);
    display: flex; align-items: center; justify-content: center;
    backdrop-filter: blur(4px);
  }
  .pw-modal {
    width: 95vw; max-width: 640px; max-height: 90vh;
    background: var(--bg-primary, #1a1a2e);
    border: 1px solid var(--border-subtle, rgba(255,255,255,0.08));
    border-radius: 16px;
    display: flex; flex-direction: column;
    box-shadow: 0 24px 64px rgba(0,0,0,0.5), 0 0 0 1px rgba(255,255,255,0.04) inset;
    overflow: hidden;
  }

  /* Header */
  .pw-header {
    padding: 20px 24px 16px;
    border-bottom: 1px solid var(--border-subtle, rgba(255,255,255,0.06));
    flex-shrink: 0;
  }
  .pw-header-top {
    display: flex; align-items: center; justify-content: space-between;
    margin-bottom: 16px;
  }
  .pw-title { font-size: 18px; font-weight: 600; margin: 0; color: var(--text-primary, #eee); }
  .pw-close {
    background: none; border: none; color: var(--text-tertiary);
    cursor: pointer; padding: 4px; border-radius: 6px; transition: all 0.15s;
  }
  .pw-close:hover { background: rgba(255,255,255,0.06); color: var(--text-primary); }

  /* Step indicator */
  .pw-steps { display: flex; align-items: center; gap: 0; }
  .pw-step {
    display: flex; align-items: center; gap: 6px;
    background: none; border: none; padding: 4px 2px; cursor: default;
    color: var(--text-tertiary, #666); font-size: 12px; font-weight: 500;
    transition: color 0.15s;
  }
  .pw-step:not(:disabled) { cursor: pointer; }
  .pw-step:not(:disabled):hover { color: var(--text-secondary, #aaa); }
  .pw-step--active { color: var(--text-primary, #eee); }
  .pw-step--active .pw-step-dot {
    background: #f97316; color: #fff; border-color: #f97316;
  }
  .pw-step--done .pw-step-dot {
    background: rgba(34,197,94,0.15); color: #22c55e; border-color: rgba(34,197,94,0.3);
  }
  .pw-step-dot {
    width: 22px; height: 22px; border-radius: 50%;
    display: flex; align-items: center; justify-content: center;
    font-size: 11px; font-weight: 600;
    border: 1.5px solid var(--border-subtle, rgba(255,255,255,0.12));
    background: rgba(255,255,255,0.04);
    transition: all 0.2s;
    flex-shrink: 0;
  }
  .pw-step-label { white-space: nowrap; }
  .pw-step-line {
    flex: 1; height: 1px; min-width: 16px; margin: 0 8px;
    background: var(--border-subtle, rgba(255,255,255,0.08));
    transition: background 0.2s;
  }
  .pw-step-line--done { background: rgba(34,197,94,0.3); }

  /* Body */
  .pw-body {
    flex: 1; overflow-y: auto; overflow-x: hidden;
    padding: 24px; min-height: 300px;
    position: relative;
  }
  .pw-step-content { min-height: 260px; }
  .pw-section-title { font-size: 16px; font-weight: 600; margin: 0 0 4px; color: var(--text-primary, #eee); }
  .pw-section-desc { font-size: 13px; color: var(--text-secondary, #aaa); margin: 0 0 20px; line-height: 1.5; }

  /* Fields */
  .pw-field { display: flex; flex-direction: column; gap: 6px; margin-bottom: 14px; }
  .pw-label { font-size: 12px; font-weight: 500; color: var(--text-secondary, #aaa); display: flex; flex-direction: column; gap: 2px; }
  .pw-label-hint { font-size: 11px; color: var(--text-tertiary, #666); font-weight: 400; }
  .pw-required { color: #f97316; }
  .pw-input, .pw-select {
    height: 36px; padding: 0 12px; border-radius: 8px; font-size: 13px;
    background: rgba(255,255,255,0.04);
    border: 1px solid var(--border-subtle, rgba(255,255,255,0.08));
    color: var(--text-primary, #eee);
    width: 100%; box-sizing: border-box;
    transition: border-color 0.15s;
  }
  .pw-input:focus, .pw-select:focus { outline: none; border-color: #f97316; }
  .pw-textarea {
    padding: 10px 12px; border-radius: 8px; font-size: 13px; font-family: inherit;
    background: rgba(255,255,255,0.04);
    border: 1px solid var(--border-subtle, rgba(255,255,255,0.08));
    color: var(--text-primary, #eee);
    width: 100%; box-sizing: border-box; resize: vertical; min-height: 80px;
    transition: border-color 0.15s;
  }
  .pw-textarea:focus { outline: none; border-color: #f97316; }

  /* Directory step */
  .pw-path-row { display: flex; gap: 6px; align-items: center; }
  .pw-input--path { flex: 1; min-width: 0; }
  .pw-btn-browse {
    height: 36px; padding: 0 14px; border-radius: 8px; font-size: 12px; font-weight: 500;
    background: rgba(255,255,255,0.06);
    border: 1px solid var(--border-subtle, rgba(255,255,255,0.08));
    color: var(--text-secondary, #aaa);
    cursor: pointer; white-space: nowrap; transition: all 0.15s;
    display: flex; align-items: center; gap: 6px;
  }
  .pw-btn-browse:hover { background: rgba(255,255,255,0.1); border-color: #f97316; color: var(--text-primary); }

  .pw-dir-status { margin-top: 10px; }
  .pw-dir-badge {
    display: flex; align-items: center; gap: 8px;
    padding: 8px 12px; border-radius: 8px; font-size: 12px;
  }
  .pw-dir-badge--exists {
    background: rgba(34,197,94,0.08); color: #4ade80;
    border: 1px solid rgba(34,197,94,0.15);
  }
  .pw-dir-badge--new {
    background: rgba(59,130,246,0.08); color: #60a5fa;
    border: 1px solid rgba(59,130,246,0.15);
  }
  .pw-dir-badge--unknown {
    background: rgba(255,255,255,0.03); color: var(--text-tertiary);
    border: 1px solid var(--border-subtle, rgba(255,255,255,0.06));
  }
  .pw-dir-hint {
    margin-top: 12px; display: flex; align-items: flex-start; gap: 8px;
    font-size: 12px; color: var(--text-tertiary, #666); line-height: 1.5;
  }
  .pw-dir-hint svg { flex-shrink: 0; margin-top: 1px; }

  /* File upload drop zone */
  .pw-drop {
    border: 2px dashed var(--border-subtle, rgba(255,255,255,0.1));
    border-radius: 12px; padding: 24px 20px;
    text-align: center; cursor: pointer;
    transition: all 0.2s;
  }
  .pw-drop:hover, .pw-drop--active {
    border-color: #f97316;
    background: rgba(249,115,22,0.04);
  }
  .pw-drop-icon { color: var(--text-tertiary); margin-bottom: 6px; }
  .pw-drop-text { font-size: 13px; color: var(--text-secondary); margin: 0 0 4px; }
  .pw-drop-hint { font-size: 11px; color: var(--text-tertiary); margin: 0 0 12px; }
  .pw-drop-browse {
    display: inline-block; padding: 6px 16px; border-radius: 6px;
    background: rgba(255,255,255,0.06); color: var(--text-secondary);
    font-size: 12px; font-weight: 500; cursor: pointer;
    border: 1px solid var(--border-subtle, rgba(255,255,255,0.08));
    transition: all 0.15s;
  }
  .pw-drop-browse:hover { background: rgba(255,255,255,0.1); }

  /* Uploaded file list */
  .pw-files { margin-top: 14px; }
  .pw-files-count { font-size: 12px; font-weight: 500; color: var(--text-secondary); display: block; margin-bottom: 6px; }
  .pw-file-list { display: flex; flex-direction: column; gap: 3px; }
  .pw-file-item {
    display: flex; align-items: center; gap: 8px;
    padding: 5px 10px; border-radius: 6px;
    background: rgba(255,255,255,0.03);
  }
  .pw-file-icon { color: var(--text-tertiary); flex-shrink: 0; }
  .pw-file-name {
    font-size: 13px; color: var(--text-primary); flex: 1;
    min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  }
  .pw-file-size { font-size: 11px; color: var(--text-tertiary); flex-shrink: 0; }
  .pw-file-remove {
    background: none; border: none; color: var(--text-tertiary);
    cursor: pointer; padding: 2px; border-radius: 4px; transition: color 0.15s;
  }
  .pw-file-remove:hover { color: #ef4444; }

  /* Error bar */
  .pw-error-bar {
    display: flex; align-items: center; gap: 8px;
    padding: 8px 16px; margin: 0;
    background: rgba(239,68,68,0.08); color: #f87171;
    border-top: 1px solid rgba(239,68,68,0.15);
    font-size: 12px; line-height: 1.4;
  }
  .pw-error-bar svg { flex-shrink: 0; }
  .pw-error-bar span { flex: 1; }
  .pw-error-dismiss {
    background: none; border: none; color: #f87171; cursor: pointer;
    padding: 2px; border-radius: 4px; opacity: 0.7; transition: opacity 0.15s;
  }
  .pw-error-dismiss:hover { opacity: 1; }

  /* Footer */
  .pw-footer {
    display: flex; align-items: center; gap: 8px;
    padding: 16px 24px;
    border-top: 1px solid var(--border-subtle, rgba(255,255,255,0.06));
    flex-shrink: 0;
  }
  .pw-footer-spacer { flex: 1; }
  .pw-btn {
    padding: 8px 20px; border-radius: 8px; font-size: 13px; font-weight: 500;
    border: none; cursor: pointer; transition: all 0.15s; white-space: nowrap;
  }
  .pw-btn:disabled { opacity: 0.4; cursor: not-allowed; }
  .pw-btn--primary { background: #f97316; color: #fff; }
  .pw-btn--primary:not(:disabled):hover { filter: brightness(1.1); }
  .pw-btn--secondary {
    background: rgba(255,255,255,0.06); color: var(--text-secondary, #aaa);
  }
  .pw-btn--secondary:not(:disabled):hover { background: rgba(255,255,255,0.1); }
  .pw-btn--skip {
    background: none; color: var(--text-tertiary); padding: 8px 12px;
  }
  .pw-btn--skip:hover { color: var(--text-secondary); }
  .pw-btn--create {
    background: linear-gradient(135deg, #f97316, #ea580c);
    color: #fff; display: inline-flex; align-items: center; gap: 8px;
  }
  .pw-btn--create:not(:disabled):hover { filter: brightness(1.1); }
  .pw-btn-spinner {
    width: 14px; height: 14px; border-radius: 50%;
    border: 2px solid rgba(255,255,255,0.3); border-top-color: #fff;
    animation: spin 0.6s linear infinite;
  }
</style>
