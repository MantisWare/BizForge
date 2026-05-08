// src/lib/stores/wizard.svelte.ts
import type {
  WizardDocument,
  WizardAgent,
  WizardTask,
  WizardSprintGroup,
  CompanyRecommendation,
} from "$api/types";

export type WizardStep = 1 | 2 | 3 | 4 | 5 | 6 | 7;

export const WIZARD_STEP_LABELS: readonly string[] = [
  "Name",
  "Documentation",
  "Company",
  "Team",
  "Project",
  "Tasks",
  "Launch",
] as const;

export interface LaunchStep {
  id: string;
  label: string;
  status: "pending" | "running" | "done" | "error" | "skipped";
  error?: string;
}

class WizardStore {
  isOpen = $state(false);
  currentStep = $state<WizardStep>(1);
  readonly totalSteps: number = 7;

  // Step 1 — Name
  workspaceName = $state("");
  workspaceDescription = $state("");
  workspacePath = $state("");

  // Step 2 — Documentation
  uploadedDocuments = $state<WizardDocument[]>([]);
  userContext = $state("");
  enhancedContext = $state<string | null>(null);
  isEnhancing = $state(false);
  enhanceSessionId = $state<string | null>(null);

  // Step 3 — Company
  aiRecommendation = $state<CompanyRecommendation | null>(null);
  selectedCompanyTemplate = $state<string | null>(null);
  selectedTeamTemplates = $state<string[]>([]);
  isAnalyzing = $state(false);

  // Step 4 — Team
  agents = $state<WizardAgent[]>([]);
  sharedAdapter = $state("osa");
  sharedModel = $state("claude-sonnet-4-6");

  // Step 5 — Project
  projectName = $state("");
  projectDescription = $state("");
  outputPath = $state("");
  lifecycleTemplate = $state("generic_development");
  autoAssign = $state(true);

  // Step 6 — Tasks
  sprintGroups = $state<WizardSprintGroup[]>([]);
  isGeneratingTasks = $state(false);
  taskGenerationComplete = $state(false);

  // Step 7 — Launch
  launchSteps = $state<LaunchStep[]>([]);
  isLaunching = $state(false);
  launchComplete = $state(false);

  // Derived
  get allTasks(): WizardTask[] {
    return this.sprintGroups.flatMap((g) => g.tasks);
  }

  get selectedTaskCount(): number {
    return this.allTasks.filter((t) => t.selected).length;
  }

  get canProceed(): boolean {
    switch (this.currentStep) {
      case 1:
        return this.workspaceName.trim().length > 0;
      case 2:
        return (
          this.uploadedDocuments.length > 0 ||
          this.userContext.trim().length > 0 ||
          this.enhancedContext !== null
        );
      case 3:
        return this.selectedTeamTemplates.length > 0;
      case 4:
        return this.agents.length > 0;
      case 5:
        return this.projectName.trim().length > 0;
      case 6:
        return true;
      case 7:
        return true;
      default:
        return false;
    }
  }

  open(): void {
    this.isOpen = true;
  }

  close(): void {
    this.isOpen = false;
  }

  reset(): void {
    this.currentStep = 1;
    this.workspaceName = "";
    this.workspaceDescription = "";
    this.workspacePath = "";
    this.uploadedDocuments = [];
    this.userContext = "";
    this.enhancedContext = null;
    this.isEnhancing = false;
    this.enhanceSessionId = null;
    this.aiRecommendation = null;
    this.selectedCompanyTemplate = null;
    this.selectedTeamTemplates = [];
    this.isAnalyzing = false;
    this.agents = [];
    this.sharedAdapter = "osa";
    this.sharedModel = "claude-sonnet-4-6";
    this.projectName = "";
    this.projectDescription = "";
    this.outputPath = "";
    this.lifecycleTemplate = "generic_development";
    this.autoAssign = true;
    this.sprintGroups = [];
    this.isGeneratingTasks = false;
    this.taskGenerationComplete = false;
    this.launchSteps = [];
    this.isLaunching = false;
    this.launchComplete = false;
  }

  nextStep(): void {
    if (this.currentStep < 7 && this.canProceed) {
      this.currentStep = (this.currentStep + 1) as WizardStep;
    }
  }

  prevStep(): void {
    if (this.currentStep > 1) {
      this.currentStep = (this.currentStep - 1) as WizardStep;
    }
  }

  goToStep(step: WizardStep): void {
    if (step >= 1 && step <= 7) {
      this.currentStep = step;
    }
  }

  addDocument(doc: WizardDocument): void {
    if (this.uploadedDocuments.some((d) => d.id === doc.id)) return;
    this.uploadedDocuments = [...this.uploadedDocuments, doc];
  }

  removeDocument(id: string): void {
    this.uploadedDocuments = this.uploadedDocuments.filter((d) => d.id !== id);
  }

  addTeamTemplate(id: string): void {
    if (this.selectedTeamTemplates.includes(id)) return;
    this.selectedTeamTemplates = [...this.selectedTeamTemplates, id];
  }

  removeTeamTemplate(id: string): void {
    this.selectedTeamTemplates = this.selectedTeamTemplates.filter(
      (t) => t !== id,
    );
    this.agents = this.agents.filter((a) => a.teamId !== id);
  }

  removeAgent(id: string): void {
    this.agents = this.agents.filter((a) => a.id !== id);
  }

  toggleTask(id: string): void {
    this.sprintGroups = this.sprintGroups.map((g) => ({
      ...g,
      tasks: g.tasks.map((t) =>
        t.id === id ? { ...t, selected: !t.selected } : t,
      ),
    }));
  }

  selectAllTasks(): void {
    this.sprintGroups = this.sprintGroups.map((g) => ({
      ...g,
      tasks: g.tasks.map((t) => ({ ...t, selected: true })),
    }));
  }

  deselectAllTasks(): void {
    this.sprintGroups = this.sprintGroups.map((g) => ({
      ...g,
      tasks: g.tasks.map((t) => ({ ...t, selected: false })),
    }));
  }

  updateLaunchStep(
    id: string,
    status: LaunchStep["status"],
    error?: string,
  ): void {
    this.launchSteps = this.launchSteps.map((s) =>
      s.id === id ? { ...s, status, error } : s,
    );
  }
}

export const wizardStore = new WizardStore();
