<!-- src/lib/components/wizard/steps/Step1Name.svelte -->
<script lang="ts">
  import { wizardStore } from '$lib/stores/wizard.svelte';
  import { isTauri } from '$lib/utils/platform';

  let pathError = $state<string | null>(null);

  async function pickDirectory(): Promise<void> {
    if (!isTauri()) return;
    try {
      const { open } = await import('@tauri-apps/plugin-dialog');
      const selected = await open({ directory: true, title: 'Choose workspace directory' });
      if (typeof selected === 'string') {
        wizardStore.workspacePath = selected;
        pathError = null;
      }
    } catch (e) {
      pathError = String(e);
    }
  }

  $effect(() => {
    if (wizardStore.workspaceName && !wizardStore.projectName) {
      wizardStore.projectName = wizardStore.workspaceName;
    }
  });

  $effect(() => {
    if (wizardStore.workspaceName && !wizardStore.workspacePath) {
      const slug = wizardStore.workspaceName
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-|-$/g, '');
      wizardStore.workspacePath = `~/.bizforge/${slug}`;
    }
  });
</script>

<div class="s1-container">
  <div class="s1-hero">
    <div class="s1-icon">
      <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="var(--accent, #f97316)" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <path d="M2.25 12.75V12A2.25 2.25 0 014.5 9.75h15A2.25 2.25 0 0121.75 12v.75m-8.69-6.44l-2.12-2.12a1.5 1.5 0 00-1.061-.44H4.5A2.25 2.25 0 002.25 6v12a2.25 2.25 0 002.25 2.25h15A2.25 2.25 0 0021.75 18V9a2.25 2.25 0 00-2.25-2.25h-5.379a1.5 1.5 0 01-1.06-.44z" />
      </svg>
    </div>
    <h3 class="s1-heading">Name your workspace</h3>
    <p class="s1-desc">A workspace is your development environment. It holds agents, projects, documentation, and all configuration in one place.</p>
  </div>

  <div class="s1-form">
    <label class="s1-label">
      <span class="s1-label-text">Workspace Name <span class="s1-required">*</span></span>
      <input
        type="text"
        class="s1-input"
        placeholder="e.g. My SaaS App, E-Commerce Platform, Data Pipeline"
        bind:value={wizardStore.workspaceName}
        autofocus
      />
    </label>

    <label class="s1-label">
      <span class="s1-label-text">Description</span>
      <textarea
        class="s1-textarea"
        placeholder="A brief summary of what this workspace is for..."
        rows="3"
        bind:value={wizardStore.workspaceDescription}
      ></textarea>
    </label>

    <label class="s1-label">
      <span class="s1-label-text">Directory</span>
      <span class="s1-hint">Where the .bizforge/ configuration and project files will be stored.</span>
      <div class="s1-path-row">
        <input
          type="text"
          class="s1-input s1-path-input"
          placeholder="~/.bizforge/my-workspace"
          bind:value={wizardStore.workspacePath}
        />
        {#if isTauri()}
          <button class="s1-browse" onclick={pickDirectory} type="button">Browse</button>
        {/if}
      </div>
      {#if pathError}
        <span class="s1-error">{pathError}</span>
      {/if}
    </label>
  </div>
</div>

<style>
  .s1-container { max-width: 560px; margin: 0 auto; }
  .s1-hero { text-align: center; margin-bottom: 32px; }
  .s1-icon {
    width: 72px; height: 72px; border-radius: 16px;
    background: rgba(249,115,22,0.1);
    display: flex; align-items: center; justify-content: center;
    margin: 0 auto 16px;
  }
  .s1-heading {
    font-size: 20px; font-weight: 600; margin: 0 0 8px;
    color: var(--text-primary);
  }
  .s1-desc {
    font-size: 13px; color: var(--text-secondary);
    margin: 0; line-height: 1.6; max-width: 420px; margin: 0 auto;
  }
  .s1-form { display: flex; flex-direction: column; gap: 20px; }
  .s1-label { display: flex; flex-direction: column; gap: 6px; }
  .s1-label-text {
    font-size: 13px; font-weight: 500; color: var(--text-primary);
  }
  .s1-required { color: var(--accent, #f97316); }
  .s1-hint { font-size: 11px; color: var(--text-tertiary); }
  .s1-input, .s1-textarea {
    background: rgba(255,255,255,0.04);
    border: 1px solid var(--border-subtle, rgba(255,255,255,0.08));
    border-radius: 8px; padding: 10px 12px;
    color: var(--text-primary); font-size: 14px;
    font-family: inherit; transition: border-color 0.15s;
  }
  .s1-input:focus, .s1-textarea:focus {
    outline: none; border-color: var(--accent, #f97316);
  }
  .s1-textarea { resize: vertical; min-height: 60px; }
  .s1-path-row { display: flex; gap: 8px; }
  .s1-path-input { flex: 1; }
  .s1-browse {
    padding: 8px 16px; border-radius: 8px; font-size: 13px; font-weight: 500;
    background: rgba(255,255,255,0.06); color: var(--text-secondary);
    border: 1px solid var(--border-subtle, rgba(255,255,255,0.08));
    cursor: pointer; white-space: nowrap; transition: all 0.15s;
  }
  .s1-browse:hover { background: rgba(255,255,255,0.1); color: var(--text-primary); }
  .s1-error { font-size: 12px; color: #ef4444; }
</style>
