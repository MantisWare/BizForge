<!-- Empty state placeholder -->
<script lang="ts">
  import type { Snippet } from 'svelte';

  interface Props {
    title: string;
    description?: string;
    icon?: Snippet;
    actions?: Snippet;
  }

  let { title, description, icon, actions }: Props = $props();
</script>

<div class="ds-empty">
  {#if icon}
    <div class="ds-empty-icon" aria-hidden="true">
      {@render icon()}
    </div>
  {/if}
  <h3 class="ds-empty-title">{title}</h3>
  {#if description}
    <p class="ds-empty-desc">{description}</p>
  {/if}
  {#if actions}
    <div class="ds-empty-actions">
      {@render actions()}
    </div>
  {/if}
</div>

<style>
  .ds-empty-icon {
    color: var(--text-muted);
    opacity: 0.7;
  }
  .ds-empty-actions {
    display: flex;
    gap: 8px;
    margin-top: 4px;
  }
</style>
