<!-- src/lib/components/wizard/WorkspaceWizard.svelte -->
<script lang="ts">
  import { fly } from 'svelte/transition';
  import { wizardStore, type WizardStep } from '$lib/stores/wizard.svelte';
  import WizardProgress from './WizardProgress.svelte';
  import Step1Name from './steps/Step1Name.svelte';
  import Step2Documentation from './steps/Step2Documentation.svelte';
  import Step3CompanySelect from './steps/Step3CompanySelect.svelte';
  import Step4TeamReview from './steps/Step4TeamReview.svelte';
  import Step5ProjectSetup from './steps/Step5ProjectSetup.svelte';
  import Step6TaskGeneration from './steps/Step6TaskGeneration.svelte';
  import Step7Review from './steps/Step7Review.svelte';

  let showCloseConfirm = $state(false);
  let direction = $state<'forward' | 'back'>('forward');

  function handleClose(): void {
    const hasData =
      wizardStore.workspaceName.trim().length > 0 ||
      wizardStore.uploadedDocuments.length > 0 ||
      wizardStore.agents.length > 0;

    if (hasData && !wizardStore.launchComplete) {
      showCloseConfirm = true;
    } else {
      confirmClose();
    }
  }

  function confirmClose(): void {
    showCloseConfirm = false;
    wizardStore.reset();
    wizardStore.close();
  }

  function handleNext(): void {
    direction = 'forward';
    wizardStore.nextStep();
  }

  function handleBack(): void {
    direction = 'back';
    wizardStore.prevStep();
  }

  function handleGoToStep(step: WizardStep): void {
    direction = step < wizardStore.currentStep ? 'back' : 'forward';
    wizardStore.goToStep(step);
  }

  function handleBackdropClick(e: MouseEvent): void {
    if ((e.target as HTMLElement).classList.contains('wz-overlay')) {
      handleClose();
    }
  }

  function handleKeyDown(e: KeyboardEvent): void {
    if (e.key === 'Escape') {
      e.preventDefault();
      if (showCloseConfirm) {
        showCloseConfirm = false;
      } else {
        handleClose();
      }
    }
  }

  const STEP_LABELS: Record<number, string> = {
    1: 'Next: Upload Docs',
    2: 'Next: Choose Team',
    3: 'Next: Review Agents',
    4: 'Next: Project Setup',
    5: 'Next: Generate Tasks',
    6: 'Next: Review & Launch',
  };
</script>

{#if wizardStore.isOpen}
  <!-- svelte-ignore a11y_no_noninteractive_element_interactions a11y_click_events_have_key_events a11y_no_static_element_interactions -->
  <div
    class="wz-overlay"
    role="dialog"
    aria-modal="true"
    aria-label="New Workspace Wizard"
    onclick={handleBackdropClick}
    onkeydown={handleKeyDown}
    tabindex="-1"
    transition:fly={{ y: 20, duration: 200 }}
  >
    <div class="wz-modal" onclick={(e) => e.stopPropagation()}>
      <!-- Header -->
      <div class="wz-header">
        <div class="wz-header-top">
          <h2 class="wz-title">New Workspace</h2>
          <button class="wz-close" onclick={handleClose} aria-label="Close wizard">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <line x1="18" y1="6" x2="6" y2="18" /><line x1="6" y1="6" x2="18" y2="18" />
            </svg>
          </button>
        </div>
        <WizardProgress currentStep={wizardStore.currentStep} onGoToStep={handleGoToStep} />
      </div>

      <!-- Step content -->
      <div class="wz-body">
        {#key wizardStore.currentStep}
          <div
            class="wz-step-content"
            in:fly={{ x: direction === 'forward' ? 60 : -60, duration: 200, delay: 50 }}
            out:fly={{ x: direction === 'forward' ? -60 : 60, duration: 150 }}
          >
            {#if wizardStore.currentStep === 1}
              <Step1Name />
            {:else if wizardStore.currentStep === 2}
              <Step2Documentation />
            {:else if wizardStore.currentStep === 3}
              <Step3CompanySelect />
            {:else if wizardStore.currentStep === 4}
              <Step4TeamReview />
            {:else if wizardStore.currentStep === 5}
              <Step5ProjectSetup />
            {:else if wizardStore.currentStep === 6}
              <Step6TaskGeneration />
            {:else if wizardStore.currentStep === 7}
              <Step7Review />
            {/if}
          </div>
        {/key}
      </div>

      <!-- Footer navigation -->
      {#if wizardStore.currentStep < 7 || !wizardStore.isLaunching}
        <div class="wz-footer">
          <button
            class="wz-btn wz-btn--secondary"
            onclick={handleBack}
            disabled={wizardStore.currentStep === 1}
          >
            Back
          </button>
          <div class="wz-footer-spacer"></div>
          {#if wizardStore.currentStep < 7}
            <button
              class="wz-btn wz-btn--skip"
              onclick={handleNext}
            >
              Skip
            </button>
            <button
              class="wz-btn wz-btn--primary"
              onclick={handleNext}
              disabled={!wizardStore.canProceed}
            >
              {STEP_LABELS[wizardStore.currentStep] ?? 'Next'}
            </button>
          {/if}
        </div>
      {/if}
    </div>

    <!-- Close confirmation dialog -->
    {#if showCloseConfirm}
      <div class="wz-confirm-overlay" transition:fly={{ y: 10, duration: 150 }}>
        <div class="wz-confirm">
          <p class="wz-confirm-text">You have unsaved wizard progress. Are you sure you want to close?</p>
          <div class="wz-confirm-actions">
            <button class="wz-btn wz-btn--secondary" onclick={() => { showCloseConfirm = false; }}>
              Keep editing
            </button>
            <button class="wz-btn wz-btn--danger" onclick={confirmClose}>
              Discard & close
            </button>
          </div>
        </div>
      </div>
    {/if}
  </div>
{/if}

<style>
  .wz-overlay {
    position: fixed; inset: 0; z-index: 9000;
    background: rgba(0,0,0,0.65);
    display: flex; align-items: center; justify-content: center;
    backdrop-filter: blur(4px);
  }
  .wz-modal {
    width: 95vw; max-width: 920px;
    max-height: 90vh;
    background: var(--bg-primary, #1a1a2e);
    border: 1px solid var(--border-subtle, rgba(255,255,255,0.08));
    border-radius: 16px;
    display: flex; flex-direction: column;
    box-shadow: 0 24px 64px rgba(0,0,0,0.5), 0 0 0 1px rgba(255,255,255,0.04) inset;
    overflow: hidden;
  }
  .wz-header {
    padding: 20px 24px 16px;
    border-bottom: 1px solid var(--border-subtle, rgba(255,255,255,0.06));
    flex-shrink: 0;
  }
  .wz-header-top {
    display: flex; align-items: center; justify-content: space-between;
    margin-bottom: 16px;
  }
  .wz-title {
    font-size: 18px; font-weight: 600; margin: 0;
    color: var(--text-primary, #eee);
  }
  .wz-close {
    background: none; border: none; color: var(--text-tertiary);
    cursor: pointer; padding: 4px; border-radius: 6px;
    transition: all 0.15s;
  }
  .wz-close:hover { background: rgba(255,255,255,0.06); color: var(--text-primary); }
  .wz-body {
    flex: 1; overflow-y: auto; overflow-x: hidden;
    padding: 24px; min-height: 360px;
    position: relative;
  }
  .wz-step-content { min-height: 320px; }
  .wz-footer {
    display: flex; align-items: center; gap: 8px;
    padding: 16px 24px;
    border-top: 1px solid var(--border-subtle, rgba(255,255,255,0.06));
    flex-shrink: 0;
  }
  .wz-footer-spacer { flex: 1; }
  .wz-btn {
    padding: 8px 20px; border-radius: 8px; font-size: 13px; font-weight: 500;
    border: none; cursor: pointer; transition: all 0.15s;
    white-space: nowrap;
  }
  .wz-btn:disabled { opacity: 0.4; cursor: not-allowed; }
  .wz-btn--primary {
    background: var(--accent, #f97316); color: #fff;
  }
  .wz-btn--primary:not(:disabled):hover { filter: brightness(1.1); }
  .wz-btn--secondary {
    background: rgba(255,255,255,0.06); color: var(--text-secondary, #aaa);
  }
  .wz-btn--secondary:not(:disabled):hover { background: rgba(255,255,255,0.1); }
  .wz-btn--skip {
    background: none; color: var(--text-tertiary);
    padding: 8px 12px;
  }
  .wz-btn--skip:hover { color: var(--text-secondary); }
  .wz-btn--danger {
    background: #dc2626; color: #fff;
  }
  .wz-btn--danger:hover { filter: brightness(1.1); }
  .wz-confirm-overlay {
    position: absolute; inset: 0; z-index: 10;
    background: rgba(0,0,0,0.5);
    display: flex; align-items: center; justify-content: center;
  }
  .wz-confirm {
    background: var(--bg-primary, #1a1a2e);
    border: 1px solid var(--border-subtle, rgba(255,255,255,0.1));
    border-radius: 12px; padding: 24px; max-width: 400px;
    box-shadow: 0 12px 32px rgba(0,0,0,0.4);
  }
  .wz-confirm-text {
    margin: 0 0 16px; font-size: 14px; color: var(--text-primary); line-height: 1.5;
  }
  .wz-confirm-actions {
    display: flex; gap: 8px; justify-content: flex-end;
  }
</style>
