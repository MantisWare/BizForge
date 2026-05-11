<!-- src/lib/components/inspector/LlmInspectorPanel.svelte -->
<script lang="ts">
  import { llmInspectorStore, type InspectorFilter } from '$lib/stores/llmInspector.svelte';
  import { hierarchyStore } from '$lib/stores/hierarchy.svelte';
  import { agentsStore } from '$lib/stores/agents.svelte';
  import type { LlmLogEntry } from '$api/types';
  import { browser } from '$app/environment';
  import OfficeMiniview from './OfficeMiniview.svelte';

  let expandedIds = $state<Set<string>>(new Set());
  let dragging = $state(false);
  let filterDropdownOpen = $state(false);

  let showMiniview = $state(true);
  $effect(() => {
    if (!browser) return;
    const stored = localStorage.getItem('bizforge-inspector-miniview');
    if (stored !== null) showMiniview = stored !== 'false';
  });
  function toggleMiniview(): void {
    showMiniview = !showMiniview;
    if (browser) localStorage.setItem('bizforge-inspector-miniview', String(showMiniview));
  }

  const isOpen = $derived(llmInspectorStore.isOpen);
  const panelWidth = $derived(llmInspectorStore.panelWidth);
  const fontSize = $derived(llmInspectorStore.fontSize);
  const allEntries = $derived(llmInspectorStore.entries);
  const searchQuery = $derived(llmInspectorStore.searchQuery);
  const activeFilter = $derived(llmInspectorStore.activeFilter);

  // ── Build agent-to-hierarchy lookup from the tree ─────────────────────
  interface AgentOrgInfo {
    teamId: string;
    teamName: string;
    departmentId: string;
    departmentName: string;
    divisionId: string;
    divisionName: string;
  }

  const agentOrgMap = $derived.by<Map<string, AgentOrgInfo>>(() => {
    const map = new Map<string, AgentOrgInfo>();
    const tree = hierarchyStore.tree;
    if (tree === null) return map;
    for (const div of tree.divisions) {
      for (const dept of div.departments) {
        for (const team of dept.teams) {
          for (const agent of team.agents) {
            map.set(agent.id, {
              teamId: team.id,
              teamName: team.name,
              departmentId: dept.id,
              departmentName: dept.name,
              divisionId: div.id,
              divisionName: div.name,
            });
          }
        }
      }
    }
    return map;
  });

  // ── Build filter options from hierarchy tree ──────────────────────────
  interface FilterOption {
    filter: InspectorFilter;
    indent: number;
  }

  const filterOptions = $derived.by<FilterOption[]>(() => {
    const opts: FilterOption[] = [
      { filter: { level: 'all', id: '', label: 'All' }, indent: 0 },
    ];
    const tree = hierarchyStore.tree;
    if (tree === null) return opts;
    for (const div of tree.divisions) {
      opts.push({ filter: { level: 'division', id: div.id, label: div.name }, indent: 0 });
      for (const dept of div.departments) {
        opts.push({ filter: { level: 'department', id: dept.id, label: dept.name }, indent: 1 });
        for (const team of dept.teams) {
          opts.push({ filter: { level: 'team', id: team.id, label: team.name }, indent: 2 });
          for (const agent of team.agents) {
            opts.push({ filter: { level: 'agent', id: agent.id, label: agent.display_name || agent.name }, indent: 3 });
          }
        }
      }
    }
    // Add unassigned agents (those with no team or not in the tree)
    const treeAgentIds = new Set(agentOrgMap.keys());
    const unassigned = agentsStore.agents.filter((a) => !treeAgentIds.has(a.id));
    if (unassigned.length > 0) {
      for (const agent of unassigned) {
        opts.push({ filter: { level: 'agent', id: agent.id, label: agent.display_name || agent.name }, indent: 0 });
      }
    }
    return opts;
  });

  // ── Collect matching agent IDs for hierarchy filters ──────────────────
  function getMatchingAgentIds(filter: InspectorFilter): Set<string> | null {
    if (filter.level === 'all') return null;
    if (filter.level === 'agent') return new Set([filter.id]);

    const ids = new Set<string>();
    const tree = hierarchyStore.tree;
    if (tree === null) return ids;

    for (const div of tree.divisions) {
      if (filter.level === 'division' && div.id !== filter.id) continue;
      for (const dept of div.departments) {
        if (filter.level === 'department' && dept.id !== filter.id) continue;
        for (const team of dept.teams) {
          if (filter.level === 'team' && team.id !== filter.id) continue;
          for (const agent of team.agents) {
            ids.add(agent.id);
          }
        }
      }
    }
    return ids;
  }

  // ── Filtered entries ──────────────────────────────────────────────────
  const entries = $derived.by<LlmLogEntry[]>(() => {
    let result = allEntries;

    const matchingIds = getMatchingAgentIds(activeFilter);
    if (matchingIds !== null) {
      result = result.filter((e) => {
        if (e.agentId === undefined) return false;
        return matchingIds.has(e.agentId);
      });
    }

    const q = searchQuery.trim().toLowerCase();
    if (q !== '') {
      result = result.filter((e) =>
        (e.agentName?.toLowerCase().includes(q) ?? false)
        || e.providerName.toLowerCase().includes(q)
        || e.providerSlug.toLowerCase().includes(q)
        || e.model.toLowerCase().includes(q)
      );
    }

    return result;
  });

  const isFiltered = $derived(activeFilter.level !== 'all' || searchQuery.trim() !== '');

  function selectFilter(filter: InspectorFilter): void {
    llmInspectorStore.setFilter(filter);
    filterDropdownOpen = false;
  }

  function toggleEntry(id: string): void {
    const next = new Set(expandedIds);
    if (next.has(id)) {
      next.delete(id);
    } else {
      next.add(id);
    }
    expandedIds = next;
  }

  function formatTimestamp(iso: string): string {
    try {
      const d = new Date(iso);
      return d.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false });
    } catch {
      return iso;
    }
  }

  function formatPayload(payload: unknown): string {
    if (payload === undefined || payload === null) return String(payload);
    try {
      if (typeof payload === 'string') return payload;
      return JSON.stringify(payload, null, 2) ?? String(payload);
    } catch {
      return String(payload);
    }
  }

  function onGutterPointerDown(e: PointerEvent): void {
    e.preventDefault();
    const target = e.currentTarget as HTMLElement;
    target.setPointerCapture(e.pointerId);
    dragging = true;

    const startX = e.clientX;
    const startWidth = panelWidth > 0 ? panelWidth : Math.round(window.innerWidth * 0.5);

    function onMove(ev: PointerEvent): void {
      const delta = startX - ev.clientX;
      const minW = 300;
      const maxW = Math.round(window.innerWidth * 0.8);
      const next = Math.max(minW, Math.min(maxW, startWidth + delta));
      llmInspectorStore.setWidth(next);
    }

    function onUp(): void {
      dragging = false;
      target.removeEventListener('pointermove', onMove);
      target.removeEventListener('pointerup', onUp);
      target.removeEventListener('pointercancel', onUp);
    }

    target.addEventListener('pointermove', onMove);
    target.addEventListener('pointerup', onUp);
    target.addEventListener('pointercancel', onUp);
  }

  function getDirectionIcon(dir: 'sent' | 'received'): string {
    return dir === 'sent' ? '↑' : '↓';
  }

  function getDirectionLabel(dir: 'sent' | 'received'): string {
    return dir === 'sent' ? 'Sent' : 'Received';
  }

  function getStatusClass(entry: LlmLogEntry): string {
    if (entry.status === 'error') return 'lip-status--error';
    if (entry.status === 'success') return 'lip-status--success';
    return 'lip-status--pending';
  }

  function getLevelIcon(level: string): string {
    if (level === 'division') return '◆';
    if (level === 'department') return '◇';
    if (level === 'team') return '▸';
    if (level === 'agent') return '●';
    return '○';
  }
</script>

{#if !isOpen}
  <!-- Collapsed rail on the right edge -->
  <div class="lip-rail">
    <button
      class="lip-tab"
      onclick={() => llmInspectorStore.toggle()}
      title="Open LLM Inspector (⌘⇧I)"
      aria-label="Open LLM Inspector"
    >
      <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" width="14" height="14">
        <rect x="2" y="3" width="12" height="10" rx="1.5" />
        <path d="M5 6h6M5 8.5h4" />
      </svg>
      {#if entries.length > 0}
        <span class="lip-tab-badge">{entries.length}</span>
      {/if}
    </button>
  </div>
{:else}
  <!-- Expanded panel -->
  <div
    class="lip-panel"
    class:lip-panel--dragging={dragging}
    style="width: {panelWidth > 0 ? panelWidth : Math.round(typeof window !== 'undefined' ? window.innerWidth * 0.5 : 600)}px"
  >
    <!-- Drag gutter -->
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div
      class="lip-gutter"
      onpointerdown={onGutterPointerDown}
    >
      <div class="lip-gutter-line"></div>
    </div>

    <!-- Header -->
    <div class="lip-header">
      <div class="lip-header-left">
        <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" width="14" height="14">
          <rect x="2" y="3" width="12" height="10" rx="1.5" />
          <path d="M5 6h6M5 8.5h4" />
        </svg>
        <span class="lip-header-title">LLM Inspector</span>
        {#if allEntries.length > 0}
          <span class="lip-header-count" title="{isFiltered ? `${entries.length} of ${allEntries.length}` : `${allEntries.length} entries`}">
            {#if isFiltered}{entries.length}/{allEntries.length}{:else}{allEntries.length}{/if}
          </span>
        {/if}
      </div>
      <div class="lip-header-right">
        <button
          class="lip-header-btn"
          class:lip-header-btn--active={showMiniview}
          onclick={toggleMiniview}
          title="{showMiniview ? 'Hide' : 'Show'} office overview"
          aria-label="{showMiniview ? 'Hide' : 'Show'} office overview"
        >
          <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" width="13" height="13">
            <rect x="1" y="3" width="14" height="10" rx="1.5" />
            <rect x="3" y="5" width="4" height="3" rx="0.5" />
            <rect x="9" y="5" width="4" height="3" rx="0.5" />
            <rect x="3" y="9" width="4" height="2" rx="0.5" />
            <rect x="9" y="9" width="4" height="2" rx="0.5" />
          </svg>
        </button>
        <div class="lip-font-controls" title="Font size: {fontSize}px">
          <button
            class="lip-font-btn"
            onclick={() => llmInspectorStore.decreaseFontSize()}
            aria-label="Decrease font size"
            disabled={fontSize <= 8}
          >
            <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" width="10" height="10"><path d="M3 8h10"/></svg>
          </button>
          <span class="lip-font-label">{fontSize}</span>
          <button
            class="lip-font-btn"
            onclick={() => llmInspectorStore.increaseFontSize()}
            aria-label="Increase font size"
            disabled={fontSize >= 16}
          >
            <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" width="10" height="10"><path d="M8 3v10M3 8h10"/></svg>
          </button>
        </div>
        <button
          class="lip-header-btn"
          onclick={() => llmInspectorStore.clear()}
          title="Clear log"
          aria-label="Clear log"
          disabled={entries.length === 0}
        >
          <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" width="13" height="13">
            <path d="M2.5 4.5h11M5.5 4.5V3a1 1 0 011-1h3a1 1 0 011 1v1.5m1.5 0v8a1 1 0 01-1 1h-6a1 1 0 01-1-1v-8" />
          </svg>
        </button>
        <button
          class="lip-header-btn"
          onclick={() => llmInspectorStore.toggle()}
          title="Close Inspector (⌘⇧I)"
          aria-label="Close Inspector"
        >
          <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" width="13" height="13">
            <path d="M4 4l8 8M12 4l-8 8" />
          </svg>
        </button>
      </div>
    </div>

    <!-- Office miniview -->
    {#if showMiniview}
      <OfficeMiniview />
    {/if}

    <!-- Filter bar -->
    <div class="lip-filter-bar">
      <div class="lip-filter-dropdown-wrap">
        <button
          class="lip-filter-trigger"
          class:lip-filter-trigger--active={activeFilter.level !== 'all'}
          onclick={() => { filterDropdownOpen = !filterDropdownOpen; }}
          aria-expanded={filterDropdownOpen}
          aria-haspopup="listbox"
        >
          <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" width="12" height="12">
            <path d="M2 4h12M4 8h8M6 12h4" />
          </svg>
          <span class="lip-filter-label">{activeFilter.label}</span>
          <svg class="lip-filter-caret" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" width="10" height="10">
            <path d="M4 6l4 4 4-4" />
          </svg>
        </button>

        {#if filterDropdownOpen}
          <!-- svelte-ignore a11y_no_static_element_interactions a11y_click_events_have_key_events -->
          <div class="lip-filter-backdrop" onclick={() => { filterDropdownOpen = false; }}></div>
          <div class="lip-filter-dropdown" role="listbox">
            {#each filterOptions as opt (opt.filter.level + ':' + opt.filter.id)}
              <button
                class="lip-filter-option"
                class:lip-filter-option--active={activeFilter.level === opt.filter.level && activeFilter.id === opt.filter.id}
                style="padding-left: {8 + opt.indent * 14}px"
                onclick={() => selectFilter(opt.filter)}
                role="option"
                aria-selected={activeFilter.level === opt.filter.level && activeFilter.id === opt.filter.id}
              >
                <span class="lip-filter-icon">{getLevelIcon(opt.filter.level)}</span>
                <span class="lip-filter-option-label">{opt.filter.label}</span>
              </button>
            {/each}
          </div>
        {/if}
      </div>

      <input
        type="text"
        class="lip-search"
        placeholder="Search agent, provider, model..."
        value={searchQuery}
        oninput={(e) => { llmInspectorStore.searchQuery = (e.target as HTMLInputElement).value; }}
      />

      {#if isFiltered}
        <button
          class="lip-filter-clear"
          onclick={() => llmInspectorStore.clearFilter()}
          title="Clear filters"
          aria-label="Clear filters"
        >
          <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" width="11" height="11">
            <path d="M4 4l8 8M12 4l-8 8" />
          </svg>
        </button>
      {/if}
    </div>

    <!-- Entry list -->
    <div class="lip-entries" style="--lip-fs: {fontSize}px">
      {#if entries.length === 0}
        <div class="lip-empty">
          <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1" stroke-linecap="round" width="28" height="28" style="opacity: 0.3">
            <rect x="2" y="3" width="12" height="10" rx="1.5" />
            <path d="M5 6h6M5 8.5h4" />
          </svg>
          {#if isFiltered}
            <span>No matching requests.</span>
            <span class="lip-empty-hint">Try adjusting the filter or search query.</span>
          {:else}
            <span>No LLM requests captured yet.</span>
            <span class="lip-empty-hint">Requests will appear here when AI providers are called.</span>
          {/if}
        </div>
      {:else}
        {#each entries as entry (entry.id)}
          {@const color = llmInspectorStore.getProviderColor(entry.providerSlug)}
          {@const isExpanded = expandedIds.has(entry.id)}
          <div class="lip-entry {getStatusClass(entry)}">
            <button
              class="lip-entry-header"
              onclick={() => toggleEntry(entry.id)}
              aria-expanded={isExpanded}
            >
              <span class="lip-provider-dot" style="background: {color}"></span>
              <span class="lip-provider-name" style="color: {color}">{entry.providerName}</span>
              {#if entry.agentName}
                <span class="lip-agent-name">{entry.agentName}</span>
              {/if}
              <span class="lip-direction" class:lip-direction--sent={entry.direction === 'sent'} class:lip-direction--received={entry.direction === 'received'}>
                {getDirectionIcon(entry.direction)}
                <span class="lip-direction-label">{getDirectionLabel(entry.direction)}</span>
              </span>
              <span class="lip-model">{entry.model}</span>
              <span class="lip-timestamp">{formatTimestamp(entry.timestamp)}</span>
              {#if entry.durationMs !== undefined}
                <span class="lip-duration">{entry.durationMs}ms</span>
              {/if}
              {#if entry.status === 'error'}
                <span class="lip-error-badge">ERR</span>
              {/if}
              <svg class="lip-chevron" class:lip-chevron--open={isExpanded} viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" width="12" height="12">
                <path d="M4 6l4 4 4-4" />
              </svg>
            </button>

            <!-- Preview lines (always visible) -->
            {#if !isExpanded}
              <div class="lip-preview">
                {#each entry.previewLines as line}
                  <span class="lip-preview-line">{line}</span>
                {/each}
              </div>
            {/if}

            <!-- Full payload (expanded) -->
            {#if isExpanded}
              <div class="lip-payload">
                {#if entry.error}
                  <div class="lip-payload-error">{entry.error}</div>
                {/if}
                <pre class="lip-payload-code"><code>{formatPayload(entry.payload)}</code></pre>
              </div>
            {/if}
          </div>
        {/each}
      {/if}
    </div>
  </div>
{/if}

<style>
  /* ── Collapsed rail ───────────────────────────────────────────────── */

  .lip-rail {
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
    width: var(--inspector-tab-width);
    height: 100%;
    border-left: 1px solid var(--border-default);
    background: var(--bg-primary);
  }

  .lip-tab {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
    padding: 10px 5px;
    background: transparent;
    border: 1px solid transparent;
    border-radius: var(--radius-sm);
    color: var(--text-tertiary);
    cursor: pointer;
    transition: color var(--transition-fast), background var(--transition-fast);
  }

  .lip-tab:hover {
    color: var(--text-primary);
    background: var(--bg-elevated);
    border-color: var(--border-default);
  }

  .lip-tab-badge {
    font-size: 9px;
    font-weight: 700;
    min-width: 16px;
    height: 16px;
    line-height: 16px;
    text-align: center;
    border-radius: var(--radius-full);
    background: var(--accent-primary);
    color: #fff;
  }

  /* ── Expanded panel ───────────────────────────────────────────────── */

  .lip-panel {
    display: flex;
    flex-direction: column;
    flex-shrink: 0;
    height: 100%;
    position: relative;
    background: var(--bg-secondary);
    border-left: 1px solid var(--border-default);
    overflow: hidden;
  }

  .lip-panel--dragging {
    user-select: none;
  }

  /* ── Drag gutter ──────────────────────────────────────────────────── */

  .lip-gutter {
    position: absolute;
    top: 0;
    left: 0;
    width: var(--inspector-gutter-width);
    height: 100%;
    cursor: col-resize;
    z-index: 10;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .lip-gutter:hover .lip-gutter-line,
  .lip-panel--dragging .lip-gutter-line {
    background: var(--accent-primary);
    opacity: 1;
  }

  .lip-gutter-line {
    width: 2px;
    height: 40px;
    border-radius: 1px;
    background: var(--text-muted);
    opacity: 0.4;
    transition: background var(--transition-fast), opacity var(--transition-fast);
  }

  /* ── Header ───────────────────────────────────────────────────────── */

  .lip-header {
    position: sticky;
    top: 0;
    z-index: 5;
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 10px 12px 10px 16px;
    background: var(--bg-secondary);
    border-bottom: 1px solid var(--border-default);
    flex-shrink: 0;
  }

  .lip-header-left {
    display: flex;
    align-items: center;
    gap: 8px;
    color: var(--text-secondary);
  }

  .lip-header-title {
    font-size: 13px;
    font-weight: 600;
    color: var(--text-primary);
  }

  .lip-header-count {
    font-size: 10px;
    font-weight: 600;
    min-width: 18px;
    height: 18px;
    line-height: 18px;
    text-align: center;
    border-radius: var(--radius-full);
    background: var(--bg-elevated);
    color: var(--text-secondary);
  }

  .lip-header-right {
    display: flex;
    align-items: center;
    gap: 4px;
  }

  .lip-header-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 28px;
    height: 28px;
    border: none;
    background: transparent;
    color: var(--text-tertiary);
    border-radius: var(--radius-xs);
    cursor: pointer;
    transition: background var(--transition-fast), color var(--transition-fast);
  }

  .lip-header-btn:hover:not(:disabled) {
    background: var(--bg-elevated);
    color: var(--text-primary);
  }

  .lip-header-btn:disabled {
    opacity: 0.3;
    cursor: not-allowed;
  }

  .lip-header-btn--active {
    color: var(--accent-primary);
  }

  /* ── Font size controls ───────────────────────────────────────────── */

  .lip-font-controls {
    display: flex;
    align-items: center;
    gap: 2px;
    padding: 0 4px;
    border-right: 1px solid var(--border-default);
    margin-right: 2px;
  }

  .lip-font-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 20px;
    height: 20px;
    border: none;
    background: transparent;
    color: var(--text-tertiary);
    border-radius: var(--radius-xs);
    cursor: pointer;
    transition: background var(--transition-fast), color var(--transition-fast);
  }

  .lip-font-btn:hover:not(:disabled) {
    background: var(--bg-elevated);
    color: var(--text-primary);
  }

  .lip-font-btn:disabled {
    opacity: 0.3;
    cursor: not-allowed;
  }

  .lip-font-label {
    font-size: 10px;
    font-family: var(--font-mono);
    color: var(--text-muted);
    min-width: 18px;
    text-align: center;
    user-select: none;
  }

  /* ── Filter bar ────────────────────────────────────────────────────── */

  .lip-filter-bar {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 6px 12px 6px 16px;
    border-bottom: 1px solid var(--border-default);
    background: var(--bg-primary);
    flex-shrink: 0;
    margin-left: var(--inspector-gutter-width);
  }

  .lip-filter-dropdown-wrap {
    position: relative;
    flex-shrink: 0;
  }

  .lip-filter-trigger {
    display: flex;
    align-items: center;
    gap: 5px;
    padding: 4px 8px;
    font-size: 11px;
    font-weight: 500;
    color: var(--text-secondary);
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-xs);
    cursor: pointer;
    white-space: nowrap;
    transition: border-color var(--transition-fast), background var(--transition-fast);
  }

  .lip-filter-trigger:hover {
    border-color: var(--border-hover);
    background: var(--bg-surface);
  }

  .lip-filter-trigger--active {
    border-color: var(--accent-primary);
    color: var(--text-primary);
  }

  .lip-filter-label {
    max-width: 120px;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .lip-filter-caret {
    color: var(--text-muted);
    flex-shrink: 0;
  }

  .lip-filter-backdrop {
    position: fixed;
    inset: 0;
    z-index: 99;
  }

  .lip-filter-dropdown {
    position: absolute;
    top: calc(100% + 4px);
    left: 0;
    z-index: 100;
    min-width: 220px;
    max-height: 320px;
    overflow-y: auto;
    background: var(--bg-tertiary);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-sm);
    box-shadow: var(--shadow-lg);
    padding: 4px 0;
  }

  .lip-filter-option {
    display: flex;
    align-items: center;
    gap: 6px;
    width: 100%;
    padding: 5px 10px;
    font-size: 11px;
    color: var(--text-secondary);
    background: transparent;
    border: none;
    cursor: pointer;
    text-align: left;
    transition: background var(--transition-fast), color var(--transition-fast);
  }

  .lip-filter-option:hover {
    background: var(--bg-elevated);
    color: var(--text-primary);
  }

  .lip-filter-option--active {
    color: var(--accent-primary);
    font-weight: 600;
  }

  .lip-filter-icon {
    font-size: 8px;
    width: 12px;
    text-align: center;
    flex-shrink: 0;
    opacity: 0.6;
  }

  .lip-filter-option-label {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .lip-search {
    flex: 1;
    min-width: 0;
    padding: 4px 8px;
    font-size: 11px;
    color: var(--text-primary);
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-xs);
    outline: none;
    transition: border-color var(--transition-fast);
  }

  .lip-search:focus {
    border-color: var(--border-focus);
  }

  .lip-search::placeholder {
    color: var(--text-muted);
  }

  .lip-filter-clear {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 22px;
    height: 22px;
    border: none;
    background: transparent;
    color: var(--text-muted);
    border-radius: var(--radius-xs);
    cursor: pointer;
    flex-shrink: 0;
    transition: color var(--transition-fast), background var(--transition-fast);
  }

  .lip-filter-clear:hover {
    color: var(--accent-error);
    background: rgba(239, 68, 68, 0.08);
  }

  /* ── Entries container ────────────────────────────────────────────── */

  .lip-entries {
    flex: 1;
    overflow-y: auto;
    overflow-x: hidden;
    padding: 4px 0;
    display: flex;
    flex-direction: column;
    margin-left: var(--inspector-gutter-width);
  }

  /* ── Empty state ──────────────────────────────────────────────────── */

  .lip-empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 8px;
    padding: 40px 20px;
    color: var(--text-muted);
    font-size: 13px;
    text-align: center;
  }

  .lip-empty-hint {
    font-size: 11px;
    color: var(--text-muted);
    opacity: 0.7;
  }

  /* ── Entry ────────────────────────────────────────────────────────── */

  .lip-entry {
    border-bottom: 1px solid var(--border-default);
  }

  .lip-entry-header {
    display: flex;
    align-items: center;
    gap: 8px;
    width: 100%;
    padding: 8px 12px;
    background: transparent;
    border: none;
    cursor: pointer;
    text-align: left;
    transition: background var(--transition-fast);
  }

  .lip-entry-header:hover {
    background: var(--bg-surface);
  }

  .lip-provider-dot {
    width: 10px;
    height: 10px;
    border-radius: 50%;
    flex-shrink: 0;
    box-shadow: 0 0 4px rgba(0, 0, 0, 0.2);
  }

  .lip-provider-name {
    font-size: var(--lip-fs, 11px);
    font-weight: 600;
    flex-shrink: 0;
    max-width: 100px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .lip-agent-name {
    font-size: calc(var(--lip-fs, 11px) - 1px);
    font-weight: 500;
    color: var(--text-tertiary);
    max-width: 90px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    flex-shrink: 0;
    padding: 1px 5px;
    background: var(--bg-elevated);
    border-radius: var(--radius-xs);
  }

  .lip-direction {
    display: inline-flex;
    align-items: center;
    gap: 3px;
    font-size: var(--lip-fs, 11px);
    font-weight: 600;
    flex-shrink: 0;
  }

  .lip-direction--sent {
    color: var(--accent-warning);
  }

  .lip-direction--received {
    color: var(--accent-success);
  }

  .lip-direction-label {
    font-size: calc(var(--lip-fs, 11px) - 1px);
    font-weight: 500;
    opacity: 0.8;
  }

  .lip-model {
    font-size: calc(var(--lip-fs, 11px) - 1px);
    font-family: var(--font-mono);
    color: var(--text-tertiary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    flex: 1;
    min-width: 0;
  }

  .lip-timestamp {
    font-size: calc(var(--lip-fs, 11px) - 1px);
    font-family: var(--font-mono);
    color: var(--text-muted);
    flex-shrink: 0;
  }

  .lip-duration {
    font-size: calc(var(--lip-fs, 11px) - 1px);
    font-family: var(--font-mono);
    color: var(--text-muted);
    flex-shrink: 0;
  }

  .lip-error-badge {
    font-size: calc(var(--lip-fs, 11px) - 2px);
    font-weight: 700;
    padding: 1px 5px;
    border-radius: var(--radius-full);
    background: rgba(239, 68, 68, 0.15);
    color: var(--accent-error);
    flex-shrink: 0;
  }

  .lip-chevron {
    flex-shrink: 0;
    color: var(--text-muted);
    transition: transform var(--transition-fast);
  }

  .lip-chevron--open {
    transform: rotate(180deg);
  }

  /* ── Preview (collapsed 3-line snippet) ───────────────────────────── */

  .lip-preview {
    padding: 0 12px 8px 38px;
    display: flex;
    flex-direction: column;
    gap: 1px;
  }

  .lip-preview-line {
    font-size: calc(var(--lip-fs, 11px) - 1px);
    font-family: var(--font-mono);
    color: var(--text-muted);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    line-height: 1.5;
  }

  /* ── Full payload (expanded) ──────────────────────────────────────── */

  .lip-payload {
    padding: 0 12px 10px 38px;
  }

  .lip-payload-error {
    font-size: var(--lip-fs, 11px);
    color: var(--accent-error);
    padding: 6px 10px;
    margin-bottom: 6px;
    background: rgba(239, 68, 68, 0.06);
    border: 1px solid rgba(239, 68, 68, 0.2);
    border-radius: var(--radius-xs);
  }

  .lip-payload-code {
    margin: 0;
    padding: 10px 12px;
    font-size: var(--lip-fs, 11px);
    font-family: var(--font-mono);
    color: var(--text-secondary);
    background: var(--bg-surface);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-sm);
    overflow-x: auto;
    max-height: 400px;
    overflow-y: auto;
    white-space: pre-wrap;
    word-break: break-word;
    line-height: 1.5;
  }

  .lip-payload-code code {
    font-family: inherit;
    font-size: inherit;
  }

  /* ── Status variants ──────────────────────────────────────────────── */

  .lip-status--error .lip-entry-header {
    border-left: 2px solid var(--accent-error);
  }

  .lip-status--success .lip-entry-header {
    border-left: 2px solid transparent;
  }

  .lip-status--pending .lip-entry-header {
    border-left: 2px solid transparent;
  }
</style>
