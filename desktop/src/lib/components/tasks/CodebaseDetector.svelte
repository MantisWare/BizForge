<!-- src/lib/components/tasks/CodebaseDetector.svelte -->
<!-- Phase 2: Detects existing codebase or prompts for scaffolding -->
<script lang="ts">
  import type { ForgeMapDetection } from '$api/types';

  interface Props {
    detection: ForgeMapDetection | null;
    loading: boolean;
    onScan: () => void;
    onScaffold: (stack: string, template: string) => void;
  }

  let { detection, loading, onScan, onScaffold }: Props = $props();

  let selectedStack = $state('');
  let selectedTemplate = $state('starter');

  const STACKS = [
    { id: 'react', label: 'React (Vite)' },
    { id: 'nextjs', label: 'Next.js' },
    { id: 'sveltekit', label: 'SvelteKit' },
    { id: 'phoenix', label: 'Phoenix (Elixir)' },
    { id: 'express', label: 'Express (Node.js)' },
    { id: 'fastapi', label: 'FastAPI (Python)' },
    { id: 'django', label: 'Django (Python)' },
    { id: 'rails', label: 'Ruby on Rails' },
    { id: 'go', label: 'Go' },
    { id: 'rust', label: 'Rust' },
  ];

  const TEMPLATES = [
    { id: 'starter', label: 'Starter', desc: 'Minimal setup with core tooling' },
    { id: 'fullstack', label: 'Full-Stack', desc: 'Frontend + API + database' },
    { id: 'api-only', label: 'API Only', desc: 'Backend REST/GraphQL API' },
    { id: 'monorepo', label: 'Monorepo', desc: 'Multi-package workspace' },
  ];
</script>

<div class="cbd-container">
  {#if loading}
    <div class="cbd-loading">
      <div class="cbd-spinner" aria-hidden="true"></div>
      <p>Detecting codebase…</p>
    </div>
  {:else if detection === null}
    <div class="cbd-loading">
      <p class="cbd-muted">No detection results yet.</p>
    </div>
  {:else if detection.has_codebase}
    <div class="cbd-result cbd-result--found">
      <div class="cbd-icon-wrap cbd-icon--found">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <polyline points="20 6 9 17 4 12" />
        </svg>
      </div>
      <div class="cbd-info">
        <h4 class="cbd-heading">Existing codebase detected</h4>
        <p class="cbd-stats">
          {detection.file_count} source file{detection.file_count !== 1 ? 's' : ''}
          {#if detection.languages.length > 0}
            — {detection.languages.join(', ')}
          {/if}
        </p>
        {#if detection.detected_stack.length > 0}
          <div class="cbd-stack-tags">
            {#each detection.detected_stack as stack}
              <span class="cbd-tag">{stack}</span>
            {/each}
          </div>
        {/if}
        {#if detection.manifests.length > 0}
          <p class="cbd-manifests">
            Manifests: {detection.manifests.slice(0, 5).join(', ')}
            {#if detection.manifests.length > 5}
              +{detection.manifests.length - 5} more
            {/if}
          </p>
        {/if}
      </div>
      <button class="cbd-btn cbd-btn--primary" type="button" onclick={onScan}>
        Scan & Index
      </button>
    </div>
  {:else}
    <div class="cbd-result cbd-result--empty">
      <div class="cbd-icon-wrap cbd-icon--empty">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
          <polyline points="14 2 14 8 20 8" />
          <line x1="12" y1="18" x2="12" y2="12" />
          <line x1="9" y1="15" x2="15" y2="15" />
        </svg>
      </div>
      <div class="cbd-info">
        <h4 class="cbd-heading">No codebase found</h4>
        <p class="cbd-stats">Choose a tech stack and template to scaffold a new project.</p>

        <div class="cbd-scaffold-form">
          <div class="cbd-field">
            <label class="cbd-label" for="cbd-stack">Tech Stack</label>
            <select id="cbd-stack" class="cbd-select" bind:value={selectedStack}>
              <option value="">Select a stack…</option>
              {#each STACKS as s (s.id)}
                <option value={s.id}>{s.label}</option>
              {/each}
            </select>
          </div>

          <div class="cbd-field">
            <label class="cbd-label" for="cbd-template">Template</label>
            <div class="cbd-template-grid">
              {#each TEMPLATES as tmpl (tmpl.id)}
                <button
                  type="button"
                  class="cbd-template-card"
                  class:cbd-template-card--active={selectedTemplate === tmpl.id}
                  onclick={() => { selectedTemplate = tmpl.id; }}
                >
                  <span class="cbd-template-name">{tmpl.label}</span>
                  <span class="cbd-template-desc">{tmpl.desc}</span>
                </button>
              {/each}
            </div>
          </div>
        </div>
      </div>
      <button
        class="cbd-btn cbd-btn--primary"
        type="button"
        disabled={selectedStack === ''}
        onclick={() => onScaffold(selectedStack, selectedTemplate)}
      >
        Scaffold Project
      </button>
    </div>
  {/if}
</div>

<style>
  .cbd-container { display: flex; flex-direction: column; gap: 12px; }

  .cbd-loading {
    display: flex; flex-direction: column; align-items: center; justify-content: center;
    gap: 12px; min-height: 120px; color: var(--text-tertiary); font-size: 13px;
  }

  .cbd-spinner {
    width: 24px; height: 24px;
    border: 2px solid var(--border-default); border-top-color: #f97316;
    border-radius: 50%; animation: cbd-spin 0.8s linear infinite;
  }
  @keyframes cbd-spin { to { transform: rotate(360deg); } }

  .cbd-muted { color: var(--text-muted); margin: 0; }

  .cbd-result {
    display: flex; flex-direction: column; gap: 12px;
    padding: 16px; border-radius: 10px;
    border: 1px solid var(--border-default);
  }

  .cbd-result--found { background: rgba(34, 197, 94, 0.04); border-color: rgba(34, 197, 94, 0.2); }
  .cbd-result--empty { background: rgba(249, 115, 22, 0.04); border-color: rgba(249, 115, 22, 0.15); }

  .cbd-icon-wrap { width: 36px; height: 36px; border-radius: 8px; display: flex; align-items: center; justify-content: center; }
  .cbd-icon--found { background: rgba(34, 197, 94, 0.12); color: #22c55e; }
  .cbd-icon--empty { background: rgba(249, 115, 22, 0.12); color: #f97316; }

  .cbd-info { flex: 1; display: flex; flex-direction: column; gap: 4px; }
  .cbd-heading { margin: 0; font-size: 14px; font-weight: 600; color: var(--text-primary); }
  .cbd-stats { margin: 0; font-size: 12px; color: var(--text-secondary); }
  .cbd-manifests { margin: 0; font-size: 11px; color: var(--text-muted); font-family: var(--font-mono, monospace); }

  .cbd-stack-tags { display: flex; flex-wrap: wrap; gap: 4px; margin-top: 4px; }
  .cbd-tag {
    font-size: 10px; font-weight: 600; padding: 2px 7px; border-radius: 10px;
    background: rgba(249, 115, 22, 0.1); border: 1px solid rgba(249, 115, 22, 0.2);
    color: #fdba74;
  }

  .cbd-scaffold-form { display: flex; flex-direction: column; gap: 12px; margin-top: 8px; }
  .cbd-field { display: flex; flex-direction: column; gap: 4px; }
  .cbd-label { font-size: 11px; font-weight: 600; color: var(--text-secondary); text-transform: uppercase; letter-spacing: 0.5px; }

  .cbd-select {
    height: 32px; padding: 0 10px; border-radius: 6px; font-size: 13px;
    background: var(--bg-elevated); border: 1px solid var(--border-default);
    color: var(--text-primary); font-family: inherit;
  }
  .cbd-select:focus { outline: none; border-color: #f97316; }

  .cbd-template-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 6px; }

  .cbd-template-card {
    display: flex; flex-direction: column; gap: 2px; padding: 8px 10px;
    border-radius: 6px; border: 1px solid var(--border-default);
    background: transparent; cursor: pointer; text-align: left;
    transition: all 100ms ease; font-family: inherit;
  }
  .cbd-template-card:hover { border-color: rgba(249, 115, 22, 0.3); background: var(--bg-elevated); }
  .cbd-template-card--active { border-color: #f97316; background: rgba(249, 115, 22, 0.06); }
  .cbd-template-name { font-size: 12px; font-weight: 600; color: var(--text-primary); }
  .cbd-template-desc { font-size: 10px; color: var(--text-muted); }

  .cbd-btn {
    height: 32px; padding: 0 14px; border-radius: 6px; font-size: 13px;
    font-weight: 500; cursor: pointer; font-family: inherit; align-self: flex-start;
    transition: all 100ms ease;
  }
  .cbd-btn--primary {
    background: rgba(249, 115, 22, 0.12); border: 1px solid rgba(249, 115, 22, 0.35); color: #fdba74;
  }
  .cbd-btn--primary:hover:not(:disabled) { background: rgba(249, 115, 22, 0.2); border-color: rgba(249, 115, 22, 0.5); }
  .cbd-btn:disabled { opacity: 0.5; cursor: not-allowed; }
</style>
