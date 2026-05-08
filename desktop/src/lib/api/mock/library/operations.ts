// Operation data (companies) — 6 operations

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
  {
    id: "domo-consultancy",
    name: "Domo Consultancy",
    emoji: "globe",
    description:
      "Full-service Domo design, development, and administration consultancy — 9 specialized agents spanning project management, UI/UX development, backend engineering, custom app building, data pipeline architecture, workflow automation, quality assurance, and instance administration. Covers the entire Domo lifecycle from initial instance setup and user provisioning through app scaffolding, data integration, and production deployment.",
    agent_count: 9,
    skill_count: 13,
    required_skills: [
      "domo-app-scaffold",
      "domo-appdb-manage",
      "domo-app-publish",
      "domo-code-engine",
      "domo-connector-build",
      "domo-dataset-manage",
      "domo-magic-etl",
      "domo-workflow-automate",
      "domo-embed-analytics",
      "domo-api-integrate",
      "domo-governance",
      "domo-data-science",
      "domo-instance-admin",
      "sprint-planning",
      "delegate",
      "board",
    ],
    category: "domo",
  },
];

export const OPERATIONS: LibraryOperation[] =
  RAW_OPERATIONS.map(enrichOperation);
