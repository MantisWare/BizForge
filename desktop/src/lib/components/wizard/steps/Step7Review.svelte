<!-- src/lib/components/wizard/steps/Step7Review.svelte -->
<script lang="ts">
  import { goto } from '$app/navigation';
  import { wizardStore, type LaunchStep } from '$lib/stores/wizard.svelte';
  import { workspaceStore } from '$lib/stores/workspace.svelte';
  import { organizationsStore } from '$lib/stores/organizations.svelte';
  import { hierarchyStore } from '$lib/stores/hierarchy.svelte';
  import { agentsStore } from '$lib/stores/agents.svelte';
  import { projectsStore } from '$lib/stores/projects.svelte';
  import { tasksStore } from '$lib/stores/tasks.svelte';
  import { skillsStore } from '$lib/stores/skills.svelte';
  import { toastStore } from '$lib/stores/toasts.svelte';
  import {
    workspaces as workspacesApi,
    sprints as sprintsApi,
    documents as documentsApi,
  } from '$api/client';
  import { resolveSkillsForTeam, lookupLibrarySkills } from '$lib/data/skill-dependencies';

  const LAUNCH_STEPS: LaunchStep[] = [
    { id: 'workspace', label: 'Create workspace', status: 'pending' },
    { id: 'activate', label: 'Activate workspace', status: 'pending' },
    { id: 'organization', label: 'Set up organization', status: 'pending' },
    { id: 'skills', label: 'Install skills', status: 'pending' },
    { id: 'agents', label: 'Create agents', status: 'pending' },
    { id: 'project', label: 'Create project', status: 'pending' },
    { id: 'documents', label: 'Upload documents', status: 'pending' },
    { id: 'sprints', label: 'Create sprints', status: 'pending' },
    { id: 'issues', label: 'Create tasks', status: 'pending' },
    { id: 'navigate', label: 'Open workspace', status: 'pending' },
  ];

  const selectedTaskCount = $derived(wizardStore.selectedTaskCount);
  const sprintCount = $derived(wizardStore.sprintGroups.length);

  function initLaunchSteps(): void {
    const steps = LAUNCH_STEPS.map((s) => ({ ...s }));
    if (wizardStore.selectedCompanyTemplate === null) {
      const orgStep = steps.find((s) => s.id === 'organization');
      if (orgStep !== undefined) orgStep.status = 'skipped';
    }
    if (wizardStore.uploadedDocuments.length === 0) {
      const docStep = steps.find((s) => s.id === 'documents');
      if (docStep !== undefined) docStep.status = 'skipped';
    }
    if (wizardStore.sprintGroups.length === 0 || selectedTaskCount === 0) {
      const sprintStep = steps.find((s) => s.id === 'sprints');
      if (sprintStep !== undefined) sprintStep.status = 'skipped';
      const issueStep = steps.find((s) => s.id === 'issues');
      if (issueStep !== undefined) issueStep.status = 'skipped';
    }
    wizardStore.launchSteps = steps;
  }

  async function launchWorkspace(): Promise<void> {
    wizardStore.isLaunching = true;
    initLaunchSteps();

    let workspaceId: string | null = null;
    let projectId: string | null = null;

    // 1. Create workspace
    try {
      wizardStore.updateLaunchStep('workspace', 'running');
      const ws = await workspaceStore.createWorkspace(
        wizardStore.workspaceName,
        wizardStore.workspacePath || undefined,
      );
      workspaceId = ws?.id ?? null;
      wizardStore.updateLaunchStep('workspace', 'done');
    } catch (e) {
      wizardStore.updateLaunchStep('workspace', 'error', String(e));
    }

    // 2. Activate workspace
    if (workspaceId !== null) {
      try {
        wizardStore.updateLaunchStep('activate', 'running');
        await workspaceStore.setActiveWorkspace(workspaceId);
        wizardStore.updateLaunchStep('activate', 'done');
      } catch (e) {
        wizardStore.updateLaunchStep('activate', 'error', String(e));
      }
    } else {
      wizardStore.updateLaunchStep('activate', 'skipped');
    }

    // 3. Organization
    const orgStep = wizardStore.launchSteps.find((s) => s.id === 'organization');
    if (orgStep !== undefined && orgStep.status !== 'skipped') {
      try {
        wizardStore.updateLaunchStep('organization', 'running');
        await organizationsStore.ensureDefault();
        wizardStore.updateLaunchStep('organization', 'done');
      } catch (e) {
        wizardStore.updateLaunchStep('organization', 'error', String(e));
      }
    }

    // 4. Install skills
    try {
      wizardStore.updateLaunchStep('skills', 'running');
      const allSkillTags = wizardStore.agents.flatMap((a) => a.skills);
      const librarySkills = lookupLibrarySkills(allSkillTags);
      if (librarySkills.length > 0) {
        await skillsStore.installFromLibrary(librarySkills);
      }
      wizardStore.updateLaunchStep('skills', 'done');
    } catch (e) {
      wizardStore.updateLaunchStep('skills', 'error', String(e));
    }

    // 5. Create agents
    try {
      wizardStore.updateLaunchStep('agents', 'running');
      if (wizardStore.agents.length > 0) {
        const requests = wizardStore.agents.map((a) => ({
          name: a.name,
          slug: a.name.toLowerCase().replace(/[^a-z0-9]+/g, '-'),
          role: a.role,
          adapter: a.adapter as any,
          model: a.model,
          system_prompt: a.system_prompt,
          avatar_emoji: a.emoji,
          workspace_id: workspaceId ?? undefined,
        }));
        await agentsStore.createAgentBatch(requests);
      }
      wizardStore.updateLaunchStep('agents', 'done');
    } catch (e) {
      wizardStore.updateLaunchStep('agents', 'error', String(e));
    }

    // 6. Create project
    try {
      wizardStore.updateLaunchStep('project', 'running');
      const deliveryConfig = wizardStore.deliveryChecks.length > 0
        ? { cwd: wizardStore.deliveryCwd, require_all_tasks_done: true, checks: wizardStore.deliveryChecks }
        : undefined;

      const project = await projectsStore.createProject({
        name: wizardStore.projectName,
        description: wizardStore.projectDescription || undefined,
        output_path: wizardStore.outputPath || undefined,
        workspace_id: workspaceId ?? undefined,
        lifecycle_config: { lifecycle: wizardStore.lifecycleTemplate },
        config: { auto_assign: wizardStore.autoAssign, ...(deliveryConfig !== undefined ? { delivery: deliveryConfig } : {}) },
      } as any);
      projectId = (project as any)?.id ?? null;
      wizardStore.updateLaunchStep('project', 'done');
    } catch (e) {
      wizardStore.updateLaunchStep('project', 'error', String(e));
    }

    // 7. Upload documents
    const docStep = wizardStore.launchSteps.find((s) => s.id === 'documents');
    if (docStep !== undefined && docStep.status !== 'skipped') {
      try {
        wizardStore.updateLaunchStep('documents', 'running');
        for (const doc of wizardStore.uploadedDocuments) {
          try {
            await documentsApi.create(doc.name, doc.content, {
              format: doc.format,
              project_id: projectId ?? undefined,
            } as any);
          } catch {
            // Non-fatal: continue uploading remaining docs
          }
        }
        wizardStore.updateLaunchStep('documents', 'done');
      } catch (e) {
        wizardStore.updateLaunchStep('documents', 'error', String(e));
      }
    }

    // 8. Create sprints
    const sprintStep = wizardStore.launchSteps.find((s) => s.id === 'sprints');
    if (sprintStep !== undefined && sprintStep.status !== 'skipped') {
      try {
        wizardStore.updateLaunchStep('sprints', 'running');
        for (const group of wizardStore.sprintGroups) {
          const selectedTasks = group.tasks.filter((t) => t.selected);
          if (selectedTasks.length === 0) continue;
          try {
            await sprintsApi.create({
              name: group.name,
              objective: group.objective,
              project_id: projectId ?? undefined,
              workspace_id: workspaceId ?? undefined,
            } as any);
          } catch {
            // Non-fatal
          }
        }
        wizardStore.updateLaunchStep('sprints', 'done');
      } catch (e) {
        wizardStore.updateLaunchStep('sprints', 'error', String(e));
      }
    }

    // 9. Create issues (with dependency data)
    const issueStep = wizardStore.launchSteps.find((s) => s.id === 'issues');
    if (issueStep !== undefined && issueStep.status !== 'skipped') {
      try {
        wizardStore.updateLaunchStep('issues', 'running');
        const selectedTasks = wizardStore.allTasks.filter((t) => t.selected);
        if (selectedTasks.length > 0) {
          const { tasks: tasksApi } = await import('$api/client');
          const idMap = new Map<string, string>();
          const sorted = topoSort(selectedTasks);
          const created: import('$api/types').Task[] = [];

          for (const t of sorted) {
            const resolvedDeps = (t.dependsOn ?? [])
              .map((depId) => idMap.get(depId))
              .filter((id): id is string => id !== undefined);
            try {
              const task = await tasksApi.create({
                title: t.title,
                description: t.description,
                priority: t.priority,
                status: 'backlog',
                workspace_id: workspaceId,
                project_id: projectId,
                task_type: t.taskType ?? undefined,
                depends_on_ids: resolvedDeps,
              });
              idMap.set(t.id, task.id);
              created.push(task);
            } catch {
              // skip failed task
            }
          }

          if (created.length > 0) {
            tasksStore.tasks = [...created, ...tasksStore.tasks];
          }
        }
        wizardStore.updateLaunchStep('issues', 'done');
      } catch (e) {
        wizardStore.updateLaunchStep('issues', 'error', String(e));
      }
    }

    // 10. Navigate
    try {
      wizardStore.updateLaunchStep('navigate', 'running');
      wizardStore.launchComplete = true;
      wizardStore.updateLaunchStep('navigate', 'done');
    } catch (e) {
      wizardStore.updateLaunchStep('navigate', 'error', String(e));
    }

    wizardStore.isLaunching = false;
  }

  function finishAndNavigate(): void {
    wizardStore.close();
    wizardStore.reset();
    toastStore.success('Workspace ready', 'Your workspace has been set up and is ready to go.');
    void goto('/app');
  }

  const STATUS_ICONS: Record<string, string> = {
    pending: '○',
    running: '◌',
    done: '✓',
    error: '✗',
    skipped: '–',
  };

  function topoSort(tasks: import('$api/types').WizardTask[]): import('$api/types').WizardTask[] {
    const idSet = new Set(tasks.map((t) => t.id));
    const visited = new Set<string>();
    const result: import('$api/types').WizardTask[] = [];
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
</script>

<div class="s7-container">
  {#if !wizardStore.isLaunching && !wizardStore.launchComplete}
    <h3 class="s7-heading">Review & Launch</h3>
    <p class="s7-desc">Everything looks good? Hit launch to create your workspace in one shot.</p>

    <div class="s7-summary">
      <div class="s7-summary-grid">
        <div class="s7-stat">
          <span class="s7-stat-value">{wizardStore.workspaceName || '—'}</span>
          <span class="s7-stat-label">Workspace</span>
        </div>
        <div class="s7-stat">
          <span class="s7-stat-value">{wizardStore.selectedTeamTemplates.length}</span>
          <span class="s7-stat-label">Teams</span>
        </div>
        <div class="s7-stat">
          <span class="s7-stat-value">{wizardStore.agents.length}</span>
          <span class="s7-stat-label">Agents</span>
        </div>
        <div class="s7-stat">
          <span class="s7-stat-value">{wizardStore.projectName || '—'}</span>
          <span class="s7-stat-label">Project</span>
        </div>
        <div class="s7-stat">
          <span class="s7-stat-value">{wizardStore.uploadedDocuments.length}</span>
          <span class="s7-stat-label">Documents</span>
        </div>
        <div class="s7-stat">
          <span class="s7-stat-value">{selectedTaskCount}</span>
          <span class="s7-stat-label">Tasks</span>
        </div>
        <div class="s7-stat">
          <span class="s7-stat-value">{sprintCount}</span>
          <span class="s7-stat-label">Sprints</span>
        </div>
        <div class="s7-stat">
          <span class="s7-stat-value">{wizardStore.lifecycleTemplate.replace(/_/g, ' ')}</span>
          <span class="s7-stat-label">Lifecycle</span>
        </div>
      </div>

      {#if wizardStore.outputPath}
        <div class="s7-detail-row">
          <span class="s7-detail-label">Output:</span>
          <span class="s7-detail-value">{wizardStore.outputPath}</span>
        </div>
      {/if}
      {#if wizardStore.workspacePath}
        <div class="s7-detail-row">
          <span class="s7-detail-label">Directory:</span>
          <span class="s7-detail-value">{wizardStore.workspacePath}</span>
        </div>
      {/if}
    </div>

    <div class="s7-launch-area">
      <button class="s7-launch-btn" onclick={launchWorkspace}>
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <path d="M15.59 14.37a6 6 0 01-5.84 7.38v-4.8m5.84-2.58a14.98 14.98 0 006.16-12.12A14.98 14.98 0 009.631 8.41m5.96 5.96a14.926 14.926 0 01-5.841 2.58m-.119-8.54a6 6 0 00-7.381 5.84h4.8m2.581-5.84a14.927 14.927 0 00-2.58 5.84m2.699 2.7c-.103.021-.207.041-.311.06a15.09 15.09 0 01-2.448-2.448 14.9 14.9 0 01.06-.312m-2.24 2.39a4.493 4.493 0 00-1.757 4.306 4.493 4.493 0 004.306-1.758M16.5 9a1.5 1.5 0 11-3 0 1.5 1.5 0 013 0z" />
        </svg>
        Launch Workspace
      </button>
    </div>

  {:else}
    <!-- Launch progress -->
    <div class="s7-progress-area">
      <h3 class="s7-heading">{wizardStore.launchComplete ? 'Workspace Ready!' : 'Setting up your workspace...'}</h3>

      <div class="s7-step-list">
        {#each wizardStore.launchSteps as step (step.id)}
          <div class="s7-step" class:running={step.status === 'running'} class:done={step.status === 'done'} class:error={step.status === 'error'} class:skipped={step.status === 'skipped'}>
            <span class="s7-step-icon" class:spinning={step.status === 'running'}>
              {STATUS_ICONS[step.status]}
            </span>
            <span class="s7-step-label">{step.label}</span>
            {#if step.error}
              <span class="s7-step-error">{step.error}</span>
            {/if}
          </div>
        {/each}
      </div>

      {#if wizardStore.launchComplete}
        <div class="s7-complete">
          <div class="s7-complete-icon">
            <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="var(--accent, #f97316)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <path d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
          </div>
          <p class="s7-complete-text">Your workspace <strong>{wizardStore.workspaceName}</strong> is ready with {wizardStore.agents.length} agents and {selectedTaskCount} tasks.</p>
          <button class="s7-open-btn" onclick={finishAndNavigate}>
            Open Workspace
          </button>
        </div>
      {/if}
    </div>
  {/if}
</div>

<style>
  .s7-container { max-width: 600px; margin: 0 auto; }
  .s7-heading { font-size: 18px; font-weight: 600; margin: 0 0 6px; color: var(--text-primary); text-align: center; }
  .s7-desc { font-size: 13px; color: var(--text-secondary); margin: 0 0 24px; text-align: center; line-height: 1.5; }

  .s7-summary {
    padding: 20px; border-radius: 12px;
    background: rgba(255,255,255,0.02);
    border: 1px solid var(--border-subtle, rgba(255,255,255,0.06));
    margin-bottom: 24px;
  }
  .s7-summary-grid {
    display: grid; grid-template-columns: repeat(4, 1fr);
    gap: 16px; margin-bottom: 16px;
  }
  .s7-stat { text-align: center; }
  .s7-stat-value {
    font-size: 14px; font-weight: 600; color: var(--text-primary);
    display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  }
  .s7-stat-label { font-size: 10px; color: var(--text-tertiary); text-transform: uppercase; letter-spacing: 0.05em; }
  .s7-detail-row {
    display: flex; gap: 8px; font-size: 12px;
    padding: 4px 0; color: var(--text-secondary);
  }
  .s7-detail-label { color: var(--text-tertiary); flex-shrink: 0; }
  .s7-detail-value {
    color: var(--text-primary); overflow: hidden; text-overflow: ellipsis;
    white-space: nowrap; font-family: 'SF Mono', monospace;
  }

  .s7-launch-area { text-align: center; }
  .s7-launch-btn {
    display: inline-flex; align-items: center; gap: 10px;
    padding: 16px 40px; border-radius: 12px;
    background: linear-gradient(135deg, #f97316, #ea580c);
    color: #fff; font-size: 18px; font-weight: 700;
    border: none; cursor: pointer; transition: all 0.2s;
    box-shadow: 0 4px 20px rgba(249,115,22,0.3);
  }
  .s7-launch-btn:hover { filter: brightness(1.1); transform: translateY(-1px); box-shadow: 0 6px 24px rgba(249,115,22,0.4); }

  .s7-progress-area { padding: 20px 0; }
  .s7-step-list { display: flex; flex-direction: column; gap: 8px; margin: 24px 0; }
  .s7-step {
    display: flex; align-items: center; gap: 10px;
    padding: 10px 14px; border-radius: 8px;
    background: rgba(255,255,255,0.02);
    font-size: 13px; color: var(--text-secondary);
    transition: all 0.2s;
  }
  .s7-step.running { background: rgba(249,115,22,0.06); color: var(--text-primary); }
  .s7-step.done { color: var(--text-primary); }
  .s7-step.error { color: #ef4444; background: rgba(239,68,68,0.06); }
  .s7-step.skipped { opacity: 0.4; }
  .s7-step-icon {
    width: 20px; height: 20px; display: flex; align-items: center; justify-content: center;
    font-size: 14px; font-weight: 700; flex-shrink: 0;
  }
  .s7-step-icon.spinning { animation: wz-spin 0.8s linear infinite; }
  @keyframes wz-spin { to { transform: rotate(360deg); } }
  .s7-step.done .s7-step-icon { color: #22c55e; }
  .s7-step.error .s7-step-icon { color: #ef4444; }
  .s7-step-label { flex: 1; }
  .s7-step-error { font-size: 11px; color: #ef4444; max-width: 200px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

  .s7-complete { text-align: center; margin-top: 24px; }
  .s7-complete-icon { margin-bottom: 12px; }
  .s7-complete-text { font-size: 14px; color: var(--text-primary); margin: 0 0 20px; line-height: 1.5; }
  .s7-open-btn {
    padding: 12px 32px; border-radius: 10px;
    background: var(--accent, #f97316); color: #fff;
    font-size: 16px; font-weight: 600; border: none;
    cursor: pointer; transition: filter 0.15s;
  }
  .s7-open-btn:hover { filter: brightness(1.1); }
</style>
