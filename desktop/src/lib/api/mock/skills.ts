import type { Skill, SkillCategory, SkillSource } from "../types";

let mockSkillData: Skill[] = [
  {
    id: "skill-codegen",
    name: "Code Generation",
    description:
      "Generate, refactor, and review source code across multiple languages.",
    category: "core",
    source: "builtin",
    enabled: true,
    triggers: ["implement", "write", "refactor", "generate code"],
    version: "1.0.0",
    author: "MIOSA",
  },
  {
    id: "skill-search",
    name: "Web Search",
    description:
      "Search the web for documentation, research papers, and technical references.",
    category: "utility",
    source: "builtin",
    enabled: true,
    triggers: ["search", "find", "look up", "research"],
    version: "1.0.0",
    author: "MIOSA",
  },
  {
    id: "skill-review",
    name: "PR Review",
    description:
      "Review pull requests for correctness, security, and style adherence.",
    category: "core",
    source: "builtin",
    enabled: true,
    triggers: ["review", "PR", "pull request", "LGTM"],
    version: "1.0.0",
    author: "MIOSA",
  },
  {
    id: "skill-deploy",
    name: "Deployment",
    description:
      "Deploy services to staging and production via automated pipelines.",
    category: "automation",
    source: "builtin",
    enabled: false,
    triggers: ["deploy", "release", "rollout", "ship"],
    version: "1.0.0",
    author: "MIOSA",
  },
];

export function mockSkills(): Skill[] {
  return mockSkillData;
}

export function getSkillById(id: string): Skill | undefined {
  return mockSkillData.find((s) => s.id === id);
}

export function toggleSkill(id: string): Skill | undefined {
  const idx = mockSkillData.findIndex((s) => s.id === id);
  if (idx === -1) return undefined;
  mockSkillData[idx] = {
    ...mockSkillData[idx],
    enabled: !mockSkillData[idx].enabled,
  };
  return mockSkillData[idx];
}

export function addSkill(skill: Skill): Skill {
  const existing = mockSkillData.find((s) => s.id === skill.id);
  if (existing !== undefined) {
    return existing;
  }
  mockSkillData = [...mockSkillData, skill];
  return skill;
}

export function bulkEnableSkills(ids: string[]): void {
  const idSet = new Set(ids);
  mockSkillData = mockSkillData.map((s) =>
    idSet.has(s.id) ? { ...s, enabled: true } : s,
  );
}

export function importSkill(body: {
  id: string;
  name: string;
  description: string;
  category?: string;
  version?: string;
}): Skill {
  const skill: Skill = {
    id: body.id,
    name: body.name,
    description: body.description,
    category: (body.category ?? "imported") as SkillCategory,
    source: "library" as SkillSource,
    enabled: true,
    triggers: [],
    version: body.version ?? "1.0.0",
    author: "Library",
  };
  return addSkill(skill);
}
