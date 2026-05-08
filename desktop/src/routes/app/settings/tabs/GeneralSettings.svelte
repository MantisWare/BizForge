<!-- src/routes/app/settings/tabs/GeneralSettings.svelte -->
<script lang="ts">
  import { goto } from '$app/navigation';
  import { settingsStore } from '$lib/stores/settings.svelte';
  import { providersStore } from '$lib/stores/providers.svelte';
  import { toastStore } from '$lib/stores/toasts.svelte';
  import { clearToken, clearCache, clearSavedCredentials } from '$api/client';
  import { isTauri } from '$lib/utils/platform';

  let loggingOut = $state(false);
  let refreshingModels = $state(false);
  let changingDir = $state(false);

  const ADAPTER_OPTIONS: { value: string; label: string }[] = [
    { value: 'osa',         label: 'OSA (default)' },
    { value: 'claude_code', label: 'Claude Code' },
    { value: 'codex',       label: 'Codex' },
    { value: 'openclaw',    label: 'OpenClaw' },
    { value: 'jidoclaw',    label: 'JidoClaw' },
    { value: 'hermes',      label: 'Hermes' },
    { value: 'bash',        label: 'Bash' },
    { value: 'http',        label: 'HTTP' },
    { value: 'custom',      label: 'Custom' },
  ];

  interface GroupedModel {
    providerName: string;
    models: string[];
  }

  const groupedModels = $derived.by((): GroupedModel[] => {
    const groups = new Map<string, GroupedModel>();
    for (const entry of providersStore.allModels) {
      let group = groups.get(entry.providerName);
      if (group === undefined) {
        group = { providerName: entry.providerName, models: [] };
        groups.set(entry.providerName, group);
      }
      group.models.push(entry.model);
    }
    return Array.from(groups.values()).sort((a, b) =>
      a.providerName.localeCompare(b.providerName),
    );
  });

  const hasModels = $derived(groupedModels.length > 0);

  async function handleRefreshModels(): Promise<void> {
    refreshingModels = true;
    try {
      await providersStore.fetch();
      const connected = providersStore.configured;
      let totalFetched = 0;
      for (const provider of connected) {
        const models = await providersStore.fetchModelsForProvider(provider.id);
        totalFetched += models.length;
      }
      if (totalFetched === 0 && connected.length === 0) {
        toastStore.error(
          'No providers configured',
          'Add an AI provider in the Providers tab first.',
        );
      }
    } catch {
      toastStore.error('Refresh failed', 'Could not refresh model list.');
    } finally {
      refreshingModels = false;
    }
  }

  function handleModelChange(e: Event): void {
    const value = (e.target as HTMLSelectElement).value;
    settingsStore.update('default_model', value);
  }

  async function handleChooseDirectory(): Promise<void> {
    if (!isTauri()) {
      toastStore.error('Not available', 'Folder selection requires the desktop app.');
      return;
    }

    changingDir = true;
    try {
      const { open } = await import('@tauri-apps/plugin-dialog');
      const selected = await open({
        directory: true,
        multiple: false,
        title: 'Select Parent Directory for .bizforge Workspace',
      });

      if (selected === null || typeof selected !== 'string') {
        return;
      }

      const currentDir = settingsStore.data.working_directory;
      const hasExisting = currentDir !== undefined && currentDir.trim() !== '';

      if (hasExisting) {
        const { invoke } = await import('@tauri-apps/api/core');
        const result = await invoke<{
          new_path: string;
          files_copied: number;
          bytes_copied: number;
        }>('copy_working_directory', {
          currentPath: currentDir,
          newParent: selected,
        });
        settingsStore.update('working_directory', result.new_path);
        const sizeKb = Math.round(result.bytes_copied / 1024);
        toastStore.success(
          'Working directory moved',
          `${result.files_copied} file${result.files_copied !== 1 ? 's' : ''} (${sizeKb} KB) copied to ${result.new_path}`,
        );
      } else {
        const newPath = selected.endsWith('/')
          ? `${selected}.bizforge`
          : `${selected}/.bizforge`;
        settingsStore.update('working_directory', newPath);
        toastStore.success('Working directory set', newPath);
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      toastStore.error('Failed to change directory', msg);
    } finally {
      changingDir = false;
    }
  }

  async function handleLogout() {
    loggingOut = true;
    await clearToken();
    await clearSavedCredentials();
    clearCache();
    try {
      localStorage.removeItem('bizforge-workspaces');
      localStorage.removeItem('bizforge-active-workspace');
      localStorage.removeItem('bizforge-onboarding');
      localStorage.removeItem('bizforge-onboarding-complete');
      localStorage.removeItem('bizforge-offline-queue');
    } catch { /* non-fatal */ }
    goto('/');
  }
</script>

<section class="stg-section">
  <h2 class="stg-section-title">General</h2>

  <div class="stg-card">
    <!-- Working Directory -->
    <div class="stg-field">
      <label class="stg-label" for="working-dir">Working Directory</label>
      <p class="stg-desc">
        Default workspace path for agent file operations. Select a parent
        directory — a <code>.bizforge</code> folder will be created inside it.
        {#if settingsStore.data.working_directory}
          Changing the directory will copy all existing workspace files to the new location.
        {/if}
      </p>
      <div class="stg-row">
        <input
          id="working-dir"
          class="stg-input stg-input-grow"
          type="text"
          placeholder="/Users/you/projects"
          readonly
          value={settingsStore.data.working_directory}
        />
        <button
          class="stg-icon-btn"
          title="Choose directory"
          disabled={changingDir}
          onclick={handleChooseDirectory}
        >
          {#if changingDir}
            <span class="stg-spinner"></span>
          {:else}
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
              <path d="M2 3.5A1.5 1.5 0 0 1 3.5 2h2.879a1.5 1.5 0 0 1 1.06.44L8.562 3.56A1.5 1.5 0 0 0 9.621 4H12.5A1.5 1.5 0 0 1 14 5.5v7a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 2 12.5v-9Z" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/>
            </svg>
          {/if}
        </button>
      </div>
    </div>

    <div class="stg-sep"></div>

    <!-- Default Adapter -->
    <div class="stg-field">
      <label class="stg-label" for="default-adapter">Default Adapter</label>
      <p class="stg-desc">The execution adapter used when spawning new agents.</p>
      <select
        id="default-adapter"
        class="stg-select"
        value={settingsStore.data.default_adapter}
        onchange={(e) => settingsStore.update('default_adapter', (e.target as HTMLSelectElement).value as typeof settingsStore.data.default_adapter)}
      >
        {#each ADAPTER_OPTIONS as opt (opt.value)}
          <option value={opt.value}>{opt.label}</option>
        {/each}
      </select>
    </div>

    <div class="stg-sep"></div>

    <!-- Default Model -->
    <div class="stg-field">
      <label class="stg-label" for="default-model">Default Model</label>
      <p class="stg-desc">
        Select the AI model used for new sessions. Models are grouped by provider.
      </p>
      <div class="stg-row">
        {#if hasModels}
          <select
            id="default-model"
            class="stg-select stg-input-grow"
            value={settingsStore.data.default_model}
            onchange={handleModelChange}
          >
            {#each groupedModels as group (group.providerName)}
              <optgroup label={group.providerName}>
                {#each group.models as model (model)}
                  <option value={model}>{model}</option>
                {/each}
              </optgroup>
            {/each}
          </select>
        {:else}
          <input
            id="default-model"
            class="stg-input stg-input-grow"
            type="text"
            placeholder="claude-sonnet-4-6"
            value={settingsStore.data.default_model}
            oninput={(e) => settingsStore.update('default_model', (e.target as HTMLInputElement).value)}
          />
        {/if}
        <button
          class="stg-icon-btn"
          title="Refresh model list from all providers"
          disabled={refreshingModels}
          onclick={handleRefreshModels}
        >
          {#if refreshingModels}
            <span class="stg-spinner"></span>
          {:else}
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
              <path d="M14 8A6 6 0 1 1 8 2" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/>
              <path d="M8 0v4l3-2-3-2Z" fill="currentColor"/>
            </svg>
          {/if}
        </button>
      </div>
      {#if !hasModels}
        <p class="stg-hint">
          No models loaded. Click refresh or add a provider in the
          <button class="stg-link-btn" onclick={() => goto('/app/settings?tab=providers')}>AI Providers</button> tab.
        </p>
      {/if}
    </div>
  </div>
</section>

<section class="stg-logout-section">
  <div class="stg-logout-card">
    <div class="stg-logout-info">
      <span class="stg-logout-title">Log Out</span>
      <span class="stg-logout-desc">Sign out of your account and clear all local session data.</span>
    </div>
    <button
      class="stg-logout-btn"
      onclick={handleLogout}
      disabled={loggingOut}
    >
      {loggingOut ? 'Logging out...' : 'Log Out'}
    </button>
  </div>
</section>

<style>
  .stg-section { max-width: 640px; }

  .stg-section-title {
    font-size: 15px;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0 0 4px;
  }

  .stg-card {
    background: var(--bg-surface);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-md);
    padding: 4px 0;
    margin-top: 16px;
  }

  .stg-sep {
    height: 1px;
    background: var(--border-default);
    margin: 0;
  }

  .stg-field {
    padding: 14px 16px;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .stg-label {
    font-size: 13px;
    font-weight: 500;
    color: var(--text-primary);
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .stg-desc {
    font-size: 12px;
    color: var(--text-tertiary);
    line-height: 1.5;
  }

  .stg-desc code {
    font-size: 11px;
    padding: 1px 4px;
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    border-radius: 3px;
    color: var(--text-secondary);
  }

  .stg-input {
    width: 100%;
    padding: 7px 10px;
    font-size: 13px;
    color: var(--text-primary);
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-sm);
    outline: none;
    transition: border-color var(--transition-fast);
  }

  .stg-input:focus { border-color: var(--border-focus); }
  .stg-input::placeholder { color: var(--text-muted); }
  .stg-input[readonly] { cursor: default; opacity: 0.85; }

  .stg-input-grow { flex: 1; min-width: 0; }

  .stg-select {
    width: 100%;
    padding: 7px 10px;
    font-size: 13px;
    color: var(--text-primary);
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-sm);
    outline: none;
    cursor: pointer;
    transition: border-color var(--transition-fast);
    appearance: auto;
  }

  .stg-select:focus { border-color: var(--border-focus); }

  .stg-row {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .stg-icon-btn {
    flex-shrink: 0;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 32px;
    height: 32px;
    border: 1px solid var(--border-default);
    border-radius: var(--radius-sm);
    background: var(--bg-elevated);
    color: var(--text-secondary);
    cursor: pointer;
    transition: background var(--transition-fast), color var(--transition-fast),
      border-color var(--transition-fast);
  }

  .stg-icon-btn:hover:not(:disabled) {
    background: var(--bg-hover);
    color: var(--text-primary);
    border-color: var(--border-focus);
  }

  .stg-icon-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .stg-spinner {
    display: inline-block;
    width: 14px;
    height: 14px;
    border: 2px solid var(--border-default);
    border-top-color: var(--text-primary);
    border-radius: 50%;
    animation: stg-spin 0.6s linear infinite;
  }

  @keyframes stg-spin {
    to { transform: rotate(360deg); }
  }

  .stg-hint {
    font-size: 11px;
    color: var(--text-muted);
    line-height: 1.4;
  }

  .stg-link-btn {
    background: none;
    border: none;
    color: var(--color-accent, #3b82f6);
    cursor: pointer;
    font-size: 11px;
    padding: 0;
    text-decoration: underline;
  }

  .stg-link-btn:hover { opacity: 0.8; }

  .stg-logout-section {
    max-width: 640px;
    margin-top: 32px;
  }

  .stg-logout-card {
    background: var(--bg-surface);
    border: 1px solid var(--border-danger, #ef4444);
    border-radius: var(--radius-md);
    padding: 20px;
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 16px;
  }

  .stg-logout-info {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .stg-logout-title {
    font-size: 14px;
    font-weight: 600;
    color: var(--text-primary);
  }

  .stg-logout-desc {
    font-size: 12px;
    color: var(--text-tertiary);
    line-height: 1.5;
  }

  .stg-logout-btn {
    padding: 8px 20px;
    font-size: 13px;
    font-weight: 500;
    color: #fff;
    background: var(--color-danger, #ef4444);
    border: none;
    border-radius: var(--radius-sm);
    cursor: pointer;
    white-space: nowrap;
    transition: opacity var(--transition-fast);
  }

  .stg-logout-btn:hover { opacity: 0.9; }
  .stg-logout-btn:disabled { opacity: 0.5; cursor: not-allowed; }
</style>
