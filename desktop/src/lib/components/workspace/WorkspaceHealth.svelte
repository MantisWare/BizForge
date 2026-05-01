<!-- src/lib/components/workspace/WorkspaceHealth.svelte -->
<script lang="ts">
  import { workspaceStore } from '$lib/stores/workspace.svelte';
  import type { HealthIssue } from '$lib/types/bizforge';

  let isRepairing = $state(false);
  let isChecking = $state(false);
  let repairSummary = $state<{ repaired: string[]; failed: string[] } | null>(null);

  const report = $derived(workspaceStore.healthReport);
  const hasRepairableIssues = $derived(
    report?.issues.some((i) => i.repairable) ?? false,
  );
  const errorCount = $derived(
    report?.issues.filter((i) => i.severity === 'error').length ?? 0,
  );
  const warnCount = $derived(
    report?.issues.filter((i) => i.severity === 'warning').length ?? 0,
  );
  const infoCount = $derived(
    report?.issues.filter((i) => i.severity === 'info').length ?? 0,
  );

  async function recheck() {
    isChecking = true;
    repairSummary = null;
    try {
      await workspaceStore.checkHealth();
    } finally {
      isChecking = false;
    }
  }

  async function repairAll() {
    isRepairing = true;
    repairSummary = null;
    try {
      const result = await workspaceStore.repairWorkspace();
      if (result !== null) {
        repairSummary = { repaired: result.repaired, failed: result.failed };
      }
    } finally {
      isRepairing = false;
    }
  }

  function severityIcon(severity: HealthIssue['severity']): string {
    switch (severity) {
      case 'error':   return 'M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z';
      case 'warning': return 'M12 9v3.75m9-.75a9 9 0 11-18 0 9 9 0 0118 0zm-9 3.75h.008v.008H12v-.008z';
      case 'info':    return 'M11.25 11.25l.041-.02a.75.75 0 011.063.852l-.708 2.836a.75.75 0 001.063.853l.041-.021M21 12a9 9 0 11-18 0 9 9 0 0118 0zm-9-3.75h.008v.008H12V8.25z';
    }
  }

  function shortPath(fullPath: string): string {
    return fullPath.replace(/^\/Users\/[^/]+/, '~');
  }
</script>

<div class="wh-panel">
  <div class="wh-header">
    <h3 class="wh-title">Workspace Health</h3>
    <div class="wh-actions">
      <button
        class="wh-btn wh-btn--secondary"
        onclick={recheck}
        disabled={isChecking}
        aria-label="Re-check health"
      >
        <svg class="wh-btn-icon" class:wh-spin={isChecking} width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
          <path d="M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0l3.181 3.183a8.25 8.25 0 0013.803-3.7M4.031 9.865a8.25 8.25 0 0113.803-3.7l3.181 3.182" />
        </svg>
        {isChecking ? 'Checking…' : 'Re-check'}
      </button>
      {#if hasRepairableIssues}
        <button
          class="wh-btn wh-btn--primary"
          onclick={repairAll}
          disabled={isRepairing}
          aria-label="Repair all fixable issues"
        >
          <svg class="wh-btn-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
            <path d="M11.42 15.17l-5.384 5.383a1.875 1.875 0 01-2.653-2.652l5.384-5.383m2.653 2.652a8.982 8.982 0 002.933-2.933m-5.586 5.586L3.75 21.75m0 0l3-3m-3 3l3 3M21.75 6.75c0 4.14-3.358 7.5-7.5 7.5S6.75 10.89 6.75 6.75 10.108-.75 14.25-.75s7.5 3.36 7.5 7.5z" />
          </svg>
          {isRepairing ? 'Repairing…' : 'Repair All'}
        </button>
      {/if}
    </div>
  </div>

  {#if report === null}
    <div class="wh-empty">
      <span class="wh-empty-text">No health check has been run yet.</span>
      <button class="wh-btn wh-btn--secondary" onclick={recheck}>Run Check</button>
    </div>
  {:else if report.healthy && report.issues.length === 0}
    <div class="wh-status wh-status--ok">
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
      <div class="wh-status-text">
        <span class="wh-status-label">Workspace is healthy</span>
        <span class="wh-status-detail">All files and directories are valid</span>
      </div>
    </div>
  {:else}
    <div class="wh-summary">
      <div class="wh-status" class:wh-status--error={errorCount > 0} class:wh-status--warn={errorCount === 0 && warnCount > 0} class:wh-status--ok={errorCount === 0 && warnCount === 0}>
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          {#if errorCount > 0}
            <path d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z" />
          {:else}
            <path d="M12 9v3.75m9-.75a9 9 0 11-18 0 9 9 0 0118 0zm-9 3.75h.008v.008H12v-.008z" />
          {/if}
        </svg>
        <div class="wh-status-text">
          <span class="wh-status-label">
            {report.issues.length} issue{report.issues.length > 1 ? 's' : ''} found
          </span>
          <span class="wh-status-detail">
            {#if errorCount > 0}{errorCount} error{errorCount > 1 ? 's' : ''}{/if}
            {#if errorCount > 0 && warnCount > 0}, {/if}
            {#if warnCount > 0}{warnCount} warning{warnCount > 1 ? 's' : ''}{/if}
            {#if (errorCount > 0 || warnCount > 0) && infoCount > 0}, {/if}
            {#if infoCount > 0}{infoCount} info{/if}
          </span>
        </div>
      </div>
    </div>

    <div class="wh-issues">
      {#each report.issues as issue (issue.code + issue.path)}
        <div class="wh-issue" class:wh-issue--error={issue.severity === 'error'} class:wh-issue--warning={issue.severity === 'warning'} class:wh-issue--info={issue.severity === 'info'}>
          <svg class="wh-issue-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
            <path d={severityIcon(issue.severity)} />
          </svg>
          <div class="wh-issue-content">
            <span class="wh-issue-message">{issue.message}</span>
            <span class="wh-issue-path" title={issue.path}>{shortPath(issue.path)}</span>
          </div>
          {#if issue.repairable}
            <span class="wh-issue-badge">auto-fixable</span>
          {/if}
        </div>
      {/each}
    </div>
  {/if}

  {#if repairSummary !== null}
    <div class="wh-repair-summary">
      <div class="wh-repair-header">Repair Results</div>
      {#if repairSummary.repaired.length > 0}
        <div class="wh-repair-section wh-repair-section--ok">
          {#each repairSummary.repaired as item}
            <div class="wh-repair-item">
              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 13l4 4L19 7" /></svg>
              {item}
            </div>
          {/each}
        </div>
      {/if}
      {#if repairSummary.failed.length > 0}
        <div class="wh-repair-section wh-repair-section--fail">
          {#each repairSummary.failed as item}
            <div class="wh-repair-item">
              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 18L18 6M6 6l12 12" /></svg>
              {item}
            </div>
          {/each}
        </div>
      {/if}
    </div>
  {/if}
</div>

<style>
  .wh-panel {
    display: flex;
    flex-direction: column;
    gap: 12px;
    padding: 16px;
    background: var(--bg-secondary);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-md);
  }

  .wh-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }

  .wh-title {
    margin: 0;
    font-size: 14px;
    font-weight: 600;
    color: var(--text-primary);
  }

  .wh-actions {
    display: flex;
    gap: 6px;
  }

  .wh-btn {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    padding: 5px 10px;
    border: none;
    border-radius: var(--radius-xs);
    font-size: 12px;
    font-weight: 500;
    cursor: pointer;
    transition: background 120ms ease, opacity 120ms ease;
  }

  .wh-btn:disabled {
    opacity: 0.5;
    cursor: default;
  }

  .wh-btn--secondary {
    background: var(--bg-surface);
    color: var(--text-secondary);
    border: 1px solid var(--border-default);
  }

  .wh-btn--secondary:hover:not(:disabled) {
    background: var(--bg-elevated);
    color: var(--text-primary);
  }

  .wh-btn--primary {
    background: var(--accent-primary, #f26522);
    color: #fff;
  }

  .wh-btn--primary:hover:not(:disabled) {
    opacity: 0.9;
  }

  .wh-btn-icon {
    flex-shrink: 0;
  }

  .wh-spin {
    animation: wh-spin-anim 800ms linear infinite;
  }

  @keyframes wh-spin-anim {
    from { transform: rotate(0deg); }
    to { transform: rotate(360deg); }
  }

  .wh-empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 10px;
    padding: 20px;
    color: var(--text-tertiary);
    font-size: 13px;
  }

  .wh-empty-text {
    color: var(--text-muted);
  }

  .wh-status {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 10px 12px;
    border-radius: var(--radius-sm);
    border: 1px solid var(--border-default);
  }

  .wh-status--ok {
    background: rgba(34, 197, 94, 0.08);
    border-color: rgba(34, 197, 94, 0.25);
    color: #22c55e;
  }

  .wh-status--warn {
    background: rgba(234, 179, 8, 0.08);
    border-color: rgba(234, 179, 8, 0.25);
    color: #eab308;
  }

  .wh-status--error {
    background: rgba(239, 68, 68, 0.08);
    border-color: rgba(239, 68, 68, 0.25);
    color: #ef4444;
  }

  .wh-status-text {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .wh-status-label {
    font-size: 13px;
    font-weight: 600;
    color: var(--text-primary);
  }

  .wh-status-detail {
    font-size: 11px;
    color: var(--text-tertiary);
  }

  .wh-issues {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .wh-issue {
    display: flex;
    align-items: flex-start;
    gap: 8px;
    padding: 8px 10px;
    border-radius: var(--radius-xs);
    background: var(--bg-surface);
    border: 1px solid transparent;
  }

  .wh-issue--error {
    border-color: rgba(239, 68, 68, 0.2);
  }

  .wh-issue--error .wh-issue-icon {
    color: #ef4444;
  }

  .wh-issue--warning {
    border-color: rgba(234, 179, 8, 0.2);
  }

  .wh-issue--warning .wh-issue-icon {
    color: #eab308;
  }

  .wh-issue--info .wh-issue-icon {
    color: var(--text-muted);
  }

  .wh-issue-icon {
    flex-shrink: 0;
    margin-top: 1px;
  }

  .wh-issue-content {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .wh-issue-message {
    font-size: 12px;
    color: var(--text-primary);
  }

  .wh-issue-path {
    font-size: 11px;
    color: var(--text-muted);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-family: var(--font-mono, monospace);
  }

  .wh-issue-badge {
    flex-shrink: 0;
    padding: 1px 6px;
    border-radius: 9999px;
    font-size: 10px;
    font-weight: 500;
    background: rgba(34, 197, 94, 0.12);
    color: #22c55e;
    border: 1px solid rgba(34, 197, 94, 0.25);
    white-space: nowrap;
    margin-top: 1px;
  }

  .wh-repair-summary {
    border-top: 1px solid var(--border-default);
    padding-top: 10px;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .wh-repair-header {
    font-size: 12px;
    font-weight: 600;
    color: var(--text-secondary);
  }

  .wh-repair-section {
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .wh-repair-item {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 12px;
    padding: 3px 0;
  }

  .wh-repair-section--ok .wh-repair-item {
    color: #22c55e;
  }

  .wh-repair-section--fail .wh-repair-item {
    color: #ef4444;
  }

  .wh-summary {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
</style>
