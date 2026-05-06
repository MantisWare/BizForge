<!-- src/lib/components/documents/GenerateDocModal.svelte -->
<!-- AI-powered document generation modal with streaming preview -->
<script lang="ts">
  import { sessions, messages } from '$api/client';
  import { isMockEnabled } from '$api/client';
  import { connectSSE } from '$api/sse';
  import type { StreamEvent } from '$api/types';
  import { documentsStore } from '$lib/stores/documents.svelte';
  import { goalsStore } from '$lib/stores/goals.svelte';
  import { issuesStore } from '$lib/stores/issues.svelte';
  import { agentsStore } from '$lib/stores/agents.svelte';
  import { workspaceStore } from '$lib/stores/workspace.svelte';
  import { settingsStore } from '$lib/stores/settings.svelte';
  import DOMPurify from 'dompurify';

  interface Props {
    projectId: string;
    projectName: string;
    projectDescription: string | null;
    onClose: () => void;
    onSaved: () => void;
  }

  let {
    projectId,
    projectName,
    projectDescription,
    onClose,
    onSaved,
  }: Props = $props();

  type DocType = 'prd' | 'technical_spec' | 'architecture' | 'api_docs' | 'user_guide' | 'runbook' | 'custom';

  const DOC_TYPES: { id: DocType; label: string; description: string }[] = [
    { id: 'prd', label: 'PRD', description: 'Product Requirements Document' },
    { id: 'technical_spec', label: 'Technical Spec', description: 'Technical specification and design' },
    { id: 'architecture', label: 'Architecture', description: 'System architecture document' },
    { id: 'api_docs', label: 'API Docs', description: 'API reference documentation' },
    { id: 'user_guide', label: 'User Guide', description: 'End-user documentation' },
    { id: 'runbook', label: 'Runbook', description: 'Operations and deployment guide' },
    { id: 'custom', label: 'Custom', description: 'Custom document type' },
  ];

  type Phase = 'configure' | 'generating' | 'preview';

  let phase = $state<Phase>('configure');
  let docType = $state<DocType>('prd');
  let customType = $state('');
  let context = $state('');
  let includeDescription = $state(true);
  let includeGoals = $state(false);
  let includeIssues = $state(false);
  let selectedAgentId = $state('');

  let generatedContent = $state('');
  let editMode = $state(false);
  let editContent = $state('');
  let saving = $state(false);
  let error = $state<string | null>(null);
  let streamController = $state<{ abort: () => void } | null>(null);

  const agents = $derived(agentsStore.agents);

  $effect(() => {
    if (agents.length === 0) {
      void agentsStore.fetchAgents(workspaceStore.activeWorkspaceId ?? undefined);
    }
  });

  const docTypeLabel = $derived(
    docType === 'custom'
      ? (customType.trim() || 'Custom Document')
      : DOC_TYPES.find((d) => d.id === docType)?.label ?? docType,
  );

  function buildPrompt(): string {
    const parts: string[] = [];
    const typeLabel = docTypeLabel;

    parts.push(`Generate a comprehensive ${typeLabel} document for the project "${projectName}".`);
    parts.push('');
    parts.push('Requirements:');
    parts.push(`- Document type: ${typeLabel}`);
    parts.push('- Format: Markdown');
    parts.push('- Include clear headings, sections, and structure');
    parts.push('- Be thorough and professional');

    if (context.trim()) {
      parts.push('');
      parts.push('--- User-provided context ---');
      parts.push(context.trim());
    }

    if (includeDescription && projectDescription) {
      parts.push('');
      parts.push('--- Project Description ---');
      parts.push(projectDescription);
    }

    if (includeGoals && goalsStore.flatGoals.length > 0) {
      parts.push('');
      parts.push('--- Project Goals ---');
      for (const g of goalsStore.flatGoals) {
        parts.push(`- [${g.status}] ${g.title}${g.description ? `: ${g.description}` : ''}`);
      }
    }

    if (includeIssues && issuesStore.issues.length > 0) {
      parts.push('');
      parts.push('--- Existing Issues ---');
      for (const i of issuesStore.issues.filter((iss) => iss.project_id === projectId)) {
        parts.push(`- [${i.status}/${i.priority}] ${i.title}${i.description ? `: ${i.description}` : ''}`);
      }
    }

    parts.push('');
    parts.push('Generate the full document content in Markdown format. Do not include any preamble or explanations outside the document itself.');

    return parts.join('\n');
  }

  async function handleGenerate() {
    error = null;
    generatedContent = '';
    phase = 'generating';

    if (isMockEnabled()) {
      await mockGenerate();
      return;
    }

    try {
      const agentId = (selectedAgentId !== '' ? selectedAgentId : undefined) ?? agents[0]?.id;
      if (agentId === undefined) {
        error = 'No agents available. Please add an agent to your workspace first.';
        phase = 'preview';
        return;
      }
      const session = await sessions.create({
        agent_id: agentId,
        title: `Doc generation: ${docTypeLabel}`,
      });

      const prompt = buildPrompt();

      let buffer = '';
      const ctrl = connectSSE(
        `/sessions/${session.id}/stream`,
        {
          onEvent: (event: StreamEvent) => {
            if (event.type === 'streaming_token') {
              const delta = (event as { delta: string }).delta;
              buffer += delta;
              generatedContent = buffer;
            } else if (event.type === 'done') {
              phase = 'preview';
            } else if (event.type === 'error') {
              error = (event as { message?: string }).message ?? 'Generation failed';
              phase = 'preview';
            }
          },
          onError: (err: Error) => {
            error = err.message;
            phase = 'preview';
          },
          onDone: () => {
            phase = 'preview';
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
      phase = 'preview';
    }
  }

  async function mockGenerate(): Promise<void> {
    const typeLabel = docTypeLabel;
    const mockDoc = [
      `# ${typeLabel} — ${projectName}`,
      '',
      '## Overview',
      '',
      `This document provides a comprehensive ${typeLabel.toLowerCase()} for the ${projectName} project.${projectDescription ? ` ${projectDescription}` : ''}`,
      '',
      '## Scope',
      '',
      '- Define key deliverables and milestones',
      '- Outline technical requirements and constraints',
      '- Establish success criteria and acceptance standards',
      '',
      '## Requirements',
      '',
      '### Functional Requirements',
      '',
      '1. **Core Functionality** — Implement the primary feature set as described in the project scope',
      '2. **User Interface** — Provide an intuitive, accessible interface following WCAG 2.1 guidelines',
      '3. **Data Management** — Ensure proper data handling, validation, and persistence',
      '4. **Integration** — Support integration with existing systems and third-party services',
      '',
      '### Non-Functional Requirements',
      '',
      '- **Performance** — Response times under 200ms for standard operations',
      '- **Scalability** — Support horizontal scaling for increased load',
      '- **Security** — Follow OWASP guidelines for application security',
      '- **Reliability** — 99.9% uptime SLA for production environments',
      '',
      '## Architecture',
      '',
      'The system follows a modular architecture with clear separation of concerns:',
      '',
      '- **Frontend** — Component-based UI with reactive state management',
      '- **Backend** — RESTful API with structured error handling',
      '- **Data Layer** — Normalized data store with caching strategy',
      '',
      '## Timeline',
      '',
      '| Phase | Duration | Deliverables |',
      '|-------|----------|-------------|',
      '| Discovery | 1 week | Requirements, architecture decisions |',
      '| Implementation | 3 weeks | Core features, API, UI |',
      '| Testing | 1 week | QA, performance testing, bug fixes |',
      '| Launch | 1 week | Deployment, monitoring, documentation |',
      '',
      '## Success Criteria',
      '',
      '- All functional requirements implemented and tested',
      '- Performance benchmarks met',
      '- Documentation complete and reviewed',
      '- Stakeholder sign-off obtained',
      '',
      `---`,
      '',
      `*Generated for ${projectName} — ${new Date().toLocaleDateString()}*`,
    ].join('\n');

    const words = mockDoc.split(' ');
    for (let i = 0; i < words.length; i++) {
      generatedContent += (i > 0 ? ' ' : '') + words[i];
      if (i % 5 === 0) {
        await new Promise<void>((r) => setTimeout(r, 20));
      }
    }
    phase = 'preview';
  }

  function handleEdit() {
    editContent = generatedContent;
    editMode = true;
  }

  function handleCancelEdit() {
    editMode = false;
    editContent = '';
  }

  function handleApplyEdit() {
    generatedContent = editContent;
    editMode = false;
    editContent = '';
  }

  function handleRegenerate() {
    if (streamController) {
      streamController.abort();
      streamController = null;
    }
    phase = 'configure';
    generatedContent = '';
    error = null;
    editMode = false;
    editContent = '';
  }

  async function handleSave() {
    saving = true;
    error = null;
    try {
      const slug = docType === 'custom'
        ? (customType.trim().toLowerCase().replace(/\s+/g, '-') || 'document')
        : docType.replace(/_/g, '-');
      const path = `${projectName.toLowerCase().replace(/\s+/g, '-')}/${slug}.md`;
      await documentsStore.createDocument({
        title: docTypeLabel,
        path,
        content: generatedContent,
        format: 'markdown',
        project_id: projectId,
      });
      onSaved();
    } catch (err) {
      error = (err as Error).message;
    } finally {
      saving = false;
    }
  }

  function handleClose() {
    if (streamController) {
      streamController.abort();
      streamController = null;
    }
    onClose();
  }

  function renderMarkdown(md: string): string {
    if (!md) return '';
    const html = md
      .replace(/^######\s(.+)$/gm, '<h6>$1</h6>')
      .replace(/^#####\s(.+)$/gm, '<h5>$1</h5>')
      .replace(/^####\s(.+)$/gm, '<h4>$1</h4>')
      .replace(/^###\s(.+)$/gm, '<h3>$1</h3>')
      .replace(/^##\s(.+)$/gm, '<h2>$1</h2>')
      .replace(/^#\s(.+)$/gm, '<h1>$1</h1>')
      .replace(/\*\*\*(.+?)\*\*\*/g, '<strong><em>$1</em></strong>')
      .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.+?)\*/g, '<em>$1</em>')
      .replace(/`([^`]+)`/g, '<code>$1</code>')
      .replace(/^>\s(.+)$/gm, '<blockquote>$1</blockquote>')
      .replace(/^[-*]\s(.+)$/gm, '<li>$1</li>')
      .replace(/^---$/gm, '<hr />')
      .split(/\n\n+/)
      .map((block) => {
        if (block.startsWith('<h') || block.startsWith('<hr') || block.startsWith('<li') || block.startsWith('<blockquote')) return block;
        return `<p>${block.replace(/\n/g, '<br/>')}</p>`;
      })
      .join('\n');
    return DOMPurify.sanitize(html);
  }

  const rendered = $derived(renderMarkdown(generatedContent));
</script>

<div
  class="gdm-overlay"
  role="dialog"
  aria-modal="true"
  aria-label="Generate documentation with AI"
  onclick={(e) => { if (e.target === e.currentTarget) handleClose(); }}
>
  <div class="gdm-modal">
    <!-- Header -->
    <div class="gdm-header">
      <h2 class="gdm-title">
        {#if phase === 'configure'}
          Generate Documentation
        {:else if phase === 'generating'}
          Generating {docTypeLabel}…
        {:else}
          Review Generated Document
        {/if}
      </h2>
      <button class="gdm-close" type="button" onclick={handleClose} aria-label="Close">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <path d="M18 6L6 18M6 6l12 12" />
        </svg>
      </button>
    </div>

    <!-- Body -->
    <div class="gdm-body">

      {#if phase === 'configure'}
        <!-- Document type -->
        <div class="gdm-section">
          <label class="gdm-label">Document Type</label>
          <div class="gdm-chips" role="radiogroup" aria-label="Document type">
            {#each DOC_TYPES as dt (dt.id)}
              <button
                class="gdm-chip"
                class:gdm-chip--active={docType === dt.id}
                type="button"
                role="radio"
                aria-checked={docType === dt.id}
                onclick={() => { docType = dt.id; }}
                title={dt.description}
              >
                {dt.label}
              </button>
            {/each}
          </div>
          {#if docType === 'custom'}
            <input
              class="gdm-input"
              type="text"
              placeholder="Custom document type name…"
              bind:value={customType}
            />
          {/if}
        </div>

        <!-- Context -->
        <div class="gdm-section">
          <label class="gdm-label" for="gdm-context">Context & Requirements</label>
          <textarea
            id="gdm-context"
            class="gdm-textarea"
            placeholder="Describe what this document should cover, key requirements, constraints, technology stack, etc."
            bind:value={context}
            rows={5}
          ></textarea>
        </div>

        <!-- Include toggles -->
        <div class="gdm-section">
          <span class="gdm-label">Include Additional Context</span>
          <div class="gdm-toggles">
            <label class="gdm-toggle">
              <input type="checkbox" bind:checked={includeDescription} />
              <span>Project description</span>
              {#if !projectDescription}
                <span class="gdm-toggle-note">(empty)</span>
              {/if}
            </label>
            <label class="gdm-toggle">
              <input type="checkbox" bind:checked={includeGoals} />
              <span>Existing goals ({goalsStore.flatGoals.length})</span>
            </label>
            <label class="gdm-toggle">
              <input type="checkbox" bind:checked={includeIssues} />
              <span>Existing issues ({issuesStore.issues.filter((i) => i.project_id === projectId).length})</span>
            </label>
          </div>
        </div>

        <!-- Agent & Model -->
        <div class="gdm-section">
          {#if agents.length > 0}
            <label class="gdm-label" for="gdm-agent">Agent</label>
            <select
              id="gdm-agent"
              class="gdm-select"
              bind:value={selectedAgentId}
            >
              <option value="">Default (first available)</option>
              {#each agents as agent (agent.id)}
                <option value={agent.id}>{agent.display_name ?? agent.name}</option>
              {/each}
            </select>
          {/if}
          <div class="gdm-model-info">
            <span class="gdm-label">Model</span>
            <code class="gdm-model-badge">{settingsStore.data.default_model || 'Not set'}</code>
            <span class="gdm-model-hint">Change in Settings → AI Providers</span>
          </div>
        </div>

      {:else if phase === 'generating'}
        <!-- Streaming preview -->
        <div class="gdm-preview-wrap">
          {#if generatedContent}
            <!-- eslint-disable-next-line svelte/no-at-html-tags -->
            <div class="gdm-preview gdm-markdown">{@html renderMarkdown(generatedContent)}</div>
          {:else}
            <div class="gdm-generating">
              <div class="gdm-spinner" aria-hidden="true"></div>
              <span>Preparing document…</span>
            </div>
          {/if}
          <div class="gdm-streaming-indicator" aria-live="polite">
            <span class="gdm-cursor" aria-hidden="true"></span>
            Generating…
          </div>
        </div>

      {:else}
        <!-- Preview / edit -->
        {#if error}
          <div class="gdm-error" role="alert">{error}</div>
        {/if}

        {#if editMode}
          <textarea
            class="gdm-editor"
            bind:value={editContent}
            rows={16}
            aria-label="Edit generated document"
          ></textarea>
        {:else}
          <div class="gdm-preview-wrap">
            <!-- eslint-disable-next-line svelte/no-at-html-tags -->
            <div class="gdm-preview gdm-markdown">{@html rendered}</div>
          </div>
        {/if}
      {/if}
    </div>

    <!-- Footer -->
    <div class="gdm-footer">
      {#if phase === 'configure'}
        <button class="gdm-btn-ghost" type="button" onclick={handleClose}>Cancel</button>
        <button
          class="gdm-btn-primary"
          type="button"
          onclick={handleGenerate}
          disabled={docType === 'custom' && !customType.trim()}
        >
          Generate
        </button>
      {:else if phase === 'generating'}
        <button class="gdm-btn-ghost" type="button" onclick={handleClose}>Cancel</button>
      {:else}
        <button class="gdm-btn-ghost" type="button" onclick={handleRegenerate}>Regenerate</button>
        {#if editMode}
          <button class="gdm-btn-ghost" type="button" onclick={handleCancelEdit}>Cancel Edit</button>
          <button class="gdm-btn-primary" type="button" onclick={handleApplyEdit}>Apply Changes</button>
        {:else}
          <button class="gdm-btn-ghost" type="button" onclick={handleEdit}>Edit</button>
          <button
            class="gdm-btn-primary"
            type="button"
            onclick={handleSave}
            disabled={saving || !generatedContent.trim()}
          >
            {saving ? 'Saving…' : 'Save as Document'}
          </button>
        {/if}
      {/if}
    </div>
  </div>
</div>

<style>
  .gdm-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0,0,0,0.6);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1100;
  }

  .gdm-modal {
    background: var(--bg-tertiary, var(--bg-surface));
    border: 1px solid var(--border-default);
    border-radius: 14px;
    width: 680px;
    max-width: calc(100vw - 40px);
    max-height: calc(100vh - 80px);
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }

  .gdm-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 18px 22px;
    border-bottom: 1px solid var(--border-default);
    flex-shrink: 0;
  }

  .gdm-title {
    font-size: 16px;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0;
  }

  .gdm-close {
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
  .gdm-close:hover { background: var(--bg-elevated); border-color: var(--border-default); color: var(--text-primary); }

  .gdm-body {
    flex: 1;
    overflow-y: auto;
    padding: 20px 22px;
    display: flex;
    flex-direction: column;
    gap: 18px;
  }

  .gdm-body::-webkit-scrollbar { width: 5px; }
  .gdm-body::-webkit-scrollbar-thumb { background: var(--border-default); border-radius: 3px; }

  .gdm-section {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .gdm-label {
    font-size: 12px;
    font-weight: 600;
    color: var(--text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.3px;
  }

  .gdm-chips {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }

  .gdm-chip {
    height: 30px;
    padding: 0 12px;
    border-radius: 15px;
    font-size: 12px;
    font-weight: 500;
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    color: var(--text-secondary);
    cursor: pointer;
    transition: all 100ms ease;
    font-family: inherit;
  }
  .gdm-chip:hover { border-color: var(--border-hover, var(--border-default)); color: var(--text-primary); }
  .gdm-chip--active { background: rgba(249, 115, 22, 0.1); border-color: rgba(249, 115, 22, 0.35); color: #fdba74; }

  .gdm-input, .gdm-select {
    height: 34px;
    padding: 0 10px;
    border-radius: 6px;
    font-size: 13px;
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    color: var(--text-primary);
    width: 100%;
    box-sizing: border-box;
    font-family: inherit;
  }
  .gdm-input:focus, .gdm-select:focus { outline: none; border-color: #f97316; }

  .gdm-textarea {
    padding: 10px 12px;
    border-radius: 6px;
    font-size: 13px;
    font-family: inherit;
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    color: var(--text-primary);
    width: 100%;
    box-sizing: border-box;
    resize: vertical;
    line-height: 1.5;
  }
  .gdm-textarea:focus { outline: none; border-color: #f97316; }

  .gdm-toggles {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .gdm-toggle {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 13px;
    color: var(--text-secondary);
    cursor: pointer;
  }

  .gdm-toggle input[type="checkbox"] {
    width: 14px;
    height: 14px;
    accent-color: #f97316;
  }

  .gdm-toggle-note {
    font-size: 11px;
    color: var(--text-muted);
    font-style: italic;
  }

  .gdm-preview-wrap {
    flex: 1;
    min-height: 200px;
    max-height: 400px;
    overflow-y: auto;
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    border-radius: 8px;
    padding: 16px 20px;
  }

  .gdm-preview-wrap::-webkit-scrollbar { width: 5px; }
  .gdm-preview-wrap::-webkit-scrollbar-thumb { background: var(--border-default); border-radius: 3px; }

  .gdm-preview {
    font-size: 14px;
    line-height: 1.7;
    color: var(--text-secondary);
    max-width: 640px;
  }

  :global(.gdm-markdown h1) { font-size: 20px; font-weight: 700; color: var(--text-primary); margin: 0 0 14px; }
  :global(.gdm-markdown h2) { font-size: 17px; font-weight: 600; color: var(--text-primary); margin: 20px 0 10px; }
  :global(.gdm-markdown h3) { font-size: 14px; font-weight: 600; color: var(--text-primary); margin: 16px 0 8px; }
  :global(.gdm-markdown p) { margin: 0 0 10px; }
  :global(.gdm-markdown strong) { color: var(--text-primary); font-weight: 600; }
  :global(.gdm-markdown code) { font-family: var(--font-mono, monospace); font-size: 12px; background: rgba(255,255,255,0.07); padding: 1px 5px; border-radius: 3px; color: #fdba74; }
  :global(.gdm-markdown blockquote) { border-left: 3px solid #f97316; padding-left: 12px; color: var(--text-tertiary); margin: 10px 0; }
  :global(.gdm-markdown hr) { border: none; border-top: 1px solid var(--border-default); margin: 16px 0; }
  :global(.gdm-markdown li) { list-style: disc; margin-left: 20px; margin-bottom: 3px; }
  :global(.gdm-markdown table) { width: 100%; border-collapse: collapse; font-size: 12px; margin: 10px 0; }
  :global(.gdm-markdown th, .gdm-markdown td) { padding: 6px 10px; border: 1px solid var(--border-default); text-align: left; }
  :global(.gdm-markdown th) { background: rgba(255,255,255,0.04); font-weight: 600; color: var(--text-primary); }

  .gdm-generating {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 12px;
    height: 180px;
    color: var(--text-tertiary);
    font-size: 13px;
  }

  .gdm-spinner {
    width: 22px;
    height: 22px;
    border: 2px solid var(--border-default);
    border-top-color: #f97316;
    border-radius: 50%;
    animation: gdm-spin 0.8s linear infinite;
  }

  @keyframes gdm-spin { to { transform: rotate(360deg); } }

  .gdm-streaming-indicator {
    display: flex;
    align-items: center;
    gap: 6px;
    margin-top: 10px;
    font-size: 11px;
    color: var(--text-muted);
  }

  .gdm-cursor {
    display: inline-block;
    width: 2px;
    height: 12px;
    background: #f97316;
    border-radius: 1px;
    animation: gdm-blink 0.9s step-start infinite;
  }

  @keyframes gdm-blink {
    0%, 100% { opacity: 1; }
    50% { opacity: 0; }
  }

  .gdm-editor {
    width: 100%;
    min-height: 300px;
    padding: 12px;
    border-radius: 8px;
    border: 1px solid var(--border-default);
    background: var(--bg-elevated);
    color: var(--text-primary);
    font-family: var(--font-mono, monospace);
    font-size: 13px;
    line-height: 1.6;
    resize: vertical;
    outline: none;
    box-sizing: border-box;
  }
  .gdm-editor:focus { border-color: #f97316; }

  .gdm-error {
    font-size: 12px;
    color: #fca5a5;
    padding: 8px 12px;
    background: rgba(239, 68, 68, 0.08);
    border: 1px solid rgba(239, 68, 68, 0.2);
    border-radius: 6px;
  }

  .gdm-footer {
    display: flex;
    align-items: center;
    justify-content: flex-end;
    gap: 8px;
    padding: 14px 22px;
    border-top: 1px solid var(--border-default);
    flex-shrink: 0;
  }

  .gdm-btn-ghost, .gdm-btn-primary {
    height: 32px;
    padding: 0 14px;
    border-radius: 6px;
    font-size: 13px;
    font-weight: 500;
    cursor: pointer;
    transition: all 100ms ease;
    font-family: inherit;
  }

  .gdm-btn-ghost {
    background: transparent;
    border: 1px solid var(--border-default);
    color: var(--text-secondary);
  }
  .gdm-btn-ghost:hover:not(:disabled) { background: var(--bg-elevated); color: var(--text-primary); }

  .gdm-btn-primary {
    background: rgba(249, 115, 22, 0.12);
    border: 1px solid rgba(249, 115, 22, 0.35);
    color: #fdba74;
  }
  .gdm-btn-primary:hover:not(:disabled) { background: rgba(249, 115, 22, 0.2); border-color: rgba(249, 115, 22, 0.5); }

  .gdm-btn-ghost:disabled, .gdm-btn-primary:disabled { opacity: 0.5; cursor: not-allowed; }

  .gdm-model-info {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-top: 8px;
  }

  .gdm-model-badge {
    font-family: var(--font-mono, monospace);
    font-size: 11px;
    padding: 2px 8px;
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    border-radius: 4px;
    color: var(--text-secondary);
  }

  .gdm-model-hint {
    font-size: 10px;
    color: var(--text-muted);
  }

  @media (prefers-reduced-motion: reduce) {
    .gdm-cursor { animation: none; opacity: 0.7; }
    .gdm-spinner { animation: none; }
  }
</style>
