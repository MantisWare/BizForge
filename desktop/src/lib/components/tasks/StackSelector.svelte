<!-- src/lib/components/tasks/StackSelector.svelte -->
<!-- Standalone tech stack selector used during scaffold flow -->
<script lang="ts">
  interface Props {
    value: string;
    onChange: (stack: string) => void;
  }

  let { value, onChange }: Props = $props();

  const STACKS = [
    { id: 'react', label: 'React', icon: '⚛️', desc: 'Vite + React 19 + TypeScript' },
    { id: 'nextjs', label: 'Next.js', icon: '▲', desc: 'App Router + RSC + TypeScript' },
    { id: 'sveltekit', label: 'SvelteKit', icon: '🔥', desc: 'Svelte 5 + Vite + TypeScript' },
    { id: 'phoenix', label: 'Phoenix', icon: '🐦', desc: 'Elixir + LiveView + PostgreSQL' },
    { id: 'express', label: 'Express', icon: '🟢', desc: 'Node.js + TypeScript + PostgreSQL' },
    { id: 'fastapi', label: 'FastAPI', icon: '🐍', desc: 'Python + Pydantic + SQLAlchemy' },
    { id: 'django', label: 'Django', icon: '🎸', desc: 'Python + DRF + PostgreSQL' },
    { id: 'rails', label: 'Rails', icon: '💎', desc: 'Ruby + PostgreSQL + Hotwire' },
    { id: 'go', label: 'Go', icon: '🐹', desc: 'Go + Gin/Chi + PostgreSQL' },
    { id: 'rust', label: 'Rust', icon: '🦀', desc: 'Axum/Actix + Diesel + PostgreSQL' },
  ];
</script>

<div class="ss-grid" role="radiogroup" aria-label="Tech stack selection">
  {#each STACKS as stack (stack.id)}
    <button
      type="button"
      class="ss-card"
      class:ss-card--active={value === stack.id}
      onclick={() => onChange(stack.id)}
      role="radio"
      aria-checked={value === stack.id}
    >
      <span class="ss-icon">{stack.icon}</span>
      <div class="ss-text">
        <span class="ss-label">{stack.label}</span>
        <span class="ss-desc">{stack.desc}</span>
      </div>
    </button>
  {/each}
</div>

<style>
  .ss-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
    gap: 6px;
  }

  .ss-card {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 10px 12px;
    border-radius: 8px;
    border: 1px solid var(--border-default);
    background: transparent;
    cursor: pointer;
    text-align: left;
    font-family: inherit;
    transition: all 100ms ease;
  }

  .ss-card:hover {
    border-color: rgba(249, 115, 22, 0.3);
    background: var(--bg-elevated);
  }

  .ss-card--active {
    border-color: #f97316;
    background: rgba(249, 115, 22, 0.06);
  }

  .ss-icon {
    font-size: 20px;
    flex-shrink: 0;
    width: 28px;
    text-align: center;
  }

  .ss-text {
    display: flex;
    flex-direction: column;
    gap: 1px;
    min-width: 0;
  }

  .ss-label {
    font-size: 13px;
    font-weight: 600;
    color: var(--text-primary);
  }

  .ss-desc {
    font-size: 10px;
    color: var(--text-muted);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
</style>
