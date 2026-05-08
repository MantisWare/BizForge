<!-- src/routes/app/reports/+page.svelte -->
<script lang="ts">
  import PageShell from '$lib/components/layout/PageShell.svelte';
  import { reportsStore } from '$lib/stores/reports.svelte';
  import type { Report, ReportType, ReportCreateRequest } from '$api/types';

  type TypeFilter = 'all' | ReportType;

  const TYPE_TABS: { value: TypeFilter; label: string }[] = [
    { value: 'all', label: 'All' },
    { value: 'agent_performance', label: 'Performance' },
    { value: 'cost_analysis', label: 'Costs' },
    { value: 'task_summary', label: 'Tasks' },
    { value: 'workflow_audit', label: 'Workflows' },
    { value: 'custom', label: 'Custom' },
  ];

  const TYPE_LABELS: Record<string, string> = {
    agent_performance: 'Agent Performance',
    cost_analysis: 'Cost Analysis',
    task_summary: 'Task Summary',
    workflow_audit: 'Workflow Audit',
    custom: 'Custom',
  };

  const FORMAT_LABELS: Record<string, string> = {
    table: 'Table',
    chart: 'Chart',
    pdf: 'PDF',
    csv: 'CSV',
  };

  // ── Local state ────────────────────────────────────────────────────────────
  let typeFilter = $state<TypeFilter>('all');
  let showNewForm = $state(false);
  let confirmDeleteId = $state<string | null>(null);
  let generatingId = $state<string | null>(null);
  let exportingAll = $state(false);

  // Per-report sort state keyed by report ID
  let sortState = $state<Map<string, { col: number | null; asc: boolean }>>(new Map());

  // New report form state
  let form = $state<Partial<ReportCreateRequest>>({
    name: '',
    description: '',
    report_type: 'agent_performance',
    format: 'table',
    schedule: '',
    config: {},
  });
  let formErrors = $state<Record<string, string>>({});
  let formSubmitting = $state(false);

  // Config builder state
  let configDateRange = $state('30d');
  let configMetrics = $state<Record<string, boolean>>({
    success_rate: true,
    task_count: true,
    avg_duration: false,
    cost: true,
  });

  // ── Derived ────────────────────────────────────────────────────────────────
  let visibleReports = $derived(
    typeFilter === 'all'
      ? reportsStore.reports
      : (reportsStore.byType[typeFilter] ?? []),
  );

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  $effect(() => {
    void reportsStore.fetchReports();
  });

  // ── Helpers ────────────────────────────────────────────────────────────────
  function formatDate(iso: string | null): string {
    if (iso === null) return '—';
    return new Date(iso).toLocaleString('en-US', {
      month: 'short',
      day: 'numeric',
      hour: 'numeric',
      minute: '2-digit',
    });
  }

  function humanCron(cron: string | null): string {
    if (cron === null) return 'One-time';
    const parts = cron.split(' ');
    if (parts.length !== 5) return cron;
    const [min, hour, dom, month, dow] = parts;
    if (dom === '*' && month === '*' && dow === '*') {
      if (hour === '*' && min === '*') return 'Every minute';
      if (hour === '*') return `Every hour at :${min.padStart(2, '0')}`;
      if (dow === '*' && dom === '*' && month === '*')
        return `Daily at ${hour}:${min.padStart(2, '0')}`;
    }
    if (dom === '*' && month === '*' && dow === '1')
      return `Weekly (Mon ${hour}:${min.padStart(2, '0')})`;
    if (dom === '1' && month === '*')
      return `Monthly (1st ${hour}:${min.padStart(2, '0')})`;
    return cron;
  }

  function statusClass(status: string): string {
    if (status === 'generating') return 'rp-status--generating';
    if (status === 'archived') return 'rp-status--archived';
    return 'rp-status--active';
  }

  function getSortState(reportId: string): { col: number | null; asc: boolean } {
    return sortState.get(reportId) ?? { col: null, asc: true };
  }

  function sortedRows(
    rows: (string | number)[][],
    col: number | null,
    asc: boolean,
  ): (string | number)[][] {
    if (col === null) return rows;
    return [...rows].sort((a, b) => {
      const va = a[col];
      const vb = b[col];
      if (typeof va === 'number' && typeof vb === 'number') {
        return asc ? va - vb : vb - va;
      }
      return asc
        ? String(va).localeCompare(String(vb))
        : String(vb).localeCompare(String(va));
    });
  }

  function toggleSort(reportId: string, colIdx: number): void {
    const current = getSortState(reportId);
    const next = new Map(sortState);
    if (current.col === colIdx) {
      next.set(reportId, { col: colIdx, asc: !current.asc });
    } else {
      next.set(reportId, { col: colIdx, asc: true });
    }
    sortState = next;
  }

  // ── Chart helpers ──────────────────────────────────────────────────────────
  function barWidths(
    data: { label: string; value: number; secondary?: number }[],
    maxPct = 90,
  ): { primary: number; secondary: number | null }[] {
    const maxVal = Math.max(...data.map((d) => Math.max(d.value, d.secondary ?? 0)), 1);
    return data.map((d) => ({
      primary: Math.max(2, Math.round((d.value / maxVal) * maxPct)),
      secondary: d.secondary !== undefined && d.secondary !== null
        ? Math.max(2, Math.round((d.secondary / maxVal) * maxPct))
        : null,
    }));
  }

  // ── Form actions ───────────────────────────────────────────────────────────
  function validateForm(): boolean {
    const errs: Record<string, string> = {};
    if (!form.name?.trim()) errs.name = 'Name is required';
    if (!form.report_type) errs.report_type = 'Type is required';
    formErrors = errs;
    return Object.keys(errs).length === 0;
  }

  async function submitNewReport(): Promise<void> {
    if (!validateForm()) return;
    formSubmitting = true;

    const enabledMetrics = Object.entries(configMetrics)
      .filter(([, v]) => v)
      .map(([k]) => k);

    const created = await reportsStore.createReport({
      name: form.name!,
      description: form.description ?? undefined,
      report_type: form.report_type!,
      format: form.format ?? 'table',
      schedule: form.schedule?.trim() || undefined,
      config: {
        date_range: configDateRange,
        metrics: enabledMetrics,
      },
      tags: [],
    });

    formSubmitting = false;
    if (created !== null) {
      showNewForm = false;
      resetForm();
    }
  }

  function resetForm(): void {
    form = {
      name: '',
      description: '',
      report_type: 'agent_performance',
      format: 'table',
      schedule: '',
      config: {},
    };
    configDateRange = '30d';
    configMetrics = { success_rate: true, task_count: true, avg_duration: false, cost: true };
    formErrors = {};
  }

  async function handleGenerate(report: Report): Promise<void> {
    generatingId = report.id;
    await reportsStore.generateReport(report.id);
    generatingId = null;
  }

  async function handleDelete(id: string): Promise<void> {
    await reportsStore.deleteReport(id);
    confirmDeleteId = null;
  }

  async function handleExportAll(format: string): Promise<void> {
    exportingAll = true;
    for (const report of visibleReports) {
      await reportsStore.exportReport(report.id, format);
    }
    exportingAll = false;
  }
</script>

<PageShell title="Reports" subtitle="Observe">
  {#snippet actions()}
    <div class="rp-header-actions">
      <!-- Export All dropdown -->
      <div class="rp-export-wrap">
        <button
          class="rp-btn-ghost"
          popovertarget="rp-export-all-pop"
          disabled={exportingAll || visibleReports.length === 0}
          aria-busy={exportingAll}
        >
          {exportingAll ? 'Exporting…' : 'Export All'}
          <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path d="M19 9l-7 7-7-7" />
          </svg>
        </button>
        <div
          id="rp-export-all-pop"
          popover="auto"
          class="rp-export-popover"
        >
          <button class="rp-export-item" onclick={() => void handleExportAll('csv')}>CSV</button>
          <button class="rp-export-item" onclick={() => void handleExportAll('pdf')}>PDF</button>
          <button class="rp-export-item" onclick={() => void handleExportAll('json')}>JSON</button>
        </div>
      </div>

      <button
        class="rp-new-btn"
        onclick={() => { showNewForm = !showNewForm; }}
        aria-expanded={showNewForm}
      >
        {showNewForm ? 'Cancel' : '+ New Report'}
      </button>
    </div>
  {/snippet}

  <div class="rp-page">
    <!-- ── Category filter pills ──────────────────────────────────────── -->
    <div class="rp-filters" role="tablist" aria-label="Filter by type">
      {#each TYPE_TABS as tab (tab.value)}
        <button
          role="tab"
          class="rp-pill"
          class:rp-pill--active={typeFilter === tab.value}
          onclick={() => { typeFilter = tab.value; }}
          aria-selected={typeFilter === tab.value}
        >
          {tab.label}
        </button>
      {/each}
    </div>

    <!-- ── New report inline form ─────────────────────────────────────── -->
    {#if showNewForm}
      <form
        class="rp-new-form"
        onsubmit={(e) => { e.preventDefault(); void submitNewReport(); }}
        aria-label="New report form"
        novalidate
      >
        <h3 class="rp-form-title">New Report</h3>

        <div class="rp-form-grid">
          <label class="rp-field">
            <span class="rp-label">Name <span class="rp-required" aria-hidden="true">*</span></span>
            <input
              class="rp-input"
              class:rp-input--err={formErrors.name}
              type="text"
              placeholder="Report name"
              bind:value={form.name}
              maxlength={200}
              aria-required="true"
              aria-invalid={!!formErrors.name}
              aria-describedby={formErrors.name ? 'err-name' : undefined}
            />
            {#if formErrors.name}
              <span id="err-name" class="rp-err-msg" role="alert">{formErrors.name}</span>
            {/if}
          </label>

          <label class="rp-field">
            <span class="rp-label">Type <span class="rp-required" aria-hidden="true">*</span></span>
            <select class="rp-select" bind:value={form.report_type} aria-required="true">
              {#each TYPE_TABS.slice(1) as t (t.value)}
                <option value={t.value}>{t.label}</option>
              {/each}
            </select>
          </label>

          <label class="rp-field">
            <span class="rp-label">Format</span>
            <select class="rp-select" bind:value={form.format}>
              {#each Object.entries(FORMAT_LABELS) as [val, label] (val)}
                <option value={val}>{label}</option>
              {/each}
            </select>
          </label>

          <label class="rp-field">
            <span class="rp-label">Schedule (cron, optional)</span>
            <input
              class="rp-input"
              type="text"
              placeholder="e.g. 0 6 * * 1 (weekly Mon)"
              bind:value={form.schedule}
            />
          </label>
        </div>

        <label class="rp-field">
          <span class="rp-label">Description</span>
          <textarea
            class="rp-input rp-textarea"
            placeholder="Optional description"
            bind:value={form.description}
            rows={2}
          ></textarea>
        </label>

        <div class="rp-config-row">
          <div class="rp-config-section">
            <span class="rp-label">Date Range</span>
            <div class="rp-radio-group" role="group" aria-label="Date range">
              {#each [['7d', '7 days'], ['30d', '30 days'], ['90d', '90 days']] as [val, lbl] (val)}
                <label class="rp-radio-label">
                  <input type="radio" name="date-range" value={val} bind:group={configDateRange} />
                  {lbl}
                </label>
              {/each}
            </div>
          </div>

          <div class="rp-config-section">
            <span class="rp-label">Metrics</span>
            <div class="rp-checkbox-grid" role="group" aria-label="Metrics to include">
              {#each Object.keys(configMetrics) as metric (metric)}
                <label class="rp-checkbox-label">
                  <input type="checkbox" bind:checked={configMetrics[metric]} />
                  {metric.replace(/_/g, ' ')}
                </label>
              {/each}
            </div>
          </div>
        </div>

        <div class="rp-form-actions">
          <button
            type="button"
            class="rp-btn-ghost"
            onclick={() => { showNewForm = false; resetForm(); }}
          >
            Cancel
          </button>
          <button
            type="submit"
            class="rp-btn-primary"
            disabled={formSubmitting}
            aria-busy={formSubmitting}
          >
            {formSubmitting ? 'Creating…' : 'Create Report'}
          </button>
        </div>
      </form>
    {/if}

    <!-- ── Loading / Error / Empty ────────────────────────────────────── -->
    {#if reportsStore.loading}
      <div class="rp-state-msg" aria-live="polite" aria-busy="true">
        <div class="rp-spinner" aria-hidden="true"></div>
        <span>Loading reports…</span>
      </div>
    {:else if reportsStore.error}
      <div class="rp-state-msg rp-state-msg--error" role="alert">
        <p>{reportsStore.error}</p>
        <button class="rp-btn-ghost" onclick={() => void reportsStore.fetchReports()}>Retry</button>
      </div>
    {:else if visibleReports.length === 0}
      <div class="rp-state-msg">
        <p>No reports{typeFilter !== 'all' ? ' for this type' : ''}.</p>
        <button class="rp-btn-ghost" onclick={() => { showNewForm = true; }}>
          Create your first report
        </button>
      </div>

    <!-- ── Stacked report cards ───────────────────────────────────────── -->
    {:else}
      <div class="rp-cards">
        {#each visibleReports as report (report.id)}
          {@const sort = getSortState(report.id)}
          <article class="rp-card" aria-label="Report: {report.name}">
            <!-- Card header -->
            <header class="rp-card-header">
              <div class="rp-card-title-row">
                <div class="rp-card-title-group">
                  <h2 class="rp-card-title">{report.name}</h2>
                  <div class="rp-card-badges">
                    <span class="rp-type-badge rp-type-badge--{report.report_type}">
                      {TYPE_LABELS[report.report_type] ?? report.report_type}
                    </span>
                    <span class="rp-status {statusClass(report.status)}">
                      {report.status}
                    </span>
                    <span class="rp-format-badge">{FORMAT_LABELS[report.format] ?? report.format}</span>
                  </div>
                </div>

                <div class="rp-card-actions" role="group" aria-label="Report actions">
                  <button
                    class="rp-btn-generate"
                    onclick={() => void handleGenerate(report)}
                    disabled={generatingId === report.id}
                    aria-busy={generatingId === report.id}
                  >
                    {#if generatingId === report.id}
                      <div class="rp-spinner rp-spinner--sm" aria-hidden="true"></div>
                      Generating…
                    {:else}
                      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                        <path d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                      </svg>
                      Generate
                    {/if}
                  </button>

                  <div class="rp-export-wrap">
                    <button class="rp-btn-ghost" popovertarget="rp-export-pop-{report.id}">
                      Export
                      <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                        <path d="M19 9l-7 7-7-7" />
                      </svg>
                    </button>
                    <div
                      id="rp-export-pop-{report.id}"
                      popover="auto"
                      class="rp-export-popover"
                    >
                      <button class="rp-export-item" onclick={() => void reportsStore.exportReport(report.id, 'csv')}>CSV</button>
                      <button class="rp-export-item" onclick={() => void reportsStore.exportReport(report.id, 'pdf')}>PDF</button>
                      <button class="rp-export-item" onclick={() => void reportsStore.exportReport(report.id, 'json')}>JSON</button>
                    </div>
                  </div>

                  {#if confirmDeleteId === report.id}
                    <div class="rp-confirm-delete" role="dialog" aria-label="Confirm delete">
                      <span>Delete?</span>
                      <button class="rp-btn-danger" onclick={() => void handleDelete(report.id)}>Delete</button>
                      <button class="rp-btn-ghost" onclick={() => { confirmDeleteId = null; }}>Cancel</button>
                    </div>
                  {:else}
                    <button
                      class="rp-btn-icon"
                      onclick={() => { confirmDeleteId = report.id; }}
                      aria-label="Delete report"
                      title="Delete report"
                    >
                      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                        <path d="M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 00-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 013.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 00-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 00-7.5 0" />
                      </svg>
                    </button>
                  {/if}
                </div>
              </div>

              {#if report.description}
                <p class="rp-card-desc">{report.description}</p>
              {/if}

              <div class="rp-card-meta-row">
                <span class="rp-meta-item">
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                    <path d="M12 6v6h4.5m4.5 0a9 9 0 11-18 0 9 9 0 0118 0z" />
                  </svg>
                  {humanCron(report.schedule)}
                </span>
                {#if report.last_generated_at !== null}
                  <span class="rp-meta-item">
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                      <path d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                    Last generated: {formatDate(report.last_generated_at)}
                  </span>
                {:else}
                  <span class="rp-meta-item rp-meta-item--dim">Never generated</span>
                {/if}
                {#if report.tags.length > 0}
                  <span class="rp-meta-item">
                    {#each report.tags as tag (tag)}
                      <span class="rp-tag">{tag}</span>
                    {/each}
                  </span>
                {/if}
              </div>
            </header>

            <!-- Card body: results -->
            {#if report.cached_result === null}
              <div class="rp-no-result">
                <p>No results yet. Click <strong>Generate</strong> to run this report.</p>
              </div>
            {:else}
              {@const result = report.cached_result}

              <!-- Summary stats -->
              {#if result.summary !== undefined && Object.keys(result.summary).length > 0}
                <div class="rp-summary-row" aria-label="Report summary">
                  {#each Object.entries(result.summary).filter(([k]) => k !== 'generated_at') as [key, val] (key)}
                    <div class="rp-summary-card">
                      <span class="rp-summary-label">{key.replace(/_/g, ' ')}</span>
                      <span class="rp-summary-value">
                        {#if typeof val === 'number'}
                          {val < 1 && val > 0
                            ? (val * 100).toFixed(1) + '%'
                            : typeof val === 'number' && val > 1000
                              ? val.toLocaleString()
                              : val}
                        {:else}
                          {String(val)}
                        {/if}
                      </span>
                    </div>
                  {/each}
                </div>
              {/if}

              <!-- Table format -->
              {#if report.format === 'table' || report.format === 'pdf' || report.format === 'csv'}
                {#if result.columns !== undefined && result.rows !== undefined}
                  <div class="rp-table-wrap">
                    <table class="rp-table" aria-label="Report data">
                      <thead>
                        <tr>
                          {#each result.columns as col, idx (col)}
                            <th
                              class="rp-th"
                              class:rp-th--sorted={sort.col === idx}
                              scope="col"
                              aria-sort={sort.col === idx ? (sort.asc ? 'ascending' : 'descending') : 'none'}
                            >
                              <button
                                class="rp-th-btn"
                                onclick={() => toggleSort(report.id, idx)}
                                aria-label="Sort by {col}"
                              >
                                {col}
                                {#if sort.col === idx}
                                  <span class="rp-sort-icon" aria-hidden="true">
                                    {sort.asc ? '↑' : '↓'}
                                  </span>
                                {:else}
                                  <span class="rp-sort-icon rp-sort-icon--idle" aria-hidden="true">↕</span>
                                {/if}
                              </button>
                            </th>
                          {/each}
                        </tr>
                      </thead>
                      <tbody>
                        {#each sortedRows(result.rows, sort.col, sort.asc) as row, rowIdx (rowIdx)}
                          <tr class="rp-tr">
                            {#each row as cell, cellIdx (cellIdx)}
                              <td class="rp-td">{cell}</td>
                            {/each}
                          </tr>
                        {/each}
                      </tbody>
                    </table>
                  </div>
                {:else}
                  <p class="rp-no-data">No data available in this report.</p>
                {/if}

              <!-- Chart format -->
              {:else if report.format === 'chart'}
                {#if result.chart_data !== undefined && result.chart_data.length > 0}
                  {@const widths = barWidths(result.chart_data)}
                  <div class="rp-chart" role="img" aria-label="Bar chart of report data">
                    {#each result.chart_data as point, i (point.label)}
                      <div class="rp-chart-row">
                        <span class="rp-chart-label" title={point.label}>{point.label}</span>
                        <div class="rp-chart-bars">
                          <div
                            class="rp-chart-bar rp-chart-bar--primary"
                            style="width: {widths[i].primary}%"
                            title="{point.label}: {point.value}"
                            aria-label="{point.label} primary value {point.value}"
                          >
                            <span class="rp-chart-bar-val">{point.value}</span>
                          </div>
                          {#if widths[i].secondary !== null}
                            <div
                              class="rp-chart-bar rp-chart-bar--secondary"
                              style="width: {widths[i].secondary}%"
                              title="{point.label} (prior): {point.secondary}"
                              aria-label="{point.label} prior value {point.secondary}"
                            >
                              <span class="rp-chart-bar-val">{point.secondary}</span>
                            </div>
                          {/if}
                        </div>
                      </div>
                    {/each}
                  </div>
                  {#if result.chart_data[0].secondary !== undefined && result.chart_data[0].secondary !== null}
                    <div class="rp-chart-legend" aria-label="Chart legend">
                      <span class="rp-legend-item">
                        <span class="rp-legend-dot rp-legend-dot--primary" aria-hidden="true"></span>
                        Current period
                      </span>
                      <span class="rp-legend-item">
                        <span class="rp-legend-dot rp-legend-dot--secondary" aria-hidden="true"></span>
                        Prior period
                      </span>
                    </div>
                  {/if}
                {:else}
                  {#if result.columns !== undefined && result.rows !== undefined}
                    <div class="rp-table-wrap">
                      <table class="rp-table" aria-label="Report data">
                        <thead>
                          <tr>
                            {#each result.columns as col (col)}
                              <th class="rp-th" scope="col">{col}</th>
                            {/each}
                          </tr>
                        </thead>
                        <tbody>
                          {#each result.rows as row, rowIdx (rowIdx)}
                            <tr class="rp-tr">
                              {#each row as cell, cellIdx (cellIdx)}
                                <td class="rp-td">{cell}</td>
                              {/each}
                            </tr>
                          {/each}
                        </tbody>
                      </table>
                    </div>
                  {/if}
                {/if}
              {/if}
            {/if}
          </article>
        {/each}
      </div>
    {/if}
  </div>
</PageShell>

<style>
  /* ── Page container ────────────────────────────────────────────────── */
  .rp-page {
    display: flex;
    flex-direction: column;
    gap: 16px;
    flex: 1;
    overflow-y: auto;
    padding-bottom: 24px;
  }

  /* ── Header actions row ────────────────────────────────────────────── */
  .rp-header-actions {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  /* ── Category filter pills ─────────────────────────────────────────── */
  .rp-filters {
    display: flex;
    gap: 6px;
    flex-wrap: wrap;
    flex-shrink: 0;
  }

  .rp-pill {
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    border-radius: 9999px;
    color: var(--text-tertiary);
    font-family: var(--font-sans);
    font-size: 12px;
    font-weight: 500;
    padding: 5px 14px;
    cursor: pointer;
    white-space: nowrap;
    transition: background 120ms ease, color 120ms ease, border-color 120ms ease;
  }

  .rp-pill:hover {
    color: var(--text-secondary);
    background: var(--bg-surface);
  }

  .rp-pill--active {
    background: var(--accent-primary, #58a6ff);
    border-color: var(--accent-primary, #58a6ff);
    color: #fff;
  }

  .rp-pill--active:hover {
    background: var(--accent-primary, #58a6ff);
    color: #fff;
    opacity: 0.9;
  }

  /* ── State messages (loading / error / empty) ──────────────────────── */
  .rp-state-msg {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 10px;
    padding: 48px 16px;
    text-align: center;
    color: var(--text-tertiary);
    font-size: 13px;
  }

  .rp-state-msg p {
    margin: 0;
  }

  .rp-state-msg--error p {
    color: var(--text-secondary);
  }

  /* ── Report cards container ────────────────────────────────────────── */
  .rp-cards {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  /* ── Individual report card ────────────────────────────────────────── */
  .rp-card {
    border: 1px solid var(--border-default);
    border-radius: var(--radius-sm);
    background: var(--bg-elevated);
    overflow: hidden;
  }

  .rp-card-header {
    padding: 14px 18px 10px;
    border-bottom: 1px solid var(--border-subtle, var(--border-default));
  }

  .rp-card-title-row {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 16px;
    margin-bottom: 6px;
  }

  .rp-card-title-group {
    display: flex;
    flex-direction: column;
    gap: 5px;
    min-width: 0;
  }

  .rp-card-title {
    font-size: 14px;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .rp-card-badges {
    display: flex;
    align-items: center;
    gap: 6px;
    flex-wrap: wrap;
  }

  .rp-card-desc {
    font-size: 12px;
    color: var(--text-tertiary);
    margin: 0 0 8px;
    line-height: 1.5;
  }

  .rp-card-meta-row {
    display: flex;
    align-items: center;
    gap: 16px;
    flex-wrap: wrap;
  }

  .rp-card-actions {
    display: flex;
    align-items: center;
    gap: 6px;
    flex-shrink: 0;
    flex-wrap: wrap;
  }

  /* ── Type badges ───────────────────────────────────────────────────── */
  .rp-type-badge {
    display: inline-block;
    font-size: 9px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    padding: 2px 6px;
    border-radius: 9999px;
    white-space: nowrap;
    flex-shrink: 0;
  }

  .rp-type-badge--agent_performance {
    background: rgba(88, 166, 255, 0.12);
    color: #58a6ff;
  }
  .rp-type-badge--cost_analysis {
    background: rgba(227, 179, 65, 0.12);
    color: #e3b341;
  }
  .rp-type-badge--task_summary {
    background: rgba(63, 185, 80, 0.12);
    color: #3fb950;
  }
  .rp-type-badge--workflow_audit {
    background: rgba(251, 146, 60, 0.12);
    color: #fb923c;
  }
  .rp-type-badge--custom {
    background: rgba(139, 148, 158, 0.12);
    color: #8b949e;
  }

  /* ── Status badges ─────────────────────────────────────────────────── */
  .rp-status {
    display: inline-block;
    font-size: 10px;
    font-weight: 500;
    padding: 1px 7px;
    border-radius: 9999px;
  }

  .rp-status--active {
    background: rgba(63, 185, 80, 0.1);
    color: #3fb950;
  }

  .rp-status--generating {
    background: rgba(88, 166, 255, 0.1);
    color: #58a6ff;
  }

  .rp-status--archived {
    background: rgba(139, 148, 158, 0.1);
    color: #8b949e;
  }

  .rp-format-badge {
    display: inline-block;
    font-size: 10px;
    font-weight: 500;
    padding: 1px 7px;
    border-radius: 9999px;
    background: var(--bg-surface);
    color: var(--text-tertiary);
    border: 1px solid var(--border-default);
  }

  /* ── Meta items ────────────────────────────────────────────────────── */
  .rp-meta-item {
    display: flex;
    align-items: center;
    gap: 5px;
    font-size: 11px;
    color: var(--text-tertiary);
  }

  .rp-meta-item--dim {
    color: var(--text-quaternary, var(--text-tertiary));
    font-style: italic;
  }

  .rp-tag {
    display: inline-block;
    font-size: 10px;
    padding: 1px 6px;
    border-radius: 9999px;
    background: var(--bg-surface);
    border: 1px solid var(--border-default);
    color: var(--text-tertiary);
    margin-right: 3px;
  }

  /* ── New report form ───────────────────────────────────────────────── */
  .rp-new-form {
    border: 1px solid var(--border-default);
    border-radius: var(--radius-sm);
    padding: 16px 18px;
    display: flex;
    flex-direction: column;
    gap: 12px;
    background: var(--bg-elevated);
    flex-shrink: 0;
  }

  .rp-form-title {
    font-size: 12px;
    font-weight: 600;
    color: var(--text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.04em;
    margin: 0;
  }

  .rp-form-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 10px;
  }

  @media (max-width: 640px) {
    .rp-form-grid {
      grid-template-columns: 1fr;
    }
  }

  .rp-field {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .rp-label {
    font-size: 11px;
    font-weight: 500;
    color: var(--text-tertiary);
  }

  .rp-required {
    color: var(--accent-danger, #f85149);
  }

  .rp-input {
    background: var(--bg-surface);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-xs);
    color: var(--text-primary);
    font-family: var(--font-sans);
    font-size: 12px;
    padding: 5px 8px;
    width: 100%;
    box-sizing: border-box;
    transition: border-color 120ms ease;
  }

  .rp-input:focus {
    outline: none;
    border-color: var(--accent-primary, #58a6ff);
  }

  .rp-input--err {
    border-color: var(--accent-danger, #f85149);
  }

  .rp-textarea {
    resize: vertical;
    min-height: 48px;
  }

  .rp-select {
    background: var(--bg-surface);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-xs);
    color: var(--text-primary);
    font-family: var(--font-sans);
    font-size: 12px;
    padding: 5px 8px;
    width: 100%;
    cursor: pointer;
  }

  .rp-err-msg {
    font-size: 10px;
    color: var(--accent-danger, #f85149);
  }

  .rp-config-row {
    display: flex;
    gap: 24px;
    flex-wrap: wrap;
  }

  .rp-config-section {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .rp-radio-group {
    display: flex;
    gap: 10px;
    flex-wrap: wrap;
  }

  .rp-radio-label,
  .rp-checkbox-label {
    display: flex;
    align-items: center;
    gap: 5px;
    font-size: 11px;
    color: var(--text-secondary);
    cursor: pointer;
  }

  .rp-checkbox-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 4px;
  }

  .rp-form-actions {
    display: flex;
    gap: 8px;
    justify-content: flex-end;
    margin-top: 2px;
  }

  /* ── New report button ─────────────────────────────────────────────── */
  .rp-new-btn {
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-xs);
    color: var(--text-primary);
    font-family: var(--font-sans);
    font-size: 12px;
    font-weight: 500;
    padding: 5px 12px;
    cursor: pointer;
    transition: background 120ms ease;
    white-space: nowrap;
  }

  .rp-new-btn:hover {
    background: var(--bg-surface);
  }

  /* ── Buttons ───────────────────────────────────────────────────────── */
  .rp-btn-generate {
    display: flex;
    align-items: center;
    gap: 5px;
    background: var(--accent-primary, #58a6ff);
    color: #fff;
    border: none;
    border-radius: var(--radius-xs);
    font-family: var(--font-sans);
    font-size: 12px;
    font-weight: 500;
    padding: 5px 12px;
    cursor: pointer;
    transition: opacity 120ms ease;
  }

  .rp-btn-generate:hover:not(:disabled) {
    opacity: 0.85;
  }

  .rp-btn-generate:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .rp-btn-ghost {
    display: flex;
    align-items: center;
    gap: 4px;
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-xs);
    color: var(--text-secondary);
    font-family: var(--font-sans);
    font-size: 12px;
    font-weight: 500;
    padding: 5px 10px;
    cursor: pointer;
    transition: background 120ms ease;
  }

  .rp-btn-ghost:hover {
    background: var(--bg-surface);
    color: var(--text-primary);
  }

  .rp-btn-ghost:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .rp-btn-icon {
    background: none;
    border: 1px solid var(--border-default);
    border-radius: var(--radius-xs);
    color: var(--text-tertiary);
    padding: 5px;
    cursor: pointer;
    display: flex;
    align-items: center;
    transition: color 120ms ease, border-color 120ms ease;
  }

  .rp-btn-icon:hover {
    color: var(--accent-danger, #f85149);
    border-color: var(--accent-danger, #f85149);
  }

  .rp-btn-primary {
    background: var(--accent-primary, #58a6ff);
    color: #fff;
    border: none;
    border-radius: var(--radius-xs);
    font-family: var(--font-sans);
    font-size: 12px;
    font-weight: 500;
    padding: 5px 12px;
    cursor: pointer;
    transition: opacity 120ms ease;
  }

  .rp-btn-primary:hover:not(:disabled) {
    opacity: 0.85;
  }

  .rp-btn-primary:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .rp-btn-danger {
    background: rgba(248, 81, 73, 0.12);
    color: #f85149;
    border: 1px solid rgba(248, 81, 73, 0.3);
    border-radius: var(--radius-xs);
    font-family: var(--font-sans);
    font-size: 12px;
    font-weight: 500;
    padding: 4px 10px;
    cursor: pointer;
    transition: background 120ms ease;
  }

  .rp-btn-danger:hover {
    background: rgba(248, 81, 73, 0.2);
  }

  /* ── Export popover ─────────────────────────────────────────────────── */
  .rp-export-wrap {
    position: relative;
  }

  .rp-export-popover {
    position: absolute;
    top: calc(100% + 4px);
    right: 0;
    background: var(--bg-surface);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-xs);
    padding: 4px 0;
    min-width: 100px;
    z-index: 50;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
  }

  .rp-export-item {
    display: block;
    width: 100%;
    background: none;
    border: none;
    padding: 6px 12px;
    text-align: left;
    font-family: var(--font-sans);
    font-size: 12px;
    color: var(--text-primary);
    cursor: pointer;
    transition: background 80ms ease;
  }

  .rp-export-item:hover {
    background: var(--bg-elevated);
  }

  /* ── Confirm delete ────────────────────────────────────────────────── */
  .rp-confirm-delete {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 12px;
    color: var(--text-secondary);
    padding: 4px 8px;
    border: 1px solid var(--border-default);
    border-radius: var(--radius-xs);
    background: var(--bg-surface);
  }

  /* ── Results ───────────────────────────────────────────────────────── */
  .rp-no-result {
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 24px 18px;
    color: var(--text-tertiary);
    font-size: 12px;
    text-align: center;
  }

  .rp-no-result p {
    margin: 0;
  }

  .rp-no-data {
    padding: 16px 18px;
    color: var(--text-tertiary);
    font-size: 12px;
    margin: 0;
  }

  /* Summary stats row */
  .rp-summary-row {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(130px, 1fr));
    gap: 8px;
    padding: 12px 18px;
    border-bottom: 1px solid var(--border-subtle, var(--border-default));
  }

  .rp-summary-card {
    background: var(--bg-surface);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-xs);
    padding: 8px 10px;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .rp-summary-label {
    font-size: 10px;
    font-weight: 500;
    color: var(--text-tertiary);
    text-transform: uppercase;
    letter-spacing: 0.04em;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .rp-summary-value {
    font-size: 15px;
    font-weight: 600;
    color: var(--text-primary);
    font-variant-numeric: tabular-nums;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  /* ── Table ─────────────────────────────────────────────────────────── */
  .rp-table-wrap {
    overflow-x: auto;
  }

  .rp-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 12px;
  }

  .rp-th {
    padding: 0;
    background: var(--bg-surface);
    color: var(--text-tertiary);
    font-weight: 500;
    text-align: left;
    border-bottom: 1px solid var(--border-default);
    position: sticky;
    top: 0;
    white-space: nowrap;
  }

  .rp-th--sorted {
    color: var(--text-primary);
  }

  .rp-th-btn {
    display: flex;
    align-items: center;
    gap: 4px;
    background: none;
    border: none;
    padding: 8px 14px;
    font-family: var(--font-sans);
    font-size: 12px;
    font-weight: 500;
    color: inherit;
    cursor: pointer;
    width: 100%;
    text-align: left;
  }

  .rp-th-btn:hover {
    color: var(--text-primary);
  }

  .rp-sort-icon {
    font-size: 10px;
    opacity: 0.8;
  }

  .rp-sort-icon--idle {
    opacity: 0.3;
  }

  .rp-tr:not(:last-child) {
    border-bottom: 1px solid var(--border-subtle, var(--border-default));
  }

  .rp-tr:hover {
    background: rgba(255, 255, 255, 0.03);
  }

  .rp-td {
    padding: 8px 14px;
    color: var(--text-primary);
    font-variant-numeric: tabular-nums;
  }

  /* ── Chart ─────────────────────────────────────────────────────────── */
  .rp-chart {
    padding: 16px 18px;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .rp-chart-row {
    display: flex;
    align-items: flex-start;
    gap: 12px;
  }

  .rp-chart-label {
    width: 140px;
    min-width: 140px;
    font-size: 12px;
    color: var(--text-secondary);
    padding-top: 4px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .rp-chart-bars {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .rp-chart-bar {
    height: 22px;
    border-radius: 3px;
    display: flex;
    align-items: center;
    overflow: hidden;
    transition: width 400ms ease;
    min-width: 2px;
  }

  .rp-chart-bar--primary {
    background: var(--accent-primary, #58a6ff);
    opacity: 0.8;
  }

  .rp-chart-bar--secondary {
    background: var(--text-tertiary);
    opacity: 0.35;
  }

  .rp-chart-bar-val {
    font-size: 10px;
    font-weight: 600;
    color: #fff;
    padding: 0 6px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: clip;
  }

  .rp-chart-legend {
    display: flex;
    gap: 16px;
    padding: 8px 18px 12px;
    border-top: 1px solid var(--border-default);
  }

  .rp-legend-item {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 11px;
    color: var(--text-tertiary);
  }

  .rp-legend-dot {
    width: 10px;
    height: 10px;
    border-radius: 2px;
  }

  .rp-legend-dot--primary {
    background: var(--accent-primary, #58a6ff);
    opacity: 0.8;
  }

  .rp-legend-dot--secondary {
    background: var(--text-tertiary);
    opacity: 0.5;
  }

  /* ── Spinner ───────────────────────────────────────────────────────── */
  .rp-spinner {
    width: 16px;
    height: 16px;
    border: 2px solid var(--border-default);
    border-top-color: var(--text-secondary);
    border-radius: 50%;
    animation: rp-spin 0.7s linear infinite;
    flex-shrink: 0;
  }

  .rp-spinner--sm {
    width: 12px;
    height: 12px;
    border-width: 2px;
  }

  @keyframes rp-spin {
    to { transform: rotate(360deg); }
  }
</style>
