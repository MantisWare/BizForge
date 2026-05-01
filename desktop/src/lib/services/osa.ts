// src/lib/services/osa.ts
// OSA (Optimal System Agent) setup and health service

import { isTauri } from "$lib/utils/platform";

// ── Types ────────────────────────────────────────────────────────────────────

export interface OsaSetupStep {
  step: string;
  success: boolean;
  message: string;
}

export interface OsaHealth {
  status: string;
  version?: string;
  provider?: string;
  model?: string;
}

// ── Health Check ─────────────────────────────────────────────────────────────

/** Check if OSA is reachable on port 9090 or 9089, return health payload */
export async function checkOsaHealth(): Promise<OsaHealth | null> {
  // Port 9090 = standalone OSA (headless), 9089 = Phoenix backend
  const probes: Array<{ port: number; path: string }> = [
    { port: 9090, path: "/health" },
    { port: 9089, path: "/api/v1/health" },
    { port: 9089, path: "/health" },
  ];
  for (const { port, path } of probes) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}${path}`, {
        signal: AbortSignal.timeout(2000),
      });
      if (res.ok) return await res.json();
    } catch {
      /* try next */
    }
  }
  return null;
}

/** Determine which port OSA is responding on */
export async function findOsaPort(): Promise<number | null> {
  const probes: Array<{ port: number; path: string }> = [
    { port: 9090, path: "/health" },
    { port: 9089, path: "/api/v1/health" },
    { port: 9089, path: "/health" },
  ];
  for (const { port, path } of probes) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}${path}`, {
        signal: AbortSignal.timeout(2000),
      });
      if (res.ok) return port;
    } catch {
      /* try next */
    }
  }
  return null;
}

// ── Setup ────────────────────────────────────────────────────────────────────

/** Run the full OSA setup flow via Tauri IPC */
export async function setupOsa(osaPath?: string): Promise<OsaSetupStep[]> {
  if (!isTauri()) {
    return [
      {
        step: "check",
        success: false,
        message: "OSA setup requires the Bizforge desktop app",
      },
    ];
  }
  const { invoke } = await import("@tauri-apps/api/core");
  return invoke<OsaSetupStep[]>("setup_osa", {
    osaPath: osaPath ?? null,
  });
}

/** Install OSA from scratch using the official install script via Tauri */
export async function installOsa(): Promise<{
  success: boolean;
  output: string;
}> {
  if (!isTauri()) {
    return { success: false, output: "Requires Bizforge desktop app" };
  }
  const { invoke } = await import("@tauri-apps/api/core");
  try {
    const output = await invoke<string>("install_adapter", {
      adapterId: "osa",
    });
    return { success: true, output };
  } catch (error) {
    return { success: false, output: String(error) };
  }
}

// ── Stop / Restart ───────────────────────────────────────────────────────────

export interface OsaStopResult {
  success: boolean;
  message: string;
}

/** Stop the running OSA instance via Tauri IPC (sends SIGTERM) */
export async function stopOsa(): Promise<OsaStopResult> {
  if (!isTauri()) {
    return { success: false, message: 'Requires Bizforge desktop app' };
  }
  const { invoke } = await import('@tauri-apps/api/core');
  return invoke<OsaStopResult>('stop_osa');
}

/** Restart OSA: stop then start */
export async function restartOsa(osaPath?: string): Promise<{ stopped: OsaStopResult; started: OsaSetupStep[] }> {
  const stopped = await stopOsa();
  // Brief pause to allow port release
  await new Promise((resolve) => setTimeout(resolve, 2000));
  const started = await setupOsa(osaPath);
  return { stopped, started };
}

// ── Onboarding ───────────────────────────────────────────────────────────────

/** Check what OSA's onboarding has detected */
export async function getOsaOnboardingStatus(): Promise<unknown | null> {
  const probes: Array<{ port: number; path: string }> = [
    { port: 9090, path: "/onboarding/status" },
    { port: 9089, path: "/api/v1/onboarding/status" },
  ];
  for (const { port, path } of probes) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}${path}`, {
        signal: AbortSignal.timeout(2000),
      });
      if (res.ok) return await res.json();
    } catch {
      /* try next */
    }
  }
  return null;
}
