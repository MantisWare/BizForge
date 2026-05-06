<!-- src/routes/app/library/companies/[id]/+page.svelte -->
<script lang="ts">
  import { page } from '$app/state';
  import { goto } from '$app/navigation';
  import PageShell from '$lib/components/layout/PageShell.svelte';
  import SkillsPreviewModal from '$lib/components/library/SkillsPreviewModal.svelte';
  import {
    getLibraryCompanyDetail,
    type LibraryOperation,
  } from '$lib/api/mock/library';
  import type { LibrarySkill } from '$lib/api/mock/library/types';
  import { deployTemplate } from '$lib/services/template-deploy';
  import { toastStore } from '$lib/stores/toasts.svelte';
  import { skillsStore } from '$lib/stores/skills.svelte';
  import {
    resolveSkillsForLibraryEntity,
    partitionSkills,
  } from '$lib/data/skill-dependencies';
  import AgentIcon from '$lib/components/shared/AgentIcon.svelte';

  const id = $derived(page.params.id ?? '');
  const company = $derived<LibraryOperation | null>(id ? getLibraryCompanyDetail(id) : null);

  let deploying = $state(false);
  let deployed = $state(false);

  let skillsModalOpen = $state(false);
  let skillsModalToAdd = $state<LibrarySkill[]>([]);
  let skillsModalActive = $state<LibrarySkill[]>([]);

  function handleDeploy() {
    if (!company || deploying) return;
    const ids = resolveSkillsForLibraryEntity(company);
    if (ids.length === 0) {
      executeDeploy();
      return;
    }
    const { alreadyActive, toAdd } = partitionSkills(ids, skillsStore.skills);
    if (toAdd.length === 0) {
      executeDeploy();
      return;
    }
    skillsModalToAdd = toAdd;
    skillsModalActive = alreadyActive;
    skillsModalOpen = true;
  }

  async function handleSkillsConfirm() {
    skillsModalOpen = false;
    await skillsStore.installFromLibrary(skillsModalToAdd);
    executeDeploy();
  }

  function handleSkillsCancel() {
    skillsModalOpen = false;
  }

  async function executeDeploy() {
    if (!company || deploying) return;
    deploying = true;
    try {
      const result = await deployTemplate(company.id, company.name);
      if (result.success) {
        deployed = true;
        toastStore.success(
          `${company.name} deployed`,
          `${result.agentCount} agents provisioned.`,
        );
        goto('/app');
      } else {
        toastStore.error('Deploy failed', result.error ?? 'Unknown error');
      }
    } catch (e) {
      toastStore.error('Deploy failed', (e as Error).message);
    } finally {
      deploying = false;
    }
  }


  function categoryColor(cat: string): string {
    const map: Record<string, string> = {
      'saas':        '#60a5fa',
      'agency':      '#fb923c',
      'startup':     'rgba(52, 211, 153, 0.6)',
      'enterprise':  '#f472b6',
      'research':    '#fb923c',
      'ops':         '#facc15',
      'finance':     'rgba(34, 197, 94, 0.6)',
      'creative':    '#f87171',
    };
    return map[cat.toLowerCase()] ?? '#94a3b8';
  }
</script>

<svelte:head>
  <title>{company ? `${company.name} — Library — Bizforge` : 'Company — Library — Bizforge'}</title>
</svelte:head>

<PageShell title={company?.name ?? 'Company'} subtitle={company ? company.category : undefined}>
  {#if !company}
    <div class="ldc-not-found" role="main">
      <span class="ldc-not-found-icon" aria-hidden="true"><AgentIcon value="magnifying" size={36} /></span>
      <p class="ldc-not-found-text">Company template not found.</p>
      <button
        class="ldc-back-btn"
        onclick={() => goto('/app/library')}
        aria-label="Go back to library"
      >
        ← Back to library
      </button>
    </div>
  {:else}
    <div class="ldc-page">

      <!-- Top bar -->
      <div class="ldc-topbar">
        <button
          class="ldc-back"
          onclick={() => goto('/app/library')}
          aria-label="Back to library"
        >
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <path d="M19 12H5M12 19l-7-7 7-7" />
          </svg>
          Library
        </button>
        <span class="ldc-breadcrumb-sep" aria-hidden="true">/</span>
        <span class="ldc-breadcrumb-cur">Companies</span>
      </div>

      <!-- Two-column layout -->
      <div class="ldc-layout">

        <!-- LEFT: content -->
        <div class="ldc-main">

          <!-- Hero -->
          <div class="ldc-hero">
            <span class="ldc-hero-emoji" aria-hidden="true"><AgentIcon value={company.emoji} size={36} /></span>
            <div class="ldc-hero-meta">
              <div class="ldc-hero-badges">
                {#if company.isOfficial}
                  <span class="ldc-badge ldc-badge--official" aria-label="Official company template">Official</span>
                {/if}
                <span
                  class="ldc-badge ldc-badge--category"
                  style="
                    background: {categoryColor(company.category)}1a;
                    border-color: {categoryColor(company.category)}40;
                    color: {categoryColor(company.category)};
                  "
                  aria-label="Category: {company.category}"
                >{company.category}</span>
              </div>
              <h1 class="ldc-hero-name">{company.name}</h1>
            </div>
          </div>

          <!-- Description -->
          <section class="ldc-card" aria-label="Company description">
            <h2 class="ldc-card-title">About</h2>
            <p class="ldc-description">{company.description}</p>
          </section>

          <!-- Composition stats -->
          <section class="ldc-card" aria-label="Company composition">
            <h2 class="ldc-card-title">Composition</h2>
            <div class="ldc-composition">
              <div class="ldc-comp-item">
                <div class="ldc-comp-icon" aria-hidden="true"><AgentIcon value="robot" size={24} /></div>
                <div class="ldc-comp-count">{company.agent_count}</div>
                <div class="ldc-comp-label">Agents</div>
              </div>
              <div class="ldc-comp-divider" aria-hidden="true"></div>
              <div class="ldc-comp-item">
                <div class="ldc-comp-icon" aria-hidden="true"><AgentIcon value="bolt" size={24} /></div>
                <div class="ldc-comp-count">{company.skill_count}</div>
                <div class="ldc-comp-label">Skills</div>
              </div>
            </div>

            {#if company.member_agents.length > 0}
              <div class="ldc-members-section">
                <h3 class="ldc-members-heading">
                  <AgentIcon value="robot" size={14} />
                  Agents
                </h3>
                <ul class="ldc-members-list" role="list">
                  {#each company.member_agents as agent (agent.id)}
                    <li class="ldc-member" title={agent.description} role="listitem">
                      {agent.name}
                    </li>
                  {/each}
                </ul>
              </div>
            {/if}

            {#if company.member_skills.length > 0}
              <div class="ldc-members-section">
                <h3 class="ldc-members-heading">
                  <AgentIcon value="bolt" size={14} />
                  Skills
                </h3>
                <ul class="ldc-members-list" role="list">
                  {#each company.member_skills as skill (skill.id)}
                    <li class="ldc-member" title={skill.description} role="listitem">
                      {skill.name}
                    </li>
                  {/each}
                </ul>
              </div>
            {/if}
          </section>

          <!-- Version -->
          <section class="ldc-card" aria-label="Company version">
            <h2 class="ldc-card-title">Version</h2>
            <p class="ldc-description">v{company.version}</p>
          </section>

          <!-- Tags -->
          {#if company.tags.length > 0}
            <section class="ldc-card" aria-label="Company tags">
              <h2 class="ldc-card-title">Tags</h2>
              <div class="ldc-tags" role="list" aria-label="Tags">
                {#each company.tags as tag}
                  <span class="ldc-tag" role="listitem">{tag}</span>
                {/each}
              </div>
            </section>
          {/if}

        </div>

        <!-- RIGHT: Configuration panel -->
        <aside class="ldc-sidebar" aria-label="Configuration panel">
          <div class="ldc-panel">
            <h2 class="ldc-panel-title">Deploy Company</h2>

            <div class="ldc-panel-info">
              <p class="ldc-panel-desc">
                Deploying this company will provision {company.agent_count}
                {company.agent_count === 1 ? 'agent' : 'agents'} and configure
                {company.skill_count} {company.skill_count === 1 ? 'skill' : 'skills'}
                across your workspace.
              </p>
            </div>

            <div class="ldc-panel-meta">
              <div class="ldc-meta-row">
                <span class="ldc-meta-label">Agents</span>
                <span class="ldc-meta-value">{company.agent_count}</span>
              </div>
              <div class="ldc-meta-row">
                <span class="ldc-meta-label">Skills</span>
                <span class="ldc-meta-value">{company.skill_count}</span>
              </div>
              <div class="ldc-meta-row">
                <span class="ldc-meta-label">Category</span>
                <span
                  class="ldc-meta-value"
                  style="color: {categoryColor(company.category)}"
                >{company.category}</span>
              </div>
              <div class="ldc-meta-row">
                <span class="ldc-meta-label">Version</span>
                <span class="ldc-meta-value">{company.version}</span>
              </div>
            </div>

            <button
              class="ldc-deploy-btn"
              class:ldc-deploy-btn--loading={deploying}
              onclick={handleDeploy}
              disabled={deploying || deployed}
              aria-label="Deploy {company.name} company"
            >
              {#if deployed}
                Deployed
              {:else if deploying}
                Deploying...
              {:else}
                Deploy Company
              {/if}
            </button>
          </div>
        </aside>

      </div>
    </div>
  {/if}
</PageShell>

<SkillsPreviewModal
  open={skillsModalOpen}
  entityName={company?.name ?? 'Company'}
  skillsToAdd={skillsModalToAdd}
  skillsAlreadyActive={skillsModalActive}
  onConfirm={handleSkillsConfirm}
  onCancel={handleSkillsCancel}
/>

<style>
  /* Not found */
  .ldc-not-found {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 12px;
    height: 100%;
    color: var(--text-tertiary);
    font-size: 13px;
  }

  .ldc-not-found-icon {
    display: flex;
    align-items: center;
    color: #f26522;
    opacity: 0.4;
  }

  .ldc-not-found-text {
    margin: 0;
  }

  .ldc-back-btn {
    height: 32px;
    padding: 0 14px;
    border-radius: var(--radius-sm);
    border: 1px solid var(--border-default);
    background: transparent;
    color: var(--text-secondary);
    font-size: 13px;
    font-family: var(--font-sans);
    cursor: pointer;
    transition: all 120ms ease;
  }

  .ldc-back-btn:hover {
    background: var(--bg-elevated);
    color: var(--text-primary);
  }

  /* Page wrapper */
  .ldc-page {
    display: flex;
    flex-direction: column;
    gap: 0;
    min-height: 100%;
  }

  /* Top bar */
  .ldc-topbar {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 16px 24px 0;
  }

  .ldc-back {
    display: flex;
    align-items: center;
    gap: 6px;
    height: 28px;
    padding: 0 10px;
    border-radius: var(--radius-xs);
    border: 1px solid transparent;
    background: transparent;
    color: var(--text-tertiary);
    font-size: 12px;
    font-family: var(--font-sans);
    cursor: pointer;
    transition: all 120ms ease;
  }

  .ldc-back:hover {
    background: var(--bg-elevated);
    border-color: var(--border-default);
    color: var(--text-primary);
  }

  .ldc-breadcrumb-sep {
    color: var(--text-muted);
    font-size: 12px;
  }

  .ldc-breadcrumb-cur {
    font-size: 12px;
    color: var(--text-secondary);
  }

  /* Two-column layout */
  .ldc-layout {
    display: grid;
    grid-template-columns: 1fr 320px;
    gap: 24px;
    padding: 24px;
    align-items: start;
  }

  .ldc-main {
    display: flex;
    flex-direction: column;
    gap: 16px;
    min-width: 0;
  }

  /* Hero */
  .ldc-hero {
    display: flex;
    align-items: flex-start;
    gap: 20px;
  }

  .ldc-hero-emoji {
    display: flex;
    align-items: center;
    color: #f26522;
    flex-shrink: 0;
  }

  .ldc-hero-meta {
    display: flex;
    flex-direction: column;
    gap: 6px;
    min-width: 0;
    padding-top: 4px;
  }

  .ldc-hero-badges {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }

  .ldc-hero-name {
    font-size: 24px;
    font-weight: 700;
    color: var(--text-primary);
    margin: 0;
    line-height: 1.2;
  }

  /* Badges */
  .ldc-badge {
    display: inline-flex;
    align-items: center;
    height: 20px;
    padding: 0 8px;
    border-radius: 10px;
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.2px;
    white-space: nowrap;
    border: 1px solid transparent;
  }

  .ldc-badge--official {
    background: rgba(251, 191, 36, 0.15);
    border-color: rgba(251, 191, 36, 0.3);
    color: #fbbf24;
  }

  .ldc-badge--category {
    text-transform: capitalize;
  }

  /* Cards */
  .ldc-card {
    background: var(--bg-surface);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-md);
    padding: 16px;
    backdrop-filter: blur(8px);
    -webkit-backdrop-filter: blur(8px);
  }

  .ldc-card-title {
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    color: var(--text-tertiary);
    margin: 0 0 12px 0;
  }

  .ldc-description {
    font-size: 14px;
    line-height: 1.6;
    color: var(--text-secondary);
    margin: 0;
  }

  /* Composition */
  .ldc-composition {
    display: flex;
    align-items: center;
    gap: 0;
  }

  .ldc-comp-item {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
    padding: 16px 32px;
    background: var(--bg-secondary);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-sm);
    flex: 1;
  }

  .ldc-comp-divider {
    width: 1px;
    height: 60px;
    background: var(--border-default);
    flex-shrink: 0;
    margin: 0 -1px;
    z-index: 1;
  }

  .ldc-comp-icon {
    display: flex;
    align-items: center;
    justify-content: center;
    color: #f26522;
  }

  .ldc-comp-count {
    font-size: 32px;
    font-weight: 700;
    color: var(--text-primary);
    font-variant-numeric: tabular-nums;
    line-height: 1;
  }

  .ldc-comp-label {
    font-size: 12px;
    color: var(--text-muted);
  }

  /* Composition member lists */
  .ldc-members-section {
    margin-top: 16px;
    padding-top: 16px;
    border-top: 1px solid var(--border-default);
  }

  .ldc-members-heading {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.4px;
    color: var(--text-tertiary);
    margin: 0 0 8px 0;
  }

  .ldc-members-heading :global(svg) {
    color: #f26522;
    flex-shrink: 0;
  }

  .ldc-members-list {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    list-style: none;
    margin: 0;
    padding: 0;
  }

  .ldc-member {
    display: inline-flex;
    align-items: center;
    height: 26px;
    padding: 0 10px;
    border-radius: var(--radius-xs);
    background: var(--bg-secondary);
    border: 1px solid var(--border-default);
    font-size: 12px;
    color: var(--text-secondary);
    cursor: default;
    transition: all 120ms ease;
  }

  .ldc-member:hover {
    background: var(--bg-elevated);
    border-color: rgba(242, 101, 34, 0.3);
    color: var(--text-primary);
  }

  /* Stats grid */
  .ldc-stats-grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 12px;
  }

  .ldc-stat {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
    padding: 12px 8px;
    background: var(--bg-secondary);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-sm);
  }

  .ldc-stat-icon {
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--text-muted);
  }

  .ldc-stat-value {
    font-size: 18px;
    font-weight: 700;
    color: var(--text-primary);
    font-variant-numeric: tabular-nums;
    line-height: 1;
  }

  .ldc-stat-label {
    font-size: 11px;
    color: var(--text-muted);
    text-align: center;
  }

  /* Tags */
  .ldc-tags {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }

  .ldc-tag {
    display: inline-flex;
    align-items: center;
    height: 24px;
    padding: 0 10px;
    border-radius: var(--radius-xs);
    background: rgba(244, 114, 182, 0.08);
    border: 1px solid rgba(244, 114, 182, 0.2);
    font-size: 12px;
    color: #f9a8d4;
    font-family: var(--font-mono);
  }

  /* Sidebar */
  .ldc-sidebar {
    position: sticky;
    top: 24px;
  }

  .ldc-panel {
    background: var(--bg-surface);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-md);
    padding: 20px;
    backdrop-filter: blur(12px);
    -webkit-backdrop-filter: blur(12px);
    display: flex;
    flex-direction: column;
    gap: 16px;
  }

  .ldc-panel-title {
    font-size: 13px;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0;
  }

  .ldc-panel-info {
    padding: 12px;
    background: var(--bg-secondary);
    border-radius: var(--radius-sm);
    border: 1px solid var(--border-default);
  }

  .ldc-panel-desc {
    font-size: 12px;
    line-height: 1.6;
    color: var(--text-tertiary);
    margin: 0;
  }

  .ldc-panel-meta {
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 12px;
    background: var(--bg-secondary);
    border-radius: var(--radius-sm);
    border: 1px solid var(--border-default);
  }

  .ldc-meta-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }

  .ldc-meta-label {
    font-size: 11px;
    color: var(--text-muted);
    flex-shrink: 0;
  }

  .ldc-meta-value {
    font-size: 12px;
    color: var(--text-secondary);
    text-align: right;
    text-transform: capitalize;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .ldc-deploy-btn {
    height: 38px;
    width: 100%;
    border-radius: var(--radius-sm);
    border: 1px solid rgba(244, 114, 182, 0.3);
    background: rgba(244, 114, 182, 0.1);
    color: #f9a8d4;
    font-size: 13px;
    font-weight: 600;
    font-family: var(--font-sans);
    cursor: pointer;
    transition: all 120ms ease;
  }

  .ldc-deploy-btn:hover {
    background: rgba(244, 114, 182, 0.18);
    border-color: rgba(244, 114, 182, 0.5);
    color: #fbcfe8;
  }

  .ldc-deploy-btn:active:not(:disabled) {
    background: rgba(244, 114, 182, 0.25);
  }

  .ldc-deploy-btn:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .ldc-deploy-btn--loading {
    cursor: wait;
  }
</style>
