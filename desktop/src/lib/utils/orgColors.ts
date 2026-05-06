// Deterministic color generation for teams and divisions in the office visualization.

export interface AgentOrgInfo {
  teamId: string | null;
  teamName: string | null;
  teamColor: string | null;
  divisionId: string | null;
  divisionName: string | null;
  divisionColor: string | null;
}

function djb2(str: string): number {
  let hash = 5381;
  for (let i = 0; i < str.length; i++) {
    hash = ((hash << 5) - hash + str.charCodeAt(i)) >>> 0;
  }
  return hash;
}

const UNASSIGNED_COLOR = "#4a4a5a";

/**
 * Deterministic team color — vivid, saturated HSL derived from team id.
 * Returns a consistent hue per team with high saturation so it pops
 * against the dark office backgrounds.
 */
export function teamColor(id: string | null | undefined): string {
  if (id === null || id === undefined) return UNASSIGNED_COLOR;
  const hue = djb2(id) % 360;
  return `hsl(${hue}, 65%, 55%)`;
}

/**
 * Deterministic division color — uses a shifted saturation/lightness band
 * so division indicators are visually distinct from team indicators.
 */
export function divisionColor(id: string | null | undefined): string {
  if (id === null || id === undefined) return UNASSIGNED_COLOR;
  const hue = djb2(id) % 360;
  return `hsl(${hue}, 50%, 65%)`;
}

export const UNASSIGNED_ORG: AgentOrgInfo = {
  teamId: null,
  teamName: null,
  teamColor: null,
  divisionId: null,
  divisionName: null,
  divisionColor: null,
};
