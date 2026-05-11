<!-- src/lib/components/tasks/AutomatedTaskPipeline.svelte -->
<!-- Multi-phase automated task creation pipeline: Context → Detection → ForgeMap → Generation → Review → Create -->
<script lang="ts">
  import type {
    Document,
    WizardTask,
    WizardSprintGroup,
    TaskPriority,
    TaskType,
    ForgeMapDetection,
    ForgeMapScanResult,
    StreamEvent,
  } from '$api/types';
  import { onDestroy } from 'svelte';
  import { sessions, messages } from '$api/client';
  import { connectSSE } from '$api/sse';
  import { tasksStore } from '$lib/stores/tasks.svelte';
  import { agentsStore } from '$lib/stores/agents.svelte';
  import { settingsStore } from '$lib/stores/settings.svelte';
  import { forgemapStore } from '$lib/stores/forgemap.svelte';
  import CodebaseDetector from './CodebaseDetector.svelte';
  import DependencyGraph from './DependencyGraph.svelte';
  import TaskSplitDialog from './TaskSplitDialog.svelte';

  onDestroy(() => {
    if (streamController) {
      streamController.abort();
      streamController = null;
    }
  });

  interface Props {
    projectId: string;
    projectName: string;
    outputPath: string | null;
    workspaceId: string;
    documents?: Document[];
    preloadedContext?: string;
    onClose: () => void;
    onCreated: () => void;
  }

  // svelte-ignore state_referenced_locally
  let {
    projectId,
    projectName,
    outputPath,
    workspaceId,
    documents = [],
    preloadedContext = '',
    onClose,
    onCreated,
  }: Props = $props();

  // ── Phase state ──────────────────────────────────────────────────────────────
  type Phase = 'context' | 'detection' | 'forgemap' | 'generation' | 'review' | 'creating';

  let phase = $state<Phase>('context');
  let error = $state<string | null>(null);

  // ── Phase 1: Context ──────────────────────────────────────────────────────────
  let selectedDocIds = $state<Set<string>>(new Set(documents.map((d) => d.id)));
  let additionalContext = $state(preloadedContext);

  const selectedDocs = $derived(documents.filter((d) => selectedDocIds.has(d.id)));

  function toggleDoc(docId: string) {
    const next = new Set(selectedDocIds);
    if (next.has(docId)) next.delete(docId);
    else next.add(docId);
    selectedDocIds = next;
  }

  // ── Phase 2: Detection ────────────────────────────────────────────────────────
  let detection = $state<ForgeMapDetection | null>(null);
  let detecting = $state(false);

  async function runDetection() {
    detecting = true;
    error = null;
    const result = await forgemapStore.detect(projectId);
    detection = result;
    if (result === null && forgemapStore.error !== null) {
      error = `Detection failed: ${forgemapStore.error}`;
    }
    detecting = false;
  }

  // ── Phase 3: ForgeMap ─────────────────────────────────────────────────────────
  let scanResult = $state<ForgeMapScanResult | null>(null);
  let scanning = $state(false);

  async function runScan() {
    scanning = true;
    error = null;
    const result = await forgemapStore.scan(projectId);
    scanResult = result;
    if (result === null && forgemapStore.error !== null) {
      error = `Scan failed: ${forgemapStore.error}`;
    }
    scanning = false;
  }

  // ── Phase 4: Generation ───────────────────────────────────────────────────────
  let sprintGroups = $state<WizardSprintGroup[]>([]);
  let generating = $state(false);
  let streamController = $state<{ abort: () => void } | null>(null);

  const allTasks = $derived(sprintGroups.flatMap((g) => g.tasks));
  const selectedTasks = $derived(allTasks.filter((t) => t.selected));

  // ── Phase 5: Review ───────────────────────────────────────────────────────────
  let splitTarget = $state<WizardTask | null>(null);
  let filterPriority = $state<string>('all');

  const filteredTasks = $derived.by(() => {
    let result = allTasks;
    if (filterPriority !== 'all') {
      result = result.filter((t) => t.priority === filterPriority);
    }
    return result;
  });

  // ── Phase 6: Creating ─────────────────────────────────────────────────────────
  let creatingProgress = $state(0);

  // ── Navigation ────────────────────────────────────────────────────────────────
  const PHASES: Phase[] = ['context', 'detection', 'forgemap', 'generation', 'review', 'creating'];
  const PHASE_LABELS: Record<Phase, string> = {
    context: 'Context',
    detection: 'Detection',
    forgemap: 'ForgeMap',
    generation: 'Generation',
    review: 'Review',
    creating: 'Creating',
  };

  const phaseIndex = $derived(PHASES.indexOf(phase));

  function goToPhase(p: Phase) {
    const idx = PHASES.indexOf(p);
    if (idx <= phaseIndex) {
      phase = p;
    }
  }

  async function handleNext() {
    error = null;
    if (phase === 'context') {
      phase = 'detection';
      void runDetection();
    } else if (phase === 'detection') {
      if (detection?.has_codebase) {
        phase = 'forgemap';
      } else {
        phase = 'generation';
        void runGeneration();
      }
    } else if (phase === 'forgemap') {
      phase = 'generation';
      void runGeneration();
    } else if (phase === 'generation') {
      phase = 'review';
    } else if (phase === 'review') {
      await handleCreate();
    }
  }

  function handleBack() {
    if (phase === 'detection') phase = 'context';
    else if (phase === 'forgemap') phase = 'detection';
    else if (phase === 'generation') {
      if (streamController) {
        streamController.abort();
        streamController = null;
      }
      phase = detection?.has_codebase ? 'forgemap' : 'detection';
    } else if (phase === 'review') phase = 'generation';
  }

  const canProceed = $derived.by(() => {
    if (phase === 'context') return selectedDocs.length > 0 || additionalContext.trim() !== '';
    if (phase === 'detection') return detection !== null && !detecting;
    if (phase === 'forgemap') return !scanning;
    if (phase === 'generation') return sprintGroups.length > 0 && !generating;
    if (phase === 'review') return selectedTasks.length > 0;
    return false;
  });

  // ── Generation logic ─────────────────────────────────────────────────────────
  function buildPrompt(): string {
    const parts: string[] = [];

    parts.push(`Analyze the following context for project "${projectName}" and generate a comprehensive, dependency-ordered set of development tasks.`);
    parts.push('');

    if (selectedDocs.length > 0) {
      parts.push('--- Project Documentation ---');
      for (const doc of selectedDocs) {
        parts.push(`### ${doc.title}`);
        parts.push(doc.content.slice(0, 3000));
        parts.push('');
      }
    }

    if (additionalContext.trim()) {
      parts.push('--- Additional Context ---');
      parts.push(additionalContext);
      parts.push('');
    }

    if (scanResult !== null) {
      parts.push('--- Codebase Index (ForgeMap) ---');
      parts.push(`Files: ${scanResult.file_count}, Languages: ${scanResult.languages.join(', ')}`);
      const topFiles = scanResult.files.slice(0, 30);
      for (const f of topFiles) {
        const exports = f.exports.length > 0 ? ` exports: ${f.exports.slice(0, 5).join(', ')}` : '';
        parts.push(`- ${f.path} (${f.language}, ${f.line_count} lines)${exports}`);
      }
      parts.push('');
    }

    if (detection !== null && !detection.has_codebase) {
      parts.push('NOTE: This is a NEW project with no existing codebase. Start with prerequisite/scaffold tasks (project setup, tech stack configuration, CI/CD, data models) before feature tasks.');
      parts.push('');
    }

    parts.push('Generate tasks organized into sprint groups. Each task MUST include:');
    parts.push('- title: concise task title');
    parts.push('- description: detailed description with acceptance criteria');
    parts.push('- priority: low | medium | high | critical');
    parts.push('- task_type: prerequisite | scaffold | feature | subtask | validation');
    parts.push('- labels: relevant category labels as an array');
    parts.push('- depends_on: array of task titles this depends on (use exact titles from other tasks)');
    parts.push('');
    parts.push('Prerequisite and scaffold tasks MUST come first. Feature tasks depend on them. Validation tasks come last.');
    parts.push('');
    parts.push('Respond ONLY with valid JSON:');
    parts.push('{ "sprints": [{ "name": "...", "objective": "...", "tasks": [{ "title": "...", "description": "...", "priority": "...", "task_type": "...", "labels": ["..."], "depends_on": ["..."] }] }] }');

    return parts.join('\n');
  }

  async function runGeneration() {
    generating = true;
    error = null;
    sprintGroups = [];

    try {
      const agent = agentsStore.agents[0];
      if (agent === undefined) {
        error = 'No agents available. Please add an agent to your workspace first.';
        generating = false;
        return;
      }

      const session = await sessions.create({
        agent_id: agent.id,
        title: `Task pipeline: ${projectName}`,
      });

      const prompt = buildPrompt();
      let buffer = '';

      const ctrl = connectSSE(`/sessions/${session.id}/stream`, {
        onEvent: (event: StreamEvent) => {
          if (event.type === 'streaming_token') {
            buffer += (event as { delta: string }).delta;
          } else if (event.type === 'done') {
            parseAndSetTasks(buffer);
            generating = false;
          } else if (event.type === 'error') {
            error = (event as { message?: string }).message ?? 'Generation failed';
            generating = false;
          }
        },
        onError: (err: Error) => {
          error = err.message;
          generating = false;
        },
        onDone: () => {
          if (generating) {
            parseAndSetTasks(buffer);
            generating = false;
          }
        },
      });

      streamController = ctrl;

      const model = settingsStore.data.default_model ?? undefined;
      await messages.send({ session_id: session.id, content: prompt, model });
    } catch (err) {
      error = (err as Error).message;
      generating = false;
    }
  }

  function parseAndSetTasks(raw: string): void {
    try {
      const jsonMatch = raw.match(/\{[\s\S]*\}/);
      if (!jsonMatch) {
        error = 'No valid JSON in AI response.';
        return;
      }
      const parsed = JSON.parse(jsonMatch[0]) as {
        sprints: Array<{
          name: string;
          objective?: string;
          goal?: string;
          tasks?: Array<{
            title: string;
            description?: string;
            priority?: string;
            task_type?: string;
            labels?: string[];
            depends_on?: string[];
          }>;
          issues?: Array<{
            title: string;
            description?: string;
            priority?: string;
            task_type?: string;
            labels?: string[];
            depends_on?: string[];
          }>;
        }>;
      };

      if (!Array.isArray(parsed.sprints)) {
        error = 'Invalid JSON structure.';
        return;
      }

      const titleToId = new Map<string, string>();
      let counter = 0;

      sprintGroups = parsed.sprints.map((sprint) => {
        const sprintTasks = sprint.tasks ?? sprint.issues ?? [];
        return {
          name: sprint.name,
          objective: sprint.objective ?? sprint.goal ?? '',
          tasks: sprintTasks.map((item) => {
            counter++;
            const id = `gen-${counter}`;
            titleToId.set(item.title, id);

            return {
              id,
              title: item.title ?? 'Untitled',
              description: item.description ?? '',
              priority: coercePriority(item.priority),
              labels: Array.isArray(item.labels) ? item.labels : [],
              sprintName: sprint.name,
              dependsOn: [],
              taskType: coerceTaskType(item.task_type),
              selected: true,
            };
          }),
        };
      });

      // Second pass: resolve depends_on by title
      parsed.sprints.forEach((sprint, si) => {
        const sprintTasks = sprint.tasks ?? sprint.issues ?? [];
        sprintTasks.forEach((item, ii) => {
          const deps = (item.depends_on ?? [])
            .map((title) => titleToId.get(title))
            .filter((id): id is string => id !== undefined);
          if (sprintGroups[si]?.tasks[ii]) {
            sprintGroups[si].tasks[ii].dependsOn = deps;
          }
        });
      });

      // Trigger reactivity
      sprintGroups = [...sprintGroups];
    } catch {
      error = 'Failed to parse generated tasks.';
    }
  }

  function coercePriority(p?: string): TaskPriority {
    if (p === 'low' || p === 'medium' || p === 'high' || p === 'critical') return p;
    return 'medium';
  }

  function coerceTaskType(t?: string): TaskType | null {
    if (t === 'prerequisite' || t === 'feature' || t === 'subtask' || t === 'validation' || t === 'scaffold') return t;
    return null;
  }

  function mockGenerate(): WizardSprintGroup[] {
    return [
      {
        name: 'Sprint 0: Foundation',
        objective: 'Project setup and scaffolding',
        tasks: [
          { id: 'gen-1', title: 'Define tech stack and initialize project', description: 'Set up build tooling, linting, CI/CD configuration, and dependency management.', priority: 'critical', labels: ['setup', 'scaffold'], sprintName: 'Sprint 0: Foundation', dependsOn: [], taskType: 'scaffold', selected: true },
          { id: 'gen-2', title: 'Create core data models and schemas', description: 'Define TypeScript interfaces, database schemas, and validation rules for primary entities.', priority: 'high', labels: ['backend', 'data-model'], sprintName: 'Sprint 0: Foundation', dependsOn: ['gen-1'], taskType: 'prerequisite', selected: true },
          { id: 'gen-3', title: 'Set up database and migrations', description: 'Initialize database, create migration system, and implement seed data.', priority: 'high', labels: ['backend', 'database'], sprintName: 'Sprint 0: Foundation', dependsOn: ['gen-1'], taskType: 'prerequisite', selected: true },
        ],
      },
      {
        name: 'Sprint 1: Core Features',
        objective: 'Implement primary API and UI',
        tasks: [
          { id: 'gen-4', title: 'Build REST API endpoints', description: 'Implement CRUD endpoints for all core entities with proper error handling and pagination.', priority: 'high', labels: ['backend', 'api'], sprintName: 'Sprint 1: Core Features', dependsOn: ['gen-2', 'gen-3'], taskType: 'feature', selected: true },
          { id: 'gen-5', title: 'Design and implement UI components', description: 'Build reusable UI components following the design system. Ensure accessibility compliance.', priority: 'medium', labels: ['frontend', 'ui'], sprintName: 'Sprint 1: Core Features', dependsOn: ['gen-4'], taskType: 'feature', selected: true },
          { id: 'gen-6', title: 'Add authentication and authorization', description: 'Implement secure auth flow with role-based access control and session management.', priority: 'critical', labels: ['security', 'auth'], sprintName: 'Sprint 1: Core Features', dependsOn: ['gen-4'], taskType: 'feature', selected: true },
        ],
      },
      {
        name: 'Sprint 2: Quality & Polish',
        objective: 'Testing, monitoring, documentation',
        tasks: [
          { id: 'gen-7', title: 'Write unit and integration tests', description: 'Achieve 80% code coverage. Focus on critical paths and API contract tests.', priority: 'medium', labels: ['testing', 'quality'], sprintName: 'Sprint 2: Quality & Polish', dependsOn: ['gen-4', 'gen-5', 'gen-6'], taskType: 'validation', selected: true },
          { id: 'gen-8', title: 'Set up monitoring and error tracking', description: 'Configure application monitoring, structured logging, and alerting.', priority: 'medium', labels: ['devops', 'monitoring'], sprintName: 'Sprint 2: Quality & Polish', dependsOn: ['gen-4'], taskType: 'feature', selected: true },
        ],
      },
    ];
  }

  // ── Task operations ───────────────────────────────────────────────────────────
  function toggleTask(taskId: string) {
    sprintGroups = sprintGroups.map((g) => ({
      ...g,
      tasks: g.tasks.map((t) =>
        t.id === taskId ? { ...t, selected: !t.selected } : t,
      ),
    }));
  }

  function selectAll() {
    sprintGroups = sprintGroups.map((g) => ({
      ...g,
      tasks: g.tasks.map((t) => ({ ...t, selected: true })),
    }));
  }

  function selectNone() {
    sprintGroups = sprintGroups.map((g) => ({
      ...g,
      tasks: g.tasks.map((t) => ({ ...t, selected: false })),
    }));
  }

  function handleSplitResult(subtasks: WizardTask[]) {
    if (splitTarget === null) return;
    const parentId = splitTarget.id;

    sprintGroups = sprintGroups.map((g) => {
      const parentIdx = g.tasks.findIndex((t) => t.id === parentId);
      if (parentIdx === -1) return g;

      const updated = [...g.tasks];
      updated[parentIdx] = { ...updated[parentIdx], selected: false };
      updated.splice(parentIdx + 1, 0, ...subtasks);
      return { ...g, tasks: updated };
    });

    splitTarget = null;
  }

  // ── Create issues ─────────────────────────────────────────────────────────────
  async function handleCreate() {
    const toCreate = topologicallySorted(selectedTasks);
    if (toCreate.length === 0) return;
    phase = 'creating';
    creatingProgress = 0;
    error = null;

    try {
      const { tasks: tasksApi } = await import('$api/client');
      const idMapping = new Map<string, string>();
      const created: import('$api/types').Task[] = [];
      const errors: string[] = [];

      for (let i = 0; i < toCreate.length; i++) {
        const t = toCreate[i];
        creatingProgress = Math.round(((i + 1) / toCreate.length) * 100);

        const resolvedDeps = (t.dependsOn ?? [])
          .map((depId) => idMapping.get(depId))
          .filter((id): id is string => id !== undefined);

        try {
          const task = await tasksApi.create({
            title: t.title,
            description: t.description || null,
            priority: t.priority,
            status: 'backlog',
            workspace_id: workspaceId,
            project_id: projectId,
            task_type: t.taskType,
            depends_on_ids: resolvedDeps,
          });
          idMapping.set(t.id, task.id);
          created.push(task);
        } catch (e) {
          errors.push(`"${t.title}": ${(e as Error).message}`);
        }
      }

      if (created.length > 0) {
        tasksStore.tasks = [...created, ...tasksStore.tasks];
        onCreated();
      } else {
        error = errors.length > 0
          ? `All ${errors.length} tasks failed to create: ${errors[0]}`
          : 'No tasks were created.';
        phase = 'review';
      }
    } catch (err) {
      error = (err as Error).message;
      phase = 'review';
    }
  }

  function topologicallySorted(tasks: WizardTask[]): WizardTask[] {
    const idSet = new Set(tasks.map((t) => t.id));
    const visited = new Set<string>();
    const result: WizardTask[] = [];
    const taskMap = new Map(tasks.map((t) => [t.id, t]));

    function visit(id: string, inStack: Set<string>) {
      if (visited.has(id) || inStack.has(id)) return;
      inStack.add(id);
      const task = taskMap.get(id);
      if (task === undefined) return;
      for (const dep of task.dependsOn ?? []) {
        if (idSet.has(dep)) visit(dep, inStack);
      }
      visited.add(id);
      result.push(task);
    }

    for (const t of tasks) {
      visit(t.id, new Set());
    }
    return result;
  }

  function handleClose() {
    if (streamController) {
      streamController.abort();
      streamController = null;
    }
    onClose();
  }

  // ── Scaffold handler ──────────────────────────────────────────────────────────
  function handleScaffold(_stack: string, _template: string) {
    // Scaffold logic would invoke Tauri IPC — for now just proceed
    phase = 'generation';
    void runGeneration();
  }

  const PRIORITY_COLORS: Record<string, string> = {
    critical: 'rgba(239, 68, 68, 0.15)',
    high: 'rgba(249, 115, 22, 0.12)',
    medium: 'rgba(234, 179, 8, 0.1)',
    low: 'rgba(107, 114, 128, 0.1)',
  };

  const PRIORITY_TEXT: Record<string, string> = {
    critical: '#fca5a5',
    high: '#fdba74',
    medium: '#fde68a',
    low: '#9ca3af',
  };

  const TYPE_BADGE: Record<string, { label: string; color: string }> = {
    prerequisite: { label: 'PRE', color: '#818cf8' },
    scaffold: { label: 'SCF', color: '#34d399' },
    feature: { label: 'FTR', color: '#60a5fa' },
    subtask: { label: 'SUB', color: '#a78bfa' },
    validation: { label: 'VAL', color: '#fbbf24' },
  };
</script>

<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
<div class="atp-overlay" role="dialog" aria-modal="true" aria-label="Automated Task Pipeline"
  tabindex="-1"
  onclick={(e) => { if (e.target === e.currentTarget) handleClose(); }}
  onkeydown={(e) => { if (e.key === 'Escape') handleClose(); }}
>
  <div class="atp-modal">
    <!-- Header -->
    <div class="atp-header">
      <h2 class="atp-title">Automated Task Pipeline</h2>
      <span class="atp-project-badge">{projectName}</span>
      <button class="atp-close" type="button" onclick={handleClose} aria-label="Close">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <path d="M18 6L6 18M6 6l12 12" />
        </svg>
      </button>
    </div>

    <!-- Progress stepper -->
    <div class="atp-stepper">
      {#each PHASES.slice(0, -1) as p, idx (p)}
        <button
          type="button"
          class="atp-step"
          class:atp-step--active={phase === p}
          class:atp-step--done={idx < phaseIndex}
          class:atp-step--disabled={idx > phaseIndex}
          onclick={() => goToPhase(p)}
          disabled={idx > phaseIndex}
        >
          <span class="atp-step-num">{idx + 1}</span>
          <span class="atp-step-label">{PHASE_LABELS[p]}</span>
        </button>
        {#if idx < PHASES.length - 2}
          <div class="atp-step-line" class:atp-step-line--done={idx < phaseIndex}></div>
        {/if}
      {/each}
    </div>

    <!-- Body -->
    <div class="atp-body">
      {#if error}
        <div class="atp-error" role="alert">{error}</div>
      {/if}

      {#if phase === 'context'}
        <p class="atp-intro">Select documents and provide additional context for AI task generation.</p>

        {#if documents.length > 0}
          <div class="atp-section-head">
            <span class="atp-section-title">Project Documents</span>
            <span class="atp-count">{selectedDocIds.size}/{documents.length}</span>
          </div>
          <div class="atp-doc-list" role="list">
            {#each documents as doc (doc.id)}
              <label class="atp-doc-item" role="listitem">
                <input type="checkbox" checked={selectedDocIds.has(doc.id)} onchange={() => toggleDoc(doc.id)} />
                <span class="atp-doc-title">{doc.title}</span>
                <span class="atp-doc-format">{doc.format}</span>
              </label>
            {/each}
          </div>
        {:else}
          <p class="atp-muted">No project documents available. Add context below.</p>
        {/if}

        <div class="atp-section-head">
          <span class="atp-section-title">Additional Context</span>
        </div>
        <textarea
          class="atp-textarea"
          placeholder="Describe the project requirements, tech preferences, constraints…"
          bind:value={additionalContext}
          rows={5}
        ></textarea>

      {:else if phase === 'detection'}
        <p class="atp-intro">Checking if your project has an existing codebase at the output path.</p>
        <CodebaseDetector
          {detection}
          loading={detecting}
          onScan={() => { phase = 'forgemap'; void runScan(); }}
          onScaffold={handleScaffold}
        />

      {:else if phase === 'forgemap'}
        {#if scanning}
          <div class="atp-center">
            <div class="atp-spinner" aria-hidden="true"></div>
            <p>Scanning and indexing codebase…</p>
            <p class="atp-sub">This may take a moment for large projects.</p>
          </div>
        {:else if scanResult !== null}
          <div class="atp-scan-result">
            <div class="atp-scan-stat">
              <span class="atp-scan-num">{scanResult.file_count}</span>
              <span class="atp-scan-label">Files Scanned</span>
            </div>
            <div class="atp-scan-stat">
              <span class="atp-scan-num">{scanResult.indexed_count}</span>
              <span class="atp-scan-label">Indexed</span>
            </div>
            <div class="atp-scan-stat">
              <span class="atp-scan-num">{scanResult.total_exports}</span>
              <span class="atp-scan-label">Exports Found</span>
            </div>
            <div class="atp-scan-stat">
              <span class="atp-scan-num">{scanResult.languages.length}</span>
              <span class="atp-scan-label">Languages</span>
            </div>
          </div>
          <div class="atp-scan-langs">
            {#each scanResult.languages as lang}
              <span class="atp-tag">{lang}</span>
            {/each}
          </div>
          <p class="atp-muted">ForgeMap index created. This context will be used for task generation.</p>
        {:else}
          <div class="atp-center">
            <p>Ready to scan. Click "Scan & Index" to analyze your codebase.</p>
            <button class="atp-btn atp-btn--primary" type="button" onclick={runScan}>Scan & Index</button>
          </div>
        {/if}

      {:else if phase === 'generation'}
        {#if generating}
          <div class="atp-center">
            <div class="atp-spinner" aria-hidden="true"></div>
            <p>Generating tasks with AI…</p>
            <p class="atp-sub">Analyzing documentation, codebase index, and project context.</p>
          </div>
        {:else if sprintGroups.length === 0}
          <div class="atp-center">
            <p>No tasks generated yet.</p>
            <button class="atp-btn atp-btn--primary" type="button" onclick={runGeneration}>Generate Tasks</button>
          </div>
        {:else}
          <p class="atp-intro">Tasks generated. Review below or proceed to the review phase for detailed editing.</p>
          {#each sprintGroups as group (group.name)}
            <div class="atp-sprint-group">
              <div class="atp-sprint-header">
                <span class="atp-sprint-name">{group.name}</span>
                <span class="atp-sprint-goal">{group.objective}</span>
              </div>
              <div class="atp-sprint-count">{group.tasks.length} tasks</div>
            </div>
          {/each}
        {/if}

      {:else if phase === 'review'}
        <div class="atp-review-toolbar">
          <div class="atp-review-info">
            <span class="atp-review-count">{allTasks.length} tasks</span>
            <span class="atp-review-sel">{selectedTasks.length} selected</span>
          </div>
          <div class="atp-review-actions">
            <button class="atp-link" type="button" onclick={selectAll}>Select All</button>
            <button class="atp-link" type="button" onclick={selectNone}>Select None</button>
            <select class="atp-filter-select" bind:value={filterPriority}>
              <option value="all">All priorities</option>
              <option value="critical">Critical</option>
              <option value="high">High</option>
              <option value="medium">Medium</option>
              <option value="low">Low</option>
            </select>
            <button class="atp-link" type="button" onclick={runGeneration}>Regenerate</button>
          </div>
        </div>

        <!-- Dependency graph preview -->
        {#if allTasks.some((t) => t.dependsOn.length > 0)}
          <details class="atp-graph-details">
            <summary class="atp-graph-summary">Dependency Graph</summary>
            <DependencyGraph tasks={allTasks} onSelect={(id) => toggleTask(id)} />
          </details>
        {/if}

        <div class="atp-task-list" role="list">
          {#each filteredTasks as task (task.id)}
            <div class="atp-task" class:atp-task--deselected={!task.selected} role="listitem">
              <div class="atp-task-row">
                <input type="checkbox" checked={task.selected} onchange={() => toggleTask(task.id)} aria-label="Include this task" />
                <input class="atp-task-title" type="text" value={task.title}
                  oninput={(e) => {
                    const val = (e.target as HTMLInputElement).value;
                    sprintGroups = sprintGroups.map((g) => ({
                      ...g, tasks: g.tasks.map((t) => t.id === task.id ? { ...t, title: val } : t),
                    }));
                  }}
                  aria-label="Task title"
                />
                {#if task.taskType !== null}
                  {@const badge = TYPE_BADGE[task.taskType]}
                  {#if badge}
                    <span class="atp-type-badge" style="background: {badge.color}22; color: {badge.color}; border-color: {badge.color}44">{badge.label}</span>
                  {/if}
                {/if}
                <select class="atp-prio-select"
                  value={task.priority}
                  onchange={(e) => {
                    const val = (e.target as HTMLSelectElement).value;
                    sprintGroups = sprintGroups.map((g) => ({
                      ...g, tasks: g.tasks.map((t) => t.id === task.id ? { ...t, priority: val as TaskPriority } : t),
                    }));
                  }}
                  style="background: {PRIORITY_COLORS[task.priority]}; color: {PRIORITY_TEXT[task.priority]}"
                  aria-label="Priority"
                >
                  <option value="critical">Critical</option>
                  <option value="high">High</option>
                  <option value="medium">Medium</option>
                  <option value="low">Low</option>
                </select>
                <button class="atp-split-btn" type="button" onclick={() => { splitTarget = task; }} aria-label="Split task" title="Split into subtasks">
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                    <path d="M16 3h5v5M4 20L21 3M21 16v5h-5M15 15l6 6M4 4l5 5" />
                  </svg>
                </button>
              </div>
              <div class="atp-task-detail">
                <textarea
                  class="atp-task-desc"
                  value={task.description}
                  oninput={(e) => {
                    const val = (e.target as HTMLTextAreaElement).value;
                    sprintGroups = sprintGroups.map((g) => ({
                      ...g, tasks: g.tasks.map((t) => t.id === task.id ? { ...t, description: val } : t),
                    }));
                  }}
                  placeholder="Add a description…"
                  rows={2}
                  aria-label="Task description"
                ></textarea>
                <div class="atp-task-meta">
                  {#if task.labels.length > 0}
                    <div class="atp-task-labels">
                      {#each task.labels as label}
                        <span class="atp-task-label">{label}</span>
                      {/each}
                    </div>
                  {/if}
                  {#if task.dependsOn.length > 0}
                    <div class="atp-task-deps">
                      depends on: {task.dependsOn.map((id) => allTasks.find((t) => t.id === id)?.title ?? id).join(', ')}
                    </div>
                  {/if}
                </div>
              </div>
            </div>
          {/each}
        </div>

      {:else if phase === 'creating'}
        <div class="atp-center">
          <div class="atp-spinner" aria-hidden="true"></div>
          <p>Creating {selectedTasks.length} task{selectedTasks.length !== 1 ? 's' : ''}…</p>
          {#if creatingProgress > 0}
            <div class="atp-progress-bar" role="progressbar" aria-valuenow={creatingProgress} aria-valuemin={0} aria-valuemax={100}>
              <div class="atp-progress-fill" style="width: {creatingProgress}%"></div>
            </div>
            <p class="atp-sub">{creatingProgress}% complete</p>
          {/if}
        </div>
      {/if}
    </div>

    <!-- Footer -->
    <div class="atp-footer">
      {#if phase !== 'creating'}
        {#if phase !== 'context'}
          <button class="atp-btn atp-btn--ghost" type="button" onclick={handleBack}>Back</button>
        {:else}
          <button class="atp-btn atp-btn--ghost" type="button" onclick={handleClose}>Cancel</button>
        {/if}

        <button class="atp-btn atp-btn--primary" type="button" onclick={handleNext} disabled={!canProceed}>
          {#if phase === 'review'}
            Create {selectedTasks.length} Task{selectedTasks.length !== 1 ? 's' : ''}
          {:else if phase === 'forgemap' && scanResult === null && !scanning}
            Skip Scan
          {:else}
            Next
          {/if}
        </button>
      {/if}
    </div>
  </div>
</div>

{#if splitTarget !== null}
  <TaskSplitDialog
    task={splitTarget}
    onSplit={handleSplitResult}
    onClose={() => { splitTarget = null; }}
  />
{/if}

<style>
  .atp-overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.6); display: flex; align-items: center; justify-content: center; z-index: 1100; }

  .atp-modal {
    background: var(--bg-tertiary, var(--bg-surface)); border: 1px solid var(--border-default);
    border-radius: 14px; width: 780px; max-width: calc(100vw - 40px);
    max-height: calc(100vh - 60px); display: flex; flex-direction: column; overflow: hidden;
  }

  .atp-header { display: flex; align-items: center; gap: 10px; padding: 16px 22px; border-bottom: 1px solid var(--border-default); flex-shrink: 0; }
  .atp-title { font-size: 16px; font-weight: 600; color: var(--text-primary); margin: 0; }
  .atp-project-badge { font-size: 11px; font-weight: 500; padding: 2px 8px; border-radius: 10px; background: rgba(249,115,22,0.1); border: 1px solid rgba(249,115,22,0.2); color: #fdba74; }
  .atp-close { display: flex; align-items: center; justify-content: center; width: 28px; height: 28px; border: 1px solid transparent; border-radius: 6px; background: transparent; color: var(--text-tertiary); cursor: pointer; margin-left: auto; }
  .atp-close:hover { background: var(--bg-elevated); border-color: var(--border-default); color: var(--text-primary); }

  /* Stepper */
  .atp-stepper { display: flex; align-items: center; padding: 12px 22px; border-bottom: 1px solid var(--border-default); gap: 0; flex-shrink: 0; overflow-x: auto; }
  .atp-step { display: flex; align-items: center; gap: 6px; background: none; border: none; cursor: pointer; font-family: inherit; padding: 4px 8px; border-radius: 6px; transition: all 100ms ease; flex-shrink: 0; }
  .atp-step:hover:not(:disabled) { background: var(--bg-elevated); }
  .atp-step--active { background: rgba(249,115,22,0.08); }
  .atp-step--disabled { opacity: 0.4; cursor: not-allowed; }
  .atp-step-num { width: 20px; height: 20px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 10px; font-weight: 700; border: 1.5px solid var(--border-default); color: var(--text-muted); }
  .atp-step--active .atp-step-num { background: #f97316; border-color: #f97316; color: #fff; }
  .atp-step--done .atp-step-num { background: rgba(34,197,94,0.15); border-color: rgba(34,197,94,0.4); color: #22c55e; }
  .atp-step-label { font-size: 11px; font-weight: 500; color: var(--text-secondary); }
  .atp-step--active .atp-step-label { color: #fdba74; font-weight: 600; }
  .atp-step-line { flex: 1; height: 1px; background: var(--border-default); min-width: 12px; }
  .atp-step-line--done { background: rgba(34,197,94,0.4); }

  /* Body */
  .atp-body { flex: 1; overflow-y: auto; padding: 18px 22px; display: flex; flex-direction: column; gap: 12px; }
  .atp-body::-webkit-scrollbar { width: 5px; }
  .atp-body::-webkit-scrollbar-thumb { background: var(--border-default); border-radius: 3px; }

  .atp-intro { font-size: 13px; color: var(--text-secondary); margin: 0; line-height: 1.5; }
  .atp-muted { font-size: 12px; color: var(--text-muted); margin: 0; }
  .atp-sub { font-size: 11px; color: var(--text-muted); margin: 0; }
  .atp-error { font-size: 12px; color: #fca5a5; padding: 8px 12px; background: rgba(239,68,68,0.08); border: 1px solid rgba(239,68,68,0.2); border-radius: 6px; }

  .atp-center { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 10px; min-height: 160px; color: var(--text-tertiary); font-size: 13px; text-align: center; }
  .atp-center p { margin: 0; }

  .atp-spinner { width: 24px; height: 24px; border: 2px solid var(--border-default); border-top-color: #f97316; border-radius: 50%; animation: atp-spin 0.8s linear infinite; }
  @keyframes atp-spin { to { transform: rotate(360deg); } }

  .atp-progress-bar { width: 200px; height: 4px; background: var(--border-default); border-radius: 2px; overflow: hidden; }
  .atp-progress-fill { height: 100%; background: #f97316; border-radius: 2px; transition: width 200ms ease; }

  /* Context phase */
  .atp-section-head { display: flex; align-items: center; justify-content: space-between; margin-top: 4px; }
  .atp-section-title { font-size: 11px; font-weight: 600; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.5px; }
  .atp-count { font-size: 11px; color: var(--text-muted); }

  .atp-doc-list { display: flex; flex-direction: column; gap: 2px; border: 1px solid var(--border-default); border-radius: 8px; overflow: hidden; max-height: 200px; overflow-y: auto; }
  .atp-doc-item { display: flex; align-items: center; gap: 8px; padding: 8px 12px; cursor: pointer; border-bottom: 1px solid rgba(255,255,255,0.03); }
  .atp-doc-item:last-child { border-bottom: none; }
  .atp-doc-item:hover { background: var(--bg-elevated); }
  .atp-doc-item input[type="checkbox"] { width: 14px; height: 14px; accent-color: #f97316; flex-shrink: 0; }
  .atp-doc-title { flex: 1; font-size: 13px; font-weight: 500; color: var(--text-primary); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .atp-doc-format { font-size: 9px; font-weight: 500; text-transform: uppercase; padding: 2px 6px; border-radius: 3px; background: rgba(255,255,255,0.06); border: 1px solid var(--border-default); color: var(--text-tertiary); flex-shrink: 0; }

  .atp-textarea { width: 100%; padding: 10px 12px; border-radius: 8px; border: 1px solid var(--border-default); background: var(--bg-elevated); color: var(--text-secondary); font-size: 13px; font-family: inherit; line-height: 1.5; resize: vertical; box-sizing: border-box; }
  .atp-textarea:focus { outline: none; border-color: #f97316; }

  /* ForgeMap scan results */
  .atp-scan-result { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; }
  .atp-scan-stat { display: flex; flex-direction: column; align-items: center; gap: 2px; padding: 12px 8px; border-radius: 8px; background: var(--bg-elevated); border: 1px solid var(--border-default); }
  .atp-scan-num { font-size: 22px; font-weight: 700; color: #fdba74; }
  .atp-scan-label { font-size: 10px; font-weight: 500; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.3px; }
  .atp-scan-langs { display: flex; flex-wrap: wrap; gap: 4px; }
  .atp-tag { font-size: 10px; font-weight: 600; padding: 2px 7px; border-radius: 10px; background: rgba(249,115,22,0.1); border: 1px solid rgba(249,115,22,0.2); color: #fdba74; }

  /* Sprint groups (generation preview) */
  .atp-sprint-group { display: flex; align-items: center; gap: 10px; padding: 10px 14px; border-radius: 8px; border: 1px solid var(--border-default); }
  .atp-sprint-header { flex: 1; display: flex; flex-direction: column; gap: 2px; }
  .atp-sprint-name { font-size: 13px; font-weight: 600; color: var(--text-primary); }
  .atp-sprint-goal { font-size: 11px; color: var(--text-muted); }
  .atp-sprint-count { font-size: 11px; font-weight: 600; color: var(--text-secondary); flex-shrink: 0; }

  /* Review */
  .atp-review-toolbar { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 8px; }
  .atp-review-info { display: flex; align-items: center; gap: 8px; }
  .atp-review-count { font-size: 13px; font-weight: 500; color: var(--text-primary); }
  .atp-review-sel { font-size: 11px; color: var(--text-muted); background: var(--bg-elevated); border: 1px solid var(--border-default); border-radius: 10px; padding: 1px 8px; }
  .atp-review-actions { display: flex; align-items: center; gap: 8px; }
  .atp-link { background: none; border: none; color: #f97316; font-size: 12px; font-weight: 500; cursor: pointer; padding: 0; font-family: inherit; }
  .atp-link:hover { text-decoration: underline; }
  .atp-filter-select { height: 24px; padding: 0 6px; border-radius: 4px; font-size: 11px; background: var(--bg-elevated); border: 1px solid var(--border-default); color: var(--text-secondary); font-family: inherit; }

  .atp-graph-details { border: 1px solid var(--border-default); border-radius: 8px; overflow: hidden; }
  .atp-graph-summary { padding: 8px 12px; font-size: 12px; font-weight: 500; color: var(--text-secondary); cursor: pointer; }
  .atp-graph-summary:hover { background: var(--bg-elevated); }

  .atp-task-list { display: flex; flex-direction: column; gap: 3px; }
  .atp-task { border: 1px solid var(--border-default); border-radius: 8px; overflow: hidden; transition: opacity 150ms ease; }
  .atp-task--deselected { opacity: 0.4; }
  .atp-task-row { display: flex; align-items: center; gap: 8px; padding: 8px 10px; }
  .atp-task-row input[type="checkbox"] { width: 14px; height: 14px; accent-color: #f97316; flex-shrink: 0; }
  .atp-task-title { flex: 1; min-width: 0; height: 26px; padding: 0 6px; border: 1px solid transparent; border-radius: 4px; background: transparent; color: var(--text-primary); font-size: 12px; font-weight: 500; font-family: inherit; }
  .atp-task-title:hover { border-color: var(--border-default); background: var(--bg-elevated); }
  .atp-task-title:focus { outline: none; border-color: #f97316; background: var(--bg-elevated); }

  .atp-type-badge { font-size: 9px; font-weight: 700; padding: 1px 5px; border-radius: 3px; border: 1px solid; flex-shrink: 0; letter-spacing: 0.3px; }

  .atp-prio-select { height: 22px; padding: 0 6px; border-radius: 11px; font-size: 10px; font-weight: 600; border: 1px solid transparent; cursor: pointer; font-family: inherit; text-transform: capitalize; flex-shrink: 0; }
  .atp-prio-select:focus { outline: none; }

  .atp-split-btn { display: flex; align-items: center; justify-content: center; width: 24px; height: 24px; border: none; border-radius: 4px; background: transparent; color: var(--text-muted); cursor: pointer; flex-shrink: 0; }
  .atp-split-btn:hover { background: var(--bg-elevated); color: var(--text-primary); }

  .atp-task-detail { padding: 0 10px 8px 36px; display: flex; flex-direction: column; gap: 4px; }
  .atp-task-desc { width: 100%; padding: 4px 6px; border-radius: 4px; border: 1px solid transparent; background: transparent; color: var(--text-secondary); font-size: 11px; font-family: inherit; line-height: 1.4; resize: vertical; box-sizing: border-box; }
  .atp-task-desc:hover { border-color: var(--border-default); background: var(--bg-elevated); }
  .atp-task-desc:focus { outline: none; border-color: #f97316; background: var(--bg-elevated); }
  .atp-task-meta { display: flex; flex-wrap: wrap; align-items: center; gap: 6px; }
  .atp-task-labels { display: flex; flex-wrap: wrap; gap: 3px; }
  .atp-task-label { font-size: 9px; font-weight: 500; padding: 1px 5px; border-radius: 3px; background: rgba(255,255,255,0.06); border: 1px solid var(--border-default); color: var(--text-tertiary); }
  .atp-task-deps { font-size: 10px; color: var(--text-muted); }

  /* Footer */
  .atp-footer { display: flex; align-items: center; justify-content: flex-end; gap: 8px; padding: 14px 22px; border-top: 1px solid var(--border-default); flex-shrink: 0; }

  .atp-btn { height: 32px; padding: 0 14px; border-radius: 6px; font-size: 13px; font-weight: 500; cursor: pointer; font-family: inherit; transition: all 100ms ease; }
  .atp-btn--ghost { background: transparent; border: 1px solid var(--border-default); color: var(--text-secondary); }
  .atp-btn--ghost:hover:not(:disabled) { background: var(--bg-elevated); color: var(--text-primary); }
  .atp-btn--primary { background: rgba(249,115,22,0.12); border: 1px solid rgba(249,115,22,0.35); color: #fdba74; }
  .atp-btn--primary:hover:not(:disabled) { background: rgba(249,115,22,0.2); border-color: rgba(249,115,22,0.5); }
  .atp-btn:disabled { opacity: 0.5; cursor: not-allowed; }

  @media (prefers-reduced-motion: reduce) {
    .atp-spinner { animation: none; }
  }
</style>
