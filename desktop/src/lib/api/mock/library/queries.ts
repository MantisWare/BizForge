// Library query functions — the public API consumed by UI routes

import type {
  CompositionMember,
  LibraryAgent,
  LibrarySkill,
  LibraryOperation,
  LibraryTemplate,
} from "./types";
import { AGENTS } from "./agents";
import { SKILLS } from "./skills";
import { OPERATIONS } from "./operations";
import { TEMPLATES } from "./templates";

// ── Composition resolution ──────────────────────────────────────────────────

const skillIndex = new Map<string, LibrarySkill>();
for (const s of SKILLS) {
  skillIndex.set(s.id, s);
}

function resolveSkillMembers(requiredIds: readonly string[]): CompositionMember[] {
  const members: CompositionMember[] = [];
  for (const id of requiredIds) {
    const skill = skillIndex.get(id);
    if (skill !== undefined) {
      members.push({ id: skill.id, name: skill.name, description: skill.description });
    }
  }
  return members.sort((a, b) => a.name.localeCompare(b.name));
}

function resolveAgentMembers(
  requiredSkillIds: readonly string[],
  count: number,
): CompositionMember[] {
  const skillSet = new Set(requiredSkillIds);

  const scored = AGENTS.map((agent) => {
    const overlap = agent.required_skills.filter((s) => skillSet.has(s)).length;
    return { agent, overlap };
  });

  scored.sort((a, b) => {
    if (b.overlap !== a.overlap) return b.overlap - a.overlap;
    return a.agent.name.localeCompare(b.agent.name);
  });

  return scored
    .filter((s) => s.overlap > 0)
    .slice(0, count)
    .map(({ agent }) => ({
      id: agent.id,
      name: agent.name,
      description: agent.description,
    }))
    .sort((a, b) => a.name.localeCompare(b.name));
}

function hydrateOperation(op: LibraryOperation): LibraryOperation {
  if (op.member_agents.length > 0) return op;
  return {
    ...op,
    member_agents: resolveAgentMembers(op.required_skills, op.agent_count),
    member_skills: resolveSkillMembers(op.required_skills),
  };
}

function hydrateTemplate(tmpl: LibraryTemplate): LibraryTemplate {
  if (tmpl.member_agents.length > 0) return tmpl;
  return {
    ...tmpl,
    member_agents: resolveAgentMembers(tmpl.required_skills, tmpl.agent_count),
    member_skills: resolveSkillMembers(tmpl.required_skills),
  };
}

// ── Public API ──────────────────────────────────────────────────────────────

export function getLibraryAgents(): LibraryAgent[] {
  return [...AGENTS].sort((a, b) => a.name.localeCompare(b.name));
}

export function getLibraryAgentsByCategory(): Map<string, LibraryAgent[]> {
  const sorted = [...AGENTS].sort((a, b) => a.name.localeCompare(b.name));
  const map = new Map<string, LibraryAgent[]>();
  for (const agent of sorted) {
    const list = map.get(agent.category) ?? [];
    list.push(agent);
    map.set(agent.category, list);
  }
  return map;
}

export function getLibrarySkills(): LibrarySkill[] {
  return [...SKILLS].sort((a, b) => a.name.localeCompare(b.name));
}

export function getLibrarySkillsByCategory(): Map<string, LibrarySkill[]> {
  const sorted = [...SKILLS].sort((a, b) => a.name.localeCompare(b.name));
  const map = new Map<string, LibrarySkill[]>();
  for (const skill of sorted) {
    const list = map.get(skill.category) ?? [];
    list.push(skill);
    map.set(skill.category, list);
  }
  return map;
}

export function getLibraryOperations(): LibraryOperation[] {
  return [...OPERATIONS].sort((a, b) => a.name.localeCompare(b.name));
}

export function getLibraryTemplates(): LibraryTemplate[] {
  return [...TEMPLATES].sort((a, b) => a.name.localeCompare(b.name));
}

export function getLibraryCategoryCounts(): {
  agents: Map<string, number>;
  skills: Map<string, number>;
} {
  const agents = new Map<string, number>();
  for (const agent of AGENTS) {
    agents.set(agent.category, (agents.get(agent.category) ?? 0) + 1);
  }

  const skills = new Map<string, number>();
  for (const skill of SKILLS) {
    skills.set(skill.category, (skills.get(skill.category) ?? 0) + 1);
  }

  return { agents, skills };
}

export function getLibraryAgentDetail(id: string): LibraryAgent | null {
  return AGENTS.find((a) => a.id === id) ?? null;
}

export function getLibrarySkillDetail(id: string): LibrarySkill | null {
  return SKILLS.find((s) => s.id === id) ?? null;
}

export function getLibraryTeamDetail(id: string): LibraryTemplate | null {
  const tmpl = TEMPLATES.find((t) => t.id === id) ?? null;
  return tmpl !== null ? hydrateTemplate(tmpl) : null;
}

export function getLibraryCompanyDetail(id: string): LibraryOperation | null {
  const op = OPERATIONS.find((o) => o.id === id) ?? null;
  return op !== null ? hydrateOperation(op) : null;
}
