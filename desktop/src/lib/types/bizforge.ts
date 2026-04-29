// src/lib/types/bizforge.ts
// Types for the .bizforge/ workspace protocol — portable AI agent definitions

// ── Workspace ────────────────────────────────────────────────────────────────

export interface BizforgeWorkspace {
  /** Absolute path to the .bizforge/ directory */
  path: string;
  /** Human-readable workspace name (from SYSTEM.md frontmatter or directory name) */
  name: string;
  /** Agents discovered in .bizforge/agents/ */
  agents: BizforgeAgentDef[];
  /** Projects discovered in .bizforge/projects/ */
  projects: BizforgeProjectDef[];
  /** Schedules discovered in .bizforge/schedules/ */
  schedules: BizforgeScheduleDef[];
  /** Skills discovered in .bizforge/skills/ */
  skills: BizforgeSkillDef[];
  /** Raw contents of .bizforge/SYSTEM.md (workspace system prompt / config) */
  system_md: string | null;
  /** Raw contents of .bizforge/COMPANY.md (organization context) */
  company_md: string | null;
  /** Last scan timestamp */
  scanned_at: string;
}

// ── Agent Definition ─────────────────────────────────────────────────────────

export interface BizforgeAgentDef {
  /** Unique agent ID (filename without extension) */
  id: string;
  /** Display name */
  name: string;
  /** Agent emoji/icon */
  emoji?: string;
  /** Role description */
  role: string;
  /** Adapter type: osa, claude-code, codex, openclaw, cursor, bash, http */
  adapter: AdapterType;
  /** Model ID */
  model?: string;
  /** System prompt */
  system_prompt?: string;
  /** Assigned skill IDs */
  skills: string[];
  /** Budget config */
  budget?: AgentBudgetConfig;
  /** Schedule cron expression */
  schedule?: string;
  /** File path of the definition */
  file_path: string;
  /** Raw YAML frontmatter */
  raw_yaml: Record<string, unknown>;
}

export type AdapterType =
  | "osa"
  | "claude-code"
  | "codex"
  | "openclaw"
  | "jidoclaw"
  | "hermes"
  | "bash"
  | "http";

export interface AgentBudgetConfig {
  /** Daily limit in cents */
  daily_limit_cents?: number;
  /** Monthly limit in cents */
  monthly_limit_cents?: number;
  /** Warning threshold percentage (0-100) */
  warning_pct?: number;
  /** Hard stop on budget exceeded */
  hard_stop?: boolean;
}

// ── Project Definition ───────────────────────────────────────────────────────

export interface BizforgeProjectDef {
  /** Project ID (directory name) */
  id: string;
  /** Display name */
  name: string;
  /** Description */
  description?: string;
  /** Absolute path to project directory */
  path: string;
  /** Agent IDs assigned to this project */
  agents: string[];
  /** Tags */
  tags: string[];
}

// ── Schedule Definition ──────────────────────────────────────────────────────

export interface BizforgeScheduleDef {
  /** Schedule ID (filename without extension) */
  id: string;
  /** Agent ID this schedule belongs to */
  agent_id: string;
  /** Cron expression */
  cron: string;
  /** Human-readable description */
  description?: string;
  /** Whether enabled */
  enabled: boolean;
  /** Context/instructions for the heartbeat run */
  context?: string;
  /** File path */
  file_path: string;
}

// ── Skill Definition ─────────────────────────────────────────────────────────

export interface BizforgeSkillDef {
  /** Skill ID */
  id: string;
  /** Display name */
  name: string;
  /** Description */
  description: string;
  /** Category */
  category: string;
  /** Version */
  version?: string;
  /** File path */
  file_path: string;
}

// ── Filesystem Events (from Tauri IPC) ───────────────────────────────────────

export interface BizforgeFsEvent {
  /** Event type */
  kind: "create" | "modify" | "remove";
  /** Affected path relative to .bizforge/ */
  path: string;
  /** Timestamp */
  timestamp: string;
}
