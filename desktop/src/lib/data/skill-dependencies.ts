// Skill dependency resolution — maps loose agent skill tags to real library skill IDs
// and provides helpers for resolving, partitioning, and looking up skills.

import type { Skill } from "$api/types";
import type {
  LibraryAgent,
  LibraryOperation,
  LibrarySkill,
  LibraryTemplate,
} from "$lib/api/mock/library/types";
import { getLibrarySkillDetail } from "$lib/api/mock/library/queries";

/**
 * Maps loose skill tags (used in team-templates.ts and bundled template agents)
 * to actual library skill IDs from library/skills.ts.
 */
export const AGENT_SKILL_TAG_MAP: Readonly<Record<string, readonly string[]>> = {
  // development
  code:       ["build", "debug", "refactor"],
  debug:      ["debug", "error-analysis"],
  test:       ["test", "tdd"],
  validate:   ["validate", "test"],
  fix:        ["fix", "debug"],

  // coordination / management
  plan:       ["roadmap", "sprint-planning"],
  prioritize: ["roadmap", "okr"],
  delegate:   ["delegate"],
  track:      ["board", "standup"],
  schedule:   ["sprint-planning", "standup"],
  coordinate: ["delegate", "board"],

  // research / knowledge
  web_search: ["web-search", "research"],
  analyze:    ["research", "summarize", "classify"],
  summarize:  ["summarize", "extract"],
  research:   ["research", "web-search"],
  enrich:     ["extract", "research"],
  visualize:  ["stats", "graph"],
  forecast:   ["stats", "research"],
  report:     ["stats", "summarize"],
  diagnose:   ["error-analysis", "health"],

  // writing / content
  write:      ["blog", "newsletter"],
  edit:       ["code-review", "lint"],
  format:     ["blog", "social-post"],
  seo:        ["blog", "web-search"],
  personalize:["blog", "social-post"],
  sequence:   ["newsletter", "social-post"],

  // design / creative
  design:     ["ads-creative"],
  brand:      ["ads-creative", "ads-audit"],

  // ops / infrastructure
  deploy:     ["deploy", "pipeline"],
  monitor:    ["health", "heartbeat"],
  provision:  ["deploy", "configure"],
  alert:      ["health", "heartbeat"],
  scan:       ["security-scan", "secret-scan"],
  remediate:  ["harden", "fix"],
  audit:      ["audit", "compliance"],

  // data engineering
  pipeline:   ["pipeline", "transform"],
  transform:  ["transform", "clean"],
  query:      ["pipeline", "extract"],
  train:      ["stats", "validate"],
  evaluate:   ["validate", "stats"],

  // ide supervision
  supervise:  ["code-review", "delegate", "ide-orchestrate"],
  instruct:   ["delegate", "ide-orchestrate"],

  // qa automation
  qa_automate:    ["qa-automate", "qa-report", "qa-startup-probe"],
  qa_test:        ["qa-automate", "test", "tdd"],
  qa_report:      ["qa-report", "error-analysis"],
  startup_probe:  ["qa-startup-probe"],
  "qa-automate":  ["qa-automate"],
  "qa-report":    ["qa-report"],
  "qa-startup-probe": ["qa-startup-probe"],

  // domo-specific (passthrough — these are already library skill IDs)
  "domo-app-scaffold":       ["domo-app-scaffold"],
  "domo-api-integrate":      ["domo-api-integrate"],
  "domo-governance":         ["domo-governance"],
  "domo-code-engine":        ["domo-code-engine"],
  "domo-appdb-manage":       ["domo-appdb-manage"],
  "domo-app-publish":        ["domo-app-publish"],
  "domo-embed-analytics":    ["domo-embed-analytics"],
  "domo-connector-build":    ["domo-connector-build"],
  "domo-dataset-manage":     ["domo-dataset-manage"],
  "domo-magic-etl":          ["domo-magic-etl"],
  "domo-data-science":       ["domo-data-science"],
  "domo-workflow-automate":  ["domo-workflow-automate"],
  "domo-instance-admin":     ["domo-instance-admin"],
} as const;

/**
 * Resolve an agent's loose skill tags into deduplicated library skill IDs.
 */
export function resolveSkillsForAgent(agent: { skills: string[] }): string[] {
  const ids = new Set<string>();
  for (const tag of agent.skills) {
    const mapped = AGENT_SKILL_TAG_MAP[tag];
    if (mapped !== undefined) {
      for (const id of mapped) ids.add(id);
    }
  }
  return [...ids];
}

/**
 * Resolve skills for an entire team of agents (union of all agents' resolved skills).
 */
export function resolveSkillsForTeam(
  agents: ReadonlyArray<{ skills: string[] }>,
): string[] {
  const ids = new Set<string>();
  for (const agent of agents) {
    for (const id of resolveSkillsForAgent(agent)) {
      ids.add(id);
    }
  }
  return [...ids];
}

/**
 * Read `required_skills` directly from a library catalog entity.
 */
export function resolveSkillsForLibraryEntity(
  entity: LibraryAgent | LibraryTemplate | LibraryOperation,
): string[] {
  return [...entity.required_skills];
}

export interface PartitionedSkills {
  alreadyActive: LibrarySkill[];
  toAdd: LibrarySkill[];
}

/**
 * Partition required skill IDs into those already in the workspace
 * and those that need to be installed.
 */
export function partitionSkills(
  requiredIds: string[],
  workspaceSkills: Skill[],
): PartitionedSkills {
  const wsEnabledSet = new Set(workspaceSkills.filter((s) => s.enabled).map((s) => s.id));
  const seen = new Set<string>();

  const alreadyActive: LibrarySkill[] = [];
  const toAdd: LibrarySkill[] = [];

  for (const id of requiredIds) {
    if (seen.has(id)) continue;
    seen.add(id);

    const libSkill = getLibrarySkillDetail(id);
    if (libSkill === null) continue;

    if (wsEnabledSet.has(id)) {
      alreadyActive.push(libSkill);
    } else {
      toAdd.push(libSkill);
    }
  }

  return { alreadyActive, toAdd };
}

/**
 * Look up full LibrarySkill objects for a list of skill IDs.
 * Silently skips IDs that don't exist in the catalog.
 */
export function lookupLibrarySkills(ids: string[]): LibrarySkill[] {
  const result: LibrarySkill[] = [];
  for (const id of ids) {
    const skill = getLibrarySkillDetail(id);
    if (skill !== null) result.push(skill);
  }
  return result;
}
