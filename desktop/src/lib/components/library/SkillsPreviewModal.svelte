<!-- src/lib/components/library/SkillsPreviewModal.svelte -->
<script lang="ts">
  import type { LibrarySkill } from '$lib/api/mock/library/types';

  interface Props {
    open: boolean;
    entityName: string;
    skillsToAdd: LibrarySkill[];
    skillsAlreadyActive: LibrarySkill[];
    onConfirm: () => void;
    onCancel: () => void;
  }

  let {
    open,
    entityName,
    skillsToAdd,
    skillsAlreadyActive,
    onConfirm,
    onCancel,
  }: Props = $props();

  const groupedToAdd = $derived.by(() => {
    const map = new Map<string, LibrarySkill[]>();
    for (const s of skillsToAdd) {
      const list = map.get(s.category) ?? [];
      list.push(s);
      map.set(s.category, list);
    }
    return map;
  });

  const groupedActive = $derived.by(() => {
    const map = new Map<string, LibrarySkill[]>();
    for (const s of skillsAlreadyActive) {
      const list = map.get(s.category) ?? [];
      list.push(s);
      map.set(s.category, list);
    }
    return map;
  });

  function formatCategory(cat: string): string {
    return cat.replace(/-/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
  }

  function handleBackdrop(e: MouseEvent) {
    if ((e.target as HTMLElement).classList.contains('spm-overlay')) onCancel();
  }

  function handleKeyDown(e: KeyboardEvent) {
    if (e.key === 'Escape') onCancel();
  }
</script>

{#if open}
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    class="spm-overlay"
    onclick={handleBackdrop}
    onkeydown={handleKeyDown}
    role="dialog"
    aria-modal="true"
    aria-label="Skills required for {entityName}"
    tabindex="-1"
  >
    <div class="spm-modal">
      <header class="spm-header">
        <h2 class="spm-title">Skills Required</h2>
        <button class="spm-close" onclick={onCancel} aria-label="Close dialog">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <path d="M18 6 6 18M6 6l12 12" />
          </svg>
        </button>
      </header>

      <div class="spm-body">
        <p class="spm-intro">
          <strong>{entityName}</strong> requires the following skills in your workspace.
        </p>

        {#if skillsToAdd.length > 0}
          <section class="spm-section">
            <h3 class="spm-section-title">
              <span class="spm-dot spm-dot--add"></span>
              Will be added ({skillsToAdd.length})
            </h3>
            {#each [...groupedToAdd.entries()] as [category, skills]}
              <div class="spm-group">
                <span class="spm-cat">{formatCategory(category)}</span>
                <div class="spm-chips">
                  {#each skills as skill}
                    <span class="spm-chip spm-chip--add" title={skill.description}>
                      {skill.name}
                    </span>
                  {/each}
                </div>
              </div>
            {/each}
          </section>
        {/if}

        {#if skillsAlreadyActive.length > 0}
          <section class="spm-section">
            <h3 class="spm-section-title">
              <span class="spm-dot spm-dot--active"></span>
              Already active ({skillsAlreadyActive.length})
            </h3>
            {#each [...groupedActive.entries()] as [category, skills]}
              <div class="spm-group">
                <span class="spm-cat">{formatCategory(category)}</span>
                <div class="spm-chips">
                  {#each skills as skill}
                    <span class="spm-chip spm-chip--active" title={skill.description}>
                      {skill.name}
                    </span>
                  {/each}
                </div>
              </div>
            {/each}
          </section>
        {/if}

        {#if skillsToAdd.length === 0 && skillsAlreadyActive.length === 0}
          <p class="spm-empty">No skills are required.</p>
        {/if}
      </div>

      <footer class="spm-footer">
        <button class="spm-btn spm-btn--secondary" onclick={onCancel}>Cancel</button>
        <div class="spm-spacer"></div>
        <button class="spm-btn spm-btn--primary" onclick={onConfirm}>
          {#if skillsToAdd.length > 0}
            Add {skillsToAdd.length} Skill{skillsToAdd.length === 1 ? '' : 's'} & Continue
          {:else}
            Continue
          {/if}
        </button>
      </footer>
    </div>
  </div>
{/if}

<style>
  .spm-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.6);
    backdrop-filter: blur(4px);
    -webkit-backdrop-filter: blur(4px);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1100;
    padding: 24px;
  }

  .spm-modal {
    background: var(--bg-tertiary);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-xl);
    width: 560px;
    max-width: 90vw;
    max-height: 70vh;
    display: flex;
    flex-direction: column;
    box-shadow: 0 24px 80px rgba(0, 0, 0, 0.5);
    overflow: hidden;
  }

  .spm-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 16px 20px;
    border-bottom: 1px solid var(--border-default);
    flex-shrink: 0;
  }

  .spm-title {
    font-size: 15px;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0;
  }

  .spm-close {
    width: 28px;
    height: 28px;
    border-radius: var(--radius-xs);
    border: 1px solid transparent;
    background: transparent;
    color: var(--text-tertiary);
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: all 120ms ease;
  }

  .spm-close:hover {
    background: var(--bg-elevated);
    border-color: var(--border-default);
    color: var(--text-primary);
  }

  .spm-body {
    flex: 1;
    overflow-y: auto;
    padding: 20px;
  }

  .spm-body::-webkit-scrollbar {
    width: 5px;
  }

  .spm-body::-webkit-scrollbar-thumb {
    background: var(--border-default);
    border-radius: 3px;
  }

  .spm-intro {
    font-size: 13px;
    color: var(--text-secondary);
    margin: 0 0 16px;
    line-height: 1.5;
  }

  .spm-section {
    margin-bottom: 16px;
  }

  .spm-section-title {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.6px;
    color: var(--text-tertiary);
    margin: 0 0 10px;
    padding-bottom: 6px;
    border-bottom: 1px solid var(--border-default);
  }

  .spm-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    flex-shrink: 0;
  }

  .spm-dot--add {
    background: rgba(59, 130, 246, 0.8);
  }

  .spm-dot--active {
    background: rgba(34, 197, 94, 0.7);
  }

  .spm-group {
    margin-bottom: 8px;
  }

  .spm-cat {
    display: block;
    font-size: 11px;
    font-weight: 500;
    color: var(--text-muted);
    margin-bottom: 4px;
  }

  .spm-chips {
    display: flex;
    flex-wrap: wrap;
    gap: 5px;
  }

  .spm-chip {
    display: inline-flex;
    align-items: center;
    height: 24px;
    padding: 0 8px;
    border-radius: var(--radius-xs);
    font-size: 11px;
    font-weight: 500;
    cursor: default;
    transition: background 120ms ease;
  }

  .spm-chip--add {
    background: rgba(59, 130, 246, 0.12);
    border: 1px solid rgba(59, 130, 246, 0.3);
    color: #93c5fd;
  }

  .spm-chip--active {
    background: rgba(34, 197, 94, 0.1);
    border: 1px solid rgba(34, 197, 94, 0.25);
    color: rgba(34, 197, 94, 0.8);
  }

  .spm-empty {
    font-size: 13px;
    color: var(--text-muted);
    text-align: center;
    padding: 24px 0;
  }

  .spm-footer {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 14px 20px;
    border-top: 1px solid var(--border-default);
    flex-shrink: 0;
    background: var(--bg-secondary);
  }

  .spm-spacer {
    flex: 1;
  }

  .spm-btn {
    height: 34px;
    padding: 0 16px;
    border-radius: var(--radius-sm);
    font-size: 13px;
    font-weight: 500;
    font-family: var(--font-sans);
    cursor: pointer;
    display: flex;
    align-items: center;
    gap: 6px;
    transition: all 120ms ease;
    border: 1px solid transparent;
    white-space: nowrap;
  }

  .spm-btn--secondary {
    background: transparent;
    border-color: var(--border-default);
    color: var(--text-secondary);
  }

  .spm-btn--secondary:hover {
    background: var(--bg-elevated);
    border-color: var(--border-hover);
    color: var(--text-primary);
  }

  .spm-btn--primary {
    background: rgba(59, 130, 246, 0.2);
    border-color: rgba(59, 130, 246, 0.5);
    color: #93c5fd;
  }

  .spm-btn--primary:hover {
    background: rgba(59, 130, 246, 0.3);
    border-color: rgba(59, 130, 246, 0.7);
    color: #bfdbfe;
  }
</style>
