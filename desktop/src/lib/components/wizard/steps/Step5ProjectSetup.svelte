<!-- src/lib/components/wizard/steps/Step5ProjectSetup.svelte -->
<script lang="ts">
  import { wizardStore } from '$lib/stores/wizard.svelte';
  import { isTauri } from '$lib/utils/platform';
  import { projects as projectsApi } from '$api/client';

  let lifecycleTemplates = $state<Array<{ id: string; name: string }>>([]);
  let loadingTemplates = $state(false);

  async function loadTemplates(): Promise<void> {
    loadingTemplates = true;
    try {
      const res = await projectsApi.lifecycleTemplates();
      const templates = (res as { templates?: Array<{ id: string; name: string }> }).templates ?? [];
      if (templates.length > 0) {
        lifecycleTemplates = templates;
      }
    } catch {
      // Use defaults
    }
    if (lifecycleTemplates.length === 0) {
      lifecycleTemplates = [
        { id: 'generic_development', name: 'Generic Development' },
        { id: 'domo_development', name: 'Domo Development' },
        { id: 'minimal', name: 'Minimal' },
      ];
    }
    loadingTemplates = false;
  }

  $effect(() => {
    if (wizardStore.currentStep === 5 && lifecycleTemplates.length === 0) {
      void loadTemplates();
    }
  });

  $effect(() => {
    if (wizardStore.projectName === '' && wizardStore.workspaceName) {
      wizardStore.projectName = wizardStore.workspaceName;
    }
  });

  $effect(() => {
    if (wizardStore.projectDescription === '' && wizardStore.enhancedContext !== null) {
      const lines = wizardStore.enhancedContext.split('\n').slice(0, 5).join('\n');
      wizardStore.projectDescription = lines;
    }
  });

  $effect(() => {
    if (wizardStore.outputPath === '' && wizardStore.workspacePath) {
      const base = wizardStore.workspacePath.replace(/\/?\.bizforge\/?$/, '');
      wizardStore.outputPath = `${base}/output`;
    }
  });

  async function pickOutputDir(): Promise<void> {
    if (!isTauri()) return;
    try {
      const { open } = await import('@tauri-apps/plugin-dialog');
      const selected = await open({ directory: true, title: 'Choose project output directory' });
      if (typeof selected === 'string') {
        wizardStore.outputPath = selected;
      }
    } catch {
      // User cancelled
    }
  }
</script>

<div class="s5-container">
  <h3 class="s5-heading">Project Setup</h3>
  <p class="s5-desc">Configure your first project. All agent work products, code, docs, and reports will be organized here.</p>

  <div class="s5-form">
    <label class="s5-label">
      <span class="s5-label-text">Project Name <span class="s5-required">*</span></span>
      <input
        type="text"
        class="s5-input"
        placeholder="e.g. My SaaS App"
        bind:value={wizardStore.projectName}
      />
    </label>

    <label class="s5-label">
      <span class="s5-label-text">Description</span>
      <textarea
        class="s5-textarea"
        rows="3"
        placeholder="What does this project deliver?"
        bind:value={wizardStore.projectDescription}
      ></textarea>
    </label>

    <label class="s5-label">
      <span class="s5-label-text">Output Directory</span>
      <span class="s5-hint">Where agent-produced code, docs, and artifacts will be saved.</span>
      <div class="s5-path-row">
        <input
          type="text"
          class="s5-input s5-path-input"
          placeholder="/path/to/output"
          bind:value={wizardStore.outputPath}
        />
        {#if isTauri()}
          <button class="s5-browse" onclick={pickOutputDir} type="button">Browse</button>
        {/if}
      </div>
    </label>

    <label class="s5-label">
      <span class="s5-label-text">Lifecycle Template</span>
      <span class="s5-hint">Defines the issue state machine (e.g. backlog &rarr; in_progress &rarr; review &rarr; done).</span>
      <select class="s5-select" bind:value={wizardStore.lifecycleTemplate}>
        {#each lifecycleTemplates as tmpl (tmpl.id)}
          <option value={tmpl.id}>{tmpl.name}</option>
        {/each}
      </select>
    </label>

    <div class="s5-toggle-row">
      <label class="s5-toggle-label">
        <input type="checkbox" class="s5-checkbox" bind:checked={wizardStore.autoAssign} />
        <span class="s5-toggle-text">Auto-assign tasks to agents</span>
      </label>
      <span class="s5-hint">When enabled, generated tasks are automatically assigned to the best-fit agent based on skill matching.</span>
    </div>
  </div>

  <!-- Scaffold preview -->
  <div class="s5-scaffold">
    <span class="s5-scaffold-label">Output directory will be scaffolded with:</span>
    <div class="s5-tree">
      <div class="s5-tree-line"><span class="s5-tree-icon">📁</span> code/src, code/tests, code/config</div>
      <div class="s5-tree-line"><span class="s5-tree-icon">📁</span> docs/specs, docs/guides, docs/api, docs/architecture</div>
      <div class="s5-tree-line"><span class="s5-tree-icon">📁</span> media/images, media/diagrams</div>
      <div class="s5-tree-line"><span class="s5-tree-icon">📁</span> data/exports, data/fixtures</div>
      <div class="s5-tree-line"><span class="s5-tree-icon">📁</span> reports, transcripts, issues</div>
      <div class="s5-tree-line"><span class="s5-tree-icon">📄</span> README.md, .gitignore, .bizforge-project.yaml</div>
    </div>
  </div>
</div>

<style>
  .s5-container { max-width: 560px; margin: 0 auto; }
  .s5-heading { font-size: 18px; font-weight: 600; margin: 0 0 6px; color: var(--text-primary); }
  .s5-desc { font-size: 13px; color: var(--text-secondary); margin: 0 0 24px; line-height: 1.5; }
  .s5-form { display: flex; flex-direction: column; gap: 18px; }
  .s5-label { display: flex; flex-direction: column; gap: 4px; }
  .s5-label-text { font-size: 13px; font-weight: 500; color: var(--text-primary); }
  .s5-required { color: var(--accent, #f97316); }
  .s5-hint { font-size: 11px; color: var(--text-tertiary); }
  .s5-input, .s5-select, .s5-textarea {
    background: rgba(255,255,255,0.04);
    border: 1px solid var(--border-subtle, rgba(255,255,255,0.08));
    border-radius: 8px; padding: 10px 12px;
    color: var(--text-primary); font-size: 14px; font-family: inherit;
    transition: border-color 0.15s;
  }
  .s5-input:focus, .s5-select:focus, .s5-textarea:focus {
    outline: none; border-color: var(--accent, #f97316);
  }
  .s5-select { appearance: auto; }
  .s5-textarea { resize: vertical; min-height: 60px; }
  .s5-path-row { display: flex; gap: 8px; }
  .s5-path-input { flex: 1; }
  .s5-browse {
    padding: 8px 16px; border-radius: 8px; font-size: 13px; font-weight: 500;
    background: rgba(255,255,255,0.06); color: var(--text-secondary);
    border: 1px solid var(--border-subtle, rgba(255,255,255,0.08));
    cursor: pointer; white-space: nowrap; transition: all 0.15s;
  }
  .s5-browse:hover { background: rgba(255,255,255,0.1); color: var(--text-primary); }
  .s5-toggle-row { display: flex; flex-direction: column; gap: 4px; }
  .s5-toggle-label {
    display: flex; align-items: center; gap: 8px; cursor: pointer;
  }
  .s5-checkbox {
    accent-color: var(--accent, #f97316);
    width: 16px; height: 16px;
  }
  .s5-toggle-text { font-size: 13px; font-weight: 500; color: var(--text-primary); }

  .s5-scaffold {
    margin-top: 24px; padding: 14px;
    border-radius: 10px; background: rgba(255,255,255,0.02);
    border: 1px solid var(--border-subtle, rgba(255,255,255,0.06));
  }
  .s5-scaffold-label { font-size: 11px; font-weight: 500; color: var(--text-secondary); display: block; margin-bottom: 10px; }
  .s5-tree { display: flex; flex-direction: column; gap: 4px; }
  .s5-tree-line {
    font-size: 12px; color: var(--text-tertiary);
    padding-left: 4px; display: flex; align-items: center; gap: 6px;
  }
  .s5-tree-icon { font-size: 13px; }
</style>
