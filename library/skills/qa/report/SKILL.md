---
name: qa/report
description: >
  Transform raw test runner output into structured QA reports with failure
  diagnostics, artifact references, trend comparisons, and actionable
  recommendations. Produces markdown, JSON, and HTML formats.
  Triggers on: "qa report", "test report", "generate report", "test results",
  "format results", "qa summary"
required_integrations: []
required_tools:
  - bash
---

# /qa-report

> Transform raw test output into structured, actionable QA reports.

## Purpose

Take the raw output from any test runner (Playwright JSON, Jest results, ExUnit
output, pytest reports, Go test JSON, custom formats) and produce a structured
QA report that humans can read and machines can parse. The report includes
pass/fail summaries, per-failure diagnostics with root cause analysis, artifact
references (screenshots, traces, coverage), trend comparison against previous
runs, and prioritized recommendations.

This skill is invoked as the final phase of `/qa-automate` or independently
when test results already exist and need to be formatted.

## Usage

```bash
# Generate report from test results file
/qa-report results.json

# Generate from multiple result files
/qa-report test-results/*.json

# Specify output format
/qa-report results.json --format markdown

# Include trend comparison against previous run
/qa-report results.json --compare qa-reports/previous/results.json

# Generate all formats at once
/qa-report results.json --format all --output qa-reports/

# Include screenshots directory
/qa-report results.json --screenshots test-results/screenshots/

# Custom project name and metadata
/qa-report results.json --project "Project Alpha" --branch main --commit abc123
```

## Arguments

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `<input>` | path(s) | required | Test result file(s) — JSON, XML (JUnit), or raw text |
| `--format` | enum | `markdown` | Output: `markdown`, `json`, `html`, `junit`, `all` |
| `--output` | path | `qa-reports/` | Output directory |
| `--compare` | path | — | Previous results file for trend comparison |
| `--screenshots` | path | — | Directory containing failure screenshots |
| `--project` | string | auto-detect | Project name for report header |
| `--branch` | string | auto-detect | Git branch name |
| `--commit` | string | auto-detect | Git commit SHA |
| `--threshold` | number | 80 | Minimum pass rate to consider "passing" (%) |
| `--severity` | enum | `all` | Filter: `critical`, `high`, `medium`, `low`, `all` |

## Workflow

### Step 1: Parse Input

Detect the test runner format and parse into a normalized structure:

| Format | Detection | Parser |
|--------|-----------|--------|
| Playwright JSON | `config.projects` key or `suites` array | Extract suites/tests/results |
| Jest JSON | `testResults` array | Extract test suites and assertions |
| Vitest JSON | `testResults` with `vitest` metadata | Same as Jest with Vitest fields |
| JUnit XML | `<testsuites>` root element | Parse XML test cases |
| ExUnit | `Finished in X.Xs` + `N tests, N failures` | Regex parse stdout |
| pytest JSON | `report.tests` array (pytest-json-report) | Extract tests and outcomes |
| Go test JSON | NDJSON with `Action` field | Parse streaming JSON lines |
| Raw text | Fallback | Best-effort regex extraction |

Normalized structure:

```json
{
  "runner": "playwright",
  "timestamp": "2026-05-06T14:30:22Z",
  "duration_ms": 12450,
  "suites": [
    {
      "name": "auth.spec.ts",
      "tests": [
        {
          "name": "should login with valid credentials",
          "status": "passed",
          "duration_ms": 1200
        },
        {
          "name": "should reject invalid credentials",
          "status": "failed",
          "duration_ms": 5023,
          "error": "Expected 401, got 500",
          "stack": "...",
          "file": "tests/auth.spec.ts",
          "line": 23,
          "screenshot": "screenshots/auth-failure.png"
        }
      ]
    }
  ]
}
```

### Step 2: Analyze Failures

For each failed test:

1. **Classify severity:**
   - **Critical:** Auth, data loss, crash, security — blocks release
   - **High:** Core feature broken, data corruption — should block release
   - **Medium:** Non-core feature, UI regression, performance — should fix soon
   - **Low:** Cosmetic, flaky, minor UX — can defer

2. **Identify root cause pattern:**
   - Timeout → performance or missing element
   - Assertion mismatch → logic error or changed behavior
   - Network error → API down or misconfigured
   - Element not found → UI changed or selector stale
   - Permission denied → auth/RBAC issue

3. **Generate recommendation:** actionable next step to fix or investigate

4. **Link artifacts:** match screenshots, traces, logs to specific failures

### Step 3: Trend Comparison (if --compare)

When a previous results file is provided:

- Calculate delta: new failures, fixed tests, flaky tests (pass/fail between runs)
- Identify regression: tests that passed before but fail now
- Track pass rate over time
- Highlight newly added tests

### Step 4: Generate Report

**Markdown format** (`report.md`):
- Header with project, branch, commit, timestamp
- Summary table: total, passed, failed, skipped, pass rate, duration
- Status badge: PASS (green), PARTIAL (yellow), FAIL (red) based on threshold
- Failures section grouped by severity
- Per-failure: test name, file:line, error, root cause, recommendation, artifact links
- Trend section (if comparison data available)
- Recommendations prioritized by severity

**JSON format** (`results.json`):
- Machine-readable normalized results
- Summary statistics
- Failure details with all metadata
- Artifact manifest

**HTML format** (`report.html`):
- Self-contained HTML with inline CSS
- Collapsible failure details
- Embedded screenshot thumbnails
- Interactive trend chart (if comparison data)

### Step 5: Write Output

Write all generated files to the output directory:

```
qa-reports/<run-id>/
├── report.md
├── results.json
├── report.html        (if --format html or all)
├── junit.xml          (if --format junit or all)
├── screenshots/       (copied from test artifacts)
├── traces/            (HAR files if available)
└── coverage/          (coverage report if available)
```

## Output

```markdown
## QA Report — Project Alpha

**Branch:** main | **Commit:** abc123 | **Date:** 2026-05-06 14:30
**Runner:** Playwright 1.42 | **Duration:** 12.4s
**Status:** PARTIAL PASS (90.5% — threshold: 80%)

### Summary

| Total | Passed | Failed | Skipped | Pass Rate | Duration |
|-------|--------|--------|---------|-----------|----------|
| 42    | 38     | 3      | 1       | 90.5%     | 12.4s    |

### Trend (vs previous run)

| Metric | Previous | Current | Delta |
|--------|----------|---------|-------|
| Pass Rate | 95.2% | 90.5% | -4.7% |
| Total | 40 | 42 | +2 new |
| Regressions | — | 2 | auth, dashboard |
| Fixed | — | 1 | signup flow |

### Failures by Severity

#### CRITICAL (1)
- **auth > should reject invalid credentials** — `tests/auth.spec.ts:23`
  - Error: Expected status 401, received 500
  - Root Cause: Server error in auth endpoint
  - [Screenshot](screenshots/auth-failure.png)

#### HIGH (1)
- **dashboard > should load charts within 3s** — `tests/dashboard.spec.ts:45`
  - Error: Timeout 5000ms waiting for '.chart-container'
  - Root Cause: Chart render performance regression

#### MEDIUM (1)
- **settings > theme toggle should persist** — `tests/settings.spec.ts:78`
  - Error: Expected 'dark', got 'light' after reload
  - Root Cause: Theme preference not saved to storage

### Recommendations

1. **[CRITICAL]** Fix 500 error in auth endpoint — security risk
2. **[HIGH]** Profile chart rendering — 2x slower than baseline
3. **[MEDIUM]** Check localStorage persistence for theme setting
```

## Dependencies

- Test result files (any supported format)
- `/test` — can invoke to generate results if none exist
- Git CLI — for branch/commit metadata auto-detection
