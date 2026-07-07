<!-- Shared button primitive -->
<script lang="ts">
  import type { Snippet } from 'svelte';

  interface Props {
    variant?: 'primary' | 'secondary' | 'ghost';
    size?: 'sm' | 'md';
    disabled?: boolean;
    type?: 'button' | 'submit' | 'reset';
    onclick?: (e: MouseEvent) => void;
    children: Snippet;
    class?: string;
    ariaLabel?: string;
  }

  let {
    variant = 'secondary',
    size = 'md',
    disabled = false,
    type = 'button',
    onclick,
    children,
    class: className = '',
    ariaLabel,
  }: Props = $props();
</script>

<button
  {type}
  class="ds-btn ds-btn--{variant} {size === 'sm' ? 'ds-btn--sm' : ''} {className}"
  {disabled}
  {onclick}
  aria-label={ariaLabel}
>
  {@render children()}
</button>
