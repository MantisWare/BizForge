<!-- src/lib/components/wizard/WizardProgress.svelte -->
<script lang="ts">
  import { WIZARD_STEP_LABELS, type WizardStep } from '$lib/stores/wizard.svelte';

  interface Props {
    currentStep: WizardStep;
    onGoToStep: (step: WizardStep) => void;
  }

  let { currentStep, onGoToStep }: Props = $props();
</script>

<div class="wz-progress" role="navigation" aria-label="Wizard steps">
  {#each WIZARD_STEP_LABELS as label, idx}
    {@const stepNum = (idx + 1) as WizardStep}
    {@const isActive = stepNum === currentStep}
    {@const isCompleted = stepNum < currentStep}
    {@const isClickable = stepNum < currentStep}
    <button
      class="wz-step"
      class:active={isActive}
      class:completed={isCompleted}
      disabled={!isClickable}
      onclick={() => { if (isClickable) onGoToStep(stepNum); }}
      aria-current={isActive ? 'step' : undefined}
      aria-label="{label} (step {stepNum} of {WIZARD_STEP_LABELS.length})"
    >
      <span class="wz-dot">
        {#if isCompleted}
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <polyline points="20 6 9 17 4 12" />
          </svg>
        {:else}
          <span class="wz-dot-num">{stepNum}</span>
        {/if}
      </span>
      <span class="wz-label">{label}</span>
    </button>
    {#if idx < WIZARD_STEP_LABELS.length - 1}
      <div class="wz-connector" class:filled={stepNum < currentStep}></div>
    {/if}
  {/each}
</div>

<style>
  .wz-progress {
    display: flex; align-items: center; justify-content: center;
    gap: 0; padding: 0 24px;
  }
  .wz-step {
    display: flex; flex-direction: column; align-items: center; gap: 6px;
    background: none; border: none; cursor: default;
    padding: 4px 8px; min-width: 56px; transition: opacity 0.15s;
    color: var(--text-tertiary);
  }
  .wz-step:not(:disabled) { cursor: pointer; }
  .wz-step:not(:disabled):hover { opacity: 0.8; }
  .wz-step.active { color: var(--accent, #f97316); }
  .wz-step.completed { color: var(--text-secondary); }
  .wz-dot {
    width: 28px; height: 28px; border-radius: 50%;
    display: flex; align-items: center; justify-content: center;
    font-size: 12px; font-weight: 600;
    border: 2px solid var(--border-subtle, rgba(255,255,255,0.08));
    transition: all 0.2s;
  }
  .wz-step.active .wz-dot {
    border-color: var(--accent, #f97316);
    background: rgba(249,115,22,0.15);
    color: var(--accent, #f97316);
  }
  .wz-step.completed .wz-dot {
    border-color: var(--accent, #f97316);
    background: var(--accent, #f97316);
    color: #fff;
  }
  .wz-dot-num { font-variant-numeric: tabular-nums; }
  .wz-label {
    font-size: 11px; font-weight: 500;
    white-space: nowrap; letter-spacing: 0.01em;
  }
  .wz-connector {
    flex: 1; height: 2px; min-width: 20px; max-width: 48px;
    background: var(--border-subtle, rgba(255,255,255,0.08));
    margin-bottom: 22px; transition: background 0.2s;
  }
  .wz-connector.filled { background: var(--accent, #f97316); }
</style>
