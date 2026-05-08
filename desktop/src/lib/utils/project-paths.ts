/**
 * Project output directory path conventions.
 *
 * Maps artifact types to their canonical subdirectory within a project's output_path.
 * All agents and stores should use these helpers so artifacts land in consistent locations.
 */

export type ArtifactCategory =
  | "code"
  | "docs"
  | "media"
  | "data"
  | "reports"
  | "transcripts"
  | "issues";

const CATEGORY_DIRS: Record<ArtifactCategory, string> = {
  code: "code/src",
  docs: "docs",
  media: "media",
  data: "data",
  reports: "reports",
  transcripts: "transcripts",
  issues: "issues",
};

const DOC_SUBDIRS: Record<string, string> = {
  prd: "docs/specs",
  technical_spec: "docs/specs",
  architecture: "docs/architecture",
  api_docs: "docs/api",
  user_guide: "docs/guides",
  runbook: "docs/guides",
  custom: "docs",
};

/**
 * Resolve the full file path within a project output directory.
 * @param outputPath - The project's root output_path
 * @param category - The artifact category
 * @param filename - The filename (e.g. "requirements.md")
 */
export function resolveProjectFilePath(
  outputPath: string,
  category: ArtifactCategory,
  filename: string,
): string {
  const dir = CATEGORY_DIRS[category];
  const normalized = outputPath.replace(/\/+$/, "");
  return `${normalized}/${dir}/${filename}`;
}

/**
 * Resolve the path for a generated document based on its type.
 * Uses more specific subdirectories for doc types (specs vs guides vs api).
 */
export function resolveDocPath(
  outputPath: string,
  docType: string,
  filename: string,
): string {
  const subdir = DOC_SUBDIRS[docType] ?? "docs";
  const normalized = outputPath.replace(/\/+$/, "");
  return `${normalized}/${subdir}/${filename}`;
}

/**
 * Resolve a relative path for use with MCP tools (no output_path prefix).
 */
export function relativeProjectPath(
  category: ArtifactCategory,
  filename: string,
): string {
  return `${CATEGORY_DIRS[category]}/${filename}`;
}

/**
 * Resolve a relative doc path for a specific document type.
 */
export function relativeDocPath(docType: string, filename: string): string {
  const subdir = DOC_SUBDIRS[docType] ?? "docs";
  return `${subdir}/${filename}`;
}
