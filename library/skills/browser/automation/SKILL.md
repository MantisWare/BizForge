---
name: browser/automation
description: >
  Drive a headless Chromium browser via Playwright. Navigate pages, snapshot
  accessibility trees, click elements, fill forms, capture screenshots, read
  console/network logs, and evaluate JavaScript. Used by QA agents to test
  running applications and by exploratory testers to generate test suites.
  Triggers on: "browser test", "UI test", "navigate page", "click button",
  "screenshot", "playwright", "puppeteer", "browser automation", "e2e"
required_integrations: []
required_tools:
  - browser_automation
---

# /browser-automation

> Interact with web applications through a real browser.

## Purpose

Give agents the ability to drive a Chromium browser instance — navigate URLs,
inspect page structure via accessibility snapshots, interact with elements
(click, fill, type, select, hover), capture screenshots, read console and
network logs, and evaluate arbitrary JavaScript. This is the foundation for
automated QA, exploratory testing, and visual verification.

## Tool Surface

All tools are gated behind the `browser_automation` ToolPermission. Agents
without this permission will not see these tools in their catalog.

| Tool | Description |
|------|-------------|
| `browser_navigate` | Navigate to a URL |
| `browser_navigate_back` | Go back in history |
| `browser_snapshot` | Get accessibility tree (for element refs) |
| `browser_take_screenshot` | Capture viewport as base64 PNG |
| `browser_click` | Click by selector or ref |
| `browser_mouse_click_xy` | Click at pixel coordinates |
| `browser_fill` | Clear and fill an input |
| `browser_type` | Type text at current focus |
| `browser_hover` | Hover over an element |
| `browser_press_key` | Press a keyboard key |
| `browser_select` | Select dropdown option |
| `browser_scroll` | Scroll up or down |
| `browser_console_messages` | Read console log entries |
| `browser_network_requests` | Read network request/response log |
| `browser_handle_dialog` | Accept or dismiss alert/confirm/prompt |
| `browser_tabs` | List, create, switch, close tabs |
| `browser_eval` | Evaluate JavaScript in page context |
| `browser_search` | Search for text in page HTML |
| `browser_wait` | Pause for a duration |

## Usage Patterns

### QA Automation (qa-automation-lead, bash adapter)
```bash
# Start app then exercise it via REST calls to the browser controller
/startup-probe --type web
curl -X POST http://localhost:9089/api/v1/browser/browser_navigate \
  -H "Authorization: Bearer $SESSION_TOKEN" \
  -d '{"url": "http://localhost:5173", "agent_id": "'$AGENT_ID'"}'
```

### Exploratory Testing (exploratory-tester, cursor-cli adapter)
The agent uses browser tools as native LLM tool calls:
1. `browser_navigate` to the app URL
2. `browser_snapshot` to understand page structure
3. `browser_click` / `browser_fill` to interact
4. `browser_take_screenshot` on failure for evidence

### Visual Verification (any vision-capable agent)
1. `browser_navigate` to the deployed page
2. `browser_take_screenshot` — returns base64 PNG
3. Pass screenshot to multimodal model for layout analysis

## Isolation

Each agent session gets its own `BrowserContext` (separate cookies, storage,
viewport). Multiple agents can run browser tests concurrently without
interfering with each other.

## TLS Tolerance

The sidecar launches Chromium with `--ignore-certificate-errors` and creates
contexts with `ignoreHTTPSErrors: true`. This is required for local dev
servers (e.g. `domo dev` runs on `https://localhost:3000` with a self-signed
certificate).

## Dependencies

- Playwright sidecar process (auto-managed by BizForge)
- Chromium browser (bundled or installed via `playwright install chromium`)
