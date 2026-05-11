<!-- src/lib/components/wizard/steps/Step3CompanySelect.svelte -->
<script lang="ts">
  import { wizardStore } from '$lib/stores/wizard.svelte';
  import { settingsStore } from '$lib/stores/settings.svelte';
  import { agentsStore } from '$lib/stores/agents.svelte';
  import { workspaceStore } from '$lib/stores/workspace.svelte';
  import { agents as agentsApi, sessions } from '$api/client';
  import { streamMessage } from '$api/sse';
  import { HIREABLE_TEAM_TEMPLATES, TEMPLATE_AGENTS } from '$lib/data/team-templates';
  import type { TeamTemplateId } from '$lib/data/team-templates';
  import type { CompanyRecommendation, WizardAgent, BizforgeAgent } from '$api/types';
  import type { StreamController } from '$api/sse';

  let showBrowse = $state(false);
  let searchQuery = $state("");
  let streamCtrl = $state<StreamController | null>(null);
  let tempAgentId: string | null = null;

  async function getOrCreateAgent(): Promise<BizforgeAgent> {
    const existing = agentsStore.agents[0];
    if (existing !== undefined) return existing;
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

  function cleanupTempAgent(): void {
    if (tempAgentId !== null) {
      agentsApi.terminate(tempAgentId).catch(() => undefined);
      agentsStore.agents = agentsStore.agents.filter((a) => a.id !== tempAgentId);
      tempAgentId = null;
    }
  }

  const filteredTemplates = $derived(
    HIREABLE_TEAM_TEMPLATES.filter((t) => {
      if (!searchQuery.trim()) return true;
      const q = searchQuery.toLowerCase();
      return t.name.toLowerCase().includes(q) || t.description.toLowerCase().includes(q);
    }),
  );

  function isSelected(id: string): boolean {
    return wizardStore.selectedTeamTemplates.includes(id);
  }

  function toggleTeam(id: string): void {
    if (isSelected(id)) {
      wizardStore.removeTeamTemplate(id);
    } else {
      wizardStore.addTeamTemplate(id);
      populateAgentsFromTemplate(id);
    }
  }

  function populateAgentsFromTemplate(templateId: string): void {
    const templateAgents = TEMPLATE_AGENTS[templateId as TeamTemplateId];
    if (templateAgents === undefined) return;
    const meta = HIREABLE_TEAM_TEMPLATES.find((t) => t.id === templateId);
    const teamName = meta?.name ?? templateId;

    const newAgents: WizardAgent[] = templateAgents.map((a) => ({
      id: `${templateId}-${a.id}`,
      name: a.name,
      emoji: a.emoji,
      role: a.role,
      adapter: wizardStore.sharedAdapter,
      model: wizardStore.sharedModel,
      skills: [...a.skills],
      system_prompt: a.system_prompt,
      teamId: templateId,
      teamName,
    }));

    wizardStore.agents = [
      ...wizardStore.agents.filter((a) => a.teamId !== templateId),
      ...newAgents,
    ];
  }

  function selectRecommendation(rec: { templateId: string; teamIds: string[] }): void {
    wizardStore.selectedCompanyTemplate = rec.templateId;
    for (const tid of rec.teamIds) {
      if (!wizardStore.selectedTeamTemplates.includes(tid)) {
        wizardStore.addTeamTemplate(tid);
        populateAgentsFromTemplate(tid);
      }
    }
  }

  async function getAIRecommendation(): Promise<void> {
    wizardStore.isAnalyzing = true;

    const teamList = HIREABLE_TEAM_TEMPLATES
      .map((t) => `- ${t.id}: ${t.name} (${t.count} agents) — ${t.description}`)
      .join('\n');

    const prompt = `You are a project staffing advisor for an AI agent platform. Given the following project context, recommend the best team template(s) to deploy.

## Project Context
${wizardStore.enhancedContext ?? wizardStore.userContext ?? wizardStore.workspaceDescription}

## Available Team Templates
${teamList}

Respond with ONLY valid JSON in this exact format (no markdown fences, no explanation outside the JSON):
{
  "primary": {
    "templateId": "<team-template-id>",
    "templateName": "<human name>",
    "reason": "<1-2 sentence justification>",
    "fitScore": <0.0-1.0>,
    "teamIds": ["<id1>", "<id2>"]
  },
  "alternatives": [
    {
      "templateId": "<team-template-id>",
      "templateName": "<human name>",
      "reason": "<1-2 sentence justification>",
      "fitScore": <0.0-1.0>,
      "teamIds": ["<id>"]
    }
  ]
}

Pick 1 primary recommendation and 2-3 alternatives. teamIds should list the team template IDs to deploy. For a company-like setup, recommend multiple teamIds working together.`;

    try {
      const agent = await getOrCreateAgent();
      const session = await sessions.create({
        agent_id: agent.id,
        title: `Wizard: Team recommendation for ${wizardStore.workspaceName}`,
      });
      const sessionId = (session as { session?: { id: string }; id?: string }).session?.id ?? (session as { id: string }).id;

      let accumulated = "";
      streamCtrl = streamMessage({
        sessionId,
        content: prompt,
        model: settingsStore.data.default_model,
        onEvent(event) {
          if (event.type === 'streaming_token') {
            accumulated += (event as { delta?: string }).delta ?? '';
          }
        },
        onDone() {
          try {
            const jsonMatch = accumulated.match(/\{[\s\S]*\}/);
            if (jsonMatch !== null) {
              wizardStore.aiRecommendation = JSON.parse(jsonMatch[0]) as CompanyRecommendation;
            }
          } catch { /* parse failed */ }
          wizardStore.isAnalyzing = false;
          cleanupTempAgent();
        },
        onError() {
          wizardStore.isAnalyzing = false;
          cleanupTempAgent();
        },
      });
    } catch {
      wizardStore.isAnalyzing = false;
      cleanupTempAgent();
    }
  }

  async function mockRecommend(): Promise<void> {
    await new Promise((r) => setTimeout(r, 1200));
    wizardStore.aiRecommendation = {
      primary: {
        templateId: 'dev-team',
        templateName: 'Dev Team',
        reason: 'This project requires a full software development team with a PM for coordination, engineers for implementation, and QA for quality assurance.',
        fitScore: 0.92,
        teamIds: ['dev-team'],
      },
      alternatives: [
        {
          templateId: 'ops-center',
          templateName: 'Dev Team + Ops Center',
          reason: 'Adding an ops team alongside dev provides infrastructure management and deployment automation for production readiness.',
          fitScore: 0.85,
          teamIds: ['dev-team', 'ops-center'],
        },
        {
          templateId: 'product-squad',
          templateName: 'Product Squad',
          reason: 'A product-focused team can handle requirements, design, and documentation before handing off to engineers.',
          fitScore: 0.72,
          teamIds: ['product-squad'],
        },
      ],
    };
    wizardStore.isAnalyzing = false;
  }

  $effect(() => {
    if (wizardStore.currentStep === 3 && wizardStore.aiRecommendation === null && !wizardStore.isAnalyzing) {
      const hasContext = (wizardStore.enhancedContext ?? wizardStore.userContext ?? '').trim().length > 0;
      if (hasContext) {
        void getAIRecommendation();
      }
    }
  });
</script>

<div class="s3-container">
  <h3 class="s3-heading">Choose Your Team</h3>
  <p class="s3-desc">Select team templates to deploy. Each template includes pre-configured agents with specialized roles and skills.</p>

  <!-- AI Recommendations -->
  {#if wizardStore.isAnalyzing}
    <div class="s3-analyzing">
      <div class="s3-spinner"></div>
      <span>Analyzing project requirements...</span>
    </div>
  {:else if wizardStore.aiRecommendation !== null}
    <div class="s3-recs">
      <span class="s3-recs-label">AI Recommendations</span>
      <div class="s3-rec-grid">
        <!-- Primary + Alternatives -->
        {#each [wizardStore.aiRecommendation.primary, ...wizardStore.aiRecommendation.alternatives] as rec, idx (rec.templateId)}
          <button
            class="s3-rec-card"
            class:s3-rec-primary={idx === 0}
            class:selected={rec.teamIds.every((id) => isSelected(id))}
            onclick={() => selectRecommendation(rec)}
          >
            {#if idx === 0}
              <div class="s3-rec-badge">Best Match</div>
            {/if}
            <div class="s3-rec-name">{rec.templateName}</div>
            <div class="s3-rec-reason">{rec.reason}</div>
            <div class="s3-rec-score">
              <div class="s3-score-bar">
                <div class="s3-score-fill" style="width: {rec.fitScore * 100}%"></div>
              </div>
              <span class="s3-score-text">{Math.round(rec.fitScore * 100)}% fit</span>
            </div>
          </button>
        {/each}
      </div>
    </div>
  {/if}

  <!-- Manual browse -->
  <div class="s3-browse-section">
    <button class="s3-browse-toggle" onclick={() => { showBrowse = !showBrowse; }}>
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class:rotated={showBrowse} aria-hidden="true">
        <path d="M19.5 8.25l-7.5 7.5-7.5-7.5" />
      </svg>
      Browse all templates ({HIREABLE_TEAM_TEMPLATES.length})
    </button>

    {#if showBrowse}
      <div class="s3-browse-panel">
        <input
          type="text"
          class="s3-search"
          placeholder="Filter templates..."
          bind:value={searchQuery}
        />
        <div class="s3-template-grid">
          {#each filteredTemplates as tmpl (tmpl.id)}
            <button
              class="s3-tmpl-card"
              class:selected={isSelected(tmpl.id)}
              onclick={() => toggleTeam(tmpl.id)}
            >
              <div class="s3-tmpl-header">
                <span class="s3-tmpl-name">{tmpl.name}</span>
                <span class="s3-tmpl-count">{tmpl.count}</span>
              </div>
              <div class="s3-tmpl-desc">{tmpl.description}</div>
              {#if isSelected(tmpl.id)}
                <div class="s3-tmpl-check">
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" aria-hidden="true">
                    <polyline points="20 6 9 17 4 12" />
                  </svg>
                </div>
              {/if}
            </button>
          {/each}
        </div>
      </div>
    {/if}
  </div>

  <!-- Selected summary -->
  {#if wizardStore.selectedTeamTemplates.length > 0}
    <div class="s3-selected">
      <span class="s3-selected-label">Selected: {wizardStore.selectedTeamTemplates.length} team{wizardStore.selectedTeamTemplates.length !== 1 ? 's' : ''}, {wizardStore.agents.length} agents</span>
      <div class="s3-selected-list">
        {#each wizardStore.selectedTeamTemplates as tid (tid)}
          {@const meta = HIREABLE_TEAM_TEMPLATES.find((t) => t.id === tid)}
          <span class="s3-selected-chip">
            {meta?.name ?? tid}
            <button class="s3-chip-remove" onclick={() => toggleTeam(tid)} aria-label="Remove {meta?.name ?? tid}">
              <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" aria-hidden="true">
                <line x1="18" y1="6" x2="6" y2="18" /><line x1="6" y1="6" x2="18" y2="18" />
              </svg>
            </button>
          </span>
        {/each}
      </div>
    </div>
  {/if}
</div>

<style>
  .s3-container { max-width: 680px; margin: 0 auto; }
  .s3-heading { font-size: 18px; font-weight: 600; margin: 0 0 6px; color: var(--text-primary); }
  .s3-desc { font-size: 13px; color: var(--text-secondary); margin: 0 0 20px; line-height: 1.5; }

  .s3-analyzing { display: flex; align-items: center; gap: 10px; padding: 20px; justify-content: center; color: var(--text-secondary); font-size: 13px; }
  .s3-spinner {
    width: 16px; height: 16px; border-radius: 50%;
    border: 2px solid rgba(249,115,22,0.2); border-top-color: var(--accent, #f97316);
    animation: wz-spin 0.6s linear infinite;
  }
  @keyframes wz-spin { to { transform: rotate(360deg); } }

  .s3-recs { margin-bottom: 20px; }
  .s3-recs-label { font-size: 12px; font-weight: 600; color: var(--accent, #f97316); text-transform: uppercase; letter-spacing: 0.05em; display: block; margin-bottom: 10px; }
  .s3-rec-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 10px; }
  .s3-rec-card {
    text-align: left; padding: 14px; border-radius: 10px;
    background: rgba(255,255,255,0.03);
    border: 1px solid var(--border-subtle, rgba(255,255,255,0.08));
    cursor: pointer; transition: all 0.15s; position: relative;
  }
  .s3-rec-card:hover { border-color: rgba(249,115,22,0.3); background: rgba(249,115,22,0.04); }
  .s3-rec-card.selected { border-color: var(--accent, #f97316); background: rgba(249,115,22,0.08); }
  .s3-rec-primary { border-color: rgba(249,115,22,0.3); }
  .s3-rec-badge {
    font-size: 10px; font-weight: 700; text-transform: uppercase;
    color: var(--accent, #f97316); letter-spacing: 0.05em; margin-bottom: 6px;
  }
  .s3-rec-name { font-size: 14px; font-weight: 600; color: var(--text-primary); margin-bottom: 6px; }
  .s3-rec-reason { font-size: 12px; color: var(--text-secondary); line-height: 1.5; margin-bottom: 10px; }
  .s3-rec-score { display: flex; align-items: center; gap: 8px; }
  .s3-score-bar { flex: 1; height: 4px; border-radius: 2px; background: rgba(255,255,255,0.06); overflow: hidden; }
  .s3-score-fill { height: 100%; border-radius: 2px; background: var(--accent, #f97316); transition: width 0.3s; }
  .s3-score-text { font-size: 11px; color: var(--text-tertiary); white-space: nowrap; }

  .s3-browse-section { margin-top: 16px; }
  .s3-browse-toggle {
    display: flex; align-items: center; gap: 8px;
    background: none; border: none; color: var(--text-secondary);
    font-size: 13px; font-weight: 500; cursor: pointer;
    padding: 8px 0; transition: color 0.15s;
  }
  .s3-browse-toggle:hover { color: var(--text-primary); }
  .s3-browse-toggle svg { transition: transform 0.2s; }
  .s3-browse-toggle svg.rotated { transform: rotate(180deg); }
  .s3-browse-panel { margin-top: 12px; }
  .s3-search {
    width: 100%; padding: 8px 12px; border-radius: 8px;
    background: rgba(255,255,255,0.04);
    border: 1px solid var(--border-subtle, rgba(255,255,255,0.08));
    color: var(--text-primary); font-size: 13px; margin-bottom: 12px;
  }
  .s3-search:focus { outline: none; border-color: var(--accent, #f97316); }
  .s3-template-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: 8px; }
  .s3-tmpl-card {
    text-align: left; padding: 12px; border-radius: 8px;
    background: rgba(255,255,255,0.02);
    border: 1px solid var(--border-subtle, rgba(255,255,255,0.06));
    cursor: pointer; transition: all 0.15s; position: relative;
  }
  .s3-tmpl-card:hover { border-color: rgba(255,255,255,0.15); }
  .s3-tmpl-card.selected { border-color: var(--accent, #f97316); background: rgba(249,115,22,0.06); }
  .s3-tmpl-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 4px; }
  .s3-tmpl-name { font-size: 13px; font-weight: 600; color: var(--text-primary); }
  .s3-tmpl-count { font-size: 11px; color: var(--text-tertiary); background: rgba(255,255,255,0.06); padding: 1px 6px; border-radius: 4px; }
  .s3-tmpl-desc { font-size: 11px; color: var(--text-secondary); line-height: 1.4; }
  .s3-tmpl-check {
    position: absolute; top: 8px; right: 8px; color: var(--accent, #f97316);
  }

  .s3-selected { margin-top: 20px; padding-top: 16px; border-top: 1px solid var(--border-subtle, rgba(255,255,255,0.06)); }
  .s3-selected-label { font-size: 12px; font-weight: 500; color: var(--text-secondary); display: block; margin-bottom: 8px; }
  .s3-selected-list { display: flex; flex-wrap: wrap; gap: 6px; }
  .s3-selected-chip {
    display: inline-flex; align-items: center; gap: 6px;
    padding: 4px 10px; border-radius: 6px;
    background: rgba(249,115,22,0.1); color: var(--accent, #f97316);
    font-size: 12px; font-weight: 500;
  }
  .s3-chip-remove {
    background: none; border: none; color: inherit;
    cursor: pointer; padding: 0; display: flex;
  }
</style>
