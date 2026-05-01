<!-- src/routes/app/users/+page.svelte -->
<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import PageShell from '$lib/components/layout/PageShell.svelte';
  import { usersStore } from '$lib/stores/users.svelte';
  import type { User, UserRole } from '$api/types';

  const isAuthError = $derived(
    usersStore.error !== null &&
    (usersStore.error.includes('unauthorized') || usersStore.error.includes('401'))
  );

  onMount(() => {
    void usersStore.fetchUsers();
  });

  const ROLE_FILTERS: { value: UserRole | 'all'; label: string }[] = [
    { value: 'all', label: 'All' },
    { value: 'admin', label: 'Admin' },
    { value: 'member', label: 'Member' },
    { value: 'viewer', label: 'Viewer' },
  ];

  const ROLES: { value: UserRole; label: string }[] = [
    { value: 'admin', label: 'Admin' },
    { value: 'member', label: 'Member' },
    { value: 'viewer', label: 'Viewer' },
  ];

  // Add user form
  let showAddForm = $state(false);
  let addName = $state('');
  let addEmail = $state('');
  let addRole = $state<UserRole>('member');
  let addPassword = $state('');
  let addSubmitting = $state(false);
  let addError = $state<string | null>(null);

  // Edit user form
  let editingUser = $state<User | null>(null);
  let editName = $state('');
  let editEmail = $state('');
  let editSubmitting = $state(false);

  // Delete confirm
  let confirmDeleteId = $state<string | null>(null);
  let deleting = $state(false);

  // Role change in-flight
  let roleChangingId = $state<string | null>(null);

  function roleClass(role: UserRole): string {
    return { admin: 'usr-role--admin', member: 'usr-role--member', viewer: 'usr-role--viewer' }[role];
  }

  function initials(name: string): string {
    return name.split(' ').slice(0, 2).map((w) => w[0] ?? '').join('').toUpperCase();
  }

  // ── Add ──────────────────────────────────────────────────────────────────────
  async function handleAdd() {
    if (!addName.trim() || !addEmail.trim()) return;
    addSubmitting = true;
    addError = null;
    const created = await usersStore.createUser({
      name: addName.trim(),
      email: addEmail.trim(),
      role: addRole,
    });
    addSubmitting = false;
    if (created !== null) {
      resetAddForm();
    } else {
      addError = usersStore.error;
    }
  }

  function resetAddForm() {
    showAddForm = false;
    addName = '';
    addEmail = '';
    addRole = 'member';
    addPassword = '';
    addError = null;
  }

  // ── Edit ─────────────────────────────────────────────────────────────────────
  function startEdit(user: User) {
    editingUser = user;
    editName = user.name;
    editEmail = user.email;
  }

  async function handleSaveEdit() {
    if (editingUser === null || !editName.trim() || !editEmail.trim()) return;
    editSubmitting = true;
    const updated = await usersStore.updateUser(editingUser.id, {
      name: editName.trim(),
      email: editEmail.trim(),
    });
    editSubmitting = false;
    if (updated !== null) {
      editingUser = null;
    }
  }

  function cancelEdit() {
    editingUser = null;
  }

  // ── Role change ──────────────────────────────────────────────────────────────
  async function handleRoleChange(user: User, newRole: UserRole) {
    if (user.role === newRole) return;
    roleChangingId = user.id;
    await usersStore.updateUser(user.id, { role: newRole });
    roleChangingId = null;
  }

  // ── Delete ───────────────────────────────────────────────────────────────────
  async function handleDelete(id: string) {
    if (confirmDeleteId !== id) {
      confirmDeleteId = id;
      return;
    }
    confirmDeleteId = null;
    deleting = true;
    await usersStore.deleteUser(id);
    deleting = false;
  }

  function cancelDelete() {
    confirmDeleteId = null;
  }
</script>

<PageShell
  title="Users"
  subtitle="{usersStore.adminCount} admin"
  badge={usersStore.totalCount > 0 ? usersStore.totalCount : undefined}
>
  {#snippet actions()}
    <div class="usr-filter-group" role="group" aria-label="Filter by role">
      {#each ROLE_FILTERS as opt (opt.value)}
        <button
          class="usr-filter-btn"
          class:usr-filter-btn--active={usersStore.filterRole === opt.value}
          onclick={() => usersStore.setRoleFilter(opt.value)}
          aria-pressed={usersStore.filterRole === opt.value}
          type="button"
        >
          {opt.label}
        </button>
      {/each}
    </div>
    <input
      class="usr-search"
      type="search"
      placeholder="Search by name or email…"
      value={usersStore.searchQuery}
      oninput={(e) => usersStore.setSearch((e.target as HTMLInputElement).value)}
      aria-label="Search users"
    />
    <button
      class="usr-add-btn"
      onclick={() => showAddForm = true}
      type="button"
      aria-label="Add user"
    >
      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" aria-hidden="true">
        <path d="M12 5v14M5 12h14" />
      </svg>
      Add User
    </button>
  {/snippet}

  {#if usersStore.loading && usersStore.users.length === 0}
    <div class="usr-loading" role="status" aria-live="polite">
      <div class="usr-spinner" aria-hidden="true"></div>
      <span>Loading users…</span>
    </div>
  {:else if usersStore.error !== null && usersStore.users.length === 0}
    <div class="usr-empty" role="alert">
      <div class="usr-error-icon" aria-hidden="true">
        <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
          {#if isAuthError}
            <rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>
          {:else}
            <circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/>
          {/if}
        </svg>
      </div>
      {#if isAuthError}
        <p class="usr-error-title">Authentication required</p>
        <p class="usr-error-detail">Your session has expired or you are not signed in. Please sign in to view users.</p>
        <div class="usr-error-actions">
          <button class="usr-retry-btn usr-retry-btn--primary" onclick={() => void goto('/auth')} type="button">Sign in</button>
          <button class="usr-retry-btn" onclick={() => void usersStore.fetchUsers()} type="button">Retry</button>
        </div>
      {:else}
        <p class="usr-error-title">Unable to load users</p>
        <p class="usr-error-detail">{usersStore.error}</p>
        <button class="usr-retry-btn" onclick={() => void usersStore.fetchUsers()} type="button">Retry</button>
      {/if}
    </div>
  {:else if usersStore.filteredUsers.length === 0}
    <div class="usr-empty" role="status">
      <p>{usersStore.searchQuery || usersStore.filterRole !== 'all'
        ? 'No users match the current filter.'
        : 'No users yet. Add your first user to get started.'}</p>
      {#if !usersStore.searchQuery && usersStore.filterRole === 'all'}
        <button class="usr-add-btn" onclick={() => showAddForm = true} type="button">Add User</button>
      {/if}
    </div>
  {:else}
    <div class="usr-list" role="list" aria-label="Users">
      {#each usersStore.filteredUsers as user (user.id)}
        {@const joinDate = user.created_at ?? user.inserted_at ?? ''}
        <div
          class="usr-row"
          role="listitem"
          class:usr-row--selected={usersStore.selected?.id === user.id}
        >
          <button
            class="usr-avatar"
            onclick={() => usersStore.selectUser(usersStore.selected?.id === user.id ? null : user)}
            aria-label="Select {user.name}"
            type="button"
          >
            {#if user.avatar_url !== undefined && user.avatar_url !== null}
              <img src={user.avatar_url} alt={user.name} class="usr-avatar-img" />
            {:else}
              <span class="usr-avatar-initials">{initials(user.name)}</span>
            {/if}
          </button>
          <div class="usr-info">
            <div class="usr-name">{user.name}</div>
            <div class="usr-email">{user.email}</div>
          </div>

          <!-- Role selector -->
          <select
            class="usr-role-select {roleClass(user.role)}"
            value={user.role}
            onchange={(e) => void handleRoleChange(user, (e.target as HTMLSelectElement).value as UserRole)}
            disabled={roleChangingId === user.id}
            aria-label="Change role for {user.name}"
          >
            {#each ROLES as r}
              <option value={r.value}>{r.label}</option>
            {/each}
          </select>

          <time class="usr-joined" datetime={joinDate}>
            {joinDate ? new Date(joinDate).toLocaleDateString() : '—'}
          </time>

          <!-- Action buttons -->
          <div class="usr-actions">
            <button
              class="usr-action-btn"
              onclick={() => startEdit(user)}
              aria-label="Edit {user.name}"
              title="Edit user"
              type="button"
            >
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7" />
                <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z" />
              </svg>
            </button>
            {#if confirmDeleteId === user.id}
              <button
                class="usr-action-btn usr-action-btn--danger-active"
                onclick={() => void handleDelete(user.id)}
                aria-label="Confirm delete {user.name}"
                title="Click again to confirm"
                type="button"
              >
                Confirm?
              </button>
              <button
                class="usr-action-btn"
                onclick={cancelDelete}
                aria-label="Cancel delete"
                title="Cancel"
                type="button"
              >
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                  <path d="M18 6 6 18M6 6l12 12" />
                </svg>
              </button>
            {:else}
              <button
                class="usr-action-btn usr-action-btn--danger"
                onclick={() => void handleDelete(user.id)}
                aria-label="Delete {user.name}"
                title="Remove user"
                type="button"
              >
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                  <path d="M3 6h18M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" />
                </svg>
              </button>
            {/if}
          </div>
        </div>
      {/each}
    </div>
  {/if}
</PageShell>

<!-- Add User dialog -->
{#if showAddForm}
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    class="usr-overlay"
    role="dialog"
    aria-modal="true"
    aria-label="Add user"
    onclick={(e) => { if (e.target === e.currentTarget) resetAddForm(); }}
    onkeydown={(e) => { if (e.key === 'Escape') resetAddForm(); }}
  >
    <div class="usr-dialog">
      <h2 class="usr-dialog-title">Add User</h2>

      <div class="usr-field">
        <label class="usr-label" for="usr-add-name">Name</label>
        <input
          id="usr-add-name"
          class="usr-input"
          type="text"
          placeholder="Jane Doe"
          bind:value={addName}
          autofocus
        />
      </div>

      <div class="usr-field">
        <label class="usr-label" for="usr-add-email">Email</label>
        <input
          id="usr-add-email"
          class="usr-input"
          type="email"
          placeholder="jane@company.com"
          bind:value={addEmail}
        />
      </div>

      <div class="usr-field">
        <label class="usr-label" for="usr-add-role">Role</label>
        <select id="usr-add-role" class="usr-input usr-select-input" bind:value={addRole}>
          {#each ROLES as r}
            <option value={r.value}>{r.label}</option>
          {/each}
        </select>
      </div>

      <div class="usr-field">
        <label class="usr-label" for="usr-add-password">
          Password <span class="usr-label-hint">(optional — generated if blank)</span>
        </label>
        <input
          id="usr-add-password"
          class="usr-input"
          type="password"
          placeholder="••••••••"
          bind:value={addPassword}
        />
      </div>

      {#if addError !== null}
        <p class="usr-form-error" role="alert">{addError}</p>
      {/if}

      <div class="usr-dialog-actions">
        <button class="usr-btn-ghost" onclick={resetAddForm} disabled={addSubmitting} type="button">Cancel</button>
        <button
          class="usr-btn-primary"
          onclick={handleAdd}
          disabled={addSubmitting || !addName.trim() || !addEmail.trim()}
          type="button"
        >
          {addSubmitting ? 'Creating…' : 'Add User'}
        </button>
      </div>
    </div>
  </div>
{/if}

<!-- Edit User dialog -->
{#if editingUser !== null}
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    class="usr-overlay"
    role="dialog"
    aria-modal="true"
    aria-label="Edit user"
    onclick={(e) => { if (e.target === e.currentTarget) cancelEdit(); }}
    onkeydown={(e) => { if (e.key === 'Escape') cancelEdit(); }}
  >
    <div class="usr-dialog">
      <h2 class="usr-dialog-title">Edit User</h2>

      <div class="usr-field">
        <label class="usr-label" for="usr-edit-name">Name</label>
        <input
          id="usr-edit-name"
          class="usr-input"
          type="text"
          bind:value={editName}
          autofocus
        />
      </div>

      <div class="usr-field">
        <label class="usr-label" for="usr-edit-email">Email</label>
        <input
          id="usr-edit-email"
          class="usr-input"
          type="email"
          bind:value={editEmail}
        />
      </div>

      <div class="usr-dialog-actions">
        <button class="usr-btn-ghost" onclick={cancelEdit} disabled={editSubmitting} type="button">Cancel</button>
        <button
          class="usr-btn-primary"
          onclick={handleSaveEdit}
          disabled={editSubmitting || !editName.trim() || !editEmail.trim()}
          type="button"
        >
          {editSubmitting ? 'Saving…' : 'Save Changes'}
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  /* ── Header controls ────────────────────────────────────────────────────────── */
  .usr-filter-group {
    display: flex; align-items: center; gap: 2px;
    background: var(--dbg2); border: 1px solid var(--dbd); border-radius: 8px; padding: 2px;
  }
  .usr-filter-btn {
    background: none; border: none; border-radius: 6px; color: var(--dt3);
    font-size: 12px; font-weight: 500; padding: 3px 10px; cursor: pointer;
    transition: background 120ms ease, color 120ms ease;
  }
  .usr-filter-btn:hover { color: var(--dt2); background: rgba(255,255,255,0.05); }
  .usr-filter-btn--active { background: var(--dbg3); color: var(--dt); border: 1px solid var(--dbd); }

  .usr-search {
    height: 28px; padding: 0 10px; border-radius: 6px; font-size: 12px;
    background: var(--dbg2); border: 1px solid var(--dbd); color: var(--dt); min-width: 220px;
  }
  .usr-search:focus { outline: none; border-color: #f97316; }

  .usr-add-btn {
    height: 28px; padding: 0 12px; border-radius: 6px; font-size: 12px; font-weight: 500;
    background: #f97316; border: none; color: white; cursor: pointer;
    display: flex; align-items: center; gap: 5px;
    transition: background 120ms ease; white-space: nowrap;
  }
  .usr-add-btn:hover { background: #ea580c; }

  /* ── Loading / Empty ────────────────────────────────────────────────────────── */
  .usr-loading, .usr-empty {
    display: flex; flex-direction: column; align-items: center;
    justify-content: center; gap: 12px; height: 240px;
    color: var(--dt3); font-size: 13px;
  }
  .usr-empty p { margin: 0; }
  .usr-error-icon { color: var(--dt3); opacity: 0.7; margin-bottom: 4px; }
  .usr-error-title { font-size: 14px; font-weight: 600; color: var(--dt1); margin: 0; }
  .usr-error-detail { font-size: 12px; color: var(--dt3); max-width: 320px; text-align: center; margin: 0; }
  .usr-error-actions { display: flex; gap: 8px; margin-top: 4px; }
  .usr-spinner {
    width: 24px; height: 24px; border-radius: 50%;
    border: 2px solid var(--dbd); border-top-color: var(--dt2);
    animation: usr-spin 0.8s linear infinite;
  }
  @keyframes usr-spin { to { transform: rotate(360deg); } }
  .usr-retry-btn {
    padding: 6px 14px; border-radius: 6px; font-size: 12px; cursor: pointer;
    border: 1px solid var(--dbd); background: var(--dbg2); color: var(--dt2);
  }
  .usr-retry-btn--primary {
    background: var(--accent, #e8731a); color: #fff; border-color: transparent;
  }

  /* ── User list ──────────────────────────────────────────────────────────────── */
  .usr-list { display: flex; flex-direction: column; gap: 4px; }
  .usr-row {
    display: flex; align-items: center; gap: 14px;
    padding: 10px 16px; border-radius: 8px;
    background: var(--dbg2); border: 1px solid var(--dbd);
    transition: background 120ms ease, border-color 120ms ease;
  }
  .usr-row:hover { background: var(--dbg3); }
  .usr-row--selected { border-color: #f97316; background: color-mix(in srgb, #f97316 6%, var(--dbg2)); }

  .usr-avatar {
    width: 36px; height: 36px; border-radius: 50%; flex-shrink: 0;
    background: var(--dbg3); border: 1px solid var(--dbd); cursor: pointer;
    overflow: hidden; display: flex; align-items: center; justify-content: center;
  }
  .usr-avatar-img { width: 100%; height: 100%; object-fit: cover; }
  .usr-avatar-initials { font-size: 12px; font-weight: 600; color: var(--dt2); }

  .usr-info { flex: 1; min-width: 0; }
  .usr-name { font-size: 14px; font-weight: 500; color: var(--dt); }
  .usr-email { font-size: 12px; color: var(--dt3); }

  /* ── Role select ────────────────────────────────────────────────────────────── */
  .usr-role-select {
    font-size: 11px; font-weight: 500; padding: 2px 22px 2px 8px; border-radius: 4px;
    appearance: none; cursor: pointer; border: 1px solid transparent;
    text-transform: capitalize; flex-shrink: 0; height: 24px;
    background-image: url("data:image/svg+xml,%3Csvg width='8' height='5' viewBox='0 0 8 5' fill='none' xmlns='http://www.w3.org/2000/svg'%3E%3Cpath d='M1 1l3 3 3-3' stroke='%23888' stroke-width='1.2' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E");
    background-repeat: no-repeat; background-position: right 6px center;
    transition: border-color 120ms ease, background-color 120ms ease;
    outline: none;
  }
  .usr-role-select:hover { border-color: var(--dbd); }
  .usr-role-select:focus { border-color: #f97316; }
  .usr-role-select:disabled { opacity: 0.5; cursor: wait; }
  .usr-role--admin { background-color: color-mix(in srgb, #ef4444 15%, transparent); color: #fca5a5; }
  .usr-role--member { background-color: color-mix(in srgb, #f97316 15%, transparent); color: #fdba74; }
  .usr-role--viewer { background-color: var(--dbg3); color: var(--dt3); }

  .usr-joined { font-size: 11px; color: var(--dt4); flex-shrink: 0; min-width: 80px; }

  /* ── Action buttons ─────────────────────────────────────────────────────────── */
  .usr-actions {
    display: flex; gap: 4px; flex-shrink: 0;
  }
  .usr-action-btn {
    width: 28px; height: 28px; border-radius: 5px; border: 1px solid transparent;
    background: transparent; color: var(--dt4); cursor: pointer;
    display: flex; align-items: center; justify-content: center;
    transition: all 120ms ease; font-size: 11px; font-weight: 500; white-space: nowrap;
  }
  .usr-action-btn:hover {
    background: var(--dbg3); border-color: var(--dbd); color: var(--dt2);
  }
  .usr-action-btn--danger:hover {
    background: rgba(239,68,68,0.1); border-color: rgba(239,68,68,0.3); color: #fca5a5;
  }
  .usr-action-btn--danger-active {
    width: auto; padding: 0 8px;
    background: rgba(239,68,68,0.12); border-color: rgba(239,68,68,0.4); color: #fca5a5;
  }

  /* ── Dialogs ────────────────────────────────────────────────────────────────── */
  .usr-overlay {
    position: fixed; inset: 0; background: rgba(0,0,0,0.5); backdrop-filter: blur(3px);
    display: flex; align-items: center; justify-content: center; z-index: 1000;
  }
  .usr-dialog {
    background: var(--dbg2); border: 1px solid var(--dbd); border-radius: 12px;
    padding: 24px; width: 440px; max-width: calc(100vw - 40px);
    display: flex; flex-direction: column; gap: 16px;
    box-shadow: 0 16px 48px rgba(0,0,0,0.4);
  }
  .usr-dialog-title { font-size: 16px; font-weight: 600; color: var(--dt); margin: 0; }
  .usr-field { display: flex; flex-direction: column; gap: 6px; }
  .usr-label { font-size: 12px; font-weight: 500; color: var(--dt2); }
  .usr-label-hint { font-weight: 400; color: var(--dt4); }
  .usr-input {
    height: 34px; padding: 0 10px; border-radius: 6px; font-size: 13px;
    background: var(--dbg3); border: 1px solid var(--dbd); color: var(--dt);
    width: 100%; box-sizing: border-box; font-family: var(--font-sans);
    outline: none;
  }
  .usr-select-input { appearance: none; cursor: pointer; }
  .usr-input:focus { border-color: #f97316; }
  .usr-form-error { font-size: 12px; color: #fca5a5; margin: 0; }
  .usr-dialog-actions { display: flex; gap: 8px; justify-content: flex-end; margin-top: 4px; }
  .usr-btn-ghost, .usr-btn-primary {
    padding: 7px 16px; border-radius: 6px; font-size: 13px; font-weight: 500; cursor: pointer;
    transition: all 120ms ease;
  }
  .usr-btn-ghost { background: transparent; border: 1px solid var(--dbd); color: var(--dt3); }
  .usr-btn-ghost:hover:not(:disabled) { background: var(--dbg3); color: var(--dt2); }
  .usr-btn-primary { background: #f97316; border: none; color: #fff; }
  .usr-btn-primary:hover:not(:disabled) { background: #ea580c; }
  .usr-btn-ghost:disabled, .usr-btn-primary:disabled { opacity: 0.5; cursor: not-allowed; }
</style>
