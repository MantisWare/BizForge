// src/lib/utils/agents.ts
// Converters between the three agent representations used in Bizforge:
//   - BizforgeAgentDef  (.bizforge/ filesystem scan, from Tauri IPC / bizforge.ts)
//   - AgentTemplateData  (onboarding store, onboarding.svelte.ts)
//   - BizforgeAgent  (API / backend wire type, api/types.ts)

import type { BizforgeAgent, AdapterType } from "$api/types";
import type { BizforgeAgentDef } from "$lib/types/bizforge";
import type { AgentTemplateData } from "$lib/stores/onboarding.svelte";

// The .bizforge/ workspace uses hyphenated adapter names (e.g. "claude-code")
// while the API uses underscored names (e.g. "claude_code"). This normalizes
// any hyphenated value into the API's AdapterType union.
function normalizeAdapter(raw: string): AdapterType {
  const normalized = raw.replace(/-/g, "_") as AdapterType;
  const valid: AdapterType[] = [
    "osa",
    "claude_code",
    "codex",
    "openclaw",
    "jidoclaw",
    "hermes",
    "bash",
    "http",
    "custom",
  ];
  return valid.includes(normalized) ? normalized : "custom";
}

function capitalize(s: string): string {
  return s.replace(/[-_]/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
}

const DEFAULT_MODEL = "claude-sonnet-4-20250514";

const ZERO_USAGE = {
  input: 0,
  output: 0,
  cache_read: 0,
  cache_write: 0,
} as const;

/** Convert a scanned BizforgeAgentDef (from Tauri IPC / .bizforge/ workspace) to a BizforgeAgent. */
export function bizforgeDefToAgent(def: BizforgeAgentDef): BizforgeAgent {
  const now = new Date().toISOString();
  return {
    id: def.id,
    name: def.name,
    display_name: capitalize(def.name),
    avatar_emoji: def.emoji ?? "robot",
    role: def.role,
    status: "idle",
    adapter: normalizeAdapter(def.adapter),
    model: def.model ?? DEFAULT_MODEL,
    system_prompt: def.system_prompt ?? "",
    config: {},
    skills: def.skills,
    team_id: null,
    schedule_id: def.schedule ?? null,
    budget_policy_id: null,
    current_task: null,
    last_active_at: now,
    token_usage_today: { ...ZERO_USAGE },
    cost_today_cents: 0,
    created_at: now,
    updated_at: now,
  };
}

/** Convert an onboarding AgentTemplateData to a BizforgeAgent. */
export function templateToAgent(tmpl: AgentTemplateData): BizforgeAgent {
  const now = new Date().toISOString();
  return {
    id: tmpl.id,
    name: tmpl.name,
    display_name: capitalize(tmpl.name),
    avatar_emoji: tmpl.emoji || "robot",
    role: tmpl.role,
    status: "idle",
    adapter: normalizeAdapter(tmpl.adapter),
    model: tmpl.model ?? DEFAULT_MODEL,
    system_prompt: tmpl.system_prompt ?? "",
    config: {},
    skills: tmpl.skills,
    team_id: null,
    schedule_id: null,
    budget_policy_id: null,
    current_task: null,
    last_active_at: now,
    token_usage_today: { ...ZERO_USAGE },
    cost_today_cents: 0,
    created_at: now,
    updated_at: now,
  };
}
