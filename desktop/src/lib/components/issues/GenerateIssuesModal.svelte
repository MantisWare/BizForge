<!-- src/lib/components/issues/GenerateIssuesModal.svelte -->
<!-- Analyze project documentation and propose issues/tasks via AI -->
<script lang="ts">
  import { sessions, messages } from '$api/client';
  import { isMockEnabled } from '$api/client';
  import { connectSSE } from '$api/sse';
  import type { Document, IssuePriority, StreamEvent } from '$api/types';
  import { issuesStore } from '$lib/stores/issues.svelte';
  import { agentsStore } from '$lib/stores/agents.svelte';
  import { workspaceStore } from '$lib/stores/workspace.svelte';
  import { settingsStore } from '$lib/stores/settings.svelte';

  interface Props {
    projectId: string;
    projectName: string;
    documents: Document[];
    onClose: () => void;
    onCreated: () => void;
  }

  let {
    projectId,
    projectName,
    documents,
    onClose,
    onCreated,
  }: Props = $props();

  interface ProposedIssue {
    selected: boolean;
    title: string;
    description: string;
    priority: IssuePriority;
    labels: string[];
    expanded: boolean;
  }

  type Phase = 'select' | 'analyzing' | 'review' | 'creating';

  let phase = $state<Phase>('select');
  let selectedDocIds = $state<Set<string>>(new Set(documents.map((d) => d.id)));
  let proposals = $state<ProposedIssue[]>([]);
  let error = $state<string | null>(null);
  let creatingProgress = $state(0);
  let streamController = $state<{ abort: () => void } | null>(null);

  const agents = $derived(agentsStore.agents);

  $effect(() => {
    if (agents.length === 0) {
      void agentsStore.fetchAgents(workspaceStore.activeWorkspaceId ?? undefined);
    }
  });

  const selectedDocs = $derived(
    documents.filter((d) => selectedDocIds.has(d.id)),
  );

  const selectedCount = $derived(
    proposals.filter((p) => p.selected).length,
  );

  const totalCount = $derived(proposals.length);

  function toggleDoc(docId: string) {
    const next = new Set(selectedDocIds);
    if (next.has(docId)) {
      next.delete(docId);
    } else {
      next.add(docId);
    }
    selectedDocIds = next;
  }

  function toggleAll() {
    if (selectedDocIds.size === documents.length) {
      selectedDocIds = new Set();
    } else {
      selectedDocIds = new Set(documents.map((d) => d.id));
    }
  }

  function selectAllProposals() {
    proposals = proposals.map((p) => ({ ...p, selected: true }));
  }

  function selectNoneProposals() {
    proposals = proposals.map((p) => ({ ...p, selected: false }));
  }

  function toggleProposal(index: number) {
    proposals = proposals.map((p, i) =>
      i === index ? { ...p, selected: !p.selected } : p,
    );
  }

  function toggleExpand(index: number) {
    proposals = proposals.map((p, i) =>
      i === index ? { ...p, expanded: !p.expanded } : p,
    );
  }

  function updateProposal(index: number, field: keyof ProposedIssue, value: unknown) {
    proposals = proposals.map((p, i) =>
      i === index ? { ...p, [field]: value } : p,
    );
  }

  function buildPrompt(): string {
    const parts: string[] = [];
    parts.push(`Analyze the following project documentation for "${projectName}" and generate a list of actionable development tasks/issues.`);
    parts.push('');
    parts.push('For each task, provide:');
    parts.push('- title: concise task title');
    parts.push('- description: detailed description with acceptance criteria');
    parts.push('- priority: low | medium | high | critical');
    parts.push('- labels: relevant category labels as an array');
    parts.push('');
    parts.push('Respond ONLY with valid JSON in this exact format:');
    parts.push('{ "issues": [{ "title": "...", "description": "...", "priority": "...", "labels": ["..."] }] }');
    parts.push('');
    parts.push('--- Project Documentation ---');
    for (const doc of selectedDocs) {
      parts.push('');
      parts.push(`### ${doc.title} (${doc.path})`);
      parts.push(doc.content);
    }
    return parts.join('\n');
  }

  function parseProposals(raw: string): ProposedIssue[] {
    const jsonMatch = raw.match(/\{[\s\S]*"issues"[\s\S]*\}/);
    if (!jsonMatch) return [];
    try {
      const parsed = JSON.parse(jsonMatch[0]) as {
        issues: Array<{
          title: string;
          description?: string;
          priority?: string;
          labels?: string[];
        }>;
      };
      if (!Array.isArray(parsed.issues)) return [];
      return parsed.issues.map((item) => ({
        selected: true,
        title: item.title ?? 'Untitled',
        description: item.description ?? '',
        priority: validatePriority(item.priority),
        labels: Array.isArray(item.labels) ? item.labels : [],
        expanded: false,
      }));
    } catch {
      return [];
    }
  }

  function validatePriority(p: string | undefined): IssuePriority {
    if (p === 'low' || p === 'medium' || p === 'high' || p === 'critical') return p;
    return 'medium';
  }

  async function handleAnalyze() {
    if (selectedDocs.length === 0) return;
    error = null;
    phase = 'analyzing';

    if (isMockEnabled()) {
      await mockAnalyze();
      return;
    }

    try {
      const agentId = agents[0]?.id;
      if (agentId === undefined) {
        error = 'No agents available. Please add an agent to your workspace first.';
        phase = 'select';
        return;
      }
      const session = await sessions.create({
        agent_id: agentId,
        title: `Issue generation: ${projectName}`,
      });

      const prompt = buildPrompt();
      let buffer = '';

      const ctrl = connectSSE(
        `/sessions/${session.id}/stream`,
        {
          onEvent: (event: StreamEvent) => {
            if (event.type === 'streaming_token') {
              buffer += (event as { delta: string }).delta;
            } else if (event.type === 'done') {
              proposals = parseProposals(buffer);
              phase = 'review';
              if (proposals.length === 0) {
                error = 'No issues could be extracted. Try providing more detailed documentation.';
              }
            } else if (event.type === 'error') {
              error = (event as { message?: string }).message ?? 'Analysis failed';
              phase = 'select';
            }
          },
          onError: (err: Error) => {
            error = err.message;
            phase = 'select';
          },
          onDone: () => {
            if (phase === 'analyzing') {
              proposals = parseProposals(buffer);
              phase = 'review';
              if (proposals.length === 0) {
                error = 'No issues could be extracted. Try providing more detailed documentation.';
              }
            }
          },
        },
      );

      streamController = ctrl;

      const model = settingsStore.data.default_model || undefined;
      await messages.send({
        session_id: session.id,
        content: prompt,
        model,
      });
    } catch (err) {
      error = (err as Error).message;
      phase = 'select';
    }
  }

  async function mockAnalyze(): Promise<void> {
    await new Promise<void>((r) => setTimeout(r, 1200));

    const mockProposals: ProposedIssue[] = [
      {
        selected: true,
        title: 'Set up project scaffolding and dependency management',
        description: 'Initialize the project structure with proper build tooling, linting, and dependency management. Include CI/CD pipeline configuration.',
        priority: 'high',
        labels: ['setup', 'infrastructure'],
        expanded: false,
      },
      {
        selected: true,
        title: 'Implement core data models and validation',
        description: 'Define TypeScript interfaces and validation schemas (e.g., Zod) for all primary entities. Ensure proper type safety across the application boundary.',
        priority: 'high',
        labels: ['backend', 'data-model'],
        expanded: false,
      },
      {
        selected: true,
        title: 'Build REST API endpoints',
        description: 'Implement CRUD endpoints for all core entities with proper error handling, pagination, and input validation. Follow RESTful conventions.',
        priority: 'high',
        labels: ['backend', 'api'],
        expanded: false,
      },
      {
        selected: true,
        title: 'Design and implement user interface components',
        description: 'Build reusable UI components following the design system. Ensure WCAG 2.1 accessibility compliance and responsive layout.',
        priority: 'medium',
        labels: ['frontend', 'ui'],
        expanded: false,
      },
      {
        selected: true,
        title: 'Add authentication and authorization',
        description: 'Implement secure authentication flow with role-based access control. Include session management and token rotation.',
        priority: 'critical',
        labels: ['security', 'auth'],
        expanded: false,
      },
      {
        selected: true,
        title: 'Write unit and integration tests',
        description: 'Achieve minimum 80% code coverage. Focus on critical paths, edge cases, and API contract tests.',
        priority: 'medium',
        labels: ['testing', 'quality'],
        expanded: false,
      },
      {
        selected: true,
        title: 'Set up monitoring and error tracking',
        description: 'Configure application monitoring, structured logging, and error tracking. Set up alerting for critical failures.',
        priority: 'medium',
        labels: ['devops', 'monitoring'],
        expanded: false,
      },
      {
        selected: true,
        title: 'Create deployment documentation and runbook',
        description: 'Document deployment procedures, environment configuration, troubleshooting steps, and rollback procedures.',
        priority: 'low',
        labels: ['documentation', 'devops'],
        expanded: false,
      },
    ];

    proposals = mockProposals;
    phase = 'review';
  }

  async function handleCreate() {
    const toCreate = proposals.filter((p) => p.selected);
    if (toCreate.length === 0) return;
    phase = 'creating';
    creatingProgress = 0;
    error = null;

    try {
      const issueData = toCreate.map((p) => ({
        title: p.title,
        description: p.description || null,
        priority: p.priority,
        labels: p.labels,
        project_id: projectId,
        status: 'backlog' as const,
      }));

      await issuesStore.batchCreateIssues(issueData);
      onCreated();
    } catch (err) {
      error = (err as Error).message;
      phase = 'review';
    }
  }

  function handleBack() {
    if (streamController) {
      streamController.abort();
      streamController = null;
    }
    proposals = [];
    error = null;
    phase = 'select';
  }

  function handleClose() {
    if (streamController) {
      streamController.abort();
      streamController = null;
    }
    onClose();
  }

  const PRIORITY_COLORS: Record<IssuePriority, string> = {
    critical: 'rgba(239, 68, 68, 0.15)',
    high: 'rgba(249, 115, 22, 0.12)',
    medium: 'rgba(234, 179, 8, 0.1)',
    low: 'rgba(107, 114, 128, 0.1)',
  };

  const PRIORITY_TEXT: Record<IssuePriority, string> = {
    critical: '#fca5a5',
    high: '#fdba74',
    medium: '#fde68a',
    low: '#9ca3af',
  };
</script>

<div
  class="gim-overlay"
  role="dialog"
  aria-modal="true"
  aria-label="Generate issues from documentation"
  onclick={(e) => { if (e.target === e.currentTarget) handleClose(); }}
>
  <div class="gim-modal">
    <!-- Header -->
    <div class="gim-header">
      <h2 class="gim-title">
        {#if phase === 'select'}
          Analyze Documentation
        {:else if phase === 'analyzing'}
          Analyzing Documents…
        {:else if phase === 'creating'}
          Creating Issues…
        {:else}
          Review Proposed Issues
        {/if}
      </h2>
      <button class="gim-close" type="button" onclick={handleClose} aria-label="Close">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <path d="M18 6L6 18M6 6l12 12" />
        </svg>
      </button>
    </div>

    <!-- Body -->
    <div class="gim-body">

      {#if phase === 'select'}
        <p class="gim-intro">Select documents to analyze. The AI will read through them and propose a set of actionable issues.</p>

        <div class="gim-doc-controls">
          <button class="gim-link-btn" type="button" onclick={toggleAll}>
            {selectedDocIds.size === documents.length ? 'Deselect All' : 'Select All'}
          </button>
          <span class="gim-doc-count">{selectedDocIds.size} of {documents.length} selected</span>
        </div>

        <div class="gim-doc-list" role="list" aria-label="Documents to analyze">
          {#each documents as doc (doc.id)}
            <label class="gim-doc-item" role="listitem">
              <input
                type="checkbox"
                checked={selectedDocIds.has(doc.id)}
                onchange={() => toggleDoc(doc.id)}
              />
              <div class="gim-doc-item-info">
                <span class="gim-doc-item-title">{doc.title}</span>
                <span class="gim-doc-item-path">{doc.path}</span>
              </div>
              <span class="gim-doc-item-format">{doc.format}</span>
            </label>
          {/each}
        </div>

        <div class="gim-model-info">
          <span class="gim-model-label">Model:</span>
          <code class="gim-model-badge">{settingsStore.data.default_model || 'Not set'}</code>
          <span class="gim-model-hint">Change in Settings → AI Providers</span>
        </div>

      {:else if phase === 'analyzing'}
        <div class="gim-analyzing">
          <div class="gim-spinner" aria-hidden="true"></div>
          <p>Reading {selectedDocs.length} document{selectedDocs.length !== 1 ? 's' : ''} and identifying tasks…</p>
          <p class="gim-analyzing-sub">This may take a moment depending on document size.</p>
        </div>

      {:else if phase === 'creating'}
        <div class="gim-analyzing">
          <div class="gim-spinner" aria-hidden="true"></div>
          <p>Creating {selectedCount} issues…</p>
        </div>

      {:else}
        {#if error}
          <div class="gim-error" role="alert">{error}</div>
        {/if}

        {#if proposals.length > 0}
          <div class="gim-review-toolbar">
            <div class="gim-review-info">
              <span class="gim-review-count">{totalCount} issues proposed</span>
              <span class="gim-review-selected">{selectedCount} selected</span>
            </div>
            <div class="gim-review-actions">
              <button class="gim-link-btn" type="button" onclick={selectAllProposals}>Select All</button>
              <button class="gim-link-btn" type="button" onclick={selectNoneProposals}>Select None</button>
            </div>
          </div>

          <div class="gim-proposals" role="list" aria-label="Proposed issues">
            {#each proposals as proposal, idx (idx)}
              <div
                class="gim-proposal"
                class:gim-proposal--deselected={!proposal.selected}
                role="listitem"
              >
                <div class="gim-proposal-header">
                  <input
                    type="checkbox"
                    checked={proposal.selected}
                    onchange={() => toggleProposal(idx)}
                    aria-label="Include this issue"
                  />
                  <input
                    class="gim-proposal-title"
                    type="text"
                    value={proposal.title}
                    oninput={(e) => updateProposal(idx, 'title', (e.target as HTMLInputElement).value)}
                    aria-label="Issue title"
                  />
                  <select
                    class="gim-priority-select"
                    value={proposal.priority}
                    onchange={(e) => updateProposal(idx, 'priority', (e.target as HTMLSelectElement).value)}
                    style="background: {PRIORITY_COLORS[proposal.priority]}; color: {PRIORITY_TEXT[proposal.priority]}"
                    aria-label="Priority"
                  >
                    <option value="critical">Critical</option>
                    <option value="high">High</option>
                    <option value="medium">Medium</option>
                    <option value="low">Low</option>
                  </select>
                  <button
                    class="gim-expand-btn"
                    type="button"
                    onclick={() => toggleExpand(idx)}
                    aria-expanded={proposal.expanded}
                    aria-label="Toggle details"
                  >
                    <svg
                      width="12" height="12" viewBox="0 0 24 24" fill="none"
                      stroke="currentColor" stroke-width="2" aria-hidden="true"
                      style="transform: rotate({proposal.expanded ? 180 : 0}deg); transition: transform 150ms ease"
                    >
                      <polyline points="6 9 12 15 18 9" />
                    </svg>
                  </button>
                </div>

                {#if proposal.expanded}
                  <div class="gim-proposal-details">
                    <textarea
                      class="gim-proposal-desc"
                      value={proposal.description}
                      oninput={(e) => updateProposal(idx, 'description', (e.target as HTMLTextAreaElement).value)}
                      rows={3}
                      placeholder="Description…"
                      aria-label="Issue description"
                    ></textarea>
                    <div class="gim-proposal-labels">
                      {#each proposal.labels as label, li (li)}
                        <span class="gim-label-chip">{label}</span>
                      {/each}
                    </div>
                  </div>
                {/if}
              </div>
            {/each}
          </div>
        {:else if !error}
          <div class="gim-analyzing">
            <p>No issues were proposed. The documentation may be too brief.</p>
          </div>
        {/if}
      {/if}
    </div>

    <!-- Footer -->
    <div class="gim-footer">
      {#if phase === 'select'}
        <button class="gim-btn-ghost" type="button" onclick={handleClose}>Cancel</button>
        <button
          class="gim-btn-primary"
          type="button"
          onclick={handleAnalyze}
          disabled={selectedDocIds.size === 0}
        >
          Analyze {selectedDocIds.size} Document{selectedDocIds.size !== 1 ? 's' : ''}
        </button>
      {:else if phase === 'analyzing'}
        <button class="gim-btn-ghost" type="button" onclick={handleClose}>Cancel</button>
      {:else if phase === 'creating'}
        <!-- no actions during creation -->
      {:else}
        <button class="gim-btn-ghost" type="button" onclick={handleBack}>Back</button>
        <button
          class="gim-btn-primary"
          type="button"
          onclick={handleCreate}
          disabled={selectedCount === 0}
        >
          Create {selectedCount} Issue{selectedCount !== 1 ? 's' : ''}
        </button>
      {/if}
    </div>
  </div>
</div>

<style>
  .gim-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0,0,0,0.6);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1100;
  }

  .gim-modal {
    background: var(--bg-tertiary, var(--bg-surface));
    border: 1px solid var(--border-default);
    border-radius: 14px;
    width: 700px;
    max-width: calc(100vw - 40px);
    max-height: calc(100vh - 80px);
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }

  .gim-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 18px 22px;
    border-bottom: 1px solid var(--border-default);
    flex-shrink: 0;
  }

  .gim-title {
    font-size: 16px;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0;
  }

  .gim-close {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 28px;
    height: 28px;
    border: 1px solid transparent;
    border-radius: 6px;
    background: transparent;
    color: var(--text-tertiary);
    cursor: pointer;
    transition: all 100ms ease;
  }
  .gim-close:hover { background: var(--bg-elevated); border-color: var(--border-default); color: var(--text-primary); }

  .gim-body {
    flex: 1;
    overflow-y: auto;
    padding: 20px 22px;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  .gim-body::-webkit-scrollbar { width: 5px; }
  .gim-body::-webkit-scrollbar-thumb { background: var(--border-default); border-radius: 3px; }

  .gim-intro {
    font-size: 13px;
    color: var(--text-secondary);
    margin: 0;
    line-height: 1.5;
  }

  .gim-doc-controls {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }

  .gim-link-btn {
    background: none;
    border: none;
    color: #f97316;
    font-size: 12px;
    font-weight: 500;
    cursor: pointer;
    padding: 0;
    font-family: inherit;
  }
  .gim-link-btn:hover { text-decoration: underline; }

  .gim-doc-count {
    font-size: 11px;
    color: var(--text-muted);
  }

  .gim-doc-list {
    display: flex;
    flex-direction: column;
    gap: 2px;
    border: 1px solid var(--border-default);
    border-radius: 8px;
    overflow: hidden;
  }

  .gim-doc-item {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 10px 14px;
    cursor: pointer;
    transition: background 80ms ease;
    border-bottom: 1px solid var(--border-subtle, rgba(255,255,255,0.03));
  }
  .gim-doc-item:last-child { border-bottom: none; }
  .gim-doc-item:hover { background: var(--bg-elevated); }

  .gim-doc-item input[type="checkbox"] {
    width: 14px;
    height: 14px;
    accent-color: #f97316;
    flex-shrink: 0;
  }

  .gim-doc-item-info {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .gim-doc-item-title {
    font-size: 13px;
    font-weight: 500;
    color: var(--text-primary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .gim-doc-item-path {
    font-size: 11px;
    color: var(--text-muted);
    font-family: var(--font-mono, monospace);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .gim-doc-item-format {
    font-size: 9px;
    font-weight: 500;
    text-transform: uppercase;
    padding: 2px 6px;
    border-radius: 3px;
    background: rgba(255,255,255,0.06);
    border: 1px solid var(--border-default);
    color: var(--text-tertiary);
    flex-shrink: 0;
  }

  .gim-analyzing {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 12px;
    min-height: 200px;
    color: var(--text-tertiary);
    font-size: 13px;
    text-align: center;
  }

  .gim-analyzing p { margin: 0; }
  .gim-analyzing-sub { font-size: 11px; color: var(--text-muted); }

  .gim-spinner {
    width: 24px;
    height: 24px;
    border: 2px solid var(--border-default);
    border-top-color: #f97316;
    border-radius: 50%;
    animation: gim-spin 0.8s linear infinite;
  }

  @keyframes gim-spin { to { transform: rotate(360deg); } }

  .gim-error {
    font-size: 12px;
    color: #fca5a5;
    padding: 8px 12px;
    background: rgba(239, 68, 68, 0.08);
    border: 1px solid rgba(239, 68, 68, 0.2);
    border-radius: 6px;
  }

  .gim-review-toolbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    padding-bottom: 4px;
  }

  .gim-review-info {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .gim-review-count {
    font-size: 13px;
    font-weight: 500;
    color: var(--text-primary);
  }

  .gim-review-selected {
    font-size: 11px;
    color: var(--text-muted);
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    border-radius: 10px;
    padding: 1px 8px;
  }

  .gim-review-actions {
    display: flex;
    gap: 10px;
  }

  .gim-proposals {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .gim-proposal {
    border: 1px solid var(--border-default);
    border-radius: 8px;
    overflow: hidden;
    transition: opacity 150ms ease;
  }

  .gim-proposal--deselected {
    opacity: 0.45;
  }

  .gim-proposal-header {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 10px 12px;
  }

  .gim-proposal-header input[type="checkbox"] {
    width: 14px;
    height: 14px;
    accent-color: #f97316;
    flex-shrink: 0;
  }

  .gim-proposal-title {
    flex: 1;
    min-width: 0;
    height: 28px;
    padding: 0 8px;
    border: 1px solid transparent;
    border-radius: 4px;
    background: transparent;
    color: var(--text-primary);
    font-size: 13px;
    font-weight: 500;
    font-family: inherit;
    transition: border-color 100ms ease, background 100ms ease;
  }

  .gim-proposal-title:hover { border-color: var(--border-default); background: var(--bg-elevated); }
  .gim-proposal-title:focus { outline: none; border-color: #f97316; background: var(--bg-elevated); }

  .gim-priority-select {
    height: 24px;
    padding: 0 6px;
    border-radius: 12px;
    font-size: 10px;
    font-weight: 600;
    border: 1px solid transparent;
    cursor: pointer;
    font-family: inherit;
    text-transform: capitalize;
    flex-shrink: 0;
  }
  .gim-priority-select:focus { outline: none; }

  .gim-expand-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 24px;
    height: 24px;
    border: none;
    border-radius: 4px;
    background: transparent;
    color: var(--text-muted);
    cursor: pointer;
    flex-shrink: 0;
  }
  .gim-expand-btn:hover { background: var(--bg-elevated); color: var(--text-primary); }

  .gim-proposal-details {
    padding: 0 12px 12px 38px;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .gim-proposal-desc {
    width: 100%;
    padding: 8px 10px;
    border-radius: 6px;
    border: 1px solid var(--border-default);
    background: var(--bg-elevated);
    color: var(--text-secondary);
    font-size: 12px;
    font-family: inherit;
    line-height: 1.5;
    resize: vertical;
    box-sizing: border-box;
  }
  .gim-proposal-desc:focus { outline: none; border-color: #f97316; }

  .gim-proposal-labels {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
  }

  .gim-label-chip {
    font-size: 10px;
    font-weight: 500;
    padding: 2px 7px;
    border-radius: 10px;
    background: rgba(249, 115, 22, 0.08);
    border: 1px solid rgba(249, 115, 22, 0.15);
    color: #fdba74;
  }

  .gim-footer {
    display: flex;
    align-items: center;
    justify-content: flex-end;
    gap: 8px;
    padding: 14px 22px;
    border-top: 1px solid var(--border-default);
    flex-shrink: 0;
  }

  .gim-btn-ghost, .gim-btn-primary {
    height: 32px;
    padding: 0 14px;
    border-radius: 6px;
    font-size: 13px;
    font-weight: 500;
    cursor: pointer;
    transition: all 100ms ease;
    font-family: inherit;
  }

  .gim-btn-ghost {
    background: transparent;
    border: 1px solid var(--border-default);
    color: var(--text-secondary);
  }
  .gim-btn-ghost:hover:not(:disabled) { background: var(--bg-elevated); color: var(--text-primary); }

  .gim-btn-primary {
    background: rgba(249, 115, 22, 0.12);
    border: 1px solid rgba(249, 115, 22, 0.35);
    color: #fdba74;
  }
  .gim-btn-primary:hover:not(:disabled) { background: rgba(249, 115, 22, 0.2); border-color: rgba(249, 115, 22, 0.5); }

  .gim-btn-ghost:disabled, .gim-btn-primary:disabled { opacity: 0.5; cursor: not-allowed; }

  .gim-model-info {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-top: 12px;
    padding-top: 12px;
    border-top: 1px solid var(--border-default);
  }

  .gim-model-label {
    font-size: 12px;
    font-weight: 500;
    color: var(--text-secondary);
  }

  .gim-model-badge {
    font-family: var(--font-mono, monospace);
    font-size: 11px;
    padding: 2px 8px;
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    border-radius: 4px;
    color: var(--text-secondary);
  }

  .gim-model-hint {
    font-size: 10px;
    color: var(--text-muted);
  }

  @media (prefers-reduced-motion: reduce) {
    .gim-spinner { animation: none; }
  }
</style>
