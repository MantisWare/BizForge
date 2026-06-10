// src/lib/api/client.ts
// HTTP API client for the Bizforge backend with mock fallback

import type {
  BizforgeAgent,
  AgentStatus,
  AgentCreateRequest,
  DashboardData,
  HealthResponse,
  Session,
  SessionChain,
  DispatchPreview,
  DispatchRoute,
  Schedule,
  HeartbeatRun,
  Task,
  Phase,
  PhaseTreeNode,
  Project,
  CostSummary,
  AgentCostBreakdown,
  ModelCostBreakdown,
  BudgetPolicy,
  ActivityEvent,
  InboxItem,
  Skill,
  Webhook,
  AlertRule,
  Integration,
  Adapter,
  Gateway,
  AIProvider,
  AIProviderCreateRequest,
  AIProviderTestResult,
  Workspace,
  Settings,
  AuditEntry,
  MemoryEntry,
  MemoryNamespace,
  MemoryCreateRequest,
  SpawnInstance,
  LogEntry,
  QueuedRequest,
  SendMessageRequest,
  SendMessageResponse,
  Signal,
  SignalPattern,
  SignalStats,
  BudgetIncident,
  Secret,
  SecretCreateRequest,
  Approval,
  ApprovalCreateRequest,
  Organization,
  OrganizationMembership,
  OrganizationCreateRequest,
  Division,
  Department,
  Team,
  TeamMembership,
  HierarchyTree,
  HierarchyDivisionNode,
  Label,
  LabelCreateRequest,
  Plugin,
  PluginLog,
  RoleAssignment,
  SidebarBadges,
  User,
  AgentTemplate,
  Document,
  DocumentTreeNode,
  DocumentRevision,
  IntegrationBinding,
  IntegrationBindingOwner,
  IntegrationBindingCreateRequest,
  DeliveryReport,
  DeliveryReadiness,
} from "./types";

// ── Logging ──────────────────────────────────────────────────────────────────

const LOG_PREFIX = "[bizforge:api]";
const LOG_STYLES = {
  info: "color: #3b82f6; font-weight: bold",
  warn: "color: #eab308; font-weight: bold",
  error: "color: #ef4444; font-weight: bold",
  success: "color: #22c55e; font-weight: bold",
  mock: "color: #f97316; font-weight: bold",
  auth: "color: #f59e0b; font-weight: bold",
  health: "color: #06b6d4; font-weight: bold",
  net: "color: #64748b; font-weight: bold",
  store: "color: #a855f7; font-weight: bold",
  boot: "color: #ec4899; font-weight: bold",
} as const;

export type LogArea = keyof typeof LOG_STYLES;

export function logInfo(area: LogArea, message: string, ...data: unknown[]) {
  console.log(`%c${LOG_PREFIX}:${area}%c ${message}`, LOG_STYLES[area], "color: inherit", ...data);
}
export function logWarn(area: LogArea, message: string, ...data: unknown[]) {
  console.warn(`%c${LOG_PREFIX}:${area}%c ${message}`, LOG_STYLES[area], "color: inherit", ...data);
}
export function logError(area: LogArea, message: string, ...data: unknown[]) {
  console.error(`%c${LOG_PREFIX}:${area}%c ${message}`, LOG_STYLES[area], "color: inherit", ...data);
}

// ── Configuration ─────────────────────────────────────────────────────────────

const BASE_URL = import.meta.env.VITE_API_URL ?? "http://127.0.0.1:9089";
const API_PREFIX = "/api/v1";

logInfo("info", `API base URL: ${BASE_URL}${API_PREFIX}`);

// ── Token Store ───────────────────────────────────────────────────────────────
// Eagerly restore token from localStorage so Vite HMR module reloads don't
// wipe in-memory auth state and leave requests hanging.

function _restoreFromLocalStorage(): {
  token: string | null;
} {
  if (typeof localStorage === "undefined") return { token: null };
  try {
    const token = localStorage.getItem("bizforge-auth-token");
    return { token: token ?? null };
  } catch {
    return { token: null };
  }
}

const _restored = _restoreFromLocalStorage();

let _token: string | null = _restored.token;
let _firstRun: boolean = false;

export function getToken(): string | null {
  return _token;
}
export function setToken(token: string | null): void {
  _token = token;
}

/**
 * Returns true if the backend reported no users exist (first-run state).
 * Only meaningful after initializeAuth() has resolved.
 */
export function isFirstRun(): boolean {
  return _firstRun;
}

// ── Auth Gate ─────────────────────────────────────────────────────────────────
// All API requests wait for auth to complete before firing.
// If we already restored a token from localStorage, pre-resolve the gate so
// requests don't hang after HMR reloads.

let _authResolve: (() => void) | null = null;
const _authPromise: Promise<void> = new Promise<void>((resolve) => {
  if (_token !== null) {
    resolve();
    _authResolve = null;
  } else {
    _authResolve = resolve;
  }
});

function resolveAuthGate(): void {
  if (_authResolve) {
    _authResolve();
    _authResolve = null;
  }
}

// ── Transition Gate ────────────────────────────────────────────────────────────
// When the backend comes online and we flip from mock to real mode, in-flight
// requests must not proceed with stale mock data. The transition gate blocks
// all new requests while the mode switch (cache clear + re-auth) completes.
// A 5-second timeout prevents a stuck transition from hanging the app forever.

const TRANSITION_TIMEOUT_MS = 5_000;
let _transitionResolve: (() => void) | null = null;
let _transitionPromise: Promise<void> | null = null;
let _transitioning = false;

function beginTransition(): void {
  if (_transitioning) return;
  _transitioning = true;
  _transitionPromise = new Promise<void>((resolve) => {
    _transitionResolve = resolve;
    // Safety: auto-resolve after timeout so requests are never blocked forever
    setTimeout(() => {
      if (_transitionResolve) {
        _transitionResolve();
        _transitionResolve = null;
        _transitioning = false;
      }
    }, TRANSITION_TIMEOUT_MS);
  });
}

function endTransition(): void {
  if (_transitionResolve) {
    _transitionResolve();
    _transitionResolve = null;
  }
  _transitioning = false;
  _transitionPromise = null;
}

// Tracks the in-flight (or completed) initializeAuth() promise so that
// concurrent or repeated callers all await the same single execution.
// Without this guard a second call — e.g. from +layout.svelte after
// +page.svelte already ran initializeAuth() and redirected to /app —
// would re-probe /health, call clearCache(), and re-verify the token,
// wasting two extra network requests and wiping freshly-cached responses.
let _initPromise: Promise<void> | null = null;

// ── Auth Initialization ───────────────────────────────────────────────────────

async function saveTokenToStore(token: string): Promise<void> {
  try {
    const { load: loadStore } = await import("@tauri-apps/plugin-store");
    const store = await loadStore("store.json", {
      autoSave: true,
      defaults: {},
    });
    await store.set("authToken", token);
    await store.save();
  } catch {
    /* non-fatal — not in Tauri or store unavailable */
  }
}

type VerifyResult = "valid" | "unauthorized" | "unreachable";

async function verifyToken(token: string): Promise<VerifyResult> {
  // Use /agents (requires auth) rather than /health (no auth required).
  // /health returns 200 for any request regardless of token validity, so
  // using it here would make verifyToken() return "valid" for stale or
  // invalid tokens, skipping re-login and sending unauthenticated requests.
  //
  // Two quick attempts with a short delay. The health probe already confirmed
  // the backend is reachable, so aggressive retries are unnecessary. Transient
  // errors return "unreachable" so callers trust the stored token rather than
  // bouncing the user to the login page on cold-start race conditions.
  const maxAttempts = 2;
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      const res = await fetch(`${BASE_URL}${API_PREFIX}/agents`, {
        headers: { Accept: "application/json", Authorization: `Bearer ${token}` },
        signal: AbortSignal.timeout(4000),
      });
      if (res.ok) return "valid";
      if (res.status === 401) return "unauthorized";
      if (attempt < maxAttempts - 1) {
        await new Promise((r) => setTimeout(r, 500));
      }
    } catch {
      if (attempt < maxAttempts - 1) {
        await new Promise((r) => setTimeout(r, 500));
      }
    }
  }
  return "unreachable";
}

export async function login(email: string, password: string): Promise<string> {
  const response = await fetch(`${BASE_URL}${API_PREFIX}/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  if (!response.ok) {
    throw new ApiError(response.status, "Login failed");
  }
  const data = (await response.json()) as { token: string; user: unknown };
  return data.token;
}

export function initializeAuth(): Promise<void> {
  // Return the in-flight or completed promise so concurrent / repeated callers
  // (e.g. +page.svelte then +layout.svelte on the same navigation) share one
  // execution and avoid redundant health probes, cache clearing, and token
  // verification requests.
  if (_initPromise) return _initPromise;

  // Fast path: if we already have a token from localStorage (set at module
  // init), resolve immediately so the layout boot sequence starts at once.
  // The full health/verify flow runs in the background — if the token turns
  // out to be invalid, the next API call will 401 and redirect to /auth.
  if (_token) {
    resolveAuthGate();
    _initPromise = _doInitializeAuth();
    return Promise.resolve();
  }

  _initPromise = _doInitializeAuth();
  return _initPromise;
}

async function _doInitializeAuth(): Promise<void> {
  logInfo("auth", "Initializing auth — probing backend health...");
  const authStartMs = performance.now();

  // 0a. Restore session state from Tauri disk store → localStorage.
  // Run concurrently with the health probe since they're independent.
  const restorePromise = restoreSessionFromStore();

  // 0b. Probe backend health — if unreachable, resolve gate immediately.
  let backendReachable = false;
  try {
    const probe = await fetch(`${BASE_URL}${API_PREFIX}/health`, {
      signal: AbortSignal.timeout(3000),
    });
    if (probe.ok) {
      backendReachable = true;
      logInfo("health", `Backend reachable (${Math.round(performance.now() - authStartMs)}ms)`);
      clearCache();
    }
  } catch {
    logWarn("health", `Backend unreachable at ${BASE_URL} — app will show disconnected state`);
    await restorePromise;
    resolveAuthGate();
    return;
  }

  // 0c. Check auth status and finish session restore in parallel.
  const [authStatusResult] = await Promise.allSettled([
    fetch(`${BASE_URL}${API_PREFIX}/auth/status`, {
      signal: AbortSignal.timeout(3000),
    }).then(async (res) => {
      if (res.ok) {
        return (await res.json()) as { has_users: boolean; registration_open: boolean };
      }
      return null;
    }),
    restorePromise,
  ]);

  if (authStatusResult.status === "fulfilled" && authStatusResult.value !== null) {
    _firstRun = !authStatusResult.value.has_users;
    logInfo("auth", `Auth status: has_users=${authStatusResult.value.has_users}, first_run=${_firstRun}`);
  } else {
    _firstRun = false;
    logWarn("auth", "Could not fetch auth status — assuming users exist");
  }

  if (_firstRun) {
    logInfo("auth", "First run detected — skipping token verification, redirecting to registration");
    resolveAuthGate();
    return;
  }

  // 1. Token was already restored at module init from localStorage.
  //    Only check Tauri store if we still don't have one.
  if (!_token) {
    try {
      const { load: loadStore } = await import("@tauri-apps/plugin-store");
      const store = await loadStore("store.json", { autoSave: true, defaults: {} });
      const stored = await store.get<string>("authToken");
      if (stored) {
        _token = stored;
        logInfo("auth", "Token restored from Tauri store");
      }
    } catch {
      logInfo("auth", "Tauri store unavailable");
    }
  }

  // 2. Still no token — try localStorage explicitly (covers edge cases
  //    where module-level restore ran before localStorage was populated).
  if (!_token) {
    try {
      const stored = localStorage.getItem("bizforge-auth-token");
      if (stored) {
        _token = stored;
        logInfo("auth", "Token restored from localStorage");
      }
    } catch {
      // localStorage unavailable (SSR / blocked)
    }
  }

  // 4. If we have a token, verify it is still valid.
  // Three outcomes: "valid" (200), "unauthorized" (401 — clear token),
  // "unreachable" (transient errors — trust the stored token so the user
  // isn't bounced to the login page on every cold-start race condition).
  if (_token) {
    logInfo("auth", "Verifying stored token...");
    const result = await verifyToken(_token);
    if (result === "valid") {
      logInfo("auth", `Auth complete — token valid (${Math.round(performance.now() - authStartMs)}ms total)`);
      resolveAuthGate();
      return;
    }
    if (result === "unreachable") {
      logWarn("auth", "Token verification inconclusive (backend routes not ready) — trusting stored token");
      resolveAuthGate();
      return;
    }
    logWarn("auth", "Stored token is invalid/expired (401) — clearing");
    _token = null;
    await clearToken();
  }

  // 5. Attempt auto re-login with saved credentials (persistent session).
  // This covers the common case where the JWT expired or localStorage was
  // cleared by the OS but the user's credentials are still saved on disk.
  const savedCreds = await restoreCredentials();
  if (savedCreds !== null) {
    logInfo("auth", `Attempting auto re-login with saved credentials (${savedCreds.email})...`);
    try {
      const token = await login(savedCreds.email, savedCreds.password);
      _token = token;
      await persistToken(token);
      logInfo("auth", `Auto re-login successful (${Math.round(performance.now() - authStartMs)}ms total)`);
      resolveAuthGate();
      return;
    } catch {
      logWarn("auth", "Auto re-login with saved credentials failed — credentials may have changed");
      await clearSavedCredentials();
    }
  }

  // 6. No valid stored token or saved credentials — try dev auto-login as FALLBACK (dev mode only)
  const devEmail = import.meta.env.VITE_DEV_EMAIL;
  const devPassword = import.meta.env.VITE_DEV_PASSWORD;
  if (devEmail && devPassword) {
    logInfo("auth", `Attempting dev auto-login as ${devEmail}...`);
    try {
      const token = await login(devEmail, devPassword);
      _token = token;
      await saveTokenToStore(token);
      try {
        localStorage.setItem("bizforge-auth-token", token);
      } catch {
        // Non-fatal
      }
      logInfo("auth", `Dev auto-login successful (${Math.round(performance.now() - authStartMs)}ms total)`);
    } catch {
      logWarn("auth", "Dev auto-login failed — will redirect to /auth");
    }
  } else {
    logInfo("auth", "No token available — user must log in manually");
  }

  resolveAuthGate();
}

// ── Typed Error ───────────────────────────────────────────────────────────────

export class ApiError extends Error {
  readonly status: number;
  readonly code: string | undefined;
  readonly body: unknown;

  constructor(status: number, message: string, body?: unknown) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.code =
      typeof body === "object" && body !== null && "code" in body
        ? String((body as Record<string, unknown>).code)
        : undefined;
    this.body = body;
  }
}

// ── Retry with Backoff ──────────────────────────────────────────────────────

const DEFAULT_RETRY = { maxRetries: 2, backoffMs: 500, maxBackoff: 5000 };

async function withRetry<T>(
  fn: () => Promise<T>,
  config = DEFAULT_RETRY,
): Promise<T> {
  let lastError: Error = new Error("No attempts made");
  for (let attempt = 0; attempt < config.maxRetries; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error as Error;
      if (error instanceof ApiError && error.status === 429) {
        const retryAfter =
          typeof (error.body as Record<string, unknown>)?.retry_after ===
          "number"
            ? ((error.body as Record<string, unknown>).retry_after as number) *
              1000
            : config.backoffMs * 2 ** attempt;
        const delay = Math.min(retryAfter, config.maxBackoff);
        logWarn("net", `429 rate-limited — retrying in ${delay}ms (attempt ${attempt + 1}/${config.maxRetries})`);
        await new Promise((r) => setTimeout(r, delay));
        continue;
      }
      if (error instanceof ApiError && error.status < 500) throw error;
      const delay = Math.min(
        config.backoffMs * 2 ** attempt,
        config.maxBackoff,
      );
      logWarn("net", `Request failed (${lastError.message}) — retrying in ${delay}ms (attempt ${attempt + 1}/${config.maxRetries})`);
      await new Promise((r) => setTimeout(r, delay));
    }
  }
  logError("net", `All ${config.maxRetries} retry attempts exhausted: ${lastError.message}`);
  throw lastError;
}

// ── Response Cache ──────────────────────────────────────────────────────────

const responseCache = new Map<string, { data: unknown; timestamp: number }>();
const CACHE_TTL: Record<string, number> = {
  "/settings": 60_000,
  "/agents": 30_000,
  "/dashboard": 15_000,
  "/schedules": 30_000,
  "/costs": 30_000,
  "/projects": 10_000,
  "/phases": 10_000,
};

function getCacheTTL(path: string): number {
  for (const [prefix, ttl] of Object.entries(CACHE_TTL)) {
    if (path.startsWith(prefix)) return ttl;
  }
  return 0;
}

function getCached<T>(path: string): T | null {
  const entry = responseCache.get(path);
  if (!entry) return null;
  if (Date.now() - entry.timestamp > getCacheTTL(path)) {
    responseCache.delete(path);
    return null;
  }
  return entry.data as T;
}

function setCache(path: string, data: unknown): void {
  if (getCacheTTL(path) > 0)
    responseCache.set(path, { data, timestamp: Date.now() });
}

export function clearCache(): void {
  responseCache.clear();
}

// ── Offline Queue ───────────────────────────────────────────────────────────

const OFFLINE_QUEUE_KEY = "bizforge-offline-queue";
const OFFLINE_QUEUE_MAX = 100;
const OFFLINE_QUEUE_TTL_MS = 24 * 60 * 60 * 1000; // 24 hours

function loadQueueFromStorage(): QueuedRequest[] {
  if (typeof localStorage === "undefined") return [];
  try {
    const raw = localStorage.getItem(OFFLINE_QUEUE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as QueuedRequest[];
    const cutoff = Date.now() - OFFLINE_QUEUE_TTL_MS;
    return parsed.filter((r) => r.timestamp > cutoff);
  } catch {
    return [];
  }
}

function saveQueueToStorage(queue: QueuedRequest[]): void {
  if (typeof localStorage === "undefined") return;
  try {
    localStorage.setItem(OFFLINE_QUEUE_KEY, JSON.stringify(queue));
  } catch {
    // Storage full or unavailable — non-fatal
  }
}

function clearQueueFromStorage(): void {
  if (typeof localStorage === "undefined") return;
  try {
    localStorage.removeItem(OFFLINE_QUEUE_KEY);
  } catch {
    // Non-fatal
  }
}

const offlineQueue: QueuedRequest[] = loadQueueFromStorage();
export function getOfflineQueue(): readonly QueuedRequest[] {
  return offlineQueue;
}
export function getOfflineQueueSize(): number {
  return offlineQueue.length;
}

export async function flushOfflineQueue(): Promise<{
  succeeded: number;
  failed: number;
}> {
  if (offlineQueue.length === 0) return { succeeded: 0, failed: 0 };
  logInfo("net", `Flushing offline queue (${offlineQueue.length} items)...`);
  let succeeded = 0,
    failed = 0;
  while (offlineQueue.length > 0) {
    const req = offlineQueue[0];
    try {
      await request(req.path, {
        method: req.method,
        body: req.body ? JSON.stringify(req.body) : undefined,
      });
      offlineQueue.shift();
      succeeded++;
    } catch {
      failed++;
      break;
    }
  }
  if (offlineQueue.length === 0) {
    clearQueueFromStorage();
  } else {
    saveQueueToStorage(offlineQueue);
  }
  logInfo("net", `Offline queue flush: ${succeeded} succeeded, ${failed} failed, ${offlineQueue.length} remaining`);
  return { succeeded, failed };
}

function queueForOffline(method: string, path: string, body?: unknown): void {
  if (offlineQueue.length >= OFFLINE_QUEUE_MAX) {
    // Discard the oldest item to make room
    offlineQueue.shift();
  }
  offlineQueue.push({
    id: crypto.randomUUID(),
    method,
    path,
    body,
    timestamp: Date.now(),
  });
  saveQueueToStorage(offlineQueue);
}

// ── Runtime Re-authentication ─────────────────────────────────────────────────
// When a 401 occurs at runtime (token expired while the app is open), attempt
// to silently re-login with saved credentials. A singleton promise ensures that
// if 30+ stores all hit 401 simultaneously, only one re-login attempt is made.

let _reAuthPromise: Promise<boolean> | null = null;
let _redirectingToAuth = false;

async function attemptReAuth(): Promise<boolean> {
  if (_reAuthPromise !== null) return _reAuthPromise;
  _reAuthPromise = _doReAuth();
  const result = await _reAuthPromise;
  _reAuthPromise = null;
  return result;
}

async function _doReAuth(): Promise<boolean> {
  await clearToken();

  const creds = await restoreCredentials();
  if (creds === null) {
    logWarn("auth", "No saved credentials — cannot re-authenticate silently");
    redirectToAuth();
    return false;
  }

  logInfo("auth", `Runtime 401 — attempting silent re-login as ${creds.email}...`);
  try {
    const token = await login(creds.email, creds.password);
    _token = token;
    await persistToken(token);
    logInfo("auth", "Silent re-login successful — resuming requests");
    return true;
  } catch {
    logWarn("auth", "Silent re-login failed — redirecting to login page");
    await clearSavedCredentials();
    redirectToAuth();
    return false;
  }
}

function redirectToAuth(): void {
  if (_redirectingToAuth) return;
  _redirectingToAuth = true;
  if (typeof window !== "undefined") {
    window.location.href = "/auth";
  }
}

export function resetAuthRedirect(): void {
  _redirectingToAuth = false;
}

// ── Core Request ──────────────────────────────────────────────────────────────

async function doFetch<T>(
  path: string,
  options: RequestInit,
  retried = false,
): Promise<T> {
  const url = `${BASE_URL}${API_PREFIX}${path}`;
  const method = (options.method ?? "GET").toUpperCase();
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    Accept: "application/json",
    ...(options.headers as Record<string, string> | undefined),
  };
  if (_token) headers["Authorization"] = `Bearer ${_token}`;

  const fetchStart = performance.now();
  logInfo("net", `${method} ${path}${retried ? " (retry)" : ""}`);

  const response = await fetch(url, {
    ...options,
    headers,
    signal: options.signal ?? AbortSignal.timeout(8_000),
  });

  const elapsed = Math.round(performance.now() - fetchStart);

  if (response.status === 401 && !retried) {
    logWarn("auth", `401 on ${path} — attempting re-authentication`);
    const reAuthed = await attemptReAuth();
    if (reAuthed) {
      return doFetch<T>(path, options, true);
    }
    throw new ApiError(401, "unauthorized");
  }

  if (!response.ok) {
    let body: unknown;
    const rawText = await response.text();
    try {
      body = JSON.parse(rawText);
    } catch {
      body = rawText;
    }
    const message =
      typeof body === "object" && body !== null && "error" in body
        ? String((body as Record<string, unknown>).error)
        : `HTTP ${response.status}: ${path}`;
    logError("net", `${method} ${path} → ${response.status} (${elapsed}ms): ${message}`);
    throw new ApiError(response.status, message, body);
  }

  logInfo("net", `${method} ${path} → ${response.status} (${elapsed}ms)`);
  if (response.status === 204) return undefined as T;
  return response.json() as Promise<T>;
}

// ── LLM Inspector Hooks ──────────────────────────────────────────────────────

export interface LlmInterceptEvent {
  requestId: string;
  path: string;
  method: string;
  direction: "sent" | "received";
  payload: unknown;
  durationMs?: number;
  status: "pending" | "success" | "error";
  error?: string;
}

type LlmInterceptListener = (event: LlmInterceptEvent) => void;

const _llmListeners: LlmInterceptListener[] = [];

const LLM_PATH_PATTERNS: RegExp[] = [
  /^\/sessions\/[^/]+\/message$/,
  /^\/conversations\/[^/]+\/messages$/,
  /^\/providers\/[^/]+\/test$/,
  /^\/providers\/discover-models$/,
  /^\/providers\/[^/]+\/discover-models$/,
  /^\/reports\/[^/]+\/generate$/,
  /^\/agents\/[^/]+\/heartbeat$/,
  /^\/agents\/[^/]+\/dispatch$/,
];

function isLlmPath(path: string): boolean {
  return LLM_PATH_PATTERNS.some((re) => re.test(path));
}

export function onLlmIntercept(listener: LlmInterceptListener): () => void {
  _llmListeners.push(listener);
  return () => {
    const idx = _llmListeners.indexOf(listener);
    if (idx !== -1) _llmListeners.splice(idx, 1);
  };
}

function emitLlmIntercept(event: LlmInterceptEvent): void {
  for (const listener of _llmListeners) {
    try {
      listener(event);
    } catch {
      // Listeners must not break the request pipeline
    }
  }
}

async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const gateStart = performance.now();
  await _authPromise;
  const gateMs = Math.round(performance.now() - gateStart);
  if (gateMs > 50) {
    logWarn("auth", `Auth gate blocked ${(options.method ?? "GET").toUpperCase()} ${path} for ${gateMs}ms`);
  }

  if (_transitionPromise) {
    logInfo("net", `Waiting for mock→real transition before ${path}...`);
    await _transitionPromise;
  }

  const isLlm = isLlmPath(path);
  const reqId = isLlm ? crypto.randomUUID() : "";
  const reqStart = isLlm ? performance.now() : 0;

  if (isLlm) {
    let body: unknown;
    try {
      body = options.body !== undefined ? JSON.parse(options.body as string) : undefined;
    } catch {
      body = options.body;
    }
    emitLlmIntercept({
      requestId: reqId,
      path,
      method: (options.method ?? "GET").toUpperCase(),
      direction: "sent",
      payload: body,
      status: "pending",
    });
  }

  // Guard: if there is no auth token, attempt silent re-login with saved
  // credentials before failing.
  if (_token === null) {
    const reAuthed = await attemptReAuth();
    if (!reAuthed) {
      throw new ApiError(401, "unauthorized");
    }
  }

  const method = (options.method ?? "GET").toUpperCase();

  // For mutating requests, generate an idempotency key once so retries reuse
  // the same key and the backend can deduplicate them.
  if (method !== "GET") {
    const existingHeaders = (options.headers ?? {}) as Record<string, string>;
    if (!existingHeaders["Idempotency-Key"]) {
      options = {
        ...options,
        headers: {
          ...existingHeaders,
          "Idempotency-Key": crypto.randomUUID(),
        },
      };
    }
  }

  if (method === "GET") {
    const cached = getCached<T>(path);
    if (cached !== null) {
      logInfo("net", `CACHE HIT ${path}`);
      return cached;
    }
    try {
      const data = await withRetry(() => doFetch<T>(path, options));
      setCache(path, data);
      return data;
    } catch (error) {
      throw error;
    }
  }

  try {
    const data = await withRetry(() => doFetch<T>(path, options));
    if (isLlm) {
      emitLlmIntercept({
        requestId: reqId,
        path,
        method,
        direction: "received",
        payload: data,
        durationMs: Math.round(performance.now() - reqStart),
        status: "success",
      });
    }
    return data;
  } catch (error) {
    if (isLlm) {
      emitLlmIntercept({
        requestId: reqId,
        path,
        method,
        direction: "received",
        payload: undefined,
        durationMs: Math.round(performance.now() - reqStart),
        status: "error",
        error: error instanceof Error ? error.message : String(error),
      });
    }
    if (!(error instanceof ApiError)) {
      logWarn("net", `Network error on ${method} ${path} — queued for offline sync`);
      const body =
        options.body !== undefined
          ? JSON.parse(options.body as string)
          : undefined;
      queueForOffline(method, path, body);
    }
    throw error;
  }
}

// ── Auth ─────────────────────────────────────────────────────────────────────

export interface AuthStatus {
  has_users: boolean;
  registration_open: boolean;
}

export interface AuthUser {
  id: string;
  name: string;
  email: string;
  role: string;
}

export interface AuthWorkspace {
  id: string;
  name: string;
}

export interface RegisterResponse {
  token: string;
  user: AuthUser;
  workspace?: AuthWorkspace;
}

export interface LoginResponse {
  token: string;
  user: AuthUser;
}

export const auth = {
  status: async (): Promise<AuthStatus> => {
    const res = await fetch(`${BASE_URL}${API_PREFIX}/auth/status`, {
      signal: AbortSignal.timeout(5000),
    });
    if (!res.ok) throw new ApiError(res.status, "Failed to fetch auth status");
    return res.json() as Promise<AuthStatus>;
  },

  register: async (data: {
    name: string;
    email: string;
    password: string;
  }): Promise<RegisterResponse> => {
    const res = await fetch(`${BASE_URL}${API_PREFIX}/auth/register`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(data),
    });
    if (!res.ok) {
      let body: unknown;
      try {
        body = await res.json();
      } catch {
        body = await res.text();
      }
      let message = "Registration failed";
      if (typeof body === "object" && body !== null) {
        const obj = body as Record<string, unknown>;
        if ("details" in obj && typeof obj.details === "object" && obj.details !== null) {
          const details = obj.details as Record<string, string[]>;
          const firstField = Object.keys(details)[0];
          if (firstField !== undefined) {
            message = `${firstField} ${details[firstField][0]}`;
          }
        } else if ("error" in obj) {
          message = String(obj.error);
        }
      }
      throw new ApiError(res.status, message, body);
    }
    return res.json() as Promise<RegisterResponse>;
  },

  login: async (data: {
    email: string;
    password: string;
  }): Promise<LoginResponse> => {
    const res = await fetch(`${BASE_URL}${API_PREFIX}/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(data),
    });
    if (!res.ok) {
      let body: unknown;
      try {
        body = await res.json();
      } catch {
        body = await res.text();
      }
      const message =
        typeof body === "object" && body !== null && "error" in body
          ? String((body as Record<string, unknown>).error)
          : "Login failed";
      throw new ApiError(res.status, message, body);
    }
    return res.json() as Promise<LoginResponse>;
  },
};

/**
 * Persist an auth token to both Tauri store and localStorage.
 * Safe to call in browser-only context (Tauri path will no-op gracefully).
 */
export async function persistToken(token: string): Promise<void> {
  _token = token;
  await saveTokenToStore(token);
  try {
    localStorage.setItem("bizforge-auth-token", token);
  } catch {
    // Non-fatal
  }
  // Mirror critical session state to the Tauri disk store so it survives
  // webview localStorage resets between app launches.
  await saveSessionToStore();
}

/**
 * Clear the stored auth token from all persistence layers.
 */
export async function clearToken(): Promise<void> {
  _token = null;
  try {
    const { load: loadStore } = await import("@tauri-apps/plugin-store");
    const store = await loadStore("store.json", {
      autoSave: true,
      defaults: {},
    });
    await store.delete("authToken");
    await store.save();
  } catch {
    // Not in Tauri or store unavailable
  }
  try {
    localStorage.removeItem("bizforge-auth-token");
  } catch {
    // Non-fatal
  }
}

// ── Session State Persistence (Tauri Store) ──────────────────────────────────
// Critical session state (onboarding, display name) must survive webview
// localStorage resets. These helpers mirror the data to the Tauri disk-backed
// store alongside the auth token.

const SESSION_KEYS = [
  "bizforge-onboarding-complete",
  "bizforge-onboarding",
  "bizforge-display-name",
  "bizforge-saved-email",
] as const;

async function saveSessionToStore(): Promise<void> {
  try {
    const { load: loadStore } = await import("@tauri-apps/plugin-store");
    const store = await loadStore("store.json", { autoSave: true, defaults: {} });
    for (const key of SESSION_KEYS) {
      const val = localStorage.getItem(key);
      if (val !== null) {
        await store.set(key, val);
      }
    }
    await store.save();
  } catch {
    // Not in Tauri or store unavailable
  }
}

async function restoreSessionFromStore(): Promise<void> {
  try {
    const { load: loadStore } = await import("@tauri-apps/plugin-store");
    const store = await loadStore("store.json", { autoSave: true, defaults: {} });
    for (const key of SESSION_KEYS) {
      const existing = localStorage.getItem(key);
      if (existing !== null) continue;
      const val = await store.get<string>(key);
      if (val !== null && val !== undefined) {
        localStorage.setItem(key, val);
      }
    }
  } catch {
    // Not in Tauri or store unavailable
  }
}

export { saveSessionToStore, restoreSessionFromStore };

// ── Credential Persistence (Auto Re-login) ──────────────────────────────────
// Save login credentials to the Tauri disk store so the app can automatically
// re-authenticate when the token expires or localStorage is cleared between
// app launches. Credentials are stored only on disk via Tauri plugin-store
// (never in localStorage) to reduce exposure surface.

interface SavedCredentials {
  email: string;
  password: string;
}

async function persistCredentials(email: string, password: string): Promise<void> {
  try {
    localStorage.setItem("bizforge-saved-email", email);
  } catch {
    // Non-fatal
  }
  try {
    const { load: loadStore } = await import("@tauri-apps/plugin-store");
    const store = await loadStore("store.json", { autoSave: true, defaults: {} });
    await store.set("savedCredentials", JSON.stringify({ email, password }));
    await store.save();
    logInfo("auth", "Credentials saved to Tauri store for auto re-login");
  } catch {
    // Not in Tauri — fall back to localStorage (obfuscated, not secure encryption)
    try {
      localStorage.setItem(
        "bizforge-saved-credentials",
        btoa(JSON.stringify({ email, password })),
      );
    } catch {
      // Non-fatal
    }
  }
}

async function restoreCredentials(): Promise<SavedCredentials | null> {
  // Try Tauri store first (preferred — survives webview resets)
  try {
    const { load: loadStore } = await import("@tauri-apps/plugin-store");
    const store = await loadStore("store.json", { autoSave: true, defaults: {} });
    const raw = await store.get<string>("savedCredentials");
    if (raw !== null && raw !== undefined) {
      const parsed = JSON.parse(raw) as SavedCredentials;
      if (parsed.email && parsed.password) {
        return parsed;
      }
    }
  } catch {
    // Not in Tauri — try localStorage fallback
  }

  // localStorage fallback (base64-obfuscated)
  try {
    const raw = localStorage.getItem("bizforge-saved-credentials");
    if (raw !== null) {
      const parsed = JSON.parse(atob(raw)) as SavedCredentials;
      if (parsed.email && parsed.password) {
        return parsed;
      }
    }
  } catch {
    // Non-fatal
  }

  return null;
}

async function clearSavedCredentials(): Promise<void> {
  try {
    localStorage.removeItem("bizforge-saved-credentials");
    localStorage.removeItem("bizforge-saved-email");
  } catch {
    // Non-fatal
  }
  try {
    const { load: loadStore } = await import("@tauri-apps/plugin-store");
    const store = await loadStore("store.json", { autoSave: true, defaults: {} });
    await store.delete("savedCredentials");
    await store.save();
  } catch {
    // Not in Tauri or store unavailable
  }
}

export { persistCredentials, clearSavedCredentials };

// ── Health ────────────────────────────────────────────────────────────────────

export const health = {
  get: async (): Promise<HealthResponse> => {
    const healthStart = performance.now();
    try {
      const res = await fetch(`${BASE_URL}${API_PREFIX}/health`, {
        headers: { Accept: "application/json" },
        signal: AbortSignal.timeout(3000),
      });
      if (!res.ok) throw new ApiError(res.status, "Health check failed");
      const data = await res.json() as HealthResponse;
      logInfo("health", `Health OK: status=${data.status}, version=${data.version}, agents_active=${data.agents_active ?? 0} (${Math.round(performance.now() - healthStart)}ms)`);
      return data;
    } catch (error) {
      if (error instanceof ApiError) {
        logError("health", `Health check returned ${error.status}: ${error.message}`);
        throw error;
      }
      logWarn("health", `Health probe failed (${Math.round(performance.now() - healthStart)}ms)`, (error as Error).message);
      throw new ApiError(0, "Backend unreachable");
    }
  },
};

// ── Dashboard ─────────────────────────────────────────────────────────────────

export const dashboard = {
  get: () => request<DashboardData>("/dashboard"),
  recentAiCalls: (limit = 10) =>
    request<{ data: import("$api/types").RecentAiCall[] }>(
      `/dashboard/recent-ai-calls?limit=${limit}`,
    ),
};

// ── Agents ────────────────────────────────────────────────────────────────────

/** Map backend agent statuses to frontend equivalents */
function mapAgentStatus(status: string): AgentStatus {
  switch (status) {
    case "active":
      return "idle";
    case "working":
      return "running";
    default:
      return status as AgentStatus;
  }
}

function mapAgentStatuses(agent: BizforgeAgent): BizforgeAgent {
  return { ...agent, status: mapAgentStatus(agent.status) };
}

export const agents = {
  list: async (workspaceId?: string): Promise<BizforgeAgent[]> => {
    const qs = workspaceId ? `?workspace_id=${workspaceId}` : "";
    const data = await request<{ agents: BizforgeAgent[]; count: number }>(
      `/agents${qs}`,
    );
    return (data.agents ?? []).map(mapAgentStatuses);
  },
  get: async (id: string): Promise<BizforgeAgent> => {
    const agent = await request<BizforgeAgent>(`/agents/${id}`);
    return mapAgentStatuses(agent);
  },
  create: async (body: AgentCreateRequest): Promise<BizforgeAgent> => {
    const data = await request<{ agent: BizforgeAgent }>("/agents", {
      method: "POST",
      body: JSON.stringify(body),
    });
    // Backend wraps response in {agent: ...}; mock returns bare agent
    return mapAgentStatuses(data.agent ?? (data as unknown as BizforgeAgent));
  },
  update: async (
    id: string,
    body: Partial<AgentCreateRequest>,
  ): Promise<BizforgeAgent> => {
    const data = await request<{ agent: BizforgeAgent }>(`/agents/${id}`, {
      method: "PATCH",
      body: JSON.stringify(body),
    });
    return mapAgentStatuses(data.agent ?? (data as unknown as BizforgeAgent));
  },
  action: async (id: string, action: string): Promise<BizforgeAgent> => {
    const data = await request<{ agent: BizforgeAgent }>(
      `/agents/${id}/${action}`,
      { method: "POST" },
    );
    return mapAgentStatuses(data.agent ?? (data as unknown as BizforgeAgent));
  },
  resume: async (id: string): Promise<BizforgeAgent> => {
    const data = await request<{ agent: BizforgeAgent }>(`/agents/${id}/resume`, {
      method: "POST",
    });
    return mapAgentStatuses(data.agent ?? (data as unknown as BizforgeAgent));
  },
  terminate: (id: string) =>
    request<void>(`/agents/${id}`, { method: "DELETE" }),
  hierarchy: () => request<{ hierarchy: unknown[] }>("/agents/hierarchy"),
  runs: (id: string) =>
    request<{ runs: unknown[]; total: number }>(`/agents/${id}/runs`),
  inbox: (id: string) =>
    request<{ items: unknown[]; pending_count: number }>(`/agents/${id}/inbox`),
};

// ── Sessions ──────────────────────────────────────────────────────────────────

export const sessions = {
  list: async (workspaceId?: string): Promise<Session[]> => {
    const qs = workspaceId ? `?workspace_id=${workspaceId}` : "";
    const data = await request<{ sessions: Session[]; count: number }>(
      `/sessions${qs}`,
    );
    return data.sessions ?? [];
  },
  get: (id: string) => request<Session>(`/sessions/${id}`),
  create: (body: { agent_id: string; title?: string }) =>
    request<Session>("/sessions", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  delete: (id: string) =>
    request<void>(`/sessions/${id}`, { method: "DELETE" }),
};

// ── Session Chain ─────────────────────────────────────────────────────────────

export const sessionChain = {
  get: (sessionId: string) =>
    request<SessionChain>(`/sessions/${sessionId}/chain`),
  compact: (sessionId: string) =>
    request<void>(`/sessions/${sessionId}/compact`, { method: "POST" }),
};

// ── Dispatch ──────────────────────────────────────────────────────────────────

export const dispatch = {
  preview: (description: string) =>
    request<DispatchPreview>("/dispatch/preview", {
      method: "POST",
      body: JSON.stringify({ description }),
    }),
  routes: () => request<{ routes: DispatchRoute[] }>("/dispatch/routes"),
};

// ── Delegations ───────────────────────────────────────────────────────────────

export const delegations = {
  create: (body: {
    parent_task_id: string;
    description: string;
    adapter?: string;
    agent_id?: string;
  }) =>
    request<Record<string, unknown>>("/delegations", {
      method: "POST",
      body: JSON.stringify(body),
    }),
};

// ── Messages ──────────────────────────────────────────────────────────────────

export const messages = {
  list: async (sessionId: string) => {
    const data = await request<{
      messages: import("./types").Message[];
      count: number;
    }>(`/sessions/${sessionId}/transcript`);
    return data.messages ?? [];
  },
  send: (body: SendMessageRequest) =>
    request<SendMessageResponse>(`/sessions/${body.session_id}/message`, {
      method: "POST",
      body: JSON.stringify({
        ...body,
        stream: true,
        attached_files: body.attached_files ?? undefined,
      }),
    }),
};

// ── Sprints ───────────────────────────────────────────────────────────────────

export const sprints = {
  list: async (projectId?: string): Promise<import("./types").Sprint[]> => {
    const qs = projectId ? `?project_id=${projectId}` : "";
    const data = await request<{ sprints: import("./types").Sprint[] }>(`/sprints${qs}`);
    return data.sprints ?? [];
  },
  get: (id: string) => request<{ sprint: import("./types").Sprint }>(`/sprints/${id}`),
  create: (body: {
    name: string;
    project_id: string;
    objective?: string;
    start_date?: string;
    end_date?: string;
    velocity_target?: number;
  }) =>
    request<{ sprint: import("./types").Sprint }>("/sprints", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  update: (id: string, body: Partial<import("./types").Sprint>) =>
    request<{ sprint: import("./types").Sprint }>(`/sprints/${id}`, {
      method: "PATCH",
      body: JSON.stringify(body),
    }),
  delete: (id: string) =>
    request<{ ok: boolean }>(`/sprints/${id}`, { method: "DELETE" }),
  start: (id: string) =>
    request<{ sprint: import("./types").Sprint }>(`/sprints/${id}/start`, { method: "POST" }),
  complete: (id: string) =>
    request<{ sprint: import("./types").Sprint; velocity: number }>(`/sprints/${id}/complete`, {
      method: "POST",
    }),
  assignTasks: (sprintId: string, taskIds: string[]) =>
    request<{ ok: boolean; assigned: number }>(`/sprints/${sprintId}/assign-tasks`, {
      method: "POST",
      body: JSON.stringify({ task_ids: taskIds }),
    }),
  unassignTasks: (sprintId: string, taskIds: string[]) =>
    request<{ ok: boolean; unassigned: number }>(`/sprints/${sprintId}/unassign-tasks`, {
      method: "POST",
      body: JSON.stringify({ task_ids: taskIds }),
    }),
};

// ── Schedules ─────────────────────────────────────────────────────────────────

export const schedules = {
  list: async (workspaceId?: string): Promise<Schedule[]> => {
    const qs = workspaceId ? `?workspace_id=${workspaceId}` : "";
    const data = await request<{ schedules: Schedule[] }>(`/schedules${qs}`);
    return data.schedules ?? [];
  },
  get: (id: string) => request<Schedule>(`/schedules/${id}`),
  create: (body: { agent_id: string; cron: string; context?: string }) =>
    request<Schedule>("/schedules", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  update: (
    id: string,
    body: Partial<{ cron: string; context: string; enabled: boolean }>,
  ) =>
    request<Schedule>(`/schedules/${id}`, {
      method: "PATCH",
      body: JSON.stringify(body),
    }),
  delete: (id: string) =>
    request<void>(`/schedules/${id}`, { method: "DELETE" }),
  runs: (id: string) =>
    request<{ runs: HeartbeatRun[] }>(`/schedules/${id}/runs`),
  triggerNow: (id: string) =>
    request<HeartbeatRun>(`/schedules/${id}/trigger`, { method: "POST" }),
  queue: () => request<{ queue: unknown[] }>("/schedules/queue"),
  wakeAll: () =>
    request<{ ok: boolean; enabled_count: number }>("/schedules/wake-all", {
      method: "POST",
    }),
  pauseAll: () =>
    request<{ ok: boolean; paused_count: number }>("/schedules/pause-all", {
      method: "POST",
    }),
};

// ── Workflows ─────────────────────────────────────────────────────────────────

export const workflows = {
  list: async (workspaceId?: string) => {
    const qs = workspaceId ? `?workspace_id=${workspaceId}` : "";
    const data = await request<{ workflows: import("./types").Workflow[] }>(
      `/workflows${qs}`,
    );
    return data.workflows ?? [];
  },
  get: (id: string) =>
    request<{ workflow: import("./types").Workflow }>(`/workflows/${id}`).then(
      (d) => d.workflow,
    ),
  create: (body: import("./types").WorkflowCreateRequest) =>
    request<{ workflow: import("./types").Workflow }>("/workflows", {
      method: "POST",
      body: JSON.stringify(body),
    }).then((d) => d.workflow),
  update: (
    id: string,
    body: Partial<import("./types").WorkflowCreateRequest>,
  ) =>
    request<{ workflow: import("./types").Workflow }>(`/workflows/${id}`, {
      method: "PATCH",
      body: JSON.stringify(body),
    }).then((d) => d.workflow),
  delete: (id: string) =>
    request<void>(`/workflows/${id}`, { method: "DELETE" }),
  fetchSteps: (workflowId: string) =>
    request<{ steps: import("./types").WorkflowStep[] }>(
      `/workflows/${workflowId}/steps`,
    ).then((d) => d.steps ?? []),
  addStep: (
    workflowId: string,
    body: Partial<import("./types").WorkflowStep>,
  ) =>
    request<{ step: import("./types").WorkflowStep }>(
      `/workflows/${workflowId}/steps`,
      { method: "POST", body: JSON.stringify(body) },
    ).then((d) => d.step),
  removeStep: (workflowId: string, stepId: string) =>
    request<void>(`/workflows/${workflowId}/steps/${stepId}`, {
      method: "DELETE",
    }),
  fetchRuns: (workflowId: string) =>
    request<{ runs: import("./types").WorkflowRun[] }>(
      `/workflows/${workflowId}/runs`,
    ).then((d) => d.runs ?? []),
  triggerRun: (workflowId: string, input?: Record<string, unknown>) =>
    request<{ run: import("./types").WorkflowRun }>(
      `/workflows/${workflowId}/trigger`,
      { method: "POST", body: JSON.stringify({ input: input ?? {} }) },
    ).then((d) => d.run),
};

// ── Tasks (formerly Issues) ───────────────────────────────────────────────────

export const tasks = {
  list: async (workspaceId?: string): Promise<Task[]> => {
    const qs = workspaceId ? `?workspace_id=${workspaceId}` : "";
    const data = await request<{ tasks: Task[] }>(`/tasks${qs}`);
    return data.tasks ?? [];
  },
  get: (id: string) => request<Task>(`/tasks/${id}`),
  create: (body: Partial<Task>) =>
    request<Task>("/tasks", { method: "POST", body: JSON.stringify(body) }),
  update: (id: string, body: Partial<Task>) =>
    request<Task>(`/tasks/${id}`, {
      method: "PATCH",
      body: JSON.stringify(body),
    }),
  delete: (id: string) => request<void>(`/tasks/${id}`, { method: "DELETE" }),
  dispatch: (taskId: string) =>
    request<{ ok: boolean; message: string }>(`/tasks/${taskId}/dispatch`, {
      method: "POST",
    }),
  assign: (id: string, agentId: string) =>
    request<void>(`/tasks/${id}/assign`, {
      method: "POST",
      body: JSON.stringify({ agent_id: agentId }),
    }),
  comments: (id: string) =>
    request<{ comments: unknown[] }>(`/tasks/${id}/comments`),
  addComment: (id: string, body: string) =>
    request<void>(`/tasks/${id}/comments`, {
      method: "POST",
      body: JSON.stringify({ body }),
    }),
  checkout: (id: string) =>
    request<void>(`/tasks/${id}/checkout`, { method: "POST" }),
};

/** @deprecated Use tasks instead */
export const issues = tasks;

// ── Phases (formerly Goals) ──────────────────────────────────────────────────

export const phases = {
  list: async (projectId: string): Promise<PhaseTreeNode[]> => {
    const data = await request<{ phases: PhaseTreeNode[] }>(
      `/projects/${projectId}/phases`,
    );
    return data.phases ?? [];
  },
  get: (id: string) => request<{ phase: Phase }>(`/phases/${id}`),
  create: (projectId: string, body: Partial<Phase>) =>
    request<Phase>("/phases", {
      method: "POST",
      body: JSON.stringify({ ...body, project_id: projectId }),
    }),
  update: (_projectId: string, id: string, body: Partial<Phase>) =>
    request<Phase>(`/phases/${id}`, {
      method: "PUT",
      body: JSON.stringify(body),
    }),
  delete: (id: string) => request<void>(`/phases/${id}`, { method: "DELETE" }),
  decompose: (
    phaseId: string,
    opts?: { max_tasks?: number; auto_assign?: boolean },
  ) =>
    request<{ status: string; phase_id: string; message: string }>(
      `/phases/${phaseId}/decompose`,
      {
        method: "POST",
        body: JSON.stringify(opts ?? {}),
      },
    ),
  ancestry: (id: string) =>
    request<{ ancestry: Phase[] }>(`/phases/${id}/ancestry`),
};

/** @deprecated Use phases instead */
export const goals = phases;

// ── Projects ──────────────────────────────────────────────────────────────────

export const projects = {
  list: async (workspaceId?: string): Promise<Project[]> => {
    const qs = workspaceId ? `?workspace_id=${workspaceId}` : "";
    const data = await request<{ projects: Project[] }>(`/projects${qs}`);
    return data.projects ?? [];
  },
  get: (id: string) => request<Project>(`/projects/${id}`),
  create: async (body: Partial<Project>): Promise<Project> => {
    const data = await request<{ project: Project } | Project>("/projects", {
      method: "POST",
      body: JSON.stringify(body),
    });
    if ("project" in data && typeof data.project === "object") {
      return data.project;
    }
    return data as Project;
  },
  update: (id: string, body: Partial<Project>) =>
    request<Project>(`/projects/${id}`, {
      method: "PATCH",
      body: JSON.stringify(body),
    }),
  delete: (id: string) =>
    request<void>(`/projects/${id}`, { method: "DELETE" }),
  workspaces: (id: string) =>
    request<{ workspaces: Workspace[] }>(`/projects/${id}/workspaces`),
  deliver: (id: string) =>
    request<{ report: DeliveryReport }>(`/projects/${id}/deliver`, { method: "POST" }),
  deliveryStatus: (id: string) =>
    request<{ readiness: DeliveryReadiness; last_report: DeliveryReport | null; project_status: string }>(
      `/projects/${id}/delivery-status`
    ),
  lifecycleTemplates: () =>
    request<{ templates: Array<{ id: string; name: string; config: Record<string, unknown> }> }>(
      `/projects/lifecycle-templates`
    ),
};

// ── ForgeMap ──────────────────────────────────────────────────────────────────

import type {
  ForgeMapDetection,
  ForgeMapScanResult,
  ForgeMapEntry,
} from './types';

export const forgemap = {
  detect: (projectId: string) =>
    request<{ detection: ForgeMapDetection }>(`/projects/${projectId}/forgemap/detect`, {
      method: 'POST',
    }),
  scan: (projectId: string, opts?: { write_headers?: boolean; session_id?: string }) =>
    request<{ scan: ForgeMapScanResult }>(`/projects/${projectId}/forgemap/scan`, {
      method: 'POST',
      body: JSON.stringify(opts ?? {}),
    }),
  index: (projectId: string) =>
    request<{ entries: ForgeMapEntry[] }>(`/projects/${projectId}/forgemap`),
  updateEntry: (projectId: string, filePath: string, updates: { content?: string; tags?: string[] }) =>
    request<{ entry: ForgeMapEntry }>(`/projects/${projectId}/forgemap/${encodeURIComponent(filePath)}`, {
      method: 'PATCH',
      body: JSON.stringify(updates),
    }),
  resolveExecutionOrder: (projectId: string) =>
    request<{ ok: boolean }>(`/projects/${projectId}/resolve-execution-order`, {
      method: 'POST',
    }),
  readyTasks: (projectId: string) =>
    request<{ tasks: import('./types').Task[] }>(`/projects/${projectId}/ready-tasks`),
};

// ── Costs ─────────────────────────────────────────────────────────────────────

export const costs = {
  summary: (workspaceId?: string) => {
    const qs = workspaceId ? `?workspace_id=${workspaceId}` : "";
    return request<CostSummary>(`/costs/summary${qs}`);
  },
  byAgent: (workspaceId?: string) => {
    const qs = workspaceId ? `?workspace_id=${workspaceId}` : "";
    return request<{ agents: AgentCostBreakdown[] }>(`/costs/by-agent${qs}`);
  },
  byModel: (workspaceId?: string) => {
    const qs = workspaceId ? `?workspace_id=${workspaceId}` : "";
    return request<{ models: ModelCostBreakdown[] }>(`/costs/by-model${qs}`);
  },
  policies: (workspaceId?: string) => {
    const qs = workspaceId ? `?workspace_id=${workspaceId}` : "";
    return request<{ policies: BudgetPolicy[] }>(`/budgets${qs}`);
  },
  incidents: (workspaceId?: string) => {
    const qs = workspaceId ? `?workspace_id=${workspaceId}` : "";
    return request<{ incidents: BudgetIncident[] }>(`/budgets/incidents${qs}`);
  },
  daily: (params?: { from?: string; to?: string; workspace_id?: string }) => {
    const qs = new URLSearchParams();
    if (params?.from) qs.set("from", params.from);
    if (params?.to) qs.set("to", params.to);
    if (params?.workspace_id) qs.set("workspace_id", params.workspace_id);
    const query = qs.toString() ? `?${qs.toString()}` : "";
    return request<{ points: Array<{ date: string; cost_cents: number }> }>(
      `/costs/daily${query}`,
    );
  },
  events: () => request<{ events: unknown[] }>("/costs/events"),
  upsertPolicy: (scopeType: string, scopeId: string, body: unknown) =>
    request<void>(`/budgets/${scopeType}/${scopeId}`, {
      method: "PUT",
      body: JSON.stringify(body),
    }),
  deletePolicy: (scopeType: string, scopeId: string) =>
    request<void>(`/budgets/${scopeType}/${scopeId}`, { method: "DELETE" }),
  resolveIncident: (id: string) =>
    request<void>(`/budgets/incidents/${id}/resolve`, { method: "POST" }),
};

// ── Activity ──────────────────────────────────────────────────────────────────

export const activity = {
  list: async (limit = 50): Promise<ActivityEvent[]> => {
    const data = await request<{ events: ActivityEvent[] }>(
      `/activity?limit=${limit}`,
    );
    return data.events ?? [];
  },
};

// ── Inbox ─────────────────────────────────────────────────────────────────────

export const inbox = {
  list: async (workspaceId?: string): Promise<InboxItem[]> => {
    const qs = workspaceId ? `?workspace_id=${workspaceId}` : "";
    const data = await request<{ messages: InboxItem[]; items: InboxItem[] }>(
      `/inbox${qs}`,
    );
    return data.messages ?? data.items ?? [];
  },
  action: (id: string, actionId: string) =>
    request<void>(`/inbox/${id}/action`, {
      method: "POST",
      body: JSON.stringify({ action_id: actionId }),
    }),
  dismiss: (id: string) =>
    request<void>(`/inbox/${id}/read`, { method: "POST" }),
  read: (id: string) =>
    request<void>(`/inbox/${id}/read`, { method: "POST" }),
  readAll: () => request<void>("/inbox/read-all", { method: "POST" }),
  reply: (id: string, body: string) =>
    request<void>(`/inbox/${id}/reply`, {
      method: "POST",
      body: JSON.stringify({ body }),
    }),
};

// ── Skills ────────────────────────────────────────────────────────────────────

export const skills = {
  list: async (workspaceId?: string): Promise<Skill[]> => {
    const qs = workspaceId ? `?workspace_id=${workspaceId}` : "";
    const data = await request<{ skills: Skill[] }>(`/skills${qs}`);
    return data.skills ?? [];
  },
  toggle: (id: string) =>
    request<Skill>(`/skills/${id}/toggle`, { method: "POST" }),
  get: (id: string) => request<{ skill: unknown }>(`/skills/${id}`),
  bulkEnable: (ids: string[]) =>
    request<void>("/skills/bulk-enable", {
      method: "POST",
      body: JSON.stringify({ ids }),
    }),
  bulkDisable: (ids: string[]) =>
    request<void>("/skills/bulk-disable", {
      method: "POST",
      body: JSON.stringify({ ids }),
    }),
  categories: () => request<{ categories: unknown[] }>("/skills/categories"),
  importSkill: (body: unknown) =>
    request<void>("/skills/import", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  inject: (id: string) =>
    request<void>(`/skills/${id}/inject`, { method: "POST" }),
};

// ── Webhooks ──────────────────────────────────────────────────────────────────

export const webhooks = {
  list: async (workspaceId?: string): Promise<Webhook[]> => {
    const qs = workspaceId ? `?workspace_id=${workspaceId}` : "";
    const data = await request<{ webhooks: Webhook[] }>(`/webhooks${qs}`);
    return data.webhooks ?? [];
  },
  create: (body: Partial<Webhook>) =>
    request<Webhook>("/webhooks", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  delete: (id: string) =>
    request<void>(`/webhooks/${id}`, { method: "DELETE" }),
  get: (id: string) => request<{ webhook: unknown }>(`/webhooks/${id}`),
  update: (id: string, body: unknown) =>
    request<void>(`/webhooks/${id}`, {
      method: "PATCH",
      body: JSON.stringify(body),
    }),
  test: (id: string) =>
    request<void>(`/webhooks/${id}/test`, { method: "POST" }),
  deliveries: (id: string) =>
    request<{ deliveries: unknown[] }>(`/webhooks/${id}/deliveries`),
};

// ── Alerts ────────────────────────────────────────────────────────────────────

export const alerts = {
  list: async (workspaceId?: string): Promise<AlertRule[]> => {
    const qs = workspaceId ? `?workspace_id=${workspaceId}` : "";
    const data = await request<{ rules: AlertRule[] }>(`/alerts/rules${qs}`);
    return data.rules ?? [];
  },
  create: (body: Partial<AlertRule>) =>
    request<AlertRule>("/alerts/rules", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  update: (id: string, body: Partial<AlertRule>) =>
    request<AlertRule>(`/alerts/rules/${id}`, {
      method: "PUT",
      body: JSON.stringify(body),
    }),
  delete: (id: string) =>
    request<void>(`/alerts/rules/${id}`, { method: "DELETE" }),
  get: (id: string) => request<{ rule: unknown }>(`/alerts/rules/${id}`),
  evaluate: () => request<void>("/alerts/evaluate", { method: "POST" }),
  history: () => request<{ history: unknown[] }>("/alerts/history"),
};

// ── Integrations ──────────────────────────────────────────────────────────────

export const integrations = {
  list: async (workspaceId?: string): Promise<Integration[]> => {
    const qs = workspaceId ? `?workspace_id=${workspaceId}` : "";
    const data = await request<{ integrations: Integration[] }>(
      `/integrations${qs}`,
    );
    return data.integrations ?? [];
  },
  pullAll: () => request<void>("/integrations/pull-all", { method: "POST" }),
  connect: (slug: string, config?: unknown) =>
    request<void>(`/integrations/${slug}/connect`, {
      method: "POST",
      body: config !== undefined ? JSON.stringify(config) : undefined,
    }),
  disconnect: (slug: string) =>
    request<void>(`/integrations/${slug}/disconnect`, { method: "POST" }),
  remove: (slug: string) =>
    request<void>(`/integrations/${slug}`, { method: "DELETE" }),
  status: (slug: string) => request<unknown>(`/integrations/${slug}/status`),
};

// ── Integration Bindings ─────────────────────────────────────────────────────

export const integrationBindings = {
  list: async (ownerType: IntegrationBindingOwner, ownerId: string): Promise<IntegrationBinding[]> => {
    const data = await request<{ bindings: IntegrationBinding[] }>(
      `/integration-bindings?owner_type=${encodeURIComponent(ownerType)}&owner_id=${encodeURIComponent(ownerId)}`,
    );
    return data.bindings ?? [];
  },
  create: async (params: IntegrationBindingCreateRequest): Promise<IntegrationBinding> => {
    const data = await request<{ binding: IntegrationBinding }>("/integration-bindings", {
      method: "POST",
      body: JSON.stringify(params),
    });
    return data.binding;
  },
  remove: (id: string) =>
    request<{ ok: boolean }>(`/integration-bindings/${id}`, { method: "DELETE" }),
  removeByOwnerAndProvider: (ownerType: IntegrationBindingOwner, ownerId: string, provider: string) =>
    request<{ ok: boolean }>(`/integration-bindings/by-owner/${ownerType}/${ownerId}/${provider}`, { method: "DELETE" }),
};

// ── Adapters ──────────────────────────────────────────────────────────────────

export const adapters = {
  list: async (): Promise<Adapter[]> => {
    try {
      const data = await request<{ adapters: Adapter[] }>("/adapters");
      return data.adapters ?? [];
    } catch (error) {
      if (error instanceof ApiError && error.status === 404) return [];
      throw error;
    }
  },
};

// ── Gateways ──────────────────────────────────────────────────────────────────

export const gateways = {
  list: async (): Promise<Gateway[]> => {
    const data = await request<{ gateways: Gateway[] }>("/gateways");
    return data.gateways ?? [];
  },
  show: (id: string) => request<Gateway>(`/gateways/${id}`),
  create: (body: Partial<Gateway>) =>
    request<Gateway>("/gateways", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  update: (id: string, body: Partial<Gateway>) =>
    request<Gateway>(`/gateways/${id}`, {
      method: "PUT",
      body: JSON.stringify(body),
    }),
  delete: (id: string) =>
    request<void>(`/gateways/${id}`, { method: "DELETE" }),
  probe: (id: string) =>
    request<Gateway>(`/gateways/${id}/probe`, { method: "POST" }),
};

// ── Providers ─────────────────────────────────────────────────────────────────

export const providers = {
  list: async (workspaceId?: string): Promise<AIProvider[]> => {
    const qs = workspaceId ? `?workspace_id=${workspaceId}` : "";
    const data = await request<{ providers: AIProvider[] }>(
      `/providers${qs}`,
    );
    return data.providers ?? [];
  },
  show: async (id: string): Promise<AIProvider> => {
    const data = await request<{ provider: AIProvider }>(`/providers/${id}`);
    return data.provider ?? (data as unknown as AIProvider);
  },
  create: async (body: AIProviderCreateRequest): Promise<AIProvider> => {
    const data = await request<{ provider: AIProvider }>("/providers", {
      method: "POST",
      body: JSON.stringify(body),
    });
    return data.provider ?? (data as unknown as AIProvider);
  },
  update: async (
    id: string,
    body: Partial<AIProviderCreateRequest>,
  ): Promise<AIProvider> => {
    const data = await request<{ provider: AIProvider }>(`/providers/${id}`, {
      method: "PUT",
      body: JSON.stringify(body),
    });
    return data.provider ?? (data as unknown as AIProvider);
  },
  delete: (id: string) =>
    request<void>(`/providers/${id}`, { method: "DELETE" }),
  test: async (
    id: string,
  ): Promise<{ provider: AIProvider; test_result: AIProviderTestResult }> => {
    return request<{ provider: AIProvider; test_result: AIProviderTestResult }>(
      `/providers/${id}/test`,
      { method: "POST" },
    );
  },

  /**
   * Fetch available models from a provider endpoint by proxying through the
   * backend. This avoids CORS issues with cloud providers (Anthropic, OpenAI,
   * Google, etc.) that reject browser-originated preflight requests.
   */
  fetchModels: async (
    endpoint: string,
    apiKey?: string,
    slug?: string,
  ): Promise<{ models: string[]; error?: string }> => {
    try {
      const result = await request<{
        status: string;
        models: string[];
        latency_ms?: number;
        error?: string;
      }>("/providers/discover-models", {
        method: "POST",
        body: JSON.stringify({
          endpoint: endpoint.replace(/\/+$/, ""),
          api_key: apiKey ?? "",
          slug: slug ?? "",
        }),
      });

      if (result.status === "connected") {
        return { models: result.models ?? [] };
      }

      return { models: [], error: result.error ?? "Connection failed" };
    } catch (e) {
      const err = e as Error;
      return { models: [], error: err.message };
    }
  },

  /**
   * Fetch models for an already-saved provider by ID. The backend reads the
   * stored API key from the database so it doesn't need to be sent from the client.
   */
  fetchModelsById: async (
    providerId: string,
  ): Promise<{ models: string[]; error?: string }> => {
    try {
      const result = await request<{
        status: string;
        models: string[];
        latency_ms?: number;
        error?: string;
      }>(`/providers/${providerId}/discover-models`, {
        method: "POST",
      });

      if (result.status === "connected") {
        return { models: result.models ?? [] };
      }

      return { models: [], error: result.error ?? "Connection failed" };
    } catch (e) {
      const err = e as Error;
      return { models: [], error: err.message };
    }
  },
};

// ── Documents ─────────────────────────────────────────────────────────────────

export const documents = {
  list: async (
    workspaceId?: string,
  ): Promise<{
    documents: Document[];
    tree: DocumentTreeNode[];
  }> => {
    const qs = workspaceId
      ? `?workspace_id=${encodeURIComponent(workspaceId)}`
      : "";
    const data = await request<{
      documents: Document[];
      tree: DocumentTreeNode[];
    }>(`/documents${qs}`);
    return { documents: data.documents ?? [], tree: data.tree ?? [] };
  },

  get: async (path: string): Promise<Document> => {
    const data = await request<Document | { document: Document }>(
      `/documents/${encodeDocPath(path)}`,
    );
    return "document" in data
      ? (data as { document: Document }).document
      : (data as Document);
  },

  create: async (doc: {
    title: string;
    path: string;
    content: string;
    format?: Document["format"];
    project_id?: string | null;
    workspace_id?: string;
  }): Promise<Document> => {
    const data = await request<Document | { document: Document }>(
      "/documents",
      { method: "POST", body: JSON.stringify(doc) },
    );
    return "document" in data
      ? (data as { document: Document }).document
      : (data as Document);
  },

  update: async (
    path: string,
    updates: { content?: string; title?: string; format?: Document["format"] },
  ): Promise<Document> => {
    const data = await request<Document | { document: Document }>(
      `/documents/${encodeDocPath(path)}`,
      { method: "PUT", body: JSON.stringify(updates) },
    );
    return "document" in data
      ? (data as { document: Document }).document
      : (data as Document);
  },

  delete: async (path: string): Promise<void> => {
    await request<void>(`/documents/${encodeDocPath(path)}`, {
      method: "DELETE",
    });
  },

  listByProject: async (
    projectId: string,
    workspaceId?: string,
  ): Promise<{
    documents: Document[];
    tree: DocumentTreeNode[];
  }> => {
    const qs = new URLSearchParams({ project_id: projectId });
    if (workspaceId !== undefined) qs.set("workspace_id", workspaceId);
    const data = await request<{
      documents: Document[];
      tree: DocumentTreeNode[];
    }>(`/documents?${qs.toString()}`);
    return { documents: data.documents ?? [], tree: data.tree ?? [] };
  },

  revisions: async (documentId: string): Promise<DocumentRevision[]> => {
    const data = await request<{ revisions: DocumentRevision[] }>(
      `/document-revisions?document_id=${encodeURIComponent(documentId)}`,
    );
    return data.revisions ?? [];
  },
};

/** Encode a document path for use in URL segments (preserves slashes). */
function encodeDocPath(path: string): string {
  return path.split("/").map(encodeURIComponent).join("/");
}

// ── Workspaces ────────────────────────────────────────────────────────────────

export const workspaces = {
  list: async (): Promise<Workspace[]> => {
    const data = await request<{ workspaces: Workspace[] }>("/workspaces");
    return data.workspaces ?? [];
  },
  create: async (params: {
    name: string;
    path?: string;
    directory?: string;
  }): Promise<Workspace> => {
    return request<Workspace>("/workspaces", {
      method: "POST",
      body: JSON.stringify(params),
    });
  },
  activate: async (id: string): Promise<Workspace> => {
    return request<{ workspace: Workspace }>(`/workspaces/${id}/activate`, {
      method: "POST",
    }).then((data) => (data as { workspace: Workspace }).workspace ?? data);
  },
  get: (id: string) => request<Workspace>(`/workspaces/${id}`),
  update: (id: string, body: unknown) =>
    request<Workspace>(`/workspaces/${id}`, {
      method: "PATCH",
      body: JSON.stringify(body),
    }),
  delete: (id: string) =>
    request<void>(`/workspaces/${id}`, { method: "DELETE" }),
  agents: (id: string) =>
    request<{ agents: BizforgeAgent[] }>(`/workspaces/${id}/agents`),
  skills: (id: string) =>
    request<{ skills: Skill[] }>(`/workspaces/${id}/skills`),
  config: (id: string) => request<unknown>(`/workspaces/${id}/config`),
};

// ── Settings ──────────────────────────────────────────────────────────────────

export const settings = {
  get: () => request<Settings>("/config"),
  update: (body: Partial<Settings>) =>
    request<Settings>("/config", {
      method: "PATCH",
      body: JSON.stringify(body),
    }),
};

// ── Audit ─────────────────────────────────────────────────────────────────────

export const audit = {
  list: async (page = 1, limit = 50): Promise<AuditEntry[]> => {
    const data = await request<{ entries: AuditEntry[]; events: AuditEntry[] }>(
      `/audit?page=${page}&limit=${limit}`,
    );
    return data.entries ?? data.events ?? [];
  },
};

// ── Logs ──────────────────────────────────────────────────────────────────────

export const logs = {
  list: async (
    limit = 100,
    params?: { level?: string; source?: string; agent_id?: string },
  ): Promise<LogEntry[]> => {
    const qs = new URLSearchParams({ limit: String(limit) });
    if (params?.level) qs.set("level", params.level);
    if (params?.source && params.source !== "all")
      qs.set("source", params.source);
    if (params?.agent_id && params.agent_id !== "all")
      qs.set("agent_id", params.agent_id);
    const data = await request<{ logs: LogEntry[]; entries: LogEntry[] }>(
      `/logs?${qs.toString()}`,
    );
    return data.logs ?? data.entries ?? [];
  },
};

// ── Memory ────────────────────────────────────────────────────────────────────

export const memory = {
  list: async (namespace?: string): Promise<MemoryEntry[]> => {
    const params = namespace
      ? `?namespace=${encodeURIComponent(namespace)}`
      : "";
    const data = await request<{ entries: MemoryEntry[] }>(`/memory${params}`);
    return data.entries ?? [];
  },
  namespaces: async (): Promise<MemoryNamespace[]> => {
    const data = await request<{ namespaces: MemoryNamespace[] }>(
      "/memory/namespaces",
    );
    return data.namespaces ?? [];
  },
  get: async (id: string): Promise<MemoryEntry> => {
    const data = await request<{ entry: MemoryEntry }>(`/memory/${id}`);
    return data.entry;
  },
  search: async (q: string): Promise<MemoryEntry[]> => {
    const data = await request<{ entries: MemoryEntry[] }>(
      `/memory/search?q=${encodeURIComponent(q)}`,
    );
    return data.entries ?? [];
  },
  create: async (body: MemoryCreateRequest): Promise<MemoryEntry> => {
    const data = await request<{ entry: MemoryEntry }>("/memory", {
      method: "POST",
      body: JSON.stringify(body),
    });
    return data.entry;
  },
  update: async (
    id: string,
    body: Partial<MemoryCreateRequest>,
  ): Promise<MemoryEntry> => {
    const data = await request<{ entry: MemoryEntry }>(`/memory/${id}`, {
      method: "PUT",
      body: JSON.stringify(body),
    });
    return data.entry;
  },
  delete: async (id: string): Promise<void> => {
    await request<void>(`/memory/${id}`, { method: "DELETE" });
  },
  byProject: async (projectId: string): Promise<MemoryEntry[]> => {
    const data = await request<{ entries: MemoryEntry[] }>(`/memory/project/${projectId}`);
    return data.entries ?? [];
  },
  company: async (): Promise<MemoryEntry[]> => {
    const data = await request<{ entries: MemoryEntry[] }>('/memory/company');
    return data.entries ?? [];
  },
  resolve: async (projectId: string): Promise<MemoryEntry[]> => {
    const data = await request<{ entries: MemoryEntry[] }>(`/memory/resolve/${projectId}`);
    return data.entries ?? [];
  },
};

// ── Signals ───────────────────────────────────────────────────────────────────

export const signals = {
  list: async (limit = 100): Promise<Signal[]> => {
    const data = await request<{ signals: Signal[] }>(
      `/signals/feed?limit=${limit}`,
    );
    return data.signals ?? [];
  },
  patterns: async (): Promise<SignalPattern[]> => {
    const data = await request<{ patterns: SignalPattern[] }>(
      "/signals/patterns",
    );
    return data.patterns ?? [];
  },
  stats: async (): Promise<SignalStats> => {
    return request<SignalStats>("/signals/stats");
  },
  classify: (body: unknown) =>
    request<unknown>("/signals/classify", {
      method: "POST",
      body: JSON.stringify(body),
    }),
};

// ── Spawn ─────────────────────────────────────────────────────────────────────

export const spawn = {
  list: async (): Promise<SpawnInstance[]> => {
    const data = await request<{ instances: SpawnInstance[] }>("/spawn/active");
    return data.instances ?? [];
  },
  create: (body: { agent_id: string; task: string; model?: string }) =>
    request<SpawnInstance>("/spawn", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  kill: (id: string) => request<void>(`/spawn/${id}`, { method: "DELETE" }),
  history: () => request<{ history: unknown[] }>("/spawn/history"),
};

// ── Secrets ───────────────────────────────────────────────────────────────────

export const secrets = {
  list: async (workspaceId?: string): Promise<Secret[]> => {
    const qs = workspaceId ? `?workspace_id=${workspaceId}` : "";
    const data = await request<{ secrets: Secret[] }>(`/secrets${qs}`);
    return data.secrets ?? [];
  },
  get: (id: string) => request<Secret>(`/secrets/${id}`),
  create: (body: SecretCreateRequest) =>
    request<Secret>("/secrets", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  delete: (id: string) => request<void>(`/secrets/${id}`, { method: "DELETE" }),
  rotate: (id: string) =>
    request<Secret>(`/secrets/${id}/rotate`, { method: "POST" }),
};

// ── Approvals ─────────────────────────────────────────────────────────────────

export const approvals = {
  list: async (params?: Record<string, string>): Promise<Approval[]> => {
    const qs = params ? "?" + new URLSearchParams(params).toString() : "";
    const data = await request<{ approvals: Approval[] }>(`/approvals${qs}`);
    return data.approvals ?? [];
  },
  get: (id: string) => request<Approval>(`/approvals/${id}`),
  create: (body: ApprovalCreateRequest) =>
    request<Approval>("/approvals", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  approve: (id: string, comment?: string) =>
    request<Approval>(`/approvals/${id}/approve`, {
      method: "POST",
      body: JSON.stringify({ comment }),
    }),
  reject: (id: string, comment?: string) =>
    request<Approval>(`/approvals/${id}/reject`, {
      method: "POST",
      body: JSON.stringify({ comment }),
    }),
  delete: (id: string) =>
    request<void>(`/approvals/${id}`, { method: "DELETE" }),
  comment: (id: string, body: string) =>
    request<void>(`/approvals/${id}/comments`, {
      method: "POST",
      body: JSON.stringify({ body }),
    }),
};

// ── Organizations ─────────────────────────────────────────────────────────────

export const organizations = {
  list: async (): Promise<Organization[]> => {
    const data = await request<{ organizations: Organization[] }>(
      "/organizations",
    );
    return data.organizations ?? [];
  },
  get: async (id: string): Promise<Organization> => {
    const data = await request<Organization | { organization: Organization }>(
      `/organizations/${id}`,
    );
    return "organization" in data
      ? (data as { organization: Organization }).organization
      : (data as Organization);
  },
  create: async (body: OrganizationCreateRequest): Promise<Organization> => {
    const data = await request<Organization | { organization: Organization }>(
      "/organizations",
      { method: "POST", body: JSON.stringify(body) },
    );
    return "organization" in data
      ? (data as { organization: Organization }).organization
      : (data as Organization);
  },
  update: async (
    id: string,
    body: Partial<OrganizationCreateRequest>,
  ): Promise<Organization> => {
    const data = await request<Organization | { organization: Organization }>(
      `/organizations/${id}`,
      { method: "PATCH", body: JSON.stringify(body) },
    );
    return "organization" in data
      ? (data as { organization: Organization }).organization
      : (data as Organization);
  },
  delete: (id: string) =>
    request<void>(`/organizations/${id}`, { method: "DELETE" }),
  members: async (id: string): Promise<OrganizationMembership[]> => {
    const data = await request<{ members: OrganizationMembership[] }>(
      `/organizations/${id}/members`,
    );
    return data.members ?? [];
  },
};

// ── Divisions ─────────────────────────────────────────────────────────────────

export const divisions = {
  list: async (orgId?: string): Promise<Division[]> => {
    const qs = orgId ? `?organization_id=${orgId}` : "";
    const data = await request<{ divisions: Division[] }>(`/divisions${qs}`);
    return data.divisions ?? [];
  },
  get: async (id: string): Promise<Division> => {
    const data = await request<Division | { division: Division }>(
      `/divisions/${id}`,
    );
    return "division" in data
      ? (data as { division: Division }).division
      : (data as Division);
  },
  create: async (body: Partial<Division>): Promise<Division> => {
    const data = await request<Division | { division: Division }>(
      "/divisions",
      { method: "POST", body: JSON.stringify(body) },
    );
    return "division" in data
      ? (data as { division: Division }).division
      : (data as Division);
  },
  update: async (id: string, body: Partial<Division>): Promise<Division> => {
    const data = await request<Division | { division: Division }>(
      `/divisions/${id}`,
      { method: "PATCH", body: JSON.stringify(body) },
    );
    return "division" in data
      ? (data as { division: Division }).division
      : (data as Division);
  },
  delete: (id: string) =>
    request<void>(`/divisions/${id}`, { method: "DELETE" }),
  departments: async (divisionId: string): Promise<Department[]> => {
    const data = await request<{ departments: Department[] }>(
      `/divisions/${divisionId}/departments`,
    );
    return data.departments ?? [];
  },
};

// ── Departments ───────────────────────────────────────────────────────────────

export const departments = {
  list: async (divisionId?: string): Promise<Department[]> => {
    const qs = divisionId ? `?division_id=${divisionId}` : "";
    const data = await request<{ departments: Department[] }>(
      `/departments${qs}`,
    );
    return data.departments ?? [];
  },
  get: async (id: string): Promise<Department> => {
    const data = await request<Department | { department: Department }>(
      `/departments/${id}`,
    );
    return "department" in data
      ? (data as { department: Department }).department
      : (data as Department);
  },
  create: async (body: Partial<Department>): Promise<Department> => {
    const data = await request<Department | { department: Department }>(
      "/departments",
      { method: "POST", body: JSON.stringify(body) },
    );
    return "department" in data
      ? (data as { department: Department }).department
      : (data as Department);
  },
  update: async (
    id: string,
    body: Partial<Department>,
  ): Promise<Department> => {
    const data = await request<Department | { department: Department }>(
      `/departments/${id}`,
      { method: "PATCH", body: JSON.stringify(body) },
    );
    return "department" in data
      ? (data as { department: Department }).department
      : (data as Department);
  },
  delete: (id: string) =>
    request<void>(`/departments/${id}`, { method: "DELETE" }),
  teams: async (departmentId: string): Promise<Team[]> => {
    const data = await request<{ teams: Team[] }>(
      `/departments/${departmentId}/teams`,
    );
    return data.teams ?? [];
  },
};

// ── Teams ─────────────────────────────────────────────────────────────────────

export const teams = {
  list: async (departmentId?: string): Promise<Team[]> => {
    const qs = departmentId ? `?department_id=${departmentId}` : "";
    const data = await request<{ teams: Team[] }>(`/teams${qs}`);
    return data.teams ?? [];
  },
  get: async (id: string): Promise<Team> => {
    const data = await request<Team | { team: Team }>(`/teams/${id}`);
    return "team" in data
      ? (data as { team: Team }).team
      : (data as Team);
  },
  create: async (body: Partial<Team>): Promise<Team> => {
    const data = await request<Team | { team: Team }>("/teams", {
      method: "POST",
      body: JSON.stringify(body),
    });
    return "team" in data
      ? (data as { team: Team }).team
      : (data as Team);
  },
  update: async (id: string, body: Partial<Team>): Promise<Team> => {
    const data = await request<Team | { team: Team }>(`/teams/${id}`, {
      method: "PATCH",
      body: JSON.stringify(body),
    });
    return "team" in data
      ? (data as { team: Team }).team
      : (data as Team);
  },
  delete: (id: string) => request<void>(`/teams/${id}`, { method: "DELETE" }),
  agents: async (teamId: string): Promise<BizforgeAgent[]> => {
    const data = await request<{ agents: BizforgeAgent[] }>(
      `/teams/${teamId}/agents`,
    );
    return data.agents ?? [];
  },
  addMember: (
    teamId: string,
    agentId: string,
    role: "member" | "manager" = "member",
  ) =>
    request<TeamMembership>(`/teams/${teamId}/members`, {
      method: "POST",
      body: JSON.stringify({ agent_id: agentId, role }),
    }),
  removeMember: (teamId: string, agentId: string) =>
    request<void>(`/teams/${teamId}/members/${agentId}`, { method: "DELETE" }),
};

// ── Hierarchy ─────────────────────────────────────────────────────────────────

export const hierarchy = {
  get: async (organizationId: string): Promise<HierarchyTree> => {
    const raw = await request<{
      organization: Organization & { divisions?: HierarchyDivisionNode[] };
    }>(`/hierarchy?organization_id=${organizationId}`);
    const { divisions, ...org } = raw.organization ?? ({} as Organization & { divisions?: HierarchyDivisionNode[] });
    return { organization: org as Organization, divisions: divisions ?? [] };
  },
};

// ── Labels ────────────────────────────────────────────────────────────────────

export const labels = {
  list: async (params?: Record<string, string>): Promise<Label[]> => {
    const qs = params ? "?" + new URLSearchParams(params).toString() : "";
    const data = await request<{ labels: Label[] }>(`/labels${qs}`);
    return data.labels ?? [];
  },
  create: (body: LabelCreateRequest) =>
    request<Label>("/labels", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  delete: (id: string) => request<void>(`/labels/${id}`, { method: "DELETE" }),
};

// ── Plugins ───────────────────────────────────────────────────────────────────

export const plugins = {
  list: async (): Promise<Plugin[]> => {
    const data = await request<{ plugins: Plugin[] }>("/plugins");
    return data.plugins ?? [];
  },
  get: (id: string) => request<Plugin>(`/plugins/${id}`),
  create: (body: Partial<Plugin>) =>
    request<Plugin>("/plugins", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  update: (id: string, body: Partial<Plugin>) =>
    request<Plugin>(`/plugins/${id}`, {
      method: "PATCH",
      body: JSON.stringify(body),
    }),
  delete: (id: string) => request<void>(`/plugins/${id}`, { method: "DELETE" }),
  logs: async (id: string): Promise<PluginLog[]> => {
    const data = await request<{ logs: PluginLog[] }>(`/plugins/${id}/logs`);
    return data.logs ?? [];
  },
};

// ── Access / Role Assignments ─────────────────────────────────────────────────

export const access = {
  list: async (params?: Record<string, string>): Promise<RoleAssignment[]> => {
    const qs = params ? "?" + new URLSearchParams(params).toString() : "";
    const data = await request<{ assignments: RoleAssignment[] }>(
      `/access${qs}`,
    );
    return data.assignments ?? [];
  },
  assign: (body: Partial<RoleAssignment>) =>
    request<RoleAssignment>("/access/assign", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  revoke: (id: string) => request<void>(`/access/${id}`, { method: "DELETE" }),
};

// ── Sidebar Badges ────────────────────────────────────────────────────────────

export const sidebarBadges = {
  get: () => request<SidebarBadges>("/sidebar-badges"),
};

// ── Users ─────────────────────────────────────────────────────────────────────

export const users = {
  list: async (): Promise<User[]> => {
    const data = await request<{ users: User[] }>("/users");
    return data.users ?? [];
  },
  get: (id: string) => request<User>(`/users/${id}`),
  create: (body: Partial<User>) =>
    request<User>("/users", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  update: (id: string, body: Partial<User>) =>
    request<User>(`/users/${id}`, {
      method: "PATCH",
      body: JSON.stringify(body),
    }),
  delete: (id: string) => request<void>(`/users/${id}`, { method: "DELETE" }),
};

// ── Templates ─────────────────────────────────────────────────────────────────

export const templates = {
  list: async (workspaceId?: string): Promise<AgentTemplate[]> => {
    const qs = workspaceId ? `?workspace_id=${workspaceId}` : "";
    const data = await request<{ templates: AgentTemplate[] }>(
      `/templates${qs}`,
    );
    return data.templates ?? [];
  },
  get: (id: string) => request<AgentTemplate>(`/templates/${id}`),
  create: (body: Partial<AgentTemplate>) =>
    request<AgentTemplate>("/templates", {
      method: "POST",
      body: JSON.stringify(body),
    }),
};

// ── Invitations ───────────────────────────────────────────────────────────────

export const invitations = {
  list: () => request<{ invitations: unknown[] }>("/invitations"),
  create: (body: unknown) =>
    request<void>("/invitations", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  accept: (token: string) =>
    request<void>(`/invitations/${token}/accept`, { method: "POST" }),
};

// ── Config Revisions ──────────────────────────────────────────────────────────

export const configRevisions = {
  list: () => request<{ revisions: unknown[] }>("/config/revisions"),
  restore: (id: string) =>
    request<void>(`/config/revisions/${id}/restore`, { method: "POST" }),
};

// ── Execution Workspaces ──────────────────────────────────────────────────────

export const executionWorkspaces = {
  list: () =>
    request<{ execution_workspaces: unknown[] }>("/execution-workspaces"),
  create: (body: unknown) =>
    request<void>("/execution-workspaces", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  delete: (id: string) =>
    request<void>(`/execution-workspaces/${id}`, { method: "DELETE" }),
};

// ── Environment ───────────────────────────────────────────────────────────────

export const environment = {
  apps: async (): Promise<unknown[]> => {
    const data = await request<{ apps: unknown[] }>("/environment/apps");
    return data.apps ?? [];
  },
  agentApps: async (): Promise<unknown[]> => {
    const data = await request<{ agent_apps: unknown[] }>(
      "/environment/agent-apps",
    );
    return data.agent_apps ?? [];
  },
  resources: async (): Promise<unknown> => {
    const data = await request<{ resources?: unknown }>("/environment/resources");
    return (data as Record<string, unknown>).resources ?? data;
  },
  capabilities: async (): Promise<unknown[]> => {
    const data = await request<{ capabilities: unknown[] }>(
      "/environment/capabilities",
    );
    return data.capabilities ?? [];
  },
  grantAccess: (appId: string, agentId: string) =>
    request<unknown>(`/environment/apps/${appId}/grant`, {
      method: "POST",
      body: JSON.stringify({ agent_id: agentId }),
    }),
  revokeAccess: (appId: string, agentId: string) =>
    request<unknown>(`/environment/apps/${appId}/revoke`, {
      method: "POST",
      body: JSON.stringify({ agent_id: agentId }),
    }),
};

// ── Analytics ─────────────────────────────────────────────────────────────────

export const analytics = {
  summary: (period: string) =>
    request<unknown>(`/analytics/summary?period=${period}`),
  agents: (period: string) =>
    request<unknown>(`/analytics/agents?period=${period}`),
  teams: (period: string) =>
    request<unknown>(`/analytics/teams?period=${period}`),
  reset: () =>
    request<{ ok: boolean; reset_at: string }>(`/analytics/reset`, {
      method: "DELETE",
    }),
};

// ── Work Products ─────────────────────────────────────────────────────────────

export const workProducts = {
  list: (filters?: Record<string, string>) => {
    const qs = filters ? "?" + new URLSearchParams(filters).toString() : "";
    return request<unknown>(`/work-products${qs}`);
  },
  get: (id: string) => request<unknown>(`/work-products/${id}`),
  archive: (id: string) =>
    request<void>(`/work-products/${id}/archive`, { method: "POST" }),
};

// ── Conversations ─────────────────────────────────────────────────────────────

export const conversations = {
  list: async (filters?: {
    agent_id?: string;
    status?: string;
    workspace_id?: string;
  }): Promise<import("./types").Conversation[]> => {
    const qs = filters
      ? "?" + new URLSearchParams(filters as Record<string, string>).toString()
      : "";
    const data = await request<{
      conversations: import("./types").Conversation[];
      total: number;
    }>(`/conversations${qs}`);
    return data.conversations ?? [];
  },
  get: (id: string) =>
    request<{
      conversation: import("./types").Conversation;
      messages: import("./types").ConversationMessage[];
    }>(`/conversations/${id}`),
  create: (agentId: string, title?: string, workspaceId?: string) =>
    request<{ conversation: import("./types").Conversation }>(
      "/conversations",
      {
        method: "POST",
        body: JSON.stringify({
          agent_id: agentId,
          title,
          workspace_id: workspaceId,
        }),
      },
    ),
  messages: async (
    id: string,
    params?: { limit?: number; before?: string },
  ): Promise<import("./types").ConversationMessage[]> => {
    const qs = params
      ? "?" + new URLSearchParams(params as Record<string, string>).toString()
      : "";
    const data = await request<{
      messages: import("./types").ConversationMessage[];
      count: number;
    }>(`/conversations/${id}/messages${qs}`);
    return data.messages ?? [];
  },
  sendMessage: (id: string, content: string) =>
    request<import("./types").SendConversationMessageResponse>(
      `/conversations/${id}/messages`,
      {
        method: "POST",
        body: JSON.stringify({ content }),
      },
    ),
  archive: (id: string) =>
    request<{ conversation: import("./types").Conversation }>(
      `/conversations/${id}/archive`,
      { method: "POST" },
    ),
  delete: (id: string) =>
    request<void>(`/conversations/${id}`, { method: "DELETE" }),
};

// ── Datasets ──────────────────────────────────────────────────────────────────

export const datasets = {
  list: async (
    workspaceId?: string,
    sourceType?: string,
  ): Promise<import("./types").Dataset[]> => {
    const params = new URLSearchParams();
    if (workspaceId) params.set("workspace_id", workspaceId);
    if (sourceType) params.set("source_type", sourceType);
    const qs = params.toString() ? `?${params.toString()}` : "";
    const data = await request<{
      datasets: import("./types").Dataset[];
      count: number;
    }>(`/datasets${qs}`);
    return data.datasets ?? [];
  },
  get: async (id: string): Promise<import("./types").Dataset> => {
    const data = await request<{ dataset: import("./types").Dataset }>(
      `/datasets/${id}`,
    );
    return data.dataset;
  },
  create: async (
    body: import("./types").DatasetCreateRequest,
  ): Promise<import("./types").Dataset> => {
    const data = await request<{ dataset: import("./types").Dataset }>(
      "/datasets",
      { method: "POST", body: JSON.stringify(body) },
    );
    return data.dataset;
  },
  update: async (
    id: string,
    body: Partial<import("./types").DatasetCreateRequest>,
  ): Promise<import("./types").Dataset> => {
    const data = await request<{ dataset: import("./types").Dataset }>(
      `/datasets/${id}`,
      { method: "PATCH", body: JSON.stringify(body) },
    );
    return data.dataset;
  },
  remove: (id: string) =>
    request<void>(`/datasets/${id}`, { method: "DELETE" }),
  preview: async (
    id: string,
  ): Promise<import("./types").DatasetPreviewResponse> => {
    return request<import("./types").DatasetPreviewResponse>(
      `/datasets/${id}/preview`,
    );
  },
  refresh: async (id: string): Promise<import("./types").Dataset> => {
    const data = await request<{ dataset: import("./types").Dataset }>(
      `/datasets/${id}/refresh`,
      { method: "POST" },
    );
    return data.dataset;
  },
  grantAccess: async (
    id: string,
    agentId: string,
  ): Promise<import("./types").Dataset> => {
    const data = await request<{ dataset: import("./types").Dataset }>(
      `/datasets/${id}/grant`,
      { method: "POST", body: JSON.stringify({ agent_id: agentId }) },
    );
    return data.dataset;
  },
  revokeAccess: async (
    id: string,
    agentId: string,
  ): Promise<import("./types").Dataset> => {
    const data = await request<{ dataset: import("./types").Dataset }>(
      `/datasets/${id}/revoke`,
      { method: "POST", body: JSON.stringify({ agent_id: agentId }) },
    );
    return data.dataset;
  },
};

// ── Notifications ─────────────────────────────────────────────────────────────

export const notifications = {
  list: async (
    filters: import("./types").NotificationFilters = {},
  ): Promise<import("./types").Notification[]> => {
    const qs = new URLSearchParams();
    if (filters.category) qs.set("category", filters.category);
    if (filters.severity) qs.set("severity", filters.severity);
    if (filters.unread !== undefined) qs.set("unread", String(filters.unread));
    if (filters.limit !== undefined) qs.set("limit", String(filters.limit));
    if (filters.offset !== undefined) qs.set("offset", String(filters.offset));
    const query = qs.toString() ? `?${qs.toString()}` : "";
    const data = await request<{
      notifications: import("./types").Notification[];
      total: number;
    }>(`/notifications${query}`);
    return data.notifications ?? [];
  },

  get: async (id: string): Promise<import("./types").Notification> => {
    const data = await request<{
      notification: import("./types").Notification;
    }>(`/notifications/${id}`);
    return (
      data.notification ?? (data as unknown as import("./types").Notification)
    );
  },

  markRead: async (id: string): Promise<import("./types").Notification> => {
    const data = await request<{
      notification: import("./types").Notification;
    }>(`/notifications/${id}/read`, { method: "POST" });
    return (
      data.notification ?? (data as unknown as import("./types").Notification)
    );
  },

  markAllRead: async (
    category?: import("./types").NotificationCategory,
  ): Promise<void> => {
    const body = category ? JSON.stringify({ category }) : undefined;
    await request<{ ok: boolean }>("/notifications/mark-all-read", {
      method: "POST",
      body,
    });
  },

  dismiss: async (id: string): Promise<import("./types").Notification> => {
    const data = await request<{
      notification: import("./types").Notification;
    }>(`/notifications/${id}/dismiss`, { method: "POST" });
    return (
      data.notification ?? (data as unknown as import("./types").Notification)
    );
  },

  badges: async (): Promise<import("./types").NotificationBadges> => {
    return request<import("./types").NotificationBadges>(
      "/notifications/badges",
    );
  },

  create: async (
    body: Partial<import("./types").Notification>,
  ): Promise<import("./types").Notification> => {
    const data = await request<{
      notification: import("./types").Notification;
    }>("/notifications", {
      method: "POST",
      body: JSON.stringify(body),
    });
    return (
      data.notification ?? (data as unknown as import("./types").Notification)
    );
  },
};

// ── Reports ───────────────────────────────────────────────────────────────────

export const reports = {
  list: async (params?: {
    report_type?: import("./types").ReportType;
  }): Promise<import("./types").Report[]> => {
    const qs = params?.report_type ? `?report_type=${params.report_type}` : "";
    const data = await request<{
      reports: import("./types").Report[];
      count: number;
    }>(`/reports${qs}`);
    return data.reports ?? [];
  },

  get: async (id: string): Promise<import("./types").Report> => {
    const data = await request<{ report: import("./types").Report }>(
      `/reports/${id}`,
    );
    return data.report;
  },

  create: async (
    body: import("./types").ReportCreateRequest,
  ): Promise<import("./types").Report> => {
    const data = await request<{ report: import("./types").Report }>(
      "/reports",
      { method: "POST", body: JSON.stringify(body) },
    );
    return data.report;
  },

  update: async (
    id: string,
    body: Partial<import("./types").ReportCreateRequest>,
  ): Promise<import("./types").Report> => {
    const data = await request<{ report: import("./types").Report }>(
      `/reports/${id}`,
      { method: "PATCH", body: JSON.stringify(body) },
    );
    return data.report;
  },

  remove: (id: string) => request<void>(`/reports/${id}`, { method: "DELETE" }),

  generate: async (id: string): Promise<import("./types").Report> => {
    const data = await request<{
      report: import("./types").Report;
      generated: boolean;
    }>(`/reports/${id}/generate`, { method: "POST" });
    return data.report;
  },

  exportReport: (id: string, format = "csv") =>
    request<Blob>(`/reports/${id}/export?format=${format}`),
};

// ── Mock Mode (disabled) ─────────────────────────────────────────────────────
// Mock mode is permanently disabled. These stubs exist for backward compat.

/** @deprecated Mock mode is disabled. Always returns false. */
export function isMockEnabled(): boolean {
  return false;
}

/**
 * Reset the singleton initializeAuth() promise so that the next call to
 * initializeAuth() re-probes the backend and re-reads the token.
 *
 * Call this after a successful login or registration so that the /app layout
 * guard sees the freshly-persisted token instead of the cached "no-token"
 * state from the first run of initializeAuth().
 */
export function resetInitPromise(): void {
  _initPromise = null;
}
