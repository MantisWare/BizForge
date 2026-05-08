<!-- src/lib/components/wizard/steps/Step6TaskGeneration.svelte -->
<script lang="ts">
  import { wizardStore } from '$lib/stores/wizard.svelte';
  import { settingsStore } from '$lib/stores/settings.svelte';
  import { agentsStore } from '$lib/stores/agents.svelte';
  import { sessions, isMockEnabled } from '$api/client';
  import { streamMessage } from '$api/sse';
  import type { WizardTask, WizardSprintGroup } from '$api/types';
  import type { StreamController } from '$api/sse';

  let streamCtrl = $state<StreamController | null>(null);
  let genPhase = $state("");
  let filterPriority = $state<string | null>(null);

  const totalTasks = $derived(wizardStore.allTasks.length);
  const selectedCount = $derived(wizardStore.selectedTaskCount);

  const filteredGroups = $derived(
    wizardStore.sprintGroups.map((g) => ({
      ...g,
      tasks: filterPriority !== null
        ? g.tasks.filter((t) => t.priority === filterPriority)
        : g.tasks,
    })).filter((g) => g.tasks.length > 0),
  );

  const PRIORITY_COLORS: Record<string, string> = {
    critical: '#ef4444',
    high: '#f97316',
    medium: '#eab308',
    low: '#22c55e',
  };

  async function generateTasks(): Promise<void> {
    wizardStore.isGeneratingTasks = true;
    wizardStore.taskGenerationComplete = false;
    genPhase = "Analyzing documentation...";

    const docContent = wizardStore.uploadedDocuments
      .map((d) => `### ${d.name}\n${d.content.slice(0, 2000)}`)
      .join('\n\n---\n\n');

    const agentRoles = wizardStore.agents
      .map((a) => `- ${a.name} (${a.role}): skills=[${a.skills.join(', ')}]`)
      .join('\n');

    const prompt = `You are a project planning assistant. Generate a structured task backlog from the following project documentation and context.

## Project: ${wizardStore.projectName}
${wizardStore.projectDescription || wizardStore.enhancedContext || wizardStore.userContext || ''}

## Documentation
${docContent || '(No documentation provided)'}

## Team Capabilities
${agentRoles || '(No agents configured)'}

## Lifecycle: ${wizardStore.lifecycleTemplate}

Generate tasks grouped into sprints. Respond with ONLY valid JSON (no markdown fences):
{
  "sprints": [
    {
      "name": "Sprint 1: Foundation",
      "goal": "Set up project infrastructure and core architecture",
      "issues": [
        {
          "title": "Set up project scaffolding",
          "description": "Initialize the project structure with...",
          "priority": "high",
          "labels": ["setup", "infrastructure"],
          "depends_on": []
        }
      ]
    }
  ]
}

Guidelines:
- Create 2-4 sprints with 3-8 tasks each
- Priorities: critical, high, medium, low
- Order tasks by dependency
- Make titles concise and actionable
- Make descriptions detailed (2-3 sentences)
- Include relevant labels`;

    if (isMockEnabled()) {
      await mockGenerate();
      return;
    }

    try {
      const agent = agentsStore.agents[0];
      if (agent === undefined) {
        wizardStore.isGeneratingTasks = false;
        return;
      }
      const session = await sessions.create({
        agent_id: agent.id,
        title: `Wizard: Generate tasks for ${wizardStore.projectName}`,
      });
      const sessionId = (session as { session?: { id: string }; id?: string }).session?.id ?? (session as { id: string }).id;

      let accumulated = "";
      streamCtrl = streamMessage({
        sessionId,
        content: prompt,
        model: settingsStore.data.default_model,
        onEvent(event) {
          if (event.type === 'streaming_token') {
            accumulated += (event as { delta?: string }).delta ?? '';
            if (accumulated.length < 200) genPhase = "Analyzing documentation...";
            else if (accumulated.length < 600) genPhase = "Planning sprints...";
            else genPhase = "Generating tasks...";
          }
        },
        onDone() { parseAndSetTasks(accumulated); },
        onError() {
          wizardStore.isGeneratingTasks = false;
          genPhase = "";
        },
      });
    } catch {
      wizardStore.isGeneratingTasks = false;
      genPhase = "";
    }
  }

  function parseAndSetTasks(raw: string): void {
    try {
      const jsonMatch = raw.match(/\{[\s\S]*\}/);
      if (jsonMatch !== null) {
        const data = JSON.parse(jsonMatch[0]) as {
          sprints: Array<{
            name: string;
            goal: string;
            issues: Array<{
              title: string;
              description: string;
              priority: string;
              labels: string[];
              depends_on?: string[];
            }>;
          }>;
        };

        wizardStore.sprintGroups = data.sprints.map((sprint) => ({
          name: sprint.name,
          goal: sprint.goal,
          tasks: sprint.issues.map((issue) => ({
            id: crypto.randomUUID(),
            title: issue.title,
            description: issue.description,
            priority: (['critical', 'high', 'medium', 'low'].includes(issue.priority) ? issue.priority : 'medium') as WizardTask['priority'],
            labels: issue.labels ?? [],
            sprintName: sprint.name,
            dependsOn: issue.depends_on ?? [],
            selected: true,
          })),
        }));
      }
    } catch { /* parse failed */ }
    wizardStore.isGeneratingTasks = false;
    wizardStore.taskGenerationComplete = true;
    genPhase = "";
  }

  async function mockGenerate(): Promise<void> {
    genPhase = "Analyzing documentation...";
    await new Promise((r) => setTimeout(r, 600));
    genPhase = "Planning sprints...";
    await new Promise((r) => setTimeout(r, 600));
    genPhase = "Generating tasks...";
    await new Promise((r) => setTimeout(r, 600));

    wizardStore.sprintGroups = [
      {
        name: 'Sprint 1: Foundation',
        goal: 'Set up project infrastructure and core architecture',
        tasks: [
          { id: crypto.randomUUID(), title: 'Initialize project repository and scaffolding', description: 'Set up the base project structure with the chosen tech stack, configure build tools, and create initial directory layout.', priority: 'high', labels: ['setup', 'infrastructure'], sprintName: 'Sprint 1: Foundation', dependsOn: [], selected: true },
          { id: crypto.randomUUID(), title: 'Configure CI/CD pipeline', description: 'Set up automated build, test, and deployment pipeline with proper staging and production environments.', priority: 'high', labels: ['devops', 'infrastructure'], sprintName: 'Sprint 1: Foundation', dependsOn: [], selected: true },
          { id: crypto.randomUUID(), title: 'Design database schema', description: 'Create the initial database schema based on domain requirements, including migrations and seed data.', priority: 'high', labels: ['backend', 'database'], sprintName: 'Sprint 1: Foundation', dependsOn: [], selected: true },
          { id: crypto.randomUUID(), title: 'Set up authentication system', description: 'Implement user registration, login, and session management with secure token handling.', priority: 'medium', labels: ['backend', 'security'], sprintName: 'Sprint 1: Foundation', dependsOn: [], selected: true },
        ],
      },
      {
        name: 'Sprint 2: Core Features',
        goal: 'Implement primary user-facing functionality',
        tasks: [
          { id: crypto.randomUUID(), title: 'Build REST API endpoints', description: 'Implement the core CRUD API endpoints with proper validation, error handling, and documentation.', priority: 'high', labels: ['backend', 'api'], sprintName: 'Sprint 2: Core Features', dependsOn: [], selected: true },
          { id: crypto.randomUUID(), title: 'Create UI component library', description: 'Build reusable UI components (buttons, forms, modals, tables) following the design system.', priority: 'medium', labels: ['frontend', 'design'], sprintName: 'Sprint 2: Core Features', dependsOn: [], selected: true },
          { id: crypto.randomUUID(), title: 'Implement main dashboard', description: 'Build the primary dashboard view with data visualization, activity feed, and quick actions.', priority: 'medium', labels: ['frontend', 'feature'], sprintName: 'Sprint 2: Core Features', dependsOn: [], selected: true },
          { id: crypto.randomUUID(), title: 'Add real-time notifications', description: 'Implement WebSocket-based notification system for live updates on user actions and system events.', priority: 'low', labels: ['fullstack', 'feature'], sprintName: 'Sprint 2: Core Features', dependsOn: [], selected: true },
        ],
      },
      {
        name: 'Sprint 3: Quality & Polish',
        goal: 'Testing, documentation, and production readiness',
        tasks: [
          { id: crypto.randomUUID(), title: 'Write integration test suite', description: 'Create comprehensive integration tests covering all critical user flows and API endpoints.', priority: 'high', labels: ['testing', 'qa'], sprintName: 'Sprint 3: Quality & Polish', dependsOn: [], selected: true },
          { id: crypto.randomUUID(), title: 'Generate API documentation', description: 'Auto-generate OpenAPI/Swagger docs from API definitions and add usage examples.', priority: 'medium', labels: ['documentation', 'api'], sprintName: 'Sprint 3: Quality & Polish', dependsOn: [], selected: true },
          { id: crypto.randomUUID(), title: 'Performance optimization', description: 'Profile and optimize slow queries, add caching layer, and ensure sub-200ms response times.', priority: 'medium', labels: ['backend', 'performance'], sprintName: 'Sprint 3: Quality & Polish', dependsOn: [], selected: true },
        ],
      },
    ];
    wizardStore.isGeneratingTasks = false;
    wizardStore.taskGenerationComplete = true;
    genPhase = "";
  }

  function cancelGeneration(): void {
    streamCtrl?.abort();
    streamCtrl = null;
    wizardStore.isGeneratingTasks = false;
    genPhase = "";
  }

  let editingTask = $state<string | null>(null);
  function updateTask(id: string, field: keyof WizardTask, value: string): void {
    wizardStore.sprintGroups = wizardStore.sprintGroups.map((g) => ({
      ...g,
      tasks: g.tasks.map((t) =>
        t.id === id ? { ...t, [field]: value } : t,
      ),
    }));
  }
</script>

<div class="s6-container">
  <h3 class="s6-heading">Generate Tasks</h3>
  <p class="s6-desc">AI analyzes your documentation and team to create an initial backlog of tasks organized into sprints.</p>

  {#if !wizardStore.taskGenerationComplete && !wizardStore.isGeneratingTasks}
    <div class="s6-start">
      <button class="s6-generate-btn" onclick={generateTasks}>
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <path d="M9.813 15.904L9 18.75l-.813-2.846a4.5 4.5 0 00-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 003.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 003.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 00-3.09 3.09zM18.259 8.715L18 9.75l-.259-1.035a3.375 3.375 0 00-2.455-2.456L14.25 6l1.036-.259a3.375 3.375 0 002.455-2.456L18 2.25l.259 1.035a3.375 3.375 0 002.455 2.456L21.75 6l-1.036.259a3.375 3.375 0 00-2.455 2.456z" />
        </svg>
        Generate Task Backlog
      </button>
      <p class="s6-start-hint">Or skip this step to create tasks manually later</p>
    </div>
  {/if}

  {#if wizardStore.isGeneratingTasks}
    <div class="s6-progress">
      <div class="s6-spinner"></div>
      <span class="s6-phase">{genPhase}</span>
      <button class="s6-cancel" onclick={cancelGeneration}>Cancel</button>
    </div>
  {/if}

  {#if wizardStore.taskGenerationComplete && wizardStore.sprintGroups.length > 0}
    <!-- Toolbar -->
    <div class="s6-toolbar">
      <div class="s6-toolbar-left">
        <span class="s6-count">{selectedCount}/{totalTasks} tasks selected</span>
        <button class="s6-link-btn" onclick={() => wizardStore.selectAllTasks()}>Select all</button>
        <button class="s6-link-btn" onclick={() => wizardStore.deselectAllTasks()}>Deselect all</button>
      </div>
      <div class="s6-toolbar-right">
        <button class="s6-filter-btn" class:active={filterPriority === null} onclick={() => { filterPriority = null; }}>All</button>
        {#each ['critical', 'high', 'medium', 'low'] as p}
          <button
            class="s6-filter-btn"
            class:active={filterPriority === p}
            onclick={() => { filterPriority = filterPriority === p ? null : p; }}
          >
            <span class="s6-priority-dot" style="background: {PRIORITY_COLORS[p]}"></span>
            {p}
          </button>
        {/each}
      </div>
    </div>

    <!-- Sprint groups -->
    {#each filteredGroups as group (group.name)}
      <div class="s6-sprint">
        <div class="s6-sprint-header">
          <span class="s6-sprint-name">{group.name}</span>
          <span class="s6-sprint-goal">{group.goal}</span>
        </div>
        <div class="s6-task-list">
          {#each group.tasks as task (task.id)}
            <div class="s6-task" class:deselected={!task.selected}>
              <label class="s6-task-check">
                <input type="checkbox" checked={task.selected} onchange={() => wizardStore.toggleTask(task.id)} />
              </label>
              <div class="s6-task-body">
                <div class="s6-task-header">
                  {#if editingTask === task.id}
                    <input
                      type="text"
                      class="s6-task-title-input"
                      value={task.title}
                      onchange={(e) => updateTask(task.id, 'title', (e.target as HTMLInputElement).value)}
                      onblur={() => { editingTask = null; }}
                      autofocus
                    />
                  {:else}
                    <span class="s6-task-title" ondblclick={() => { editingTask = task.id; }}>{task.title}</span>
                  {/if}
                  <span class="s6-priority" style="color: {PRIORITY_COLORS[task.priority]}">{task.priority}</span>
                </div>
                <p class="s6-task-desc">{task.description}</p>
                {#if task.labels.length > 0}
                  <div class="s6-task-labels">
                    {#each task.labels as label}
                      <span class="s6-label-chip">{label}</span>
                    {/each}
                  </div>
                {/if}
              </div>
            </div>
          {/each}
        </div>
      </div>
    {/each}

    <div class="s6-regen">
      <button class="s6-regen-btn" onclick={generateTasks}>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <path d="M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0l3.181 3.183a8.25 8.25 0 0013.803-3.7M4.031 9.865a8.25 8.25 0 0113.803-3.7l3.181 3.182" />
        </svg>
        Regenerate tasks
      </button>
    </div>
  {/if}
</div>

<style>
  .s6-container { max-width: 700px; margin: 0 auto; }
  .s6-heading { font-size: 18px; font-weight: 600; margin: 0 0 6px; color: var(--text-primary); }
  .s6-desc { font-size: 13px; color: var(--text-secondary); margin: 0 0 20px; line-height: 1.5; }

  .s6-start { text-align: center; padding: 40px 20px; }
  .s6-generate-btn {
    display: inline-flex; align-items: center; gap: 10px;
    padding: 14px 28px; border-radius: 10px;
    background: linear-gradient(135deg, #f97316, #ea580c);
    color: #fff; font-size: 16px; font-weight: 600;
    border: none; cursor: pointer; transition: filter 0.15s;
  }
  .s6-generate-btn:hover { filter: brightness(1.1); }
  .s6-start-hint { font-size: 12px; color: var(--text-tertiary); margin-top: 12px; }

  .s6-progress { display: flex; align-items: center; gap: 10px; justify-content: center; padding: 30px; }
  .s6-spinner {
    width: 18px; height: 18px; border-radius: 50%;
    border: 2px solid rgba(249,115,22,0.2); border-top-color: var(--accent, #f97316);
    animation: wz-spin 0.6s linear infinite;
  }
  @keyframes wz-spin { to { transform: rotate(360deg); } }
  .s6-phase { font-size: 14px; color: var(--text-secondary); }
  .s6-cancel {
    background: none; border: none; color: var(--text-tertiary);
    font-size: 12px; cursor: pointer; text-decoration: underline;
  }

  .s6-toolbar {
    display: flex; align-items: center; justify-content: space-between;
    padding: 10px 0; flex-wrap: wrap; gap: 8px; margin-bottom: 8px;
  }
  .s6-toolbar-left { display: flex; align-items: center; gap: 10px; }
  .s6-toolbar-right { display: flex; align-items: center; gap: 4px; }
  .s6-count { font-size: 12px; color: var(--text-secondary); }
  .s6-link-btn {
    background: none; border: none; color: var(--accent, #f97316);
    font-size: 12px; cursor: pointer; text-decoration: underline;
  }
  .s6-filter-btn {
    display: inline-flex; align-items: center; gap: 4px;
    padding: 3px 8px; border-radius: 4px;
    background: rgba(255,255,255,0.04);
    border: 1px solid transparent; color: var(--text-tertiary);
    font-size: 11px; cursor: pointer; text-transform: capitalize;
  }
  .s6-filter-btn.active { border-color: var(--accent, #f97316); color: var(--accent, #f97316); }
  .s6-priority-dot { width: 6px; height: 6px; border-radius: 50%; flex-shrink: 0; }

  .s6-sprint { margin-bottom: 16px; }
  .s6-sprint-header {
    padding: 10px 12px; border-radius: 8px 8px 0 0;
    background: rgba(249,115,22,0.06);
    border: 1px solid rgba(249,115,22,0.1);
    border-bottom: none;
  }
  .s6-sprint-name { font-size: 13px; font-weight: 600; color: var(--text-primary); display: block; }
  .s6-sprint-goal { font-size: 11px; color: var(--text-secondary); }
  .s6-task-list {
    border: 1px solid var(--border-subtle, rgba(255,255,255,0.06));
    border-top: none; border-radius: 0 0 8px 8px;
  }
  .s6-task {
    display: flex; gap: 10px; padding: 10px 12px;
    border-bottom: 1px solid var(--border-subtle, rgba(255,255,255,0.03));
    transition: opacity 0.15s;
  }
  .s6-task:last-child { border-bottom: none; }
  .s6-task.deselected { opacity: 0.4; }
  .s6-task-check { flex-shrink: 0; padding-top: 2px; }
  .s6-task-check input { accent-color: var(--accent, #f97316); }
  .s6-task-body { flex: 1; min-width: 0; }
  .s6-task-header { display: flex; align-items: center; justify-content: space-between; gap: 8px; margin-bottom: 4px; }
  .s6-task-title { font-size: 13px; font-weight: 500; color: var(--text-primary); cursor: pointer; }
  .s6-task-title:hover { color: var(--accent, #f97316); }
  .s6-task-title-input {
    flex: 1; background: rgba(255,255,255,0.06);
    border: 1px solid var(--accent, #f97316);
    border-radius: 4px; padding: 2px 6px;
    color: var(--text-primary); font-size: 13px; font-weight: 500;
  }
  .s6-priority { font-size: 10px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.05em; flex-shrink: 0; }
  .s6-task-desc { font-size: 12px; color: var(--text-secondary); margin: 0 0 6px; line-height: 1.5; }
  .s6-task-labels { display: flex; flex-wrap: wrap; gap: 4px; }
  .s6-label-chip {
    padding: 1px 6px; border-radius: 3px;
    background: rgba(255,255,255,0.05); color: var(--text-tertiary);
    font-size: 10px;
  }

  .s6-regen { margin-top: 12px; text-align: center; }
  .s6-regen-btn {
    display: inline-flex; align-items: center; gap: 6px;
    background: none; border: none; color: var(--text-tertiary);
    font-size: 12px; cursor: pointer;
  }
  .s6-regen-btn:hover { color: var(--text-secondary); }
</style>
