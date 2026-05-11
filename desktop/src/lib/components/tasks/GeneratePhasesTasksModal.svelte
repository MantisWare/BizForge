<!-- src/lib/components/tasks/GeneratePhasesTasksModal.svelte -->
<script lang="ts">
  import { sessions, messages, phases as phasesApi, tasks as tasksApi } from '$api/client';
  import { connectSSE } from '$api/sse';
  import type { Document, TaskPriority, StreamEvent } from '$api/types';
  import { phasesStore } from '$lib/stores/phases.svelte';
  import { tasksStore } from '$lib/stores/tasks.svelte';
  import { agentsStore } from '$lib/stores/agents.svelte';
  import { workspaceStore } from '$lib/stores/workspace.svelte';
  import { settingsStore } from '$lib/stores/settings.svelte';

  interface Props {
    projectId: string;
    projectName: string;
    outputPath: string | null;
    documents: Document[];
    onClose: () => void;
    onCreated: () => void;
  }

  let {
    projectId,
    projectName,
    outputPath,
    documents,
    onClose,
    onCreated,
  }: Props = $props();

  interface ProposedTask {
    selected: boolean;
    title: string;
    description: string;
    priority: TaskPriority;
    task_type: string;
  }

  interface ProposedPhase {
    selected: boolean;
    title: string;
    description: string;
    tasks: ProposedTask[];
    expanded: boolean;
  }

  type ModalStep = 'select' | 'analyzing' | 'review' | 'creating';

  let step = $state<ModalStep>('select');
  // svelte-ignore state_referenced_locally
  let selectedDocIds = $state<Set<string>>(new Set(documents.map((d: Document) => d.id)));
  let additionalContext = $state('');
  let proposedPhases = $state<ProposedPhase[]>([]);
  let error = $state<string | null>(null);
  let creatingProgress = $state(0);
  let creatingTotal = $state(0);
  let streamController = $state<{ abort: () => void } | null>(null);

  const agents = $derived(agentsStore.agents);

  $effect(() => {
    if (agents.length === 0) {
      void agentsStore.fetchAgents(workspaceStore.activeWorkspaceId ?? undefined);
    }
  });

  const selectedDocs = $derived(
    documents.filter((d) => selectedDocIds.has(d.id)),
  );

  const selectedTaskCount = $derived(
    proposedPhases
      .filter((p) => p.selected)
      .reduce((sum, p) => sum + p.tasks.filter((t) => t.selected).length, 0),
  );

  const selectedPhaseCount = $derived(
    proposedPhases.filter((p) => p.selected).length,
  );

  const totalPhaseCount = $derived(proposedPhases.length);
  const totalTaskCount = $derived(
    proposedPhases.reduce((sum, p) => sum + p.tasks.length, 0),
  );

  function toggleDoc(docId: string) {
    const next = new Set(selectedDocIds);
    if (next.has(docId)) {
      next.delete(docId);
    } else {
      next.add(docId);
    }
    selectedDocIds = next;
  }

  function toggleAllDocs() {
    if (selectedDocIds.size === documents.length) {
      selectedDocIds = new Set();
    } else {
      selectedDocIds = new Set(documents.map((d) => d.id));
    }
  }

  function togglePhase(phaseIdx: number) {
    proposedPhases = proposedPhases.map((p, i) =>
      i === phaseIdx ? { ...p, selected: !p.selected } : p,
    );
  }

  function togglePhaseExpand(phaseIdx: number) {
    proposedPhases = proposedPhases.map((p, i) =>
      i === phaseIdx ? { ...p, expanded: !p.expanded } : p,
    );
  }

  function toggleTask(phaseIdx: number, taskIdx: number) {
    proposedPhases = proposedPhases.map((p, pi) =>
      pi === phaseIdx
        ? { ...p, tasks: p.tasks.map((t, ti) => ti === taskIdx ? { ...t, selected: !t.selected } : t) }
        : p,
    );
  }

  function selectAllPhasesTasks() {
    proposedPhases = proposedPhases.map((p) => ({
      ...p,
      selected: true,
      tasks: p.tasks.map((t) => ({ ...t, selected: true })),
    }));
  }

  function selectNonePhasesTasks() {
    proposedPhases = proposedPhases.map((p) => ({
      ...p,
      selected: false,
      tasks: p.tasks.map((t) => ({ ...t, selected: false })),
    }));
  }

  function selectAllTasksInPhase(phaseIdx: number) {
    proposedPhases = proposedPhases.map((p, i) =>
      i === phaseIdx
        ? { ...p, tasks: p.tasks.map((t) => ({ ...t, selected: true })) }
        : p,
    );
  }

  function selectNoneTasksInPhase(phaseIdx: number) {
    proposedPhases = proposedPhases.map((p, i) =>
      i === phaseIdx
        ? { ...p, tasks: p.tasks.map((t) => ({ ...t, selected: false })) }
        : p,
    );
  }

  function updatePhaseTitle(phaseIdx: number, value: string) {
    proposedPhases = proposedPhases.map((p, i) =>
      i === phaseIdx ? { ...p, title: value } : p,
    );
  }

  function updateTaskTitle(phaseIdx: number, taskIdx: number, value: string) {
    proposedPhases = proposedPhases.map((p, pi) =>
      pi === phaseIdx
        ? { ...p, tasks: p.tasks.map((t, ti) => ti === taskIdx ? { ...t, title: value } : t) }
        : p,
    );
  }

  function buildPrompt(): string {
    const parts: string[] = [];
    parts.push(`Analyze the following project documentation for "${projectName}" and generate implementation phases.`);
    parts.push('Each phase should represent a logical stage of development.');
    parts.push('Each phase contains multiple tasks that can be worked on.');
    parts.push('');

    if (additionalContext.trim()) {
      parts.push('Additional context / instructions:');
      parts.push(additionalContext.trim());
      parts.push('');
    }

    parts.push('Output ONLY valid JSON in this exact format:');
    parts.push('{');
    parts.push('  "phases": [');
    parts.push('    {');
    parts.push('      "title": "Phase name",');
    parts.push('      "description": "What this phase accomplishes",');
    parts.push('      "tasks": [');
    parts.push('        {');
    parts.push('          "title": "Task title",');
    parts.push('          "description": "Detailed task description",');
    parts.push('          "priority": "high|medium|low",');
    parts.push('          "task_type": "prerequisite|scaffold|feature|subtask|validation"');
    parts.push('        }');
    parts.push('      ]');
    parts.push('    }');
    parts.push('  ]');
    parts.push('}');
    parts.push('');
    parts.push('--- Project Documentation ---');
    for (const doc of selectedDocs) {
      parts.push('');
      parts.push(`### ${doc.title} (${doc.path})`);
      parts.push(doc.content);
    }
    return parts.join('\n');
  }

  function parseProposedPhases(raw: string): ProposedPhase[] {
    const jsonMatch = raw.match(/\{[\s\S]*"phases"[\s\S]*\}/);
    if (jsonMatch === null) return [];
    try {
      const parsed = JSON.parse(jsonMatch[0]) as {
        phases: Array<{
          title: string;
          description?: string;
          tasks?: Array<{
            title: string;
            description?: string;
            priority?: string;
            task_type?: string;
          }>;
        }>;
      };
      if (!Array.isArray(parsed.phases)) return [];
      return parsed.phases.map((phase) => ({
        selected: true,
        title: phase.title ?? 'Untitled Phase',
        description: phase.description ?? '',
        expanded: true,
        tasks: Array.isArray(phase.tasks)
          ? phase.tasks.map((t) => ({
              selected: true,
              title: t.title ?? 'Untitled Task',
              description: t.description ?? '',
              priority: validatePriority(t.priority),
              task_type: t.task_type ?? 'feature',
            }))
          : [],
      }));
    } catch {
      return [];
    }
  }

  function validatePriority(p: string | undefined): TaskPriority {
    if (p === 'low' || p === 'medium' || p === 'high' || p === 'critical') return p;
    return 'medium';
  }

  const PRIORITY_COLORS: Record<TaskPriority, string> = {
    critical: 'rgba(239, 68, 68, 0.15)',
    high: 'rgba(249, 115, 22, 0.12)',
    medium: 'rgba(234, 179, 8, 0.1)',
    low: 'rgba(107, 114, 128, 0.1)',
  };

  const PRIORITY_TEXT: Record<TaskPriority, string> = {
    critical: '#fca5a5',
    high: '#fdba74',
    medium: '#fde68a',
    low: '#9ca3af',
  };

  async function handleAnalyze() {
    if (selectedDocs.length === 0) return;
    error = null;
    step = 'analyzing';

    try {
      const agentId = agents[0]?.id;
      if (agentId === undefined) {
        error = 'No agents available. Please add an agent to your workspace first.';
        step = 'select';
        return;
      }
      const session = await sessions.create({
        agent_id: agentId,
        title: `Phase & task generation: ${projectName}`,
      });

      const prompt = buildPrompt();
      let buffer = '';

      const ctrl = connectSSE(
        `/sessions/${session.id}/stream`,
        {
          onEvent: (event: StreamEvent) => {
            if (event.type === 'streaming_token') {
              buffer += (event as { delta: string }).delta;
            } else if (event.type === 'done') {
              proposedPhases = parseProposedPhases(buffer);
              step = 'review';
              if (proposedPhases.length === 0) {
                error = 'No phases could be extracted. Try providing more detailed documentation.';
              }
            } else if (event.type === 'error') {
              error = (event as { message?: string }).message ?? 'Analysis failed';
              step = 'select';
            }
          },
          onError: (err: Error) => {
            error = err.message;
            step = 'select';
          },
          onDone: () => {
            if (step === 'analyzing') {
              proposedPhases = parseProposedPhases(buffer);
              step = 'review';
              if (proposedPhases.length === 0) {
                error = 'No phases could be extracted. Try providing more detailed documentation.';
              }
            }
          },
        },
      );

      streamController = ctrl;

      const model = settingsStore.data.default_model || undefined;
      await messages.send({
        session_id: session.id,
        content: prompt,
        model,
      });
    } catch (err) {
      error = (err as Error).message;
      step = 'select';
    }
  }

  async function handleCreate() {
    const phasesToCreate = proposedPhases.filter((p) => p.selected);
    if (phasesToCreate.length === 0) return;
    step = 'creating';
    creatingProgress = 0;
    const totalItems = phasesToCreate.reduce(
      (sum, p) => sum + 1 + p.tasks.filter((t) => t.selected).length, 0,
    );
    creatingTotal = totalItems;
    error = null;

    try {
      const wsId = workspaceStore.activeWorkspaceId ?? undefined;

      for (const proposedPhase of phasesToCreate) {
        const createdPhase = await phasesApi.create(projectId, {
          title: proposedPhase.title,
          description: proposedPhase.description,
          status: 'planning',
          workspace_id: wsId,
        });
        creatingProgress++;

        const selectedTasks = proposedPhase.tasks.filter((t) => t.selected);
        for (const proposedTask of selectedTasks) {
          await tasksApi.create({
            title: proposedTask.title,
            description: proposedTask.description,
            priority: proposedTask.priority,
            task_type: proposedTask.task_type,
            phase_id: createdPhase.id,
            project_id: projectId,
            status: 'backlog',
            workspace_id: wsId,
          });
          creatingProgress++;
        }
      }

      await phasesStore.fetchPhases(projectId);
      await tasksStore.fetchTasks(wsId);
      onCreated();
    } catch (err) {
      error = (err as Error).message;
      step = 'review';
    }
  }

  function handleBack() {
    if (streamController !== null) {
      streamController.abort();
      streamController = null;
    }
    proposedPhases = [];
    error = null;
    step = 'select';
  }

  function handleClose() {
    if (streamController !== null) {
      streamController.abort();
      streamController = null;
    }
    onClose();
  }
</script>

<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
<div
  class="gpt-overlay"
  role="dialog"
  aria-modal="true"
  aria-label="Generate phases and tasks"
  tabindex="-1"
  onclick={(e) => { if (e.target === e.currentTarget) handleClose(); }}
  onkeydown={(e) => { if (e.key === 'Escape') handleClose(); }}
>
  <div class="gpt-modal">
    <!-- Header -->
    <div class="gpt-header">
      <div class="gpt-header-left">
        <h2 class="gpt-title">
          {#if step === 'select'}
            Generate Phases &amp; Tasks
          {:else if step === 'analyzing'}
            Analyzing Documentation…
          {:else if step === 'creating'}
            Creating Phases &amp; Tasks…
          {:else}
            Review Proposed Phases &amp; Tasks
          {/if}
        </h2>
        <div class="gpt-steps">
          <span class="gpt-step" class:gpt-step--active={step === 'select'} class:gpt-step--done={step !== 'select'}>1. Select</span>
          <span class="gpt-step-sep" aria-hidden="true">→</span>
          <span class="gpt-step" class:gpt-step--active={step === 'analyzing'} class:gpt-step--done={step === 'review' || step === 'creating'}>2. Analyze</span>
          <span class="gpt-step-sep" aria-hidden="true">→</span>
          <span class="gpt-step" class:gpt-step--active={step === 'review'} class:gpt-step--done={step === 'creating'}>3. Review</span>
          <span class="gpt-step-sep" aria-hidden="true">→</span>
          <span class="gpt-step" class:gpt-step--active={step === 'creating'}>4. Create</span>
        </div>
      </div>
      <button class="gpt-close" type="button" onclick={handleClose} aria-label="Close">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <path d="M18 6L6 18M6 6l12 12" />
        </svg>
      </button>
    </div>

    <!-- Body -->
    <div class="gpt-body">

      {#if step === 'select'}
        <p class="gpt-intro">
          Select project documents to include as context. The AI will analyze them and propose implementation phases with grouped tasks.
        </p>

        <div class="gpt-doc-controls">
          <button class="gpt-link-btn" type="button" onclick={toggleAllDocs}>
            {selectedDocIds.size === documents.length ? 'Deselect All' : 'Select All'}
          </button>
          <span class="gpt-doc-count">{selectedDocIds.size} of {documents.length} selected</span>
        </div>

        <div class="gpt-doc-list" role="list" aria-label="Documents to include">
          {#each documents as doc (doc.id)}
            <label class="gpt-doc-item" role="listitem">
              <input
                type="checkbox"
                checked={selectedDocIds.has(doc.id)}
                onchange={() => toggleDoc(doc.id)}
              />
              <div class="gpt-doc-item-info">
                <span class="gpt-doc-item-title">{doc.title}</span>
                <span class="gpt-doc-item-path">{doc.path}</span>
              </div>
              <span class="gpt-doc-item-format">{doc.format}</span>
            </label>
          {/each}
        </div>

        <div class="gpt-context-section">
          <label class="gpt-context-label" for="gpt-additional-context">
            Additional context <span class="gpt-optional">(optional)</span>
          </label>
          <textarea
            id="gpt-additional-context"
            class="gpt-context-textarea"
            placeholder="Extra instructions, project goals, or constraints for the AI…"
            bind:value={additionalContext}
            rows={3}
          ></textarea>
        </div>

        <div class="gpt-model-info">
          <span class="gpt-model-label">Model:</span>
          <code class="gpt-model-badge">{settingsStore.data.default_model || 'Not set'}</code>
          <span class="gpt-model-hint">Change in Settings → AI Providers</span>
        </div>

      {:else if step === 'analyzing'}
        <div class="gpt-analyzing">
          <div class="gpt-spinner" aria-hidden="true"></div>
          <p>Reading {selectedDocs.length} document{selectedDocs.length !== 1 ? 's' : ''} and generating phases with tasks…</p>
          <p class="gpt-analyzing-sub">This may take a moment depending on document size.</p>
        </div>

      {:else if step === 'creating'}
        <div class="gpt-analyzing">
          <div class="gpt-spinner" aria-hidden="true"></div>
          <p>Creating {selectedPhaseCount} phases and {selectedTaskCount} tasks…</p>
          {#if creatingTotal > 0}
            <div class="gpt-create-progress">
              <div class="gpt-progress-track" role="progressbar" aria-valuenow={creatingProgress} aria-valuemin={0} aria-valuemax={creatingTotal}>
                <div class="gpt-progress-fill" style="width: {Math.round((creatingProgress / creatingTotal) * 100)}%"></div>
              </div>
              <span class="gpt-progress-text">{creatingProgress} / {creatingTotal}</span>
            </div>
          {/if}
        </div>

      {:else}
        {#if error}
          <div class="gpt-error" role="alert">{error}</div>
        {/if}

        {#if proposedPhases.length > 0}
          <div class="gpt-review-toolbar">
            <div class="gpt-review-info">
              <span class="gpt-review-count">{totalPhaseCount} phases, {totalTaskCount} tasks</span>
              <span class="gpt-review-selected">{selectedPhaseCount} phases / {selectedTaskCount} tasks selected</span>
            </div>
            <div class="gpt-review-actions">
              <button class="gpt-link-btn" type="button" onclick={selectAllPhasesTasks}>Select All</button>
              <button class="gpt-link-btn" type="button" onclick={selectNonePhasesTasks}>Select None</button>
            </div>
          </div>

          <div class="gpt-phases" role="list" aria-label="Proposed phases">
            {#each proposedPhases as phase, phaseIdx (phaseIdx)}
              <div
                class="gpt-phase-card"
                class:gpt-phase-card--deselected={!phase.selected}
                role="listitem"
              >
                <div class="gpt-phase-header">
                  <input
                    type="checkbox"
                    checked={phase.selected}
                    onchange={() => togglePhase(phaseIdx)}
                    aria-label="Include this phase"
                  />
                  <button
                    class="gpt-expand-btn"
                    type="button"
                    onclick={() => togglePhaseExpand(phaseIdx)}
                    aria-expanded={phase.expanded}
                    aria-label="Toggle phase details"
                  >
                    <svg
                      width="12" height="12" viewBox="0 0 24 24" fill="none"
                      stroke="currentColor" stroke-width="2" aria-hidden="true"
                      style="transform: rotate({phase.expanded ? 180 : 0}deg); transition: transform 150ms ease"
                    >
                      <polyline points="6 9 12 15 18 9" />
                    </svg>
                  </button>
                  <input
                    class="gpt-phase-title-input"
                    type="text"
                    value={phase.title}
                    oninput={(e) => updatePhaseTitle(phaseIdx, (e.target as HTMLInputElement).value)}
                    aria-label="Phase title"
                  />
                  <span class="gpt-task-count-badge" aria-label="{phase.tasks.length} tasks">
                    {phase.tasks.filter((t) => t.selected).length}/{phase.tasks.length} tasks
                  </span>
                </div>

                {#if phase.expanded}
                  <div class="gpt-phase-body">
                    {#if phase.description}
                      <p class="gpt-phase-desc">{phase.description}</p>
                    {/if}

                    <div class="gpt-phase-task-controls">
                      <button class="gpt-link-btn gpt-link-btn--sm" type="button" onclick={() => selectAllTasksInPhase(phaseIdx)}>All</button>
                      <button class="gpt-link-btn gpt-link-btn--sm" type="button" onclick={() => selectNoneTasksInPhase(phaseIdx)}>None</button>
                    </div>

                    <div class="gpt-task-list" role="list" aria-label="Tasks in {phase.title}">
                      {#each phase.tasks as task, taskIdx (taskIdx)}
                        <div class="gpt-task-row" class:gpt-task-row--deselected={!task.selected} role="listitem">
                          <input
                            type="checkbox"
                            checked={task.selected}
                            onchange={() => toggleTask(phaseIdx, taskIdx)}
                            aria-label="Include this task"
                          />
                          <input
                            class="gpt-task-title-input"
                            type="text"
                            value={task.title}
                            oninput={(e) => updateTaskTitle(phaseIdx, taskIdx, (e.target as HTMLInputElement).value)}
                            aria-label="Task title"
                          />
                          <span
                            class="gpt-priority-badge"
                            style="background: {PRIORITY_COLORS[task.priority]}; color: {PRIORITY_TEXT[task.priority]}"
                          >
                            {task.priority}
                          </span>
                          <span class="gpt-type-badge">{task.task_type}</span>
                        </div>
                      {/each}
                    </div>
                  </div>
                {/if}
              </div>
            {/each}
          </div>
        {:else if error === null}
          <div class="gpt-analyzing">
            <p>No phases were proposed. The documentation may be too brief.</p>
          </div>
        {/if}
      {/if}
    </div>

    <!-- Footer -->
    <div class="gpt-footer">
      {#if step === 'select'}
        <button class="gpt-btn-ghost" type="button" onclick={handleClose}>Cancel</button>
        <button
          class="gpt-btn-primary"
          type="button"
          onclick={handleAnalyze}
          disabled={selectedDocIds.size === 0}
        >
          Generate from {selectedDocIds.size} Document{selectedDocIds.size !== 1 ? 's' : ''}
        </button>
      {:else if step === 'analyzing'}
        <button class="gpt-btn-ghost" type="button" onclick={handleClose}>Cancel</button>
      {:else if step === 'creating'}
        <!-- no actions during creation -->
      {:else}
        <button class="gpt-btn-ghost" type="button" onclick={handleBack}>Back</button>
        <button
          class="gpt-btn-primary"
          type="button"
          onclick={handleCreate}
          disabled={selectedPhaseCount === 0}
        >
          Create {selectedPhaseCount} Phase{selectedPhaseCount !== 1 ? 's' : ''} &amp; {selectedTaskCount} Task{selectedTaskCount !== 1 ? 's' : ''}
        </button>
      {/if}
    </div>
  </div>
</div>

<style>
  .gpt-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0,0,0,0.6);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1100;
  }

  .gpt-modal {
    background: var(--bg-tertiary, var(--bg-surface));
    border: 1px solid var(--border-default);
    border-radius: 14px;
    width: 760px;
    max-width: calc(100vw - 40px);
    max-height: calc(100vh - 80px);
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }

  .gpt-header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    padding: 18px 22px 14px;
    border-bottom: 1px solid var(--border-default);
    flex-shrink: 0;
    gap: 12px;
  }

  .gpt-header-left {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .gpt-title {
    font-size: 16px;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0;
  }

  .gpt-steps {
    display: flex;
    align-items: center;
    gap: 6px;
  }

  .gpt-step {
    font-size: 10px;
    font-weight: 500;
    color: var(--text-muted);
    padding: 2px 6px;
    border-radius: 3px;
    transition: all 120ms ease;
  }

  .gpt-step--active {
    color: #fdba74;
    background: rgba(249, 115, 22, 0.1);
    font-weight: 600;
  }

  .gpt-step--done {
    color: rgba(34, 197, 94, 0.7);
  }

  .gpt-step-sep {
    font-size: 9px;
    color: var(--text-muted);
    opacity: 0.5;
  }

  .gpt-close {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 28px;
    height: 28px;
    border: 1px solid transparent;
    border-radius: 6px;
    background: transparent;
    color: var(--text-tertiary);
    cursor: pointer;
    transition: all 100ms ease;
    flex-shrink: 0;
  }
  .gpt-close:hover { background: var(--bg-elevated); border-color: var(--border-default); color: var(--text-primary); }

  .gpt-body {
    flex: 1;
    overflow-y: auto;
    padding: 20px 22px;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  .gpt-body::-webkit-scrollbar { width: 5px; }
  .gpt-body::-webkit-scrollbar-thumb { background: var(--border-default); border-radius: 3px; }

  .gpt-intro {
    font-size: 13px;
    color: var(--text-secondary);
    margin: 0;
    line-height: 1.5;
  }

  .gpt-doc-controls {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }

  .gpt-link-btn {
    background: none;
    border: none;
    color: #f97316;
    font-size: 12px;
    font-weight: 500;
    cursor: pointer;
    padding: 0;
    font-family: inherit;
  }
  .gpt-link-btn:hover { text-decoration: underline; }
  .gpt-link-btn--sm { font-size: 10px; }

  .gpt-doc-count {
    font-size: 11px;
    color: var(--text-muted);
  }

  .gpt-doc-list {
    display: flex;
    flex-direction: column;
    gap: 2px;
    border: 1px solid var(--border-default);
    border-radius: 8px;
    overflow: hidden;
  }

  .gpt-doc-item {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 10px 14px;
    cursor: pointer;
    transition: background 80ms ease;
    border-bottom: 1px solid var(--border-subtle, rgba(255,255,255,0.03));
  }
  .gpt-doc-item:last-child { border-bottom: none; }
  .gpt-doc-item:hover { background: var(--bg-elevated); }

  .gpt-doc-item input[type="checkbox"] {
    width: 14px;
    height: 14px;
    accent-color: #f97316;
    flex-shrink: 0;
  }

  .gpt-doc-item-info {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .gpt-doc-item-title {
    font-size: 13px;
    font-weight: 500;
    color: var(--text-primary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .gpt-doc-item-path {
    font-size: 11px;
    color: var(--text-muted);
    font-family: var(--font-mono, monospace);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .gpt-doc-item-format {
    font-size: 9px;
    font-weight: 500;
    text-transform: uppercase;
    padding: 2px 6px;
    border-radius: 3px;
    background: rgba(255,255,255,0.06);
    border: 1px solid var(--border-default);
    color: var(--text-tertiary);
    flex-shrink: 0;
  }

  /* Context textarea */
  .gpt-context-section {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .gpt-context-label {
    font-size: 12px;
    font-weight: 500;
    color: var(--text-secondary);
  }

  .gpt-optional {
    font-weight: 400;
    color: var(--text-muted);
  }

  .gpt-context-textarea {
    width: 100%;
    padding: 10px 12px;
    border-radius: 8px;
    border: 1px solid var(--border-default);
    background: var(--bg-elevated);
    color: var(--text-primary);
    font-size: 13px;
    font-family: inherit;
    line-height: 1.5;
    resize: vertical;
    box-sizing: border-box;
  }
  .gpt-context-textarea:focus { outline: none; border-color: #f97316; }
  .gpt-context-textarea::placeholder { color: var(--text-muted); }

  /* Analyzing state */
  .gpt-analyzing {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 12px;
    min-height: 200px;
    color: var(--text-tertiary);
    font-size: 13px;
    text-align: center;
  }

  .gpt-analyzing p { margin: 0; }
  .gpt-analyzing-sub { font-size: 11px; color: var(--text-muted); }

  .gpt-spinner {
    width: 24px;
    height: 24px;
    border: 2px solid var(--border-default);
    border-top-color: #f97316;
    border-radius: 50%;
    animation: gpt-spin 0.8s linear infinite;
  }

  @keyframes gpt-spin { to { transform: rotate(360deg); } }

  /* Creation progress */
  .gpt-create-progress {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 6px;
    width: 280px;
  }

  .gpt-progress-track {
    width: 100%;
    height: 6px;
    border-radius: 3px;
    background: var(--bg-elevated);
    overflow: hidden;
  }

  .gpt-progress-fill {
    height: 100%;
    border-radius: 3px;
    background: #f97316;
    transition: width 200ms ease;
  }

  .gpt-progress-text {
    font-size: 11px;
    color: var(--text-muted);
  }

  /* Error */
  .gpt-error {
    font-size: 12px;
    color: #fca5a5;
    padding: 8px 12px;
    background: rgba(239, 68, 68, 0.08);
    border: 1px solid rgba(239, 68, 68, 0.2);
    border-radius: 6px;
  }

  /* Review toolbar */
  .gpt-review-toolbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    padding-bottom: 4px;
  }

  .gpt-review-info {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .gpt-review-count {
    font-size: 13px;
    font-weight: 500;
    color: var(--text-primary);
  }

  .gpt-review-selected {
    font-size: 11px;
    color: var(--text-muted);
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    border-radius: 10px;
    padding: 1px 8px;
  }

  .gpt-review-actions {
    display: flex;
    gap: 10px;
  }

  /* Phase cards */
  .gpt-phases {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .gpt-phase-card {
    border: 1px solid var(--border-default);
    border-radius: 10px;
    overflow: hidden;
    transition: opacity 150ms ease;
  }

  .gpt-phase-card--deselected {
    opacity: 0.4;
  }

  .gpt-phase-header {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 10px 14px;
    background: var(--bg-elevated);
    border-bottom: 1px solid var(--border-subtle, rgba(255,255,255,0.03));
  }

  .gpt-phase-header input[type="checkbox"] {
    width: 14px;
    height: 14px;
    accent-color: #f97316;
    flex-shrink: 0;
  }

  .gpt-expand-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 22px;
    height: 22px;
    border: none;
    border-radius: 4px;
    background: transparent;
    color: var(--text-muted);
    cursor: pointer;
    flex-shrink: 0;
  }
  .gpt-expand-btn:hover { background: var(--bg-tertiary); color: var(--text-primary); }

  .gpt-phase-title-input {
    flex: 1;
    min-width: 0;
    height: 28px;
    padding: 0 8px;
    border: 1px solid transparent;
    border-radius: 4px;
    background: transparent;
    color: var(--text-primary);
    font-size: 14px;
    font-weight: 600;
    font-family: inherit;
    transition: border-color 100ms ease, background 100ms ease;
  }
  .gpt-phase-title-input:hover { border-color: var(--border-default); background: var(--bg-surface); }
  .gpt-phase-title-input:focus { outline: none; border-color: #f97316; background: var(--bg-surface); }

  .gpt-task-count-badge {
    font-size: 10px;
    font-weight: 500;
    color: var(--text-tertiary);
    background: rgba(255,255,255,0.06);
    border: 1px solid var(--border-default);
    border-radius: 10px;
    padding: 2px 8px;
    white-space: nowrap;
    flex-shrink: 0;
  }

  .gpt-phase-body {
    padding: 10px 14px 14px;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .gpt-phase-desc {
    font-size: 12px;
    color: var(--text-tertiary);
    margin: 0;
    line-height: 1.5;
    padding-left: 34px;
  }

  .gpt-phase-task-controls {
    display: flex;
    gap: 8px;
    padding-left: 34px;
  }

  /* Task rows inside a phase */
  .gpt-task-list {
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding-left: 20px;
  }

  .gpt-task-row {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 10px;
    border-radius: 6px;
    transition: opacity 100ms ease, background 80ms ease;
  }
  .gpt-task-row:hover { background: var(--bg-elevated); }

  .gpt-task-row--deselected {
    opacity: 0.4;
  }

  .gpt-task-row input[type="checkbox"] {
    width: 13px;
    height: 13px;
    accent-color: #f97316;
    flex-shrink: 0;
  }

  .gpt-task-title-input {
    flex: 1;
    min-width: 0;
    height: 26px;
    padding: 0 6px;
    border: 1px solid transparent;
    border-radius: 4px;
    background: transparent;
    color: var(--text-primary);
    font-size: 12px;
    font-weight: 500;
    font-family: inherit;
    transition: border-color 100ms ease, background 100ms ease;
  }
  .gpt-task-title-input:hover { border-color: var(--border-default); background: var(--bg-surface); }
  .gpt-task-title-input:focus { outline: none; border-color: #f97316; background: var(--bg-surface); }

  .gpt-priority-badge {
    font-size: 9px;
    font-weight: 600;
    padding: 2px 6px;
    border-radius: 8px;
    text-transform: capitalize;
    white-space: nowrap;
    flex-shrink: 0;
  }

  .gpt-type-badge {
    font-size: 9px;
    font-weight: 500;
    padding: 2px 6px;
    border-radius: 8px;
    background: rgba(99, 102, 241, 0.08);
    color: #a5b4fc;
    white-space: nowrap;
    flex-shrink: 0;
  }

  /* Model info */
  .gpt-model-info {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-top: 12px;
    padding-top: 12px;
    border-top: 1px solid var(--border-default);
  }

  .gpt-model-label {
    font-size: 12px;
    font-weight: 500;
    color: var(--text-secondary);
  }

  .gpt-model-badge {
    font-family: var(--font-mono, monospace);
    font-size: 11px;
    padding: 2px 8px;
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    border-radius: 4px;
    color: var(--text-secondary);
  }

  .gpt-model-hint {
    font-size: 10px;
    color: var(--text-muted);
  }

  /* Footer */
  .gpt-footer {
    display: flex;
    align-items: center;
    justify-content: flex-end;
    gap: 8px;
    padding: 14px 22px;
    border-top: 1px solid var(--border-default);
    flex-shrink: 0;
  }

  .gpt-btn-ghost, .gpt-btn-primary {
    height: 32px;
    padding: 0 14px;
    border-radius: 6px;
    font-size: 13px;
    font-weight: 500;
    cursor: pointer;
    transition: all 100ms ease;
    font-family: inherit;
  }

  .gpt-btn-ghost {
    background: transparent;
    border: 1px solid var(--border-default);
    color: var(--text-secondary);
  }
  .gpt-btn-ghost:hover:not(:disabled) { background: var(--bg-elevated); color: var(--text-primary); }

  .gpt-btn-primary {
    background: rgba(249, 115, 22, 0.12);
    border: 1px solid rgba(249, 115, 22, 0.35);
    color: #fdba74;
  }
  .gpt-btn-primary:hover:not(:disabled) { background: rgba(249, 115, 22, 0.2); border-color: rgba(249, 115, 22, 0.5); }

  .gpt-btn-ghost:disabled, .gpt-btn-primary:disabled { opacity: 0.5; cursor: not-allowed; }

  @media (prefers-reduced-motion: reduce) {
    .gpt-spinner { animation: none; }
  }
</style>
