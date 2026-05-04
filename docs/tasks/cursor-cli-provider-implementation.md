# Cursor CLI Provider — Implementation Specification

> **Generated:** 2026-05-04  
> **Source project:** VibeForge (Electron + React + TypeScript)  
> **Purpose:** Describe the full Cursor CLI provider so another project can replicate the integration.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [Prerequisites & Installation](#3-prerequisites--installation)
4. [Shared Types](#4-shared-types)
5. [Core Service: `cursor-cli-service`](#5-core-service-cursor-cli-service)
6. [Detection & Installation: `cursor-cli-detector`](#6-detection--installation-cursor-cli-detector)
7. [IPC Wiring (Electron-specific)](#7-ipc-wiring-electron-specific)
8. [LLM Service Integration (Routing Layer)](#8-llm-service-integration-routing-layer)
9. [Model Catalog & Pricing](#9-model-catalog--pricing)
10. [Validation](#10-validation)
11. [UI Integration Notes](#11-ui-integration-notes)
12. [Configuration & Environment Variables](#12-configuration--environment-variables)
13. [Error Handling & Retry Strategy](#13-error-handling--retry-strategy)
14. [Adaptation Guide (Non-Electron Projects)](#14-adaptation-guide-non-electron-projects)

---

## 1. Overview

The **Cursor CLI provider** (`cursor-cli`) enables an application to use Cursor's AI models by spawning the local **`agent`** CLI binary. It does **not** call a hosted REST API from your app code — instead it shells out to the `agent` binary that ships with (or is installed alongside) the Cursor IDE.

**Authentication** is handled via:
- The user's Cursor IDE installation (`agent login` — opens browser OAuth), or
- An optional `CURSOR_API_KEY` environment variable for headless/CI scenarios.

**Key characteristics:**
- No per-token API cost (uses Cursor subscription)
- Works offline after initial auth
- Supports sync and streaming execution
- Supports multiple models (Claude family, GPT family, auto-select)

---

## 2. Architecture

```
┌──────────────────────────────────────────────────────┐
│                    Your Application                   │
│                                                       │
│  ┌─────────────┐     ┌──────────────────────────┐    │
│  │  LLM Router  │────▶│  cursor-cli-service.ts    │    │
│  │  (dispatch)  │     │  - resolveCursorModel()   │    │
│  └─────────────┘     │  - buildPromptFromMessages │    │
│                       │  - runCursorAgentSync()    │    │
│                       │  - runCursorAgentStream()  │    │
│                       │  - listCursorModels()      │    │
│                       └────────────┬───────────────┘    │
│                                    │ spawn              │
│  ┌──────────────────────────┐      │                    │
│  │  cursor-cli-detector.ts  │      ▼                    │
│  │  - detectCursorCli()     │   ┌───────────┐          │
│  │  - installAgentCli()     │   │  `agent`  │          │
│  │  - loginAgentCli()       │   │  binary   │          │
│  └──────────────────────────┘   └───────────┘          │
└──────────────────────────────────────────────────────┘
```

The implementation splits into two services:

| Service | Responsibility |
|---------|---------------|
| **cursor-cli-service** | Spawns the `agent` binary, maps model names, builds prompts, parses streaming JSON, lists available models. |
| **cursor-cli-detector** | Three-tier detection (IDE installed → CLI available → authenticated), automated CLI installation, login flow. |

---

## 3. Prerequisites & Installation

### Cursor IDE
The Cursor IDE must be installed on the host machine:

| Platform | Expected Path |
|----------|--------------|
| macOS | `/Applications/Cursor.app` |
| Windows | `%LOCALAPPDATA%\Programs\cursor\Cursor.exe` |
| Linux | `/usr/bin/cursor`, `/usr/share/cursor/cursor`, `~/.local/bin/cursor`, or `/snap/cursor/current/cursor` |

### Agent CLI Binary
The `agent` binary is the command-line interface to Cursor's AI:

**Installation:**
```bash
curl https://cursor.com/install -fsS | bash
```

**Expected locations:**
- `~/.local/bin/agent`
- `/usr/local/bin/agent`
- Windows: `%LOCALAPPDATA%\Programs\cursor\agent`

**Authentication:**
```bash
agent login
```
This opens the system browser for Cursor OAuth. After completion, the agent binary stores credentials locally.

---

## 4. Shared Types

### Provider Type
```typescript
type LLMProvider =
  | 'openai'
  | 'anthropic'
  | 'cursor-cli'
  // ... other providers
  ;
```

### Detection Result
```typescript
interface CursorCliDetectionResult {
  /** Tier 1: Is Cursor IDE installed? Gates provider visibility. */
  cursorAppInstalled: boolean;
  /** Tier 2: Is the `agent` CLI binary available? Gates functionality. */
  agentInstalled: boolean;
  /** Tier 3: Is the agent authenticated? Gates actual use. */
  agentAuthenticated: boolean;
  /** CLI version string from `agent --version` */
  version?: string;
  /** Resolved path to the agent binary */
  agentPath?: string;
  /** Human-readable error if any tier fails */
  error?: string;
}
```

### Agent Result (sync execution)
```typescript
interface CursorAgentResult {
  code: number;
  stdout: string;
  stderr: string;
}
```

### CLI Model
```typescript
interface CursorCliModel {
  id: string;
  name: string;
}
```

### Agent Config
```typescript
interface CursorAgentConfig {
  agentBin: string;     // Default: 'agent'
  timeoutMs: number;    // Default: 300_000 (5 min)
  chatOnlyWorkspace: boolean; // Default: true
}
```

### Agent Options (per-call)
```typescript
interface CursorAgentOptions {
  agentBin?: string;
  apiKey?: string;
  chatOnly: boolean;
  workspacePath?: string;
  abortSignal?: AbortSignal;
  timeoutMs?: number;
}
```

### Stream Callback
```typescript
type StreamTextCallback = (chunk: string, accumulated: string) => void;
```

---

## 5. Core Service: `cursor-cli-service`

This is the main implementation file. Full source follows with inline documentation.

### 5.1 Model Name Mapping

The service maps Anthropic-style model names to Cursor CLI model IDs:

```typescript
const ANTHROPIC_TO_CURSOR: Record<string, string> = {
  'claude-opus-4-6':             'claude-4.6-opus-high',
  'claude-opus-4.6':             'claude-4.6-opus-high',
  'claude-sonnet-4-6':           'claude-4.6-sonnet-medium',
  'claude-sonnet-4.6':           'claude-4.6-sonnet-medium',
  'claude-opus-4-5':             'claude-4.5-opus-high',
  'claude-opus-4.5':             'claude-4.5-opus-high',
  'claude-sonnet-4-5':           'claude-4.5-sonnet',
  'claude-sonnet-4.5':           'claude-4.5-sonnet',
  'claude-opus-4':               'claude-4.6-opus-high',
  'claude-sonnet-4':             'claude-4.6-sonnet-medium',
  'claude-haiku-4-5-20251001':   'claude-4.5-sonnet',
  'claude-haiku-4-5':            'claude-4.5-sonnet',
  'claude-haiku-4-6':            'claude-4.6-sonnet-medium',
  'claude-haiku-4':              'claude-4.5-sonnet',
  'claude-opus-4-6-thinking':    'claude-4.6-opus-high-thinking',
  'claude-sonnet-4-6-thinking':  'claude-4.6-sonnet-medium-thinking',
  'claude-opus-4-5-thinking':    'claude-4.5-opus-high-thinking',
  'claude-sonnet-4-5-thinking':  'claude-4.5-sonnet-thinking',
  'claude-sonnet-4-thinking':    'claude-4-sonnet-thinking',
};

function resolveCursorModel(requested: string | undefined): string {
  if (requested === undefined || requested === null || requested.trim() === '') {
    return 'auto';
  }
  const trimmed = requested.trim();
  const parts = trimmed.split('/');
  const normalized = parts[parts.length - 1] ?? trimmed;
  const key = normalized.toLowerCase();
  return ANTHROPIC_TO_CURSOR[key] ?? normalized;
}
```

### 5.2 Prompt Building

Converts an array of OpenAI-style chat messages into a single flat prompt string for the CLI:

```typescript
function messageContentToText(content: unknown): string {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    return content
      .map((part) => {
        if (part === null || part === undefined) return '';
        if (typeof part === 'string') return part;
        if (part.type === 'text' && typeof part.text === 'string') return part.text;
        return '';
      })
      .join('');
  }
  return '';
}

function buildPromptFromMessages(
  messages: Array<{ role: string; content: unknown }>,
): string {
  const systemParts: string[] = [];
  const convo: string[] = [];

  for (const m of messages) {
    const role = m.role;
    const text = messageContentToText(m.content);
    if (text === '') continue;

    if (role === 'system' || role === 'developer') {
      systemParts.push(text);
    } else if (role === 'user') {
      convo.push(`User: ${text}`);
    } else if (role === 'assistant') {
      convo.push(`Assistant: ${text}`);
    } else if (role === 'tool' || role === 'function') {
      convo.push(`Tool: ${text}`);
    }
  }

  const system = systemParts.length > 0
    ? `System:\n${systemParts.join('\n\n')}\n\n`
    : '';
  const transcript = convo.join('\n\n');
  return system + transcript + '\n\nAssistant:';
}
```

### 5.3 Workspace Resolution

The CLI needs a `--workspace` directory. For "chat only" (no project context), a temporary directory is created:

```typescript
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

interface WorkspaceResult {
  workspaceDir: string;
  tempDir?: string;
}

function resolveWorkspace(
  chatOnly: boolean,
  workspacePath?: string,
): WorkspaceResult {
  if (chatOnly) {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'vibeforge-cursor-'));
    return { workspaceDir: tempDir, tempDir };
  }
  return { workspaceDir: workspacePath ?? process.cwd() };
}

function cleanupTempDir(tempDir?: string): void {
  if (tempDir !== undefined) {
    try {
      fs.rmSync(tempDir, { recursive: true, force: true });
    } catch {
      /* best-effort cleanup */
    }
  }
}
```

### 5.4 CLI Argument Construction

```typescript
function buildAgentArgs(
  workspaceDir: string,
  model: string,
  prompt: string,
  stream: boolean,
  mode: 'agent' | 'ask' = 'ask',
): string[] {
  const args = ['-f', '--print'];
  args.push('--mode', mode);
  args.push('--workspace', workspaceDir);
  args.push('--model', model);

  if (stream) {
    args.push('--stream-partial-output', '--output-format', 'stream-json');
  } else {
    args.push('--output-format', 'text');
  }

  args.push(prompt);
  return args;
}
```

**CLI flags explained:**
| Flag | Purpose |
|------|---------|
| `-f` | Force non-interactive mode |
| `--print` | Print output to stdout |
| `--mode ask` | Read-only chat mode |
| `--mode agent` | Agent mode (can write files) |
| `--workspace <dir>` | Project directory for context |
| `--model <id>` | Model to use (or `auto`) |
| `--stream-partial-output` | Enable streaming |
| `--output-format text` | Plain text output (sync) |
| `--output-format stream-json` | Newline-delimited JSON (streaming) |

### 5.5 Agent Binary Resolution

The service searches well-known directories because Electron apps on macOS often launch with a minimal PATH:

```typescript
function getAgentSearchDirs(): string[] {
  const home = os.homedir();
  const dirs = [
    path.join(home, '.local', 'bin'),
    '/usr/local/bin',
  ];
  if (process.platform === 'win32') {
    const localAppData = process.env.LOCALAPPDATA ?? path.join(home, 'AppData', 'Local');
    dirs.push(path.join(localAppData, 'Programs', 'cursor'));
  }
  return dirs;
}

let resolvedAgentPath: string | null = null;

function resolveAgentBin(requested: string): string {
  if (requested !== 'agent') {
    return requested; // User specified a custom path
  }
  if (resolvedAgentPath !== null) {
    return resolvedAgentPath; // Cached
  }
  for (const dir of getAgentSearchDirs()) {
    const candidate = path.join(dir, 'agent');
    if (fs.existsSync(candidate)) {
      resolvedAgentPath = candidate;
      return candidate;
    }
  }
  return requested; // Fall back to PATH lookup
}
```

### 5.6 Spawn Helper

```typescript
import { spawn } from 'node:child_process';

function spawnAgent(
  agentBin: string,
  args: string[],
  options: { cwd: string; timeoutMs: number; apiKey?: string },
): ReturnType<typeof spawn> {
  const env = { ...process.env };
  if (options.apiKey !== undefined && options.apiKey !== '') {
    env.CURSOR_API_KEY = options.apiKey;
  }

  // Augment PATH so the agent binary can be found
  const searchDirs = getAgentSearchDirs();
  const currentPath = env.PATH ?? '';
  const missingDirs = searchDirs.filter((d) => !currentPath.includes(d));
  if (missingDirs.length > 0) {
    env.PATH = [...missingDirs, currentPath].join(path.delimiter);
  }

  const bin = resolveAgentBin(agentBin);

  return spawn(bin, args, {
    cwd: options.cwd,
    env,
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
  });
}
```

### 5.7 Synchronous Execution

```typescript
async function runCursorAgentSync(
  prompt: string,
  model: string,
  options?: {
    agentBin?: string;
    timeoutMs?: number;
    workspacePath?: string;
    chatOnly?: boolean;
    apiKey?: string;
    mode?: 'agent' | 'ask';
  },
): Promise<CursorAgentResult> {
  const config = { ...DEFAULT_CONFIG, ...options };
  const resolvedModel = resolveCursorModel(model);
  const { workspaceDir, tempDir } = resolveWorkspace(
    config.chatOnly ?? config.chatOnlyWorkspace,
    config.workspacePath,
  );
  const args = buildAgentArgs(
    workspaceDir, resolvedModel, prompt, false, options?.mode ?? 'ask',
  );

  return new Promise((resolve, reject) => {
    const child = spawnAgent(config.agentBin ?? DEFAULT_CONFIG.agentBin, args, {
      cwd: workspaceDir,
      timeoutMs: config.timeoutMs ?? DEFAULT_CONFIG.timeoutMs,
      apiKey: config.apiKey,
    });

    const timeout = setTimeout(() => {
      child.kill('SIGKILL');
      cleanupTempDir(tempDir);
      reject(new Error(`Cursor agent timed out after ${config.timeoutMs ?? DEFAULT_CONFIG.timeoutMs}ms`));
    }, config.timeoutMs ?? DEFAULT_CONFIG.timeoutMs);

    let stdout = '';
    let stderr = '';

    child.stdout?.setEncoding('utf8');
    child.stderr?.setEncoding('utf8');
    child.stdout?.on('data', (c: string) => { stdout += c; });
    child.stderr?.on('data', (c: string) => { stderr += c; });

    child.on('error', (err: NodeJS.ErrnoException) => {
      clearTimeout(timeout);
      cleanupTempDir(tempDir);
      if (err.code === 'ENOENT') {
        reject(new Error(
          'Cursor agent CLI not found. Install it with: curl https://cursor.com/install -fsS | bash',
        ));
        return;
      }
      reject(err);
    });

    child.on('close', (code) => {
      clearTimeout(timeout);
      cleanupTempDir(tempDir);
      resolve({ code: code ?? 0, stdout, stderr });
    });
  });
}
```

### 5.8 Stream-JSON Parser

When streaming, the CLI outputs newline-delimited JSON. Each line is parsed:

```typescript
function parseCliStreamLine(
  line: string,
  onText: (text: string) => void,
  onDone: () => void,
): void {
  try {
    const obj = JSON.parse(line) as {
      type?: string;
      subtype?: string;
      message?: { content?: Array<{ type?: string; text?: string }> };
    };
    if (obj.type === 'assistant' && obj.message?.content !== undefined) {
      for (const part of obj.message.content) {
        if (part.type === 'text' && part.text !== undefined && part.text !== '') {
          onText(part.text);
        }
      }
    }
    if (obj.type === 'result' && obj.subtype === 'success') {
      onDone();
    }
  } catch {
    /* ignore non-JSON lines */
  }
}
```

**Stream JSON format examples:**
```json
{"type":"assistant","message":{"content":[{"type":"text","text":"Hello"}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":" world"}]}}
{"type":"result","subtype":"success"}
```

### 5.9 Streaming Execution

```typescript
async function runCursorAgentStream(
  prompt: string,
  model: string,
  onText: StreamTextCallback,
  options?: {
    agentBin?: string;
    timeoutMs?: number;
    workspacePath?: string;
    chatOnly?: boolean;
    apiKey?: string;
    abortSignal?: AbortSignal;
    mode?: 'agent' | 'ask';
  },
): Promise<{ fullContent: string; code: number }> {
  const config = { ...DEFAULT_CONFIG, ...options };
  const resolvedModel = resolveCursorModel(model);
  const { workspaceDir, tempDir } = resolveWorkspace(
    config.chatOnly ?? config.chatOnlyWorkspace,
    config.workspacePath,
  );
  const args = buildAgentArgs(
    workspaceDir, resolvedModel, prompt, true, options?.mode ?? 'ask',
  );

  return new Promise((resolve, reject) => {
    const child = spawnAgent(config.agentBin ?? DEFAULT_CONFIG.agentBin, args, {
      cwd: workspaceDir,
      timeoutMs: config.timeoutMs ?? DEFAULT_CONFIG.timeoutMs,
      apiKey: config.apiKey,
    });

    const timeout = setTimeout(() => {
      child.kill('SIGKILL');
      cleanupTempDir(tempDir);
      reject(new Error(`Cursor agent timed out after ${config.timeoutMs ?? DEFAULT_CONFIG.timeoutMs}ms`));
    }, config.timeoutMs ?? DEFAULT_CONFIG.timeoutMs);

    let fullContent = '';
    let lineBuffer = '';
    let stderr = '';

    const handleAbort = (): void => {
      clearTimeout(timeout);
      child.kill();
      cleanupTempDir(tempDir);
      reject(new Error('Cursor agent execution cancelled'));
    };

    if (options?.abortSignal !== undefined) {
      options.abortSignal.addEventListener('abort', handleAbort);
    }

    child.stdout?.setEncoding('utf8');
    child.stderr?.setEncoding('utf8');
    child.stderr?.on('data', (c: string) => { stderr += c; });

    child.stdout?.on('data', (chunk: string) => {
      lineBuffer += chunk;
      const lines = lineBuffer.split('\n');
      lineBuffer = lines.pop() ?? '';

      for (const line of lines) {
        if (line.trim() === '') continue;
        parseCliStreamLine(
          line,
          (text) => {
            fullContent += text;
            onText(text, fullContent);
          },
          () => { /* stream done — close event will fire */ },
        );
      }
    });

    child.on('error', (err: NodeJS.ErrnoException) => {
      clearTimeout(timeout);
      cleanupTempDir(tempDir);
      options?.abortSignal?.removeEventListener('abort', handleAbort);
      if (err.code === 'ENOENT') {
        reject(new Error(
          'Cursor agent CLI not found. Install it with: curl https://cursor.com/install -fsS | bash',
        ));
        return;
      }
      reject(err);
    });

    child.on('close', (code) => {
      clearTimeout(timeout);
      cleanupTempDir(tempDir);
      options?.abortSignal?.removeEventListener('abort', handleAbort);

      // Flush remaining buffer
      if (lineBuffer.trim() !== '') {
        parseCliStreamLine(
          lineBuffer.trim(),
          (text) => {
            fullContent += text;
            onText(text, fullContent);
          },
          () => {},
        );
      }

      if (code !== 0 && code !== null && fullContent === '') {
        reject(new Error(`Cursor agent exited with code ${code}: ${stderr || 'Unknown error'}`));
        return;
      }

      resolve({ fullContent, code: code ?? 0 });
    });
  });
}
```

### 5.10 Model Listing

Queries available models from the CLI:

```typescript
function parseCursorCliModels(output: string): CursorCliModel[] {
  const lines = output.split(/\r?\n/g).map((l) => l.trim());
  const models: CursorCliModel[] = [];

  for (const line of lines) {
    // Format: "model-id  -  Description (notes)"
    const match = line.match(/^([A-Za-z0-9][A-Za-z0-9._:/-]*)\s+-\s+(.*)$/);
    if (match === null) continue;
    const id = match[1];
    const rawName = match[2];
    const name = rawName.replace(/\s*\([^)]*\)\s*$/g, '').trim();
    models.push({ id, name: name !== '' ? name : id });
  }

  // Deduplicate by ID
  const byId = new Map<string, CursorCliModel>();
  for (const m of models) byId.set(m.id, m);
  return [...byId.values()];
}

async function listCursorModels(
  agentBin?: string,
  timeoutMs?: number,
): Promise<CursorCliModel[]> {
  const bin = resolveAgentBin(agentBin ?? 'agent');
  const timeout = timeoutMs ?? 15_000;

  const env = { ...process.env };
  const searchDirs = getAgentSearchDirs();
  const currentPath = env.PATH ?? '';
  const missingDirs = searchDirs.filter((d) => !currentPath.includes(d));
  if (missingDirs.length > 0) {
    env.PATH = [...missingDirs, currentPath].join(path.delimiter);
  }

  return new Promise((resolve, reject) => {
    const child = spawn(bin, ['--list-models'], {
      cwd: os.tmpdir(),
      env,
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true,
    });

    const timer = setTimeout(() => {
      child.kill('SIGKILL');
      reject(new Error('agent --list-models timed out'));
    }, timeout);

    let stdout = '';
    let stderr = '';

    child.stdout?.setEncoding('utf8');
    child.stderr?.setEncoding('utf8');
    child.stdout?.on('data', (c: string) => { stdout += c; });
    child.stderr?.on('data', (c: string) => { stderr += c; });

    child.on('error', (err: NodeJS.ErrnoException) => {
      clearTimeout(timer);
      if (err.code === 'ENOENT') {
        reject(new Error('Cursor agent CLI not found'));
        return;
      }
      reject(err);
    });

    child.on('close', (code) => {
      clearTimeout(timer);
      if (code !== 0) {
        reject(new Error(`agent --list-models failed (code ${code}): ${stderr.trim()}`));
        return;
      }
      resolve(parseCursorCliModels(stdout));
    });
  });
}
```

---

## 6. Detection & Installation: `cursor-cli-detector`

### 6.1 Three-Tier Detection

Detection follows a cascading check:

1. **Tier 1 — Cursor IDE installed?** Checks for the Cursor app at well-known OS paths.
2. **Tier 2 — Agent CLI available?** Runs `agent --version` and `which agent`.
3. **Tier 3 — Agent authenticated?** Runs `agent --list-models` (requires auth) with a fallback to a minimal prompt test.

```typescript
import { exec } from 'node:child_process';
import { promisify } from 'node:util';
import { access, constants } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';

const execAsync = promisify(exec);

// Cache detection results for 5 minutes
const CACHE_DURATION_MS = 5 * 60 * 1000;
let detectionCache: { result: CursorCliDetectionResult; timestamp: number } | null = null;

function clearCursorCliCache(): void {
  detectionCache = null;
}

async function detectCursorCli(useCache = true): Promise<CursorCliDetectionResult> {
  // Return cached result if fresh enough
  if (useCache && detectionCache !== null) {
    const age = Date.now() - detectionCache.timestamp;
    if (age < CACHE_DURATION_MS) {
      return detectionCache.result;
    }
  }

  const result: CursorCliDetectionResult = {
    cursorAppInstalled: false,
    agentInstalled: false,
    agentAuthenticated: false,
  };

  // Tier 1: Check Cursor IDE
  result.cursorAppInstalled = await isCursorAppInstalled();
  if (!result.cursorAppInstalled) {
    result.error = 'Cursor IDE is not installed on this system';
    detectionCache = { result, timestamp: Date.now() };
    return result;
  }

  // Tier 2: Check agent CLI
  const agentResult = await detectAgentCli();
  result.agentInstalled = agentResult.installed;
  result.version = agentResult.version;
  result.agentPath = agentResult.agentPath;
  if (!agentResult.installed) {
    result.error = agentResult.error ?? 'agent CLI not found';
    detectionCache = { result, timestamp: Date.now() };
    return result;
  }

  // Tier 3: Check authentication
  result.agentAuthenticated = await isAgentAuthenticated(result.agentPath);
  if (!result.agentAuthenticated) {
    result.error = 'agent CLI is installed but not authenticated. Run `agent login` in your terminal.';
  }

  detectionCache = { result, timestamp: Date.now() };
  return result;
}
```

### 6.2 Cursor IDE App Detection (Tier 1)

```typescript
async function pathExists(filePath: string): Promise<boolean> {
  try {
    await access(filePath, constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

async function isCursorAppInstalled(): Promise<boolean> {
  switch (process.platform) {
    case 'darwin':
      return pathExists('/Applications/Cursor.app');

    case 'win32': {
      const localAppData = process.env.LOCALAPPDATA;
      if (localAppData !== undefined) {
        const cursorPath = join(localAppData, 'Programs', 'cursor', 'Cursor.exe');
        if (await pathExists(cursorPath)) return true;
      }
      const userProfile = process.env.USERPROFILE ?? homedir();
      return pathExists(join(userProfile, 'AppData', 'Local', 'Programs', 'cursor', 'Cursor.exe'));
    }

    case 'linux': {
      const linuxPaths = [
        '/usr/bin/cursor',
        '/usr/share/cursor/cursor',
        join(homedir(), '.local', 'bin', 'cursor'),
        '/snap/cursor/current/cursor',
      ];
      for (const p of linuxPaths) {
        if (await pathExists(p)) return true;
      }
      return false;
    }

    default:
      return false;
  }
}
```

### 6.3 Agent CLI Detection (Tier 2)

```typescript
async function detectAgentCli(): Promise<{
  installed: boolean;
  version?: string;
  agentPath?: string;
  error?: string;
}> {
  try {
    const { stdout } = await execAsync('agent --version', {
      timeout: 10_000,
      windowsHide: true,
    });

    const version = stdout.trim();
    if (version === '') {
      return { installed: false, error: 'agent --version returned empty output' };
    }

    let agentPath: string | undefined;
    try {
      const whichCmd = process.platform === 'win32' ? 'where agent' : 'which agent';
      const { stdout: pathOut } = await execAsync(whichCmd, { timeout: 5_000, windowsHide: true });
      agentPath = pathOut.trim().split('\n')[0]?.trim();
    } catch {
      /* non-critical */
    }

    return { installed: true, version, agentPath };
  } catch (error) {
    const msg = error instanceof Error ? error.message.toLowerCase() : '';
    if (msg.includes('command not found') || msg.includes('not recognized') || msg.includes('enoent')) {
      return { installed: false, error: 'agent CLI not found in PATH' };
    }
    return { installed: false, error: `Error checking agent CLI: ${error instanceof Error ? error.message : String(error)}` };
  }
}
```

### 6.4 Authentication Check (Tier 3)

```typescript
async function isAgentAuthenticated(agentBin?: string): Promise<boolean> {
  const bin = agentBin ?? 'agent';

  // Primary: `agent --list-models` requires auth
  try {
    const { stdout } = await execAsync(`${bin} --list-models`, {
      timeout: 15_000,
      windowsHide: true,
    });
    const lines = stdout.trim().split('\n').filter((l) => l.trim() !== '');
    if (lines.length > 0) return true;
  } catch (error) {
    const msg = error instanceof Error ? error.message : '';
    if (msg.includes('Authentication required') || msg.includes('agent login')) {
      return false;
    }
  }

  // Fallback: minimal prompt
  try {
    await execAsync(`${bin} -f --print --mode ask "test"`, {
      timeout: 10_000,
      windowsHide: true,
    });
    return true;
  } catch (error) {
    const msg = error instanceof Error ? error.message : '';
    if (msg.includes('Authentication required') || msg.includes('agent login')) {
      return false;
    }
    return true; // Other errors assume authenticated but broken
  }
}
```

### 6.5 Automated Installation

```typescript
interface CursorCliInstallProgress {
  status: 'installing' | 'success' | 'error';
  message: string;
  output?: string;
}

async function installAgentCli(
  onProgress?: (progress: CursorCliInstallProgress) => void,
): Promise<CursorCliInstallProgress> {
  onProgress?.({
    status: 'installing',
    message: 'Installing Cursor agent CLI...',
  });

  try {
    const { stdout, stderr } = await execAsync(
      'curl https://cursor.com/install -fsS | bash',
      {
        timeout: 120_000,
        windowsHide: true,
        shell: process.platform === 'win32' ? 'cmd.exe' : '/bin/bash',
      },
    );

    const output = (stdout + '\n' + stderr).trim();
    clearCursorCliCache();

    const successResult: CursorCliInstallProgress = {
      status: 'success',
      message: 'Cursor agent CLI installed successfully! Run `agent login` to authenticate.',
      output,
    };
    onProgress?.(successResult);
    return successResult;
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    const errorResult: CursorCliInstallProgress = {
      status: 'error',
      message: `Failed to install agent CLI: ${errorMessage}`,
    };
    onProgress?.(errorResult);
    return errorResult;
  }
}
```

### 6.6 Login (OAuth via Browser)

```typescript
interface CursorCliLoginResult {
  success: boolean;
  message: string;
  output?: string;
}

async function loginAgentCli(agentBin?: string): Promise<CursorCliLoginResult> {
  const bin = agentBin ?? 'agent';

  try {
    const { stdout, stderr } = await execAsync(`${bin} login`, {
      timeout: 120_000,
      windowsHide: true,
    });

    const output = (stdout + '\n' + stderr).trim();
    clearCursorCliCache();

    const authenticated = await isAgentAuthenticated(bin);
    if (authenticated) {
      return { success: true, message: 'Successfully authenticated with Cursor.', output };
    }

    return {
      success: false,
      message: 'Login flow completed but authentication could not be verified.',
      output,
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);

    if (errorMessage.toLowerCase().includes('timeout')) {
      clearCursorCliCache();
      const authenticated = await isAgentAuthenticated();
      if (authenticated) {
        return { success: true, message: 'Successfully authenticated with Cursor.' };
      }
      return { success: false, message: 'Login timed out. Try `agent login` in your terminal.' };
    }

    return { success: false, message: `Login failed: ${errorMessage}` };
  }
}
```

### 6.7 Status Message Helper

```typescript
function getCursorCliStatusMessage(result: CursorCliDetectionResult): string {
  if (!result.cursorAppInstalled) {
    return 'Cursor IDE is not installed on this system';
  }
  if (!result.agentInstalled) {
    return 'Cursor is installed but the agent CLI is not. Click "Install Agent CLI" to set it up.';
  }
  if (!result.agentAuthenticated) {
    return `Agent CLI v${result.version ?? 'unknown'} installed but not authenticated. Run \`agent login\`.`;
  }
  return `Cursor CLI agent v${result.version ?? 'unknown'} detected and ready`;
}
```

---

## 7. IPC Wiring (Electron-specific)

If your project uses Electron, you need IPC channels between the main process and renderer.

### 7.1 IPC Channel Names

```typescript
const IPC = {
  CURSOR_CLI: {
    DETECT: 'cursor-cli:detect',
    INSTALL_AGENT: 'cursor-cli:install-agent',
    LOGIN: 'cursor-cli:login',
    LIST_MODELS: 'cursor-cli:list-models',
    CLEAR_CACHE: 'cursor-cli:clear-cache',
  },
  EVENTS: {
    CURSOR_CLI_INSTALL_PROGRESS: 'cursor-cli:install-progress',
  },
};
```

### 7.2 Main Process Handlers

```typescript
import { ipcMain } from 'electron';

function registerCursorCliHandlers(): void {
  ipcMain.handle(IPC.CURSOR_CLI.DETECT, async (_event, useCache?: boolean) => {
    try {
      return await detectCursorCli(useCache ?? true);
    } catch (error) {
      return {
        cursorAppInstalled: false,
        agentInstalled: false,
        agentAuthenticated: false,
        error: error instanceof Error ? error.message : String(error),
      };
    }
  });

  ipcMain.handle(IPC.CURSOR_CLI.INSTALL_AGENT, async (event) => {
    try {
      const result = await installAgentCli((progress) => {
        event.sender.send(IPC.EVENTS.CURSOR_CLI_INSTALL_PROGRESS, progress);
      });
      return { success: result.status === 'success', error: result.status === 'error' ? result.message : undefined };
    } catch (error) {
      return { success: false, error: error instanceof Error ? error.message : String(error) };
    }
  });

  ipcMain.handle(IPC.CURSOR_CLI.LOGIN, async () => {
    try {
      return await loginAgentCli();
    } catch (error) {
      return { success: false, message: error instanceof Error ? error.message : String(error) };
    }
  });

  ipcMain.handle(IPC.CURSOR_CLI.LIST_MODELS, async () => {
    try {
      return await listCursorModels();
    } catch (error) {
      return [];
    }
  });

  ipcMain.handle(IPC.CURSOR_CLI.CLEAR_CACHE, async () => {
    clearCursorCliCache();
  });
}
```

### 7.3 Preload (Renderer API Surface)

```typescript
// Exposed via contextBridge as window.vibeforge.cursorCli
cursorCli: {
  detect: (useCache?: boolean) =>
    ipcRenderer.invoke('cursor-cli:detect', useCache),
  installAgent: () =>
    ipcRenderer.invoke('cursor-cli:install-agent'),
  login: () =>
    ipcRenderer.invoke('cursor-cli:login') as Promise<{ success: boolean; message: string }>,
  listModels: () =>
    ipcRenderer.invoke('cursor-cli:list-models'),
  clearCache: () =>
    ipcRenderer.invoke('cursor-cli:clear-cache'),
},
```

---

## 8. LLM Service Integration (Routing Layer)

The LLM service routes `cursor-cli` requests to the appropriate sync/streaming functions.

### 8.1 Sync Dispatch

```typescript
async function sendToCursorCli(
  credential: LLMCredential,
  request: LLMRequest,
  callContext?: LLMCallContext,
): Promise<LLMResponse> {
  const model = credential.model ?? 'auto';

  let prompt = request.prompt;
  if (request.systemPrompt !== undefined && request.systemPrompt !== '') {
    prompt = `System:\n${request.systemPrompt}\n\nUser: ${request.prompt}\n\nAssistant:`;
  }

  const hasWorkspace = request.workspacePath !== undefined && request.workspacePath !== '';
  // Use agent mode (can write files) only for specific pipeline phases
  const useAgentMode = hasWorkspace && CURSOR_CLI_AGENT_MODE_PHASES.has(callContext?.sourceDetail ?? '');
  const cliMode: 'agent' | 'ask' = useAgentMode ? 'agent' : 'ask';

  let lastError: Error | null = null;

  for (let attempt = 0; attempt <= CURSOR_CLI_MAX_RETRIES; attempt++) {
    if (attempt > 0) {
      const delay = CURSOR_CLI_RETRY_BASE_MS * attempt + Math.random() * 500;
      await new Promise(resolve => setTimeout(resolve, delay));
    }

    const result = await runCursorAgentSync(prompt, model, {
      apiKey: credential.apiKey ?? undefined,
      chatOnly: !hasWorkspace,
      workspacePath: hasWorkspace ? request.workspacePath : undefined,
      timeoutMs: 300_000,
      mode: cliMode,
    });

    if (result.code !== 0 && result.stdout.trim() === '') {
      const stderr = result.stderr ?? 'Unknown error';
      if (isCursorCliTransientError(stderr) && attempt < CURSOR_CLI_MAX_RETRIES) {
        lastError = new Error(`Cursor agent exited with code ${result.code}: ${stderr}`);
        continue;
      }
      throw new Error(`Cursor agent exited with code ${result.code}: ${stderr}`);
    }

    return {
      content: result.stdout.trim(),
      provider: 'cursor-cli',
      model,
      usage: { promptTokens: 0, completionTokens: 0, totalTokens: 0 },
    };
  }

  throw lastError ?? new Error('Cursor CLI failed after retries');
}
```

### 8.2 Streaming Dispatch

```typescript
async function streamFromCursorCli(
  credential: LLMCredential,
  request: StreamingLLMRequest,
  onChunk?: (chunk: string, accumulatedContent: string) => void,
): Promise<LLMResponse> {
  const model = credential.model ?? 'auto';

  let prompt = request.prompt;
  if (request.systemPrompt !== undefined && request.systemPrompt !== '') {
    prompt = `System:\n${request.systemPrompt}\n\nUser: ${request.prompt}\n\nAssistant:`;
  }

  const hasWorkspace = request.workspacePath !== undefined && request.workspacePath !== '';

  let lastError: Error | null = null;
  for (let attempt = 0; attempt <= CURSOR_CLI_MAX_RETRIES; attempt++) {
    if (attempt > 0) {
      const delay = CURSOR_CLI_RETRY_BASE_MS * attempt + Math.random() * 500;
      await new Promise(resolve => setTimeout(resolve, delay));
    }

    try {
      const { fullContent } = await runCursorAgentStream(
        prompt,
        model,
        (chunk, accumulated) => { onChunk?.(chunk, accumulated); },
        {
          apiKey: credential.apiKey ?? undefined,
          chatOnly: !hasWorkspace,
          workspacePath: hasWorkspace ? request.workspacePath : undefined,
          timeoutMs: 300_000,
        },
      );

      return {
        content: fullContent,
        provider: 'cursor-cli',
        model,
        usage: { promptTokens: 0, completionTokens: 0, totalTokens: 0 },
      };
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      if (isCursorCliTransientError(msg) && attempt < CURSOR_CLI_MAX_RETRIES) {
        lastError = err instanceof Error ? err : new Error(msg);
        continue;
      }
      throw err;
    }
  }

  throw lastError ?? new Error('Cursor CLI streaming failed after retries');
}
```

### 8.3 Workspace Options Builder

Helper to build per-call options from stored credentials:

```typescript
function buildWorkspaceOptions(
  credential: { endpoint?: string | null; apiKey?: string | null },
  overrides?: { workspacePath?: string; chatOnly?: boolean; abortSignal?: AbortSignal },
): CursorAgentOptions {
  let workspacePath = overrides?.workspacePath;
  if (workspacePath === undefined || workspacePath === '') {
    // Try to resolve from app context (adapt to your framework)
    try {
      workspacePath = getAppCurrentWorkspacePath() ?? undefined;
    } catch {
      workspacePath = undefined;
    }
  }
  const hasWorkspace = workspacePath !== undefined && workspacePath !== '';
  return {
    agentBin: credential.endpoint ?? undefined, // endpoint field stores custom agent binary path
    apiKey: credential.apiKey ?? undefined,
    chatOnly: overrides?.chatOnly ?? !hasWorkspace,
    workspacePath: hasWorkspace ? workspacePath : undefined,
    abortSignal: overrides?.abortSignal,
  };
}
```

---

## 9. Model Catalog & Pricing

### 9.1 Static Fallback Models

Used when `agent --list-models` is unavailable:

```typescript
const CURSOR_CLI_MODELS = [
  { id: 'auto', name: 'Auto', description: 'Cursor auto-selects the best model', isDefault: true },
  { id: 'claude-4.6-opus-high', name: 'Claude 4.6 Opus (High)', description: 'Anthropic Claude 4.6 Opus' },
  { id: 'claude-4.6-sonnet-medium', name: 'Claude 4.6 Sonnet', description: 'Anthropic Claude 4.6 Sonnet' },
  { id: 'claude-4.5-sonnet', name: 'Claude 4.5 Sonnet', description: 'Anthropic Claude 4.5 Sonnet' },
];
```

### 9.2 Pricing

No per-token cost — uses the Cursor subscription:

```typescript
const CURSOR_CLI_PRICING = {
  default: { input: 0, output: 0 },
  models: {},
};
```

---

## 10. Validation

### 10.1 API Key Not Required

The `cursor-cli` provider does not require an API key (auth is via `agent login`):

```typescript
const noApiKeyProviders = ['cursor-cli', 'claude-code', 'waldo-local', 'custom'];
```

### 10.2 Model Name Patterns

Regex patterns for validating model names:

```typescript
const CURSOR_CLI_MODEL_PATTERNS = [
  /^claude-/,
  /^gpt-/,
  /^o[134]-/,
  /^cursor-/,
  /^auto$/,
];
```

---

## 11. UI Integration Notes

The UI layer in VibeForge handles:

1. **Provider Configuration (Settings):** A modal that shows detection status, an "Install Agent CLI" button, a "Login" button, optional CURSOR_API_KEY field, and optional agent binary path override (stored in the `endpoint` field of the provider connection).

2. **Login Modal (Forge Console):** When a chat response includes a `CURSOR_CLI_AUTH_REQUIRED` error, a modal is shown with a "Sign In" button that calls `cursorCli.login()` followed by `cursorCli.clearCache()`.

3. **Inline Auth Recovery:** The message display component detects Cursor auth errors in assistant text and renders an inline "Sign in" action.

4. **Model Selector:** Icon and label mapping for `'cursor-cli'` in the model picker.

5. **Cost Tracking:** Color and label for `'cursor-cli'` in usage graphs (always $0).

---

## 12. Configuration & Environment Variables

| Item | Where Stored | Purpose |
|------|-------------|---------|
| **CURSOR_API_KEY** | Provider connection `apiKey` field → passed as env var to `agent` process | Optional headless auth (bypasses `agent login`) |
| **Agent binary path** | Provider connection `endpoint` field → passed as `agentBin` option | Custom agent binary location (overrides PATH search) |
| **Detection cache** | In-memory, 5-minute TTL | Avoids repeated filesystem/process checks |

No `.env` file is required specifically for Cursor. All configuration is stored in the app's provider connection settings.

---

## 13. Error Handling & Retry Strategy

### Transient Error Detection

Concurrent Cursor IDE / agent access can cause filesystem race conditions:

```typescript
function isCursorCliTransientError(stderr: string): boolean {
  return (
    stderr.includes('ENOENT') && stderr.includes('cli-config.json')
  ) || (
    stderr.includes('EBUSY') && stderr.includes('cli-config.json')
  );
}
```

### Retry Configuration

```typescript
const CURSOR_CLI_MAX_RETRIES = 3;
const CURSOR_CLI_RETRY_BASE_MS = 1500; // Linear backoff + jitter
```

Retries use `base * attempt + random(0..500)ms` delay.

### Agent Mode Gating

Only specific pipeline phases are allowed to use `--mode agent` (which can write files):

```typescript
const CURSOR_CLI_AGENT_MODE_PHASES = new Set([
  'Implementation',
  'QA Fix',
  'Linting Fix',
  'Format Rescue',
]);
```

All other calls use `--mode ask` (read-only).

---

## 14. Adaptation Guide (Non-Electron Projects)

If your project is **not** Electron-based, here's how to adapt:

### Node.js Backend (Express, Fastify, etc.)
- Use `cursor-cli-service.ts` and `cursor-cli-detector.ts` directly — they are pure Node.js (no Electron dependencies).
- Skip the IPC layer entirely. Call the service functions directly from your route handlers.
- Replace `getHandlerContext().getCurrentWorkspacePath()` in `buildWorkspaceOptions` with your own workspace resolution logic.

### Web Frontend
- Detection and execution must happen server-side (the CLI runs on the host machine).
- Expose REST endpoints for detect, install, login, list-models, and execute.
- The frontend calls these endpoints instead of Electron IPC.

### CLI Application
- Import the service functions directly.
- Detection can run once at startup.
- No IPC or preload needed.

### Key Dependencies
The implementation only requires Node.js built-ins:
- `node:child_process` (spawn, exec)
- `node:fs` / `node:fs/promises`
- `node:os`
- `node:path`
- `node:util` (promisify)

No third-party packages are needed for the Cursor CLI provider itself.

---

## Summary

The Cursor CLI provider is a self-contained integration that:

1. **Detects** the Cursor IDE and agent CLI installation (three tiers)
2. **Installs** the agent CLI if missing (`curl https://cursor.com/install | bash`)
3. **Authenticates** via `agent login` (browser OAuth) or `CURSOR_API_KEY`
4. **Executes** prompts by spawning the `agent` binary in sync or streaming mode
5. **Maps models** from Anthropic-style names to Cursor CLI model IDs
6. **Parses** streaming newline-delimited JSON output
7. **Retries** on transient filesystem errors with linear backoff + jitter
8. **Lists available models** via `agent --list-models`

All code is TypeScript using only Node.js built-in modules with no external dependencies.
