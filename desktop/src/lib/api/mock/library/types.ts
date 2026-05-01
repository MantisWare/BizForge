// Library type definitions

export type Visibility = "public" | "unlisted" | "private";

export interface LibraryAgent {
  id: string;
  name: string;
  emoji: string;
  category: string;
  role: string;
  adapter: string;
  budget: number;
  description: string;
  required_skills: string[];
  tags: string[];
  visibility: Visibility;
  version: string;
  isOfficial: boolean;
}

export interface LibrarySkill {
  id: string;
  name: string;
  category: string;
  description: string;
  enabled: boolean;
  tags: string[];
  visibility: Visibility;
  version: string;
  isOfficial: boolean;
}

export interface LibraryOperation {
  id: string;
  name: string;
  description: string;
  agent_count: number;
  skill_count: number;
  required_skills: string[];
  category: string;
  emoji: string;
  tags: string[];
  version: string;
  isOfficial: boolean;
}

export interface LibraryTemplate {
  id: string;
  name: string;
  description: string;
  size: string;
  agent_count: number;
  required_skills: string[];
  emoji: string;
  tags: string[];
  version: string;
  isOfficial: boolean;
}
