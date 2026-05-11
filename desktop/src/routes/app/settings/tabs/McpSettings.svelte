<!-- src/routes/app/settings/tabs/McpSettings.svelte -->
<script lang="ts">
  import { onMount } from 'svelte';
  import { mcpStore } from '$lib/stores/mcp.svelte';
  import { toastStore } from '$lib/stores/toasts.svelte';

  let configSnippet = $state('');
  let copied = $state(false);

  const TOOLS = [
    { category: 'Agents',         tools: 'List, get, create, update, wake, sleep, pause, resume, terminate, hierarchy' },
    { category: 'Sessions',       tools: 'List, create, send message, get transcript' },
    { category: 'Task Dispatch',  tools: 'Spawn task, list active, kill, history' },
    { category: 'Workflows',      tools: 'List, get details, trigger, list runs' },
    { category: 'Projects',       tools: 'List, get, create' },
    { category: 'Tasks',          tools: 'List, create, update, assign, dispatch' },
    { category: 'Phases',         tools: 'List, create' },
    { category: 'Documents',      tools: 'List, read, write' },
    { category: 'Memory',         tools: 'Search, store, list namespaces' },
    { category: 'Skills',         tools: 'List, assign to agent' },
    { category: 'Schedules',      tools: 'List, create' },
    { category: 'Costs & Budget', tools: 'Summary, per-agent breakdown, budget policies' },
    { category: 'Activity & Logs', tools: 'Recent activity, log entries' },
    { category: 'Config',         tools: 'Get settings, update settings' },
    { category: 'Organization',   tools: 'Teams, hierarchy, conversations' },
    { category: 'Integrations',   tools: 'Webhooks, integrations status' },
  ] as const;

  onMount(() => {
    void mcpStore.fetchStatus();
    void mcpStore.fetchClientConfig().then(() => {
      if (mcpStore.clientConfig !== null) {
        configSnippet = JSON.stringify(mcpStore.clientConfig, null, 2);
      }
    });
  });

  async function handleBuild() {
    await mcpStore.build();
    if (mcpStore.error !== null) {
      toastStore.error('MCP Build Failed', mcpStore.error);
    } else {
      toastStore.success('MCP server built successfully');
      await mcpStore.fetchClientConfig();
      if (mcpStore.clientConfig !== null) {
        configSnippet = JSON.stringify(mcpStore.clientConfig, null, 2);
      }
    }
  }

  async function handleCopyConfig() {
    try {
      await navigator.clipboard.writeText(configSnippet);
      copied = true;
      toastStore.success('Configuration copied to clipboard');
      setTimeout(() => { copied = false; }, 2000);
    } catch {
      toastStore.error('Copy failed', 'Could not access clipboard');
    }
  }
</script>

<section class="stg-section">
  <h2 class="stg-section-title">MCP Server</h2>
  <p class="stg-section-desc">
    Expose BizForge as a Model Context Protocol (MCP) server so external AI
    agents and LLMs can interact with your workspace — manage agents, dispatch
    tasks, query data, and more.
  </p>

  <div class="stg-card">
    <!-- Server readiness -->
    <div class="stg-field stg-field--row">
      <div class="stg-field-text">
        <span class="stg-label">
          Server Status
          <span class="mcp-status-badge" class:mcp-status-badge--ready={mcpStore.isReady}>
            <span class="mcp-status-dot"></span>
            {mcpStore.isReady ? 'Ready' : 'Not Built'}
          </span>
        </span>
        <p class="stg-desc">
          {#if mcpStore.isReady}
            The MCP server is built and ready. Add the configuration below to your
            MCP client to connect.
          {:else}
            The MCP server needs to be built before external AI clients can use it.
          {/if}
        </p>
      </div>
      {#if !mcpStore.isReady}
        <button
          class="stg-btn stg-btn--primary"
          disabled={mcpStore.building}
          onclick={handleBuild}
          aria-label="Build MCP server"
        >
          {mcpStore.building ? 'Building…' : 'Build Server'}
        </button>
      {/if}
    </div>

    {#if mcpStore.error !== null}
      <div class="stg-sep"></div>
      <div class="stg-field">
        <p class="mcp-error">{mcpStore.error}</p>
      </div>
    {/if}

    <div class="stg-sep"></div>

    <!-- Server path -->
    <div class="stg-field">
      <span class="stg-label">Server Path</span>
      <p class="stg-desc mcp-mono">
        {mcpStore.status.server_path !== '' ? mcpStore.status.server_path : 'Not resolved'}
      </p>
    </div>
  </div>
</section>

<!-- How it works -->
<section class="stg-section stg-section--mt">
  <h2 class="stg-section-title">How It Works</h2>
  <p class="stg-section-desc">
    The MCP server is a standalone process launched by your AI client (Claude Desktop,
    Cursor, etc.) — not by BizForge itself. When an external AI calls a tool, the MCP
    server forwards the request to the BizForge backend API running on this machine.
  </p>

  <div class="mcp-steps">
    <div class="mcp-step">
      <span class="mcp-step-num">1</span>
      <div class="mcp-step-body">
        <span class="mcp-step-title">Build the server</span>
        <span class="mcp-step-desc">Click "Build Server" above (or run <code class="mcp-inline-code">npm run build</code> in <code class="mcp-inline-code">desktop/mcp-server/</code>).</span>
      </div>
    </div>
    <div class="mcp-step">
      <span class="mcp-step-num">2</span>
      <div class="mcp-step-body">
        <span class="mcp-step-title">Copy the config</span>
        <span class="mcp-step-desc">Copy the JSON snippet below and paste it into your MCP client's configuration.</span>
      </div>
    </div>
    <div class="mcp-step">
      <span class="mcp-step-num">3</span>
      <div class="mcp-step-body">
        <span class="mcp-step-title">Keep BizForge running</span>
        <span class="mcp-step-desc">The MCP server communicates with the BizForge backend, so it must be running for tools to work.</span>
      </div>
    </div>
  </div>
</section>

<!-- Client configuration -->
<section class="stg-section stg-section--mt">
  <h2 class="stg-section-title">Client Configuration</h2>
  <p class="stg-section-desc">
    Add this to your MCP client's configuration file to connect to BizForge.
  </p>

  <div class="stg-card">
    <div class="stg-field">
      <div class="mcp-config-header">
        <span class="stg-label">MCP Client Config (JSON)</span>
        <button
          class="stg-btn stg-btn--ghost stg-btn--sm"
          onclick={handleCopyConfig}
          aria-label="Copy configuration to clipboard"
        >
          {copied ? 'Copied!' : 'Copy'}
        </button>
      </div>
      <pre class="mcp-config-block"><code>{configSnippet !== '' ? configSnippet : 'Loading…'}</code></pre>
      <p class="stg-desc">
        For <strong>Claude Desktop</strong>, paste into <code class="mcp-inline-code">claude_desktop_config.json</code>.
        For <strong>Cursor</strong>, add via Settings > MCP Servers.
      </p>
    </div>
  </div>
</section>

<!-- Available tools catalog -->
<section class="stg-section stg-section--mt">
  <h2 class="stg-section-title">Available Tools ({TOOLS.length} categories, 59 tools)</h2>
  <p class="stg-section-desc">
    The MCP server exposes these tool categories. External AI agents can use
    any of them to interact with your BizForge workspace.
  </p>

  <div class="mcp-tools-grid">
    {#each TOOLS as tool (tool.category)}
      <div class="mcp-tool-card">
        <span class="mcp-tool-category">{tool.category}</span>
        <span class="mcp-tool-list">{tool.tools}</span>
      </div>
    {/each}
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

  .stg-section-desc {
    font-size: 13px;
    color: var(--text-secondary);
    margin: 0 0 16px;
    line-height: 1.5;
  }

  .stg-section--mt { margin-top: 32px; }

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

  .stg-field--row {
    flex-direction: row;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
  }

  .stg-field-text {
    display: flex;
    flex-direction: column;
    gap: 4px;
    flex: 1;
    min-width: 0;
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

  .stg-btn {
    display: inline-flex;
    align-items: center;
    padding: 7px 14px;
    font-size: 13px;
    font-weight: 500;
    border-radius: var(--radius-sm);
    cursor: pointer;
    transition: background var(--transition-fast), border-color var(--transition-fast);
    border: 1px solid;
    align-self: flex-start;
    flex-shrink: 0;
    white-space: nowrap;
  }

  .stg-btn:disabled {
    opacity: 0.5;
    cursor: default;
  }

  .stg-btn--primary {
    color: #fff;
    background: var(--accent-primary);
    border-color: var(--accent-primary);
  }

  .stg-btn--primary:hover:not(:disabled) {
    background: #2563eb;
    border-color: #2563eb;
  }

  .stg-btn--ghost {
    color: var(--text-primary);
    background: var(--bg-elevated);
    border-color: var(--border-default);
  }

  .stg-btn--ghost:hover:not(:disabled) {
    background: var(--bg-tertiary);
    border-color: var(--border-hover);
  }

  .stg-btn--sm {
    padding: 4px 10px;
    font-size: 12px;
  }

  /* ── MCP-specific ─────────────────────────────────── */

  .mcp-status-badge {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    font-size: 11px;
    font-weight: 500;
    padding: 2px 8px;
    border-radius: var(--radius-full);
    background: rgba(239, 68, 68, 0.1);
    color: var(--accent-error);
  }

  .mcp-status-badge--ready {
    background: rgba(34, 197, 94, 0.12);
    color: var(--accent-success);
  }

  .mcp-status-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: var(--accent-error);
  }

  .mcp-status-badge--ready .mcp-status-dot {
    background: var(--accent-success);
    box-shadow: 0 0 4px var(--accent-success);
  }

  .mcp-error {
    font-size: 12px;
    color: var(--accent-error);
    line-height: 1.5;
    margin: 0;
  }

  .mcp-mono {
    font-family: var(--font-mono, monospace);
    font-size: 11px;
    word-break: break-all;
  }

  .mcp-steps {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .mcp-step {
    display: flex;
    align-items: flex-start;
    gap: 12px;
  }

  .mcp-step-num {
    width: 24px;
    height: 24px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 12px;
    font-weight: 600;
    color: var(--accent-primary);
    background: rgba(59, 130, 246, 0.1);
    border-radius: 50%;
    flex-shrink: 0;
  }

  .mcp-step-body {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .mcp-step-title {
    font-size: 13px;
    font-weight: 500;
    color: var(--text-primary);
  }

  .mcp-step-desc {
    font-size: 12px;
    color: var(--text-tertiary);
    line-height: 1.5;
  }

  .mcp-config-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 8px;
  }

  .mcp-config-block {
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-sm);
    padding: 12px 14px;
    overflow-x: auto;
    font-size: 12px;
    font-family: var(--font-mono, monospace);
    line-height: 1.6;
    color: var(--text-primary);
    margin: 0 0 8px;
    white-space: pre;
  }

  .mcp-config-block code {
    font-family: inherit;
  }

  .mcp-inline-code {
    font-family: var(--font-mono, monospace);
    font-size: 11px;
    background: var(--bg-elevated);
    padding: 1px 5px;
    border-radius: 3px;
    border: 1px solid var(--border-default);
  }

  .mcp-tools-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
    gap: 8px;
    margin-top: 16px;
  }

  .mcp-tool-card {
    display: flex;
    flex-direction: column;
    gap: 4px;
    padding: 12px 14px;
    background: var(--bg-surface);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-md);
    transition: border-color var(--transition-fast);
  }

  .mcp-tool-card:hover {
    border-color: var(--border-hover);
  }

  .mcp-tool-category {
    font-size: 13px;
    font-weight: 500;
    color: var(--text-primary);
  }

  .mcp-tool-list {
    font-size: 12px;
    color: var(--text-tertiary);
    line-height: 1.4;
  }
</style>
