<!-- src/lib/components/phases/PhaseForm.svelte -->
<script lang="ts">
  import type { Phase, PhaseStatus, PhasePriority, PhaseTreeNode } from '$api/types';
  import { phasesStore } from '$lib/stores/phases.svelte';

  interface Props {
    phase?: PhaseTreeNode;
    parentId?: string;
    onSubmit: (data: Partial<Phase>) => void;
    onCancel: () => void;
  }

  let { phase, parentId, onSubmit, onCancel }: Props = $props();

  let title = $state(phase?.title ?? '');
  let description = $state(phase?.description ?? '');
  let status = $state<PhaseStatus>(phase?.status ?? 'active');
  let priority = $state<PhasePriority>(phase?.priority ?? 'medium');
  let selectedParentId = $state(phase?.parent_id ?? parentId ?? '');

  let titleError = $state('');
  let submitting = $state(false);

  const STATUSES: { value: PhaseStatus; label: string }[] = [
    { value: 'active',      label: 'Active'      },
    { value: 'in_progress', label: 'In Progress' },
    { value: 'completed',   label: 'Completed'   },
    { value: 'blocked',     label: 'Blocked'     },
  ];

  const PRIORITIES: PhasePriority[] = ['low', 'medium', 'high'];

  const PRIORITY_COLORS: Record<string, string> = {
    low: '#3b82f6', medium: '#f59e0b', high: '#ef4444',
  };

  let parentOptions = $derived.by(() => {
    if (phase === undefined) return phasesStore.flatPhases;
    const selfAndDescendants = new Set<string>();
    function collect(id: string) {
      selfAndDescendants.add(id);
      const node = phasesStore.flatPhases.find(g => g.id === id);
      if (node !== undefined) node.children.forEach(c => collect(c.id));
    }
    collect(phase.id);
    return phasesStore.flatPhases.filter(g => !selfAndDescendants.has(g.id));
  });

  function validate(): boolean {
    titleError = '';
    if (!title.trim()) { titleError = 'Title is required.'; return false; }
    return true;
  }

  async function handleSubmit(e: SubmitEvent) {
    e.preventDefault();
    if (!validate()) return;
    submitting = true;
    const data: Partial<Phase> = {
      title: title.trim(),
      description: description.trim() || null,
      status,
      priority,
      parent_id: selectedParentId || null,
    };
    try {
      await onSubmit(data);
    } finally {
      submitting = false;
    }
  }
</script>

<div
  class="gf-backdrop"
  role="presentation"
  onclick={onCancel}
  aria-hidden="true"
></div>

<div
  class="gf-modal"
  role="dialog"
  aria-modal="true"
  aria-label={phase !== undefined ? 'Edit phase' : 'Create new phase'}
>
  <header class="gf-header">
    <h2 class="gf-title">{phase !== undefined ? 'Edit Phase' : 'New Phase'}</h2>
    <button class="gf-close" onclick={onCancel} aria-label="Close dialog" type="button">
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
        <path d="M18 6L6 18M6 6l12 12" />
      </svg>
    </button>
  </header>

  <form class="gf-form" onsubmit={handleSubmit} novalidate>
    <div class="gf-field">
      <label class="gf-label" for="gf-title">Title <span class="gf-required" aria-label="required">*</span></label>
      <input
        id="gf-title"
        class="gf-input"
        class:gf-input--error={!!titleError}
        type="text"
        placeholder="Phase title..."
        bind:value={title}
        aria-required="true"
        aria-describedby={titleError ? 'gf-title-error' : undefined}
        autocomplete="off"
      />
      {#if titleError}
        <span id="gf-title-error" class="gf-error" role="alert">{titleError}</span>
      {/if}
    </div>

    <div class="gf-field">
      <label class="gf-label" for="gf-desc">Description</label>
      <textarea
        id="gf-desc"
        class="gf-textarea"
        placeholder="Describe this phase..."
        bind:value={description}
        rows={4}
      ></textarea>
    </div>

    <div class="gf-row">
      <div class="gf-field">
        <label class="gf-label" for="gf-status">Status</label>
        <select id="gf-status" class="gf-select" bind:value={status} aria-label="Select status">
          {#each STATUSES as s (s.value)}
            <option value={s.value}>{s.label}</option>
          {/each}
        </select>
      </div>

      <div class="gf-field">
        <label class="gf-label" for="gf-priority">Priority</label>
        <select id="gf-priority" class="gf-select" bind:value={priority} aria-label="Select priority">
          {#each PRIORITIES as p (p)}
            <option value={p} style="color: {PRIORITY_COLORS[p]}">{p.charAt(0).toUpperCase() + p.slice(1)}</option>
          {/each}
        </select>
      </div>
    </div>

    <div class="gf-field">
      <label class="gf-label" for="gf-parent">Parent Phase</label>
      <select id="gf-parent" class="gf-select" bind:value={selectedParentId} aria-label="Select parent phase">
        <option value="">No parent (top-level)</option>
        {#each parentOptions as pg (pg.id)}
          <option value={pg.id}>{pg.title}</option>
        {/each}
      </select>
    </div>

    <footer class="gf-actions">
      <button class="gf-btn gf-btn--cancel" type="button" onclick={onCancel} aria-label="Cancel">Cancel</button>
      <button class="gf-btn gf-btn--submit" type="submit" disabled={submitting} aria-label={phase !== undefined ? 'Save phase' : 'Create phase'}>
        {submitting ? 'Saving…' : (phase !== undefined ? 'Save Changes' : 'Create Phase')}
      </button>
    </footer>
  </form>
</div>

<style>
  .gf-backdrop {
    position: fixed; inset: 0;
    background: rgba(0,0,0,0.6);
    backdrop-filter: blur(4px);
    z-index: 100;
  }

  .gf-modal {
    position: fixed; top: 50%; left: 50%;
    transform: translate(-50%, -50%);
    z-index: 101;
    width: 480px;
    max-width: calc(100vw - 48px);
    max-height: calc(100vh - 80px);
    background: var(--bg-tertiary);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-lg);
    display: flex; flex-direction: column;
    overflow: hidden;
    box-shadow: 0 24px 80px rgba(0,0,0,0.6);
  }

  .gf-header {
    display: flex; align-items: center; justify-content: space-between;
    padding: 16px 20px;
    border-bottom: 1px solid var(--border-default);
    flex-shrink: 0;
  }

  .gf-title { font-size: 15px; font-weight: 600; color: var(--text-primary); margin: 0; }

  .gf-close {
    display: flex; align-items: center; justify-content: center;
    width: 28px; height: 28px;
    border: none; background: transparent; color: var(--text-tertiary);
    cursor: pointer; border-radius: var(--radius-xs);
    transition: background 100ms, color 100ms;
  }
  .gf-close:hover { background: rgba(255,255,255,0.07); color: var(--text-primary); }
  .gf-close:focus-visible { outline: 2px solid var(--accent-primary); }

  .gf-form {
    padding: 20px; display: flex; flex-direction: column; gap: 14px;
    overflow-y: auto; flex: 1;
  }

  .gf-field { display: flex; flex-direction: column; gap: 5px; }
  .gf-row { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }

  .gf-label { font-size: 12px; font-weight: 500; color: var(--text-secondary); }
  .gf-required { color: var(--accent-error); margin-left: 2px; }

  .gf-input, .gf-select, .gf-textarea {
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-sm);
    color: var(--text-primary);
    font-size: 13px; font-family: inherit;
    padding: 7px 10px;
    transition: border-color 150ms ease; outline: none;
  }
  .gf-input:focus, .gf-select:focus, .gf-textarea:focus { border-color: var(--accent-primary); }
  .gf-input--error { border-color: var(--accent-error) !important; }
  .gf-textarea { resize: vertical; min-height: 80px; line-height: 1.5; }
  .gf-error { font-size: 11px; color: var(--accent-error); }

  .gf-actions {
    display: flex; justify-content: flex-end; gap: 8px; padding-top: 4px;
  }

  .gf-btn {
    height: 32px; padding: 0 14px;
    border-radius: var(--radius-sm);
    font-size: 13px; font-weight: 500; font-family: inherit;
    cursor: pointer; border: none;
    transition: opacity 150ms ease, background 150ms ease;
  }
  .gf-btn--cancel {
    background: var(--bg-elevated); color: var(--text-secondary);
    border: 1px solid var(--border-default);
  }
  .gf-btn--cancel:hover { background: rgba(255,255,255,0.07); }
  .gf-btn--cancel:focus-visible { outline: 2px solid var(--accent-primary); }
  .gf-btn--submit { background: var(--accent-primary); color: #fff; }
  .gf-btn--submit:hover { opacity: 0.88; }
  .gf-btn--submit:disabled { opacity: 0.5; cursor: not-allowed; }
  .gf-btn--submit:focus-visible { outline: 2px solid var(--accent-primary); outline-offset: 2px; }
</style>
