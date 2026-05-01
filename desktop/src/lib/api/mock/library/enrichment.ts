// Deterministic enrichment helpers — hash-based metadata generation

import type {
  LibraryAgent,
  LibrarySkill,
  LibraryOperation,
  LibraryTemplate,
  Visibility,
} from "./types";

const TAG_POOL = [
  "automation",
  "analysis",
  "generation",
  "optimization",
  "monitoring",
  "security",
  "testing",
  "deployment",
  "integration",
  "reporting",
  "ai-native",
  "real-time",
  "batch",
  "streaming",
  "composable",
  "enterprise",
  "starter",
  "advanced",
  "lightweight",
  "full-stack",
] as const;

function hashId(id: string): number {
  let h = 0;
  for (let i = 0; i < id.length; i++) {
    h = (Math.imul(31, h) + id.charCodeAt(i)) | 0;
  }
  return Math.abs(h);
}

function deriveTags(id: string, category: string): string[] {
  const h = hashId(id);
  const count = 2 + (h % 3);
  const result: string[] = [];
  const catTag = category.replace("-", " ");
  const poolTags: string[] = [];
  for (let i = 0; i < TAG_POOL.length; i++) {
    poolTags.push(TAG_POOL[(h + i * 7) % TAG_POOL.length]);
  }
  const seen = new Set<string>([catTag]);
  result.push(catTag);
  for (const t of poolTags) {
    if (!seen.has(t)) {
      seen.add(t);
      result.push(t);
    }
    if (result.length >= count) break;
  }
  return result;
}

function deriveVersion(id: string): string {
  const h = hashId(id + "ver");
  const major = 1 + (h % 3);
  const minor = h % 10;
  const patch = (h >> 4) % 10;
  return `${major}.${minor}.${patch}`;
}

// ── Raw input types (before enrichment) ──────────────────────────────────────

export type RawAgent = Omit<
  LibraryAgent,
  "tags" | "visibility" | "version" | "isOfficial" | "required_skills"
> & { version?: string; required_skills?: string[] };

export type RawSkill = Omit<
  LibrarySkill,
  "enabled" | "tags" | "visibility" | "version" | "isOfficial"
> & { version?: string };

export type RawOperation = Omit<
  LibraryOperation,
  "emoji" | "tags" | "version" | "isOfficial" | "required_skills"
> & { emoji?: string; version?: string; required_skills?: string[] };

export type RawTemplate = Omit<
  LibraryTemplate,
  "emoji" | "tags" | "version" | "isOfficial" | "required_skills"
> & { emoji?: string; version?: string; required_skills?: string[] };

// ── Enrichment functions ─────────────────────────────────────────────────────

export function enrichAgent(a: RawAgent): LibraryAgent {
  const isOfficial = a.adapter === "osa";
  return {
    ...a,
    required_skills: a.required_skills ?? [],
    isOfficial,
    tags: deriveTags(a.id, a.category),
    visibility: "public" as Visibility,
    version: a.version ?? deriveVersion(a.id),
  };
}

export function enrichSkill(s: RawSkill): LibrarySkill {
  const isOfficial = true;
  return {
    ...s,
    enabled: false,
    isOfficial,
    tags: deriveTags(s.id, s.category),
    visibility: "public" as Visibility,
    version: s.version ?? deriveVersion(s.id),
  };
}

export function enrichOperation(o: RawOperation): LibraryOperation {
  const isOfficial = true;
  return {
    ...o,
    required_skills: o.required_skills ?? [],
    emoji: o.emoji ?? "building",
    isOfficial,
    tags: deriveTags(o.id, o.category),
    version: o.version ?? deriveVersion(o.id),
  };
}

export function enrichTemplate(t: RawTemplate): LibraryTemplate {
  const isOfficial = true;
  return {
    ...t,
    required_skills: t.required_skills ?? [],
    emoji: t.emoji ?? "document-text",
    isOfficial,
    tags: deriveTags(t.id, t.size),
    version: t.version ?? deriveVersion(t.id),
  };
}
