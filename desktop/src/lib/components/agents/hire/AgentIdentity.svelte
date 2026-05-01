<!-- src/lib/components/agents/hire/AgentIdentity.svelte -->
<script lang="ts">
  import { ALL_ICONS, ICON_CATEGORIES, getIconDef } from '$lib/utils/agent-icons';

  interface Props {
    name: string;
    displayName: string;
    emoji: string;
    role: string;
    errors: Record<string, string>;
    onName: (v: string) => void;
    onDisplayName: (v: string) => void;
    onEmoji: (v: string) => void;
    onRole: (v: string) => void;
  }

  let {
    name,
    displayName,
    emoji,
    role,
    errors,
    onName,
    onDisplayName,
    onEmoji,
    onRole,
  }: Props = $props();

  let activeCategory = $state<string | null>(null);

  const filteredIcons = $derived(
    activeCategory !== null
      ? ALL_ICONS.filter((ic) => ic.category === activeCategory)
      : ALL_ICONS,
  );
</script>

<section class="hid-section">
  <h3 class="hid-section-title">Identity</h3>

  <!-- Icon picker -->
  <div class="hid-field">
    <label class="hid-label">Avatar Icon</label>

    <div class="hid-cat-row" role="tablist" aria-label="Icon categories">
      <button
        type="button"
        class="hid-cat-btn"
        class:hid-cat-btn--active={activeCategory === null}
        onclick={() => { activeCategory = null; }}
        role="tab"
        aria-selected={activeCategory === null}
      >All</button>
      {#each ICON_CATEGORIES as cat}
        <button
          type="button"
          class="hid-cat-btn"
          class:hid-cat-btn--active={activeCategory === cat}
          onclick={() => { activeCategory = cat; }}
          role="tab"
          aria-selected={activeCategory === cat}
        >{cat}</button>
      {/each}
    </div>

    <div class="hid-icon-grid" role="group" aria-label="Choose avatar icon">
      {#each filteredIcons as ic (ic.id)}
        <button
          type="button"
          class="hid-icon-btn"
          class:hid-icon-btn--selected={emoji === ic.id}
          onclick={() => onEmoji(ic.id)}
          aria-label="Use {ic.label} as avatar"
          aria-pressed={emoji === ic.id}
          title={ic.label}
        >
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
            {#each ic.paths as d}
              <path d={d} />
            {/each}
          </svg>
        </button>
      {/each}
    </div>
    <span class="hid-hint" aria-live="polite">
      {(() => {
        const sel = getIconDef(emoji);
        return sel !== undefined ? `Selected: ${sel.label}` : `Selected: ${emoji}`;
      })()}
    </span>
  </div>

  <div class="hid-row">
    <div class="hid-field">
      <label class="hid-label" for="hid-name">Name <span class="hid-required">*</span></label>
      <input
        id="hid-name"
        class="hid-input"
        class:hid-input--error={errors.name}
        type="text"
        value={name}
        oninput={(e) => onName((e.target as HTMLInputElement).value)}
        placeholder="scout"
        autocomplete="off"
        aria-describedby={errors.name ? 'hid-name-error' : undefined}
        aria-required="true"
      />
      {#if errors.name}
        <span id="hid-name-error" class="hid-error" role="alert">{errors.name}</span>
      {/if}
    </div>

    <div class="hid-field">
      <label class="hid-label" for="hid-display-name">Display Name <span class="hid-required">*</span></label>
      <input
        id="hid-display-name"
        class="hid-input"
        class:hid-input--error={errors.displayName}
        type="text"
        value={displayName}
        oninput={(e) => onDisplayName((e.target as HTMLInputElement).value)}
        placeholder="Scout"
        autocomplete="off"
        aria-describedby={errors.displayName ? 'hid-display-name-error' : undefined}
        aria-required="true"
      />
      {#if errors.displayName}
        <span id="hid-display-name-error" class="hid-error" role="alert">{errors.displayName}</span>
      {/if}
    </div>
  </div>

  <div class="hid-field">
    <label class="hid-label" for="hid-role">Role <span class="hid-required">*</span></label>
    <input
      id="hid-role"
      class="hid-input"
      class:hid-input--error={errors.role}
      type="text"
      value={role}
      oninput={(e) => onRole((e.target as HTMLInputElement).value)}
      placeholder="Security Analyst"
      autocomplete="off"
      aria-describedby={errors.role ? 'hid-role-error' : undefined}
      aria-required="true"
    />
    {#if errors.role}
      <span id="hid-role-error" class="hid-error" role="alert">{errors.role}</span>
    {/if}
  </div>
</section>

<style>
  .hid-section {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .hid-section-title {
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.6px;
    color: var(--text-tertiary);
    margin: 0;
    padding-bottom: 8px;
    border-bottom: 1px solid var(--border-default);
  }

  .hid-row {
    display: flex;
    gap: 12px;
  }

  .hid-row .hid-field {
    flex: 1;
  }

  .hid-field {
    display: flex;
    flex-direction: column;
    gap: 5px;
  }

  .hid-label {
    font-size: 12px;
    font-weight: 500;
    color: var(--text-secondary);
  }

  .hid-required {
    color: var(--accent-error);
  }

  .hid-hint {
    font-size: 11px;
    color: var(--text-muted);
  }

  .hid-error {
    font-size: 11px;
    color: var(--accent-error);
  }

  .hid-input {
    height: 34px;
    padding: 0 10px;
    border-radius: var(--radius-sm);
    border: 1px solid var(--border-default);
    background: var(--bg-surface);
    color: var(--text-primary);
    font-size: 13px;
    font-family: var(--font-sans);
    outline: none;
    transition: border-color 120ms ease;
  }

  .hid-input:focus {
    border-color: var(--border-focus);
  }

  .hid-input--error {
    border-color: var(--accent-error);
  }

  /* ── Category tabs ── */
  .hid-cat-row {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
  }

  .hid-cat-btn {
    height: 24px;
    padding: 0 10px;
    border-radius: 12px;
    border: 1px solid var(--border-default);
    background: transparent;
    color: var(--text-tertiary);
    font-size: 11px;
    font-weight: 500;
    font-family: var(--font-sans);
    cursor: pointer;
    transition: all 120ms ease;
    white-space: nowrap;
  }

  .hid-cat-btn:hover {
    background: var(--bg-elevated);
    color: var(--text-secondary);
  }

  .hid-cat-btn--active {
    background: rgba(242, 101, 34, 0.15);
    border-color: rgba(242, 101, 34, 0.4);
    color: #f26522;
  }

  /* ── Icon grid ── */
  .hid-icon-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(38px, 1fr));
    gap: 4px;
    max-height: 220px;
    overflow-y: auto;
    padding: 2px;
  }

  .hid-icon-grid::-webkit-scrollbar {
    width: 4px;
  }

  .hid-icon-grid::-webkit-scrollbar-thumb {
    background: var(--border-default);
    border-radius: 2px;
  }

  .hid-icon-btn {
    width: 38px;
    height: 38px;
    border-radius: var(--radius-xs);
    border: 1px solid transparent;
    background: transparent;
    color: var(--text-tertiary);
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: all 100ms ease;
  }

  .hid-icon-btn:hover {
    background: var(--bg-elevated);
    border-color: var(--border-default);
    color: var(--text-primary);
  }

  .hid-icon-btn--selected {
    background: rgba(242, 101, 34, 0.15);
    border-color: rgba(242, 101, 34, 0.4);
    color: #f26522;
  }
</style>
