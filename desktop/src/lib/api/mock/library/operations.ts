// Operation data (companies) — 5 operations

import type { LibraryOperation } from "./types";
import type { RawOperation } from "./enrichment";
import { enrichOperation } from "./enrichment";

const RAW_OPERATIONS: RawOperation[] = [
  {
    id: "growth-os",
    name: "Growth OS",
    emoji: "rocket",
    description:
      "Creator business growth operating system — 36 agents across 6 modes covering research, content, outreach, sales, and analytics.",
    agent_count: 36,
    skill_count: 42,
    required_skills: [
      "research", "web-search", "summarize", "blog", "newsletter", "social-post",
      "video-script", "competitive-analysis", "swot", "ads-google", "ads-meta",
      "ads-plan", "ads-creative", "ads-budget", "stats", "pipeline", "delegate",
      "board", "roadmap", "okr",
    ],
    category: "growth",
  },
  {
    id: "sales-engine",
    name: "Sales Engine",
    emoji: "briefcase",
    description:
      "B2B SaaS sales operation — full-cycle pipeline from prospect to closed-won.",
    agent_count: 5,
    skill_count: 5,
    required_skills: [
      "research", "web-search", "summarize", "competitive-analysis",
      "blog", "stats", "delegate", "board",
    ],
    category: "sales",
  },
  {
    id: "dev-shop",
    name: "Dev Shop",
    emoji: "building",
    description:
      "Software development operation — spec to production with quality-first engineering.",
    agent_count: 6,
    skill_count: 6,
    required_skills: [
      "build", "test", "deploy", "code-review", "debug", "refactor",
      "sprint-planning", "release", "commit", "create-pr", "review-pr",
      "delegate", "board",
    ],
    category: "engineering",
  },
  {
    id: "content-factory",
    name: "Content Factory",
    emoji: "document-text",
    description:
      "Content production operation — ideation to published, optimized, multi-platform content.",
    agent_count: 5,
    skill_count: 5,
    required_skills: [
      "blog", "newsletter", "social-post", "video-script", "press-release",
      "research", "web-search", "summarize", "ads-creative",
    ],
    category: "marketing",
  },
  {
    id: "cognitive-os",
    name: "Cognitive OS",
    emoji: "light-bulb",
    description:
      "Personal knowledge management system — capture, organize, retrieve, and synthesize information.",
    agent_count: 4,
    skill_count: 14,
    required_skills: [
      "research", "summarize", "extract", "classify", "synthesize", "index",
      "web-search", "doc-search", "pattern-capture", "memory-consolidate",
      "context-inject", "compare", "cite",
    ],
    category: "productivity",
  },
];

export const OPERATIONS: LibraryOperation[] =
  RAW_OPERATIONS.map(enrichOperation);
