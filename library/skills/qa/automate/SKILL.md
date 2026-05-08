---
name: qa/automate
description: >
  End-to-end QA automation pipeline: detect app type, start the application,
  run functional tests (browser, API, or CLI), collect artifacts, and produce
  structured reports with failure diagnostics. Works headless by default.
  Triggers on: "qa automate", "functional test", "run qa", "test application",
  "automate testing", "startup test", "end to end test", "e2e test"
required_integrations: []
required_tools:
  - bash
---

# /qa-automate

> Start the app, run functional tests, produce a structured report.

## Purpose

Fully automate the QA lifecycle for any project: detect what kind of application
it is, start it in the host environment, execute the appropriate test suite
(Playwright for browser apps, API test runners for services, integration scripts
for CLI tools), capture all artifacts (screenshots, HAR traces, coverage, logs),
and produce a structured pass/fail report that becomes a BizForge WorkProduct.

The pipeline has three sequential phases. Each phase gates the next — if startup
fails, testing is skipped; if testing fails, the report still captures what
happened.

## Usage

```bash
# Full pipeline — detect everything automatically
/qa-automate

# Specify app type explicitly
/qa-automate --type web --url http://localhost:5173

# API-only testing (no browser)
/qa-automate --type api --base-url http://localhost:4000/api

# CLI application testing
/qa-automate --type cli --binary ./my-tool

# Skip startup (app is already running)
/qa-automate --skip-startup --url http://localhost:3000

# Use specific test directory
/qa-automate --tests e2e/

# Headless mode (default) vs headed for debugging
/qa-automate --headed

# Generate tests if none exist (exploratory mode)
/qa-automate --exploratory
```

## Arguments

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--type` | enum | auto-detect | App type: `web`, `api`, `cli`, `desktop` |
| `--url` | string | auto-detect | URL for web/API apps once running |
| `--base-url` | string | — | API base URL for API-type apps |
| `--binary` | string | — | Path to CLI binary for cli-type apps |
| `--tests` | path | auto-detect | Directory or glob for test files |
| `--skip-startup` | flag | false | Skip Phase 1 (app already running) |
| `--headed` | flag | false | Run browser tests in headed mode |
| `--exploratory` | flag | false | Generate tests on-the-fly if none exist |
| `--timeout` | number | 120 | Startup timeout in seconds |
| `--reporter` | enum | `json` | Test reporter format: `json`, `html`, `junit` |
| `--output` | path | `qa-reports/` | Directory for artifacts and reports |
| `--coverage` | flag | false | Collect code coverage data |
| `--retries` | number | 0 | Retry failed tests N times |

## Workflow

### Phase 1: Startup

Detect the application type and start it. This phase uses the `/startup-probe`
skill internally.

1. **Detect app type** from project files:
   | Config File | Framework | Start Command | Default URL |
   |-------------|-----------|---------------|-------------|
   | `package.json` (has `dev` script) | Node/SvelteKit/Next/Vite | `npm run dev` | `http://localhost:5173` or `http://localhost:3000` |
   | `mix.exs` (has phoenix) | Phoenix | `mix phx.server` | `http://localhost:4000` |
   | `manage.py` | Django | `python manage.py runserver` | `http://localhost:8000` |
   | `Cargo.toml` (has actix/axum) | Rust web | `cargo run` | `http://localhost:8080` |
   | `go.mod` | Go | `go run .` | `http://localhost:8080` |
   | `domo-manifest.json` | Domo Custom App | `domo dev` | `https://localhost:3000` |
   | Binary/script | CLI tool | Direct execution | N/A |

2. **Install dependencies** if needed (`npm install`, `mix deps.get`, `pip install -r requirements.txt`).

3. **Start the application** in background, capture PID.

4. **Wait for readiness** using probes:
   - HTTP probe: `curl -sf $URL` with retries (default 30 attempts, 2s interval)
   - TCP probe: `nc -z localhost $PORT` for non-HTTP services
   - Stdout probe: watch process output for "ready", "listening", "started" patterns
   - Timeout: fail after `--timeout` seconds with startup diagnostics

5. **Record startup metadata**: PID, actual URL, startup duration, framework detected.

**Failure handling:** If startup fails, capture stdout/stderr, exit code, and last
10 lines of output. Write a startup failure report and skip to Phase 3.

### Phase 2: Test

Run the appropriate test suite against the running application.

1. **Detect test framework and files:**
   | Framework | Detection | Run Command |
   |-----------|-----------|-------------|
   | Playwright | `playwright.config.*` or `@playwright/test` in deps | `npx playwright test --reporter=json` |
   | Cypress | `cypress.config.*` or `cypress` in deps | `npx cypress run --reporter json` |
   | Jest | `jest.config.*` or `jest` in deps | `npx jest --json --outputFile=results.json` |
   | Vitest | `vitest.config.*` or `vitest` in deps | `npx vitest run --reporter=json` |
   | ExUnit | `test/` dir + `mix.exs` | `mix test --formatter ExUnit.CLIFormatter` |
   | pytest | `pytest.ini`, `pyproject.toml[tool.pytest]`, or `conftest.py` | `pytest --tb=short -q --json-report` |
   | Go test | `*_test.go` files | `go test -json ./...` |

2. **Configure environment:**
   - Set `BASE_URL` / `APP_URL` environment variable to the running app URL
   - Set `HEADLESS=true` unless `--headed` flag
   - Set `CI=true` for deterministic behavior
   - Configure screenshot-on-failure for browser tests

3. **Execute tests:**
   - Run with JSON reporter for structured output
   - Capture stdout, stderr, exit code
   - Record wall-clock duration
   - If `--retries` > 0, retry failed tests

4. **Collect artifacts:**
   - Screenshots (on failure, or all if configured)
   - HAR network traces (browser tests)
   - Video recordings (if Playwright `video: 'on'`)
   - Coverage reports (if `--coverage`)
   - Console logs from browser (if available)

5. **If no tests found and `--exploratory`:**
   - Delegate to the exploratory-tester agent
   - That agent navigates the app, generates test scripts, and runs them
   - Results flow back into this pipeline

**Failure handling:** Test failures are expected and captured — they do not abort
the pipeline. The report phase processes all results regardless of pass/fail.

### Phase 3: Report

Parse results and generate the QA report.

1. **Parse test output** into structured format:
   ```json
   {
     "summary": {
       "total": 42,
       "passed": 38,
       "failed": 3,
       "skipped": 1,
       "duration_ms": 12450,
       "pass_rate": 90.5
     },
     "failures": [
       {
         "test": "login flow > should reject invalid credentials",
         "file": "tests/auth.spec.ts",
         "line": 23,
         "error": "Expected status 401, received 500",
         "screenshot": "qa-reports/screenshots/auth-failure-1.png",
         "stack_trace": "..."
       }
     ],
     "artifacts": {
       "screenshots": ["..."],
       "har_traces": ["..."],
       "coverage": "qa-reports/coverage/index.html"
     }
   }
   ```

2. **Generate markdown report** with:
   - Run metadata (timestamp, duration, app type, framework, URL)
   - Pass/fail summary with visual indicators
   - Per-failure diagnostics: test name, file, line, assertion, expected vs actual
   - Artifact links (screenshots, traces)
   - Coverage summary (if collected)
   - Recommendations for failing tests

3. **Write artifacts** to `output_path/qa-reports/<run-id>/`:
   - `report.md` — human-readable report
   - `results.json` — machine-readable results
   - `screenshots/` — failure screenshots
   - `traces/` — HAR/video traces
   - `coverage/` — coverage report (if collected)

4. **Cleanup:**
   - Kill the application process (PID from Phase 1)
   - Remove temporary files
   - Report final status

## Output

```markdown
## QA Automation Report

**Project:** project-alpha
**Run ID:** qa-20260506-143022
**App Type:** web (SvelteKit)
**URL:** http://localhost:5173
**Duration:** 2m 14s
**Status:** PARTIAL PASS

### Summary

| Metric | Value |
|--------|-------|
| Total Tests | 42 |
| Passed | 38 |
| Failed | 3 |
| Skipped | 1 |
| Pass Rate | 90.5% |
| Coverage | 78.2% |

### Failures

#### 1. login flow > should reject invalid credentials
- **File:** tests/auth.spec.ts:23
- **Error:** Expected status 401, received 500
- **Root Cause:** Server returns 500 instead of 401 for invalid credentials
- **Screenshot:** [auth-failure-1.png](qa-reports/screenshots/auth-failure-1.png)
- **Recommendation:** Check error handling in auth endpoint

#### 2. dashboard > should load charts within 3s
- **File:** tests/dashboard.spec.ts:45
- **Error:** Timeout waiting for selector '.chart-container' (5000ms)
- **Root Cause:** Chart rendering exceeds 3s threshold under test data
- **Screenshot:** [dashboard-timeout-1.png](qa-reports/screenshots/dashboard-timeout-1.png)
- **Recommendation:** Optimize chart rendering or increase timeout threshold

### Artifacts

- [Full Report (HTML)](qa-reports/qa-20260506-143022/report.html)
- [Results (JSON)](qa-reports/qa-20260506-143022/results.json)
- [Screenshots (3)](qa-reports/qa-20260506-143022/screenshots/)
- [Coverage Report](qa-reports/qa-20260506-143022/coverage/index.html)
```

## Dependencies

- `/startup-probe` — App lifecycle management (used in Phase 1)
- `/test` — Framework detection and test execution (used in Phase 2)
- `/qa-report` — Report generation and formatting (used in Phase 3)
- Platform tools: Node.js/npm, Playwright, curl, nc (netcat)
