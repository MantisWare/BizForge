<!-- src/lib/components/wizard/steps/Step2Documentation.svelte -->
<script lang="ts">
  import { onMount } from 'svelte';
  import { wizardStore } from '$lib/stores/wizard.svelte';
  import { settingsStore } from '$lib/stores/settings.svelte';
  import { agentsStore } from '$lib/stores/agents.svelte';
  import { workspaceStore } from '$lib/stores/workspace.svelte';
  import { agents as agentsApi, sessions, messages } from '$api/client';
  import { streamMessage } from '$api/sse';
  import type { WizardDocument, DocumentFormat, BizforgeAgent } from '$api/types';
  import type { StreamController } from '$api/sse';
  import { isTauri } from '$lib/utils/platform';

  let dragOver = $state(false);
  let streamCtrl = $state<StreamController | null>(null);
  let enhanceProgress = $state("");

  const ACCEPTED_EXTENSIONS: Record<string, DocumentFormat> = {
    '.md': 'markdown',
    '.txt': 'text',
    '.json': 'json',
    '.yaml': 'yaml',
    '.yml': 'yaml',
    '.csv': 'text',
    '.dbml': 'text',
    '.sql': 'sql',
    '.pdf': 'pdf',
    '.doc': 'binary',
    '.docx': 'binary',
    '.xls': 'binary',
    '.xlsx': 'binary',
  };

  const BINARY_EXTENSIONS = new Set(['.pdf', '.doc', '.docx', '.xls', '.xlsx']);

  function getFormat(name: string): DocumentFormat {
    const ext = name.slice(name.lastIndexOf('.')).toLowerCase();
    return ACCEPTED_EXTENSIONS[ext] ?? 'markdown';
  }

  function getExt(name: string): string {
    return name.slice(name.lastIndexOf('.')).toLowerCase();
  }

  function isAccepted(name: string): boolean {
    return getExt(name) in ACCEPTED_EXTENSIONS;
  }

  function readFileAsBase64(file: File): Promise<string> {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => {
        const result = reader.result as string;
        resolve(result.split(',')[1] ?? '');
      };
      reader.onerror = () => reject(new Error('Failed to read file'));
      reader.readAsDataURL(file);
    });
  }

  async function extractTextContent(file: File, ext: string): Promise<string> {
    if (BINARY_EXTENSIONS.has(ext)) {
      const base64 = await readFileAsBase64(file);
      const label = ext.replace('.', '').toUpperCase();
      return `[${label} Document: ${file.name}]\n[Binary content — ${formatSize(file.size)} — will be processed by AI during enhancement]\n[Base64 length: ${base64.length} chars]\n\n--- Base64 content (first 200 chars) ---\n${base64.slice(0, 200)}...`;
    }
    return file.text();
  }

  async function handleFiles(files: FileList | null): Promise<void> {
    if (files === null) return;
    for (const file of Array.from(files)) {
      const ext = getExt(file.name);
      if (!isAccepted(file.name)) continue;
      const content = await extractTextContent(file, ext);
      const doc: WizardDocument = {
        id: crypto.randomUUID(),
        name: file.name,
        content,
        format: getFormat(file.name),
        size: file.size,
      };
      wizardStore.addDocument(doc);
    }
  }

  async function handleTauriDroppedPaths(paths: string[]): Promise<void> {
    const fs = await import('@tauri-apps/plugin-fs');
    for (const filePath of paths) {
      const name = filePath.split('/').pop() ?? filePath;
      if (!isAccepted(name)) continue;
      const ext = getExt(name);
      try {
        let content: string;
        let size: number;

        if (BINARY_EXTENSIONS.has(ext)) {
          const bytes = await fs.readFile(filePath);
          size = bytes.byteLength;
          const base64 = btoa(
            Array.from(new Uint8Array(bytes.buffer ?? bytes), (b) => String.fromCharCode(b)).join('')
          );
          const label = ext.replace('.', '').toUpperCase();
          content = `[${label} Document: ${name}]\n[Binary content — ${formatSize(size)} — will be processed by AI during enhancement]\n[Base64 length: ${base64.length} chars]\n\n--- Base64 content (first 200 chars) ---\n${base64.slice(0, 200)}...`;
        } else {
          content = await fs.readTextFile(filePath);
          size = new TextEncoder().encode(content).byteLength;
        }

        const doc: WizardDocument = {
          id: crypto.randomUUID(),
          name,
          content,
          format: getFormat(name),
          size,
        };
        wizardStore.addDocument(doc);
      } catch (err) {
        console.error(`[Wizard] Failed to read dropped file "${filePath}":`, err);
      }
    }
  }

  // Tauri native drag-drop events (HTML5 drag-drop is blocked by Tauri's handler)
  onMount(() => {
    if (!isTauri()) return;
    let unlisten: (() => void) | undefined;
    (async () => {
      const { getCurrentWebview } = await import('@tauri-apps/api/webview');
      unlisten = await getCurrentWebview().onDragDropEvent((event) => {
        const { type } = event.payload;
        if (type === 'enter' || type === 'over') {
          dragOver = true;
        } else if (type === 'leave' || type === 'cancel') {
          dragOver = false;
        } else if (type === 'drop') {
          dragOver = false;
          const payload = event.payload as { type: 'drop'; paths: string[] };
          void handleTauriDroppedPaths(payload.paths);
        }
      });
    })();
    return () => { unlisten?.(); };
  });

  function removeDoc(id: string): void {
    wizardStore.removeDocument(id);
  }

  function formatSize(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }

  let tempAgentId: string | null = null;

  async function getOrCreateAgent(): Promise<BizforgeAgent> {
    const existing = agentsStore.agents[0];
    if (existing !== undefined) return existing;

    enhanceProgress = "Setting up AI assistant...";
    const wsId = workspaceStore.activeWorkspaceId;
    const model = settingsStore.data.default_model ?? 'claude-sonnet-4-6';
    const created = await agentsApi.create({
      name: 'wizard-assistant',
      display_name: 'Wizard Assistant',
      role: 'assistant',
      adapter: 'cursor_cli',
      model,
      avatar_emoji: '🧙',
      system_prompt: 'You are a helpful project planning assistant.',
      workspace_id: wsId ?? undefined,
    });
    tempAgentId = created.id;
    return created;
  }

  async function enhanceWithAI(): Promise<void> {
    wizardStore.isEnhancing = true;
    enhanceProgress = "Preparing context...";

    const docSummary = wizardStore.uploadedDocuments
      .map((d) => `### ${d.name}\n${d.content.slice(0, 3000)}`)
      .join('\n\n---\n\n');

    const prompt = `You are a project planning assistant. Analyze the following project documentation and user context, then produce a comprehensive project brief.

## Uploaded Documentation
${docSummary || '(No documents uploaded)'}

## User-Provided Context
${wizardStore.userContext || '(No additional context)'}

## Workspace
Name: ${wizardStore.workspaceName}
Description: ${wizardStore.workspaceDescription || '(none)'}

Please analyze this and produce a structured project brief that includes:
1. **Project Summary** — A concise 2-3 sentence overview
2. **Domain** — The project domain (SaaS, mobile app, data pipeline, DevOps, etc.)
3. **Tech Stack** — Identified or recommended technologies
4. **Key Deliverables** — Major milestones and outputs
5. **Team Needs** — Suggested roles and team composition
6. **Risks & Gaps** — Potential risks or missing requirements
7. **Architecture Notes** — Any architectural patterns or considerations

Write in clear prose. Be specific and actionable.`;

    try {
      const agent = await getOrCreateAgent();

      const session = await sessions.create({
        agent_id: agent.id,
        title: `Wizard: Enhance context for ${wizardStore.workspaceName}`,
      });

      const sessionId = (session as { session?: { id: string }; id?: string }).session?.id ?? (session as { id: string }).id;
      wizardStore.enhanceSessionId = sessionId;
      enhanceProgress = "Analyzing documentation...";

      let accumulated = "";
      streamCtrl = streamMessage({
        sessionId,
        content: prompt,
        model: settingsStore.data.default_model,
        onEvent(event) {
          if (event.type === 'streaming_token') {
            const delta = (event as { delta?: string }).delta ?? '';
            accumulated += delta;
            wizardStore.enhancedContext = accumulated;
            if (accumulated.length < 100) enhanceProgress = "Analyzing documentation...";
            else if (accumulated.length < 500) enhanceProgress = "Identifying tech stack...";
            else enhanceProgress = "Building project brief...";
          }
        },
        onDone() {
          wizardStore.isEnhancing = false;
          enhanceProgress = "";
          cleanupTempAgent();
        },
        onError() {
          wizardStore.isEnhancing = false;
          enhanceProgress = "";
          cleanupTempAgent();
          if (!accumulated) wizardStore.enhancedContext = "Enhancement failed. You can try again or proceed with your manual context.";
        },
      });
    } catch (err) {
      console.error('[Wizard] Enhancement failed:', err);
      wizardStore.enhancedContext = `Enhancement failed: ${(err as Error).message}. You can try again or proceed with your manual context.`;
      wizardStore.isEnhancing = false;
      enhanceProgress = "";
      cleanupTempAgent();
    }
  }

  function cleanupTempAgent(): void {
    if (tempAgentId !== null) {
      agentsApi.terminate(tempAgentId).catch(() => undefined);
      agentsStore.agents = agentsStore.agents.filter((a) => a.id !== tempAgentId);
      tempAgentId = null;
    }
  }

  async function mockEnhance(_prompt: string): Promise<void> {
    const brief = `## Project Brief: ${wizardStore.workspaceName}

**Project Summary:** ${wizardStore.workspaceDescription || wizardStore.workspaceName} is a modern software project that requires a coordinated team of AI agents. Based on the provided documentation, this project involves full-stack development with automated testing and deployment capabilities.

**Domain:** Software Development / SaaS Platform

**Tech Stack:**
- Frontend: React/TypeScript, Tailwind CSS
- Backend: Elixir/Phoenix, PostgreSQL
- Infrastructure: Docker, CI/CD pipelines
- Testing: Playwright, ExUnit

**Key Deliverables:**
1. Core application architecture and scaffolding
2. API design and implementation
3. Frontend UI components and user flows
4. Database schema and migrations
5. Test suite and QA automation
6. Documentation and deployment guides

**Team Needs:**
- Project Manager for task coordination
- 2-3 Software Engineers for implementation
- QA Engineer for testing automation
- DevOps Engineer for infrastructure

**Risks & Gaps:**
- Integration complexity between frontend and backend
- Need for comprehensive API documentation
- Performance testing requirements not yet defined

**Architecture Notes:**
- Recommend a modular monolith approach for initial development
- Event-driven architecture for async operations
- Separate concerns between data layer, business logic, and presentation`;

    const words = brief.split(' ');
    let acc = "";
    for (let i = 0; i < words.length; i++) {
      acc += (i > 0 ? ' ' : '') + words[i];
      wizardStore.enhancedContext = acc;
      if (i < 20) enhanceProgress = "Analyzing documentation...";
      else if (i < 60) enhanceProgress = "Identifying tech stack...";
      else enhanceProgress = "Building project brief...";
      await new Promise((r) => setTimeout(r, 15));
    }
    wizardStore.isEnhancing = false;
    enhanceProgress = "";
  }

  function cancelEnhance(): void {
    streamCtrl?.abort();
    streamCtrl = null;
    wizardStore.isEnhancing = false;
    enhanceProgress = "";
  }
</script>

<div class="s2-container">
  <h3 class="s2-heading">Upload Documentation & Context</h3>
  <p class="s2-desc">Add project docs, requirements, specs, or ERD files. Then describe your vision and let AI enhance it into a comprehensive project brief.</p>

  <!-- File upload zone -->
  <div
    class="s2-drop"
    class:dragover={dragOver}
    role="region"
    aria-label="Drop files here or click to upload"
  >
    <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" class="s2-drop-icon">
      <path d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5m-13.5-9L12 3m0 0l4.5 4.5M12 3v13.5" />
    </svg>
    <p class="s2-drop-text">Drag & drop files here</p>
    <p class="s2-drop-hint">.md, .txt, .pdf, .doc, .docx, .xls, .xlsx, .json, .yaml, .csv, .sql, .dbml</p>
    <label class="s2-browse-btn">
      Choose Files
      <input type="file" multiple accept=".md,.txt,.json,.yaml,.yml,.csv,.sql,.dbml,.pdf,.doc,.docx,.xls,.xlsx" onchange={(e) => handleFiles((e.target as HTMLInputElement).files)} hidden />
    </label>
  </div>

  <!-- Uploaded files list -->
  {#if wizardStore.uploadedDocuments.length > 0}
    <div class="s2-files">
      <span class="s2-files-label">{wizardStore.uploadedDocuments.length} file{wizardStore.uploadedDocuments.length !== 1 ? 's' : ''} uploaded</span>
      <div class="s2-file-list">
        {#each wizardStore.uploadedDocuments as doc (doc.id)}
          <div class="s2-file-item">
            <span class="s2-file-icon">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true">
                <path d="M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m2.25 0H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z" />
              </svg>
            </span>
            <span class="s2-file-name">{doc.name}</span>
            <span class="s2-file-size">{formatSize(doc.size)}</span>
            <button class="s2-file-remove" onclick={() => removeDoc(doc.id)} aria-label="Remove {doc.name}">
              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                <line x1="18" y1="6" x2="6" y2="18" /><line x1="6" y1="6" x2="18" y2="18" />
              </svg>
            </button>
          </div>
        {/each}
      </div>
    </div>
  {/if}

  <!-- Context textarea -->
  <div class="s2-context">
    <label class="s2-label">
      <span class="s2-label-text">Project Context</span>
      <span class="s2-label-hint">Describe your project vision, requirements, tech stack, domain knowledge, or constraints.</span>
      <textarea
        class="s2-textarea"
        rows="5"
        placeholder="e.g. We're building a multi-tenant SaaS platform for project management. The backend is Elixir/Phoenix with PostgreSQL. We need user auth, team management, real-time collaboration..."
        bind:value={wizardStore.userContext}
      ></textarea>
    </label>
  </div>

  <!-- Enhance with AI -->
  <div class="s2-enhance">
    {#if wizardStore.isEnhancing}
      <div class="s2-enhance-progress">
        <div class="s2-spinner"></div>
        <span class="s2-progress-text">{enhanceProgress}</span>
        <button class="s2-cancel" onclick={cancelEnhance}>Cancel</button>
      </div>
    {:else}
      <button
        class="s2-enhance-btn"
        onclick={enhanceWithAI}
        disabled={wizardStore.uploadedDocuments.length === 0 && wizardStore.userContext.trim().length === 0}
      >
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <path d="M9.813 15.904L9 18.75l-.813-2.846a4.5 4.5 0 00-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 003.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 003.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 00-3.09 3.09zM18.259 8.715L18 9.75l-.259-1.035a3.375 3.375 0 00-2.455-2.456L14.25 6l1.036-.259a3.375 3.375 0 002.455-2.456L18 2.25l.259 1.035a3.375 3.375 0 002.455 2.456L21.75 6l-1.036.259a3.375 3.375 0 00-2.455 2.456z" />
        </svg>
        Enhance with AI
      </button>
      <span class="s2-enhance-hint">Uses your primary model ({settingsStore.data.default_model}) to analyze docs and build a project brief</span>
    {/if}
  </div>

  <!-- Enhanced context preview -->
  {#if wizardStore.enhancedContext !== null}
    <div class="s2-preview">
      <div class="s2-preview-header">
        <span class="s2-preview-label">Enhanced Project Brief</span>
        {#if !wizardStore.isEnhancing}
          <button class="s2-preview-redo" onclick={enhanceWithAI}>
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
              <path d="M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0l3.181 3.183a8.25 8.25 0 0013.803-3.7M4.031 9.865a8.25 8.25 0 0113.803-3.7l3.181 3.182" />
            </svg>
            Redo
          </button>
        {/if}
      </div>
      <div class="s2-preview-content">
        {wizardStore.enhancedContext}
        {#if wizardStore.isEnhancing}
          <span class="s2-cursor">|</span>
        {/if}
      </div>
    </div>
  {/if}
</div>

<style>
  .s2-container { max-width: 640px; margin: 0 auto; }
  .s2-heading {
    font-size: 18px; font-weight: 600; margin: 0 0 6px;
    color: var(--text-primary);
  }
  .s2-desc {
    font-size: 13px; color: var(--text-secondary);
    margin: 0 0 20px; line-height: 1.5;
  }
  .s2-drop {
    border: 2px dashed var(--border-subtle, rgba(255,255,255,0.1));
    border-radius: 12px; padding: 28px 20px;
    text-align: center; cursor: pointer;
    transition: all 0.2s;
  }
  .s2-drop:hover, .s2-drop.dragover {
    border-color: var(--accent, #f97316);
    background: rgba(249,115,22,0.04);
  }
  .s2-drop-icon { color: var(--text-tertiary); margin-bottom: 8px; }
  .s2-drop-text { font-size: 14px; color: var(--text-secondary); margin: 0 0 4px; }
  .s2-drop-hint { font-size: 11px; color: var(--text-tertiary); margin: 0 0 12px; }
  .s2-browse-btn {
    display: inline-block; padding: 6px 16px; border-radius: 6px;
    background: rgba(255,255,255,0.06); color: var(--text-secondary);
    font-size: 12px; font-weight: 500; cursor: pointer;
    border: 1px solid var(--border-subtle, rgba(255,255,255,0.08));
    transition: all 0.15s;
  }
  .s2-browse-btn:hover { background: rgba(255,255,255,0.1); }
  .s2-files { margin-top: 16px; }
  .s2-files-label {
    font-size: 12px; font-weight: 500; color: var(--text-secondary);
    margin-bottom: 8px; display: block;
  }
  .s2-file-list { display: flex; flex-direction: column; gap: 4px; }
  .s2-file-item {
    display: flex; align-items: center; gap: 8px;
    padding: 6px 10px; border-radius: 6px;
    background: rgba(255,255,255,0.03);
  }
  .s2-file-icon { color: var(--text-tertiary); flex-shrink: 0; }
  .s2-file-name { font-size: 13px; color: var(--text-primary); flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .s2-file-size { font-size: 11px; color: var(--text-tertiary); flex-shrink: 0; }
  .s2-file-remove {
    background: none; border: none; color: var(--text-tertiary);
    cursor: pointer; padding: 2px; border-radius: 4px;
    transition: color 0.15s;
  }
  .s2-file-remove:hover { color: #ef4444; }
  .s2-context { margin-top: 20px; }
  .s2-label { display: flex; flex-direction: column; gap: 4px; }
  .s2-label-text { font-size: 13px; font-weight: 500; color: var(--text-primary); }
  .s2-label-hint { font-size: 11px; color: var(--text-tertiary); }
  .s2-textarea {
    background: rgba(255,255,255,0.04);
    border: 1px solid var(--border-subtle, rgba(255,255,255,0.08));
    border-radius: 8px; padding: 10px 12px;
    color: var(--text-primary); font-size: 13px;
    font-family: inherit; resize: vertical; min-height: 80px;
    transition: border-color 0.15s;
  }
  .s2-textarea:focus { outline: none; border-color: var(--accent, #f97316); }
  .s2-enhance { margin-top: 20px; display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
  .s2-enhance-btn {
    display: inline-flex; align-items: center; gap: 8px;
    padding: 10px 20px; border-radius: 8px;
    background: linear-gradient(135deg, #f97316, #ea580c);
    color: #fff; font-size: 14px; font-weight: 600;
    border: none; cursor: pointer; transition: filter 0.15s;
  }
  .s2-enhance-btn:not(:disabled):hover { filter: brightness(1.1); }
  .s2-enhance-btn:disabled { opacity: 0.4; cursor: not-allowed; }
  .s2-enhance-hint { font-size: 11px; color: var(--text-tertiary); flex: 1; min-width: 200px; }
  .s2-enhance-progress { display: flex; align-items: center; gap: 10px; }
  .s2-spinner {
    width: 16px; height: 16px; border-radius: 50%;
    border: 2px solid rgba(249,115,22,0.2);
    border-top-color: var(--accent, #f97316);
    animation: wz-spin 0.6s linear infinite;
  }
  @keyframes wz-spin { to { transform: rotate(360deg); } }
  .s2-progress-text { font-size: 13px; color: var(--text-secondary); }
  .s2-cancel {
    background: none; border: none; color: var(--text-tertiary);
    font-size: 12px; cursor: pointer; text-decoration: underline;
  }
  .s2-preview {
    margin-top: 20px; border: 1px solid var(--border-subtle, rgba(255,255,255,0.08));
    border-radius: 10px; overflow: hidden;
  }
  .s2-preview-header {
    display: flex; align-items: center; justify-content: space-between;
    padding: 10px 14px;
    background: rgba(249,115,22,0.06);
    border-bottom: 1px solid var(--border-subtle, rgba(255,255,255,0.06));
  }
  .s2-preview-label { font-size: 12px; font-weight: 600; color: var(--accent, #f97316); }
  .s2-preview-redo {
    display: inline-flex; align-items: center; gap: 4px;
    background: none; border: none; color: var(--text-tertiary);
    font-size: 11px; cursor: pointer;
  }
  .s2-preview-redo:hover { color: var(--text-secondary); }
  .s2-preview-content {
    padding: 14px; font-size: 13px; color: var(--text-primary);
    line-height: 1.7; white-space: pre-wrap; max-height: 300px; overflow-y: auto;
  }
  .s2-cursor {
    animation: wz-blink 0.8s step-end infinite;
    color: var(--accent, #f97316); font-weight: 600;
  }
  @keyframes wz-blink { 50% { opacity: 0; } }
</style>
