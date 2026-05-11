<!-- src/lib/components/tasks/TaskSplitDialog.svelte -->
<!-- AI-assisted task splitting: breaks one task into multiple subtasks -->
<script lang="ts">
  import type { WizardTask, IssueTaskType } from '$api/types';
  import { onDestroy } from 'svelte';
  import { sessions, messages } from '$api/client';
  import { connectSSE } from '$api/sse';
  import type { StreamEvent } from '$api/types';
  import { agentsStore } from '$lib/stores/agents.svelte';
  import { settingsStore } from '$lib/stores/settings.svelte';

  interface Props {
    task: WizardTask;
    onSplit: (subtasks: WizardTask[]) => void;
    onClose: () => void;
  }

  let { task, onSplit, onClose }: Props = $props();

  let subtasks = $state<WizardTask[]>([]);
  let splitting = $state(false);
  let error = $state<string | null>(null);
  let splitCount = $state(3);
  let splitController: import('$api/sse').StreamController | null = null;

  onDestroy(() => {
    if (splitController !== null) {
      splitController.abort();
      splitController = null;
    }
  });

  async function handleSplit() {
    splitting = true;
    error = null;

    try {
      const agent = agentsStore.agents[0];
      if (agent === undefined) {
        error = 'No agents available for task splitting.';
        splitting = false;
        return;
      }

      const session = await sessions.create({
        agent_id: agent.id,
        title: `Split task: ${task.title}`,
      });

      const prompt = [
        `Split the following development task into ${splitCount} smaller, actionable subtasks.`,
        '',
        `Task: ${task.title}`,
        `Description: ${task.description}`,
        `Priority: ${task.priority}`,
        `Labels: ${task.labels.join(', ')}`,
        '',
        'For each subtask provide:',
        '- title: concise subtask title',
        '- description: detailed description with acceptance criteria',
        '- priority: low | medium | high | critical',
        '- task_type: subtask',
        '',
        'Respond ONLY with valid JSON: { "subtasks": [{ "title": "...", "description": "...", "priority": "...", "task_type": "subtask" }] }',
      ].join('\n');

      let buffer = '';

      const controller = connectSSE(`/sessions/${session.id}/stream`, {
        onEvent: (event: StreamEvent) => {
          if (event.type === 'streaming_token') {
            buffer += (event as { delta: string }).delta;
          } else if (event.type === 'error') {
            const msg = (event as { message?: string }).message ?? 'Stream error';
            error = msg;
            splitting = false;
          } else if (event.type === 'done') {
            parseSubtasks(buffer);
            splitting = false;
          }
        },
        onError: (err: Error) => {
          error = err.message;
          splitting = false;
        },
        onDone: () => {
          if (splitting) {
            parseSubtasks(buffer);
            splitting = false;
          }
        },
      });

      splitController = controller;

      const model = settingsStore.data.default_model ?? undefined;
      await messages.send({ session_id: session.id, content: prompt, model });
    } catch (err) {
      error = (err as Error).message;
      splitting = false;
    }
  }

  function parseSubtasks(raw: string): void {
    try {
      const jsonMatch = raw.match(/\{[\s\S]*"subtasks"[\s\S]*\}/);
      if (!jsonMatch) {
        error = 'Could not parse AI response.';
        return;
      }
      const parsed = JSON.parse(jsonMatch[0]) as {
        subtasks: Array<{ title: string; description?: string; priority?: string; task_type?: string }>;
      };
      if (!Array.isArray(parsed.subtasks)) {
        error = 'Invalid response format.';
        return;
      }

      subtasks = parsed.subtasks.map((s, i) => ({
        id: `${task.id}-sub-${i + 1}`,
        title: s.title ?? `Subtask ${i + 1}`,
        description: s.description ?? '',
        priority: validatePriority(s.priority),
        labels: [...task.labels, 'subtask'],
        sprintName: task.sprintName,
        dependsOn: i > 0 ? [`${task.id}-sub-${i}`] : task.dependsOn,
        taskType: 'subtask' as IssueTaskType,
        selected: true,
      }));
    } catch {
      error = 'Failed to parse subtask response.';
    }
  }

  function validatePriority(p?: string): 'low' | 'medium' | 'high' | 'critical' {
    if (p === 'low' || p === 'medium' || p === 'high' || p === 'critical') return p;
    return task.priority;
  }

  function handleConfirm() {
    onSplit(subtasks.filter((s) => s.selected));
  }
</script>

<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
<div class="tsd-overlay" role="dialog" aria-modal="true" aria-label="Split task into subtasks" tabindex="-1" onclick={(e) => { if (e.target === e.currentTarget) onClose(); }} onkeydown={(e) => { if (e.key === 'Escape') onClose(); }}>
  <div class="tsd-modal">
    <div class="tsd-header">
      <h3 class="tsd-title">Split Task</h3>
      <button class="tsd-close" type="button" onclick={onClose} aria-label="Close">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <path d="M18 6L6 18M6 6l12 12" />
        </svg>
      </button>
    </div>

    <div class="tsd-body">
      <div class="tsd-source">
        <span class="tsd-label">Original task:</span>
        <span class="tsd-source-title">{task.title}</span>
      </div>

      {#if subtasks.length === 0}
        <div class="tsd-config">
          <label class="tsd-label" for="tsd-count">Split into how many subtasks?</label>
          <input id="tsd-count" type="number" class="tsd-input" min="2" max="10" bind:value={splitCount} />
        </div>

        {#if error}
          <div class="tsd-error" role="alert">{error}</div>
        {/if}
      {:else}
        <div class="tsd-list" role="list" aria-label="Proposed subtasks">
          {#each subtasks as sub, idx (sub.id)}
            <label class="tsd-item" role="listitem">
              <input type="checkbox" bind:checked={sub.selected} />
              <div class="tsd-item-info">
                <input class="tsd-item-title" type="text" bind:value={sub.title} aria-label="Subtask title" />
                <span class="tsd-item-desc">{sub.description.slice(0, 100)}{sub.description.length > 100 ? '…' : ''}</span>
              </div>
              <span class="tsd-item-order">#{idx + 1}</span>
            </label>
          {/each}
        </div>
      {/if}
    </div>

    <div class="tsd-footer">
      <button class="tsd-btn tsd-btn--ghost" type="button" onclick={onClose}>Cancel</button>
      {#if subtasks.length === 0}
        <button class="tsd-btn tsd-btn--primary" type="button" onclick={handleSplit} disabled={splitting}>
          {splitting ? 'Splitting…' : `Split into ${splitCount} subtasks`}
        </button>
      {:else}
        <button class="tsd-btn tsd-btn--ghost" type="button" onclick={() => { subtasks = []; }}>Re-split</button>
        <button class="tsd-btn tsd-btn--primary" type="button" onclick={handleConfirm} disabled={subtasks.filter((s) => s.selected).length === 0}>
          Confirm {subtasks.filter((s) => s.selected).length} subtask{subtasks.filter((s) => s.selected).length !== 1 ? 's' : ''}
        </button>
      {/if}
    </div>
  </div>
</div>

<style>
  .tsd-overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.5); display: flex; align-items: center; justify-content: center; z-index: 1200; }

  .tsd-modal {
    background: var(--bg-tertiary, var(--bg-surface));
    border: 1px solid var(--border-default); border-radius: 14px;
    width: 520px; max-width: calc(100vw - 40px); max-height: calc(100vh - 80px);
    display: flex; flex-direction: column; overflow: hidden;
  }

  .tsd-header { display: flex; align-items: center; justify-content: space-between; padding: 16px 20px; border-bottom: 1px solid var(--border-default); }
  .tsd-title { font-size: 15px; font-weight: 600; color: var(--text-primary); margin: 0; }

  .tsd-close { display: flex; align-items: center; justify-content: center; width: 28px; height: 28px; border: 1px solid transparent; border-radius: 6px; background: transparent; color: var(--text-tertiary); cursor: pointer; }
  .tsd-close:hover { background: var(--bg-elevated); border-color: var(--border-default); color: var(--text-primary); }

  .tsd-body { flex: 1; overflow-y: auto; padding: 16px 20px; display: flex; flex-direction: column; gap: 14px; }

  .tsd-source { display: flex; align-items: center; gap: 8px; padding: 10px 12px; border-radius: 8px; background: var(--bg-elevated); border: 1px solid var(--border-default); }
  .tsd-label { font-size: 11px; font-weight: 600; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.5px; flex-shrink: 0; }
  .tsd-source-title { font-size: 13px; font-weight: 500; color: var(--text-primary); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

  .tsd-config { display: flex; align-items: center; gap: 10px; }
  .tsd-input { width: 60px; height: 32px; padding: 0 8px; border-radius: 6px; font-size: 13px; background: var(--bg-elevated); border: 1px solid var(--border-default); color: var(--text-primary); font-family: inherit; text-align: center; }
  .tsd-input:focus { outline: none; border-color: #f97316; }

  .tsd-error { font-size: 12px; color: #fca5a5; padding: 8px 12px; background: rgba(239,68,68,0.08); border: 1px solid rgba(239,68,68,0.2); border-radius: 6px; }

  .tsd-list { display: flex; flex-direction: column; gap: 4px; }

  .tsd-item { display: flex; align-items: center; gap: 8px; padding: 8px 10px; border-radius: 6px; border: 1px solid var(--border-default); cursor: pointer; }
  .tsd-item:hover { background: var(--bg-elevated); }
  .tsd-item input[type="checkbox"] { width: 14px; height: 14px; accent-color: #f97316; flex-shrink: 0; }

  .tsd-item-info { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 2px; }
  .tsd-item-title { font-size: 13px; font-weight: 500; color: var(--text-primary); background: transparent; border: 1px solid transparent; border-radius: 4px; padding: 2px 4px; font-family: inherit; }
  .tsd-item-title:hover { border-color: var(--border-default); background: var(--bg-elevated); }
  .tsd-item-title:focus { outline: none; border-color: #f97316; background: var(--bg-elevated); }
  .tsd-item-desc { font-size: 11px; color: var(--text-muted); padding: 0 4px; }
  .tsd-item-order { font-size: 10px; font-weight: 700; color: var(--text-muted); flex-shrink: 0; }

  .tsd-footer { display: flex; align-items: center; justify-content: flex-end; gap: 8px; padding: 14px 20px; border-top: 1px solid var(--border-default); }

  .tsd-btn { height: 32px; padding: 0 14px; border-radius: 6px; font-size: 13px; font-weight: 500; cursor: pointer; font-family: inherit; transition: all 100ms ease; }
  .tsd-btn--ghost { background: transparent; border: 1px solid var(--border-default); color: var(--text-secondary); }
  .tsd-btn--ghost:hover:not(:disabled) { background: var(--bg-elevated); color: var(--text-primary); }
  .tsd-btn--primary { background: rgba(249,115,22,0.12); border: 1px solid rgba(249,115,22,0.35); color: #fdba74; }
  .tsd-btn--primary:hover:not(:disabled) { background: rgba(249,115,22,0.2); border-color: rgba(249,115,22,0.5); }
  .tsd-btn:disabled { opacity: 0.5; cursor: not-allowed; }
</style>
