<!-- src/lib/components/layout/SidebarNavItem.svelte -->
<script lang="ts">
  interface Props {
    href: string;
    label: string;
    icon: string;
    shortcut?: string;
    badge?: number;
    active?: boolean;
    description?: string;
  }

  let { href, label, icon, shortcut, badge, active = false, description }: Props = $props();

  let showTooltip = $state(false);
  let infoEl: HTMLSpanElement | undefined = $state(undefined);
  let tipX = $state(0);
  let tipY = $state(0);

  function showInfo(e: MouseEvent): void {
    e.preventDefault();
    e.stopPropagation();
    if (infoEl === undefined) return;
    const rect = infoEl.getBoundingClientRect();
    tipX = rect.right + 10;
    tipY = rect.top + rect.height / 2;
    showTooltip = true;
  }

  function hideInfo(): void {
    showTooltip = false;
  }
</script>

<a
  {href}
  class="sni-item"
  class:active
  aria-current={active ? 'page' : undefined}
>
  <span class="sni-icon" aria-hidden="true">
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
      <path d={icon} />
    </svg>
  </span>

  <span class="sni-label">{label}</span>

  <span class="sni-right">
    {#if description}
      <!-- svelte-ignore a11y_no_static_element_interactions a11y_click_events_have_key_events a11y_no_noninteractive_element_interactions -->
      <span
        class="sni-info"
        bind:this={infoEl}
        onmouseenter={showInfo}
        onmouseleave={hideInfo}
        onclick={showInfo}
        role="note"
        aria-label="{label} info"
      >
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <circle cx="12" cy="12" r="10" />
          <path d="M12 16v-4" />
          <path d="M12 8h.01" />
        </svg>
      </span>
    {/if}
    {#if shortcut}
      <span class="sni-shortcut">{shortcut}</span>
    {/if}
    {#if badge !== undefined && badge > 0}
      <span class="sni-badge">{badge > 99 ? '99+' : badge}</span>
    {/if}
  </span>
</a>

{#if showTooltip && description}
  <div
    class="sni-tooltip"
    style="left: {tipX}px; top: {tipY}px;"
    role="tooltip"
  >
    {description}
  </div>
{/if}

<style>
  .sni-item {
    display: flex;
    align-items: center;
    gap: 8px;
    height: 32px;
    padding: 0 12px;
    border-radius: var(--radius-xs);
    text-decoration: none;
    color: var(--text-secondary);
    transition: background 120ms ease, color 120ms ease;
    position: relative;
    overflow: hidden;
  }

  .sni-item:hover {
    background: var(--bg-surface);
    color: var(--text-primary);
  }

  .sni-item.active {
    background: var(--bg-elevated);
    color: var(--text-primary);
  }

  .sni-item.active::before {
    content: '';
    position: absolute;
    left: 0;
    top: 6px;
    bottom: 6px;
    width: 2px;
    background: var(--accent-primary);
    border-radius: 0 1px 1px 0;
  }

  .sni-icon {
    flex-shrink: 0;
    display: flex;
    color: var(--text-tertiary);
    transition: color 120ms ease;
  }

  .sni-item:hover .sni-icon,
  .sni-item.active .sni-icon {
    color: var(--text-primary);
  }

  .sni-label {
    flex: 1;
    font-size: 13px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .sni-right {
    display: flex;
    align-items: center;
    gap: 4px;
    flex-shrink: 0;
  }

  .sni-info {
    display: flex;
    align-items: center;
    color: var(--text-muted);
    opacity: 0;
    transition: opacity 0.15s, color 0.15s;
    cursor: help;
  }

  .sni-item:hover .sni-info {
    opacity: 1;
  }

  .sni-info:hover {
    color: var(--text-secondary);
  }

  .sni-shortcut {
    font-size: 10px;
    color: var(--text-muted);
    letter-spacing: 0.02em;
  }

  .sni-badge {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 16px;
    height: 16px;
    padding: 0 4px;
    border-radius: 8px;
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    color: var(--text-secondary);
    font-size: 10px;
    font-weight: 500;
  }

  .sni-tooltip {
    position: fixed;
    transform: translateY(-50%);
    width: 220px;
    padding: 10px 12px;
    background: #1e2433;
    border: 1px solid #2e3650;
    border-radius: 8px;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.55);
    font-size: 12px;
    font-weight: 400;
    line-height: 1.55;
    color: #c8cdd8;
    white-space: normal;
    z-index: 9999;
    pointer-events: none;
  }
</style>
