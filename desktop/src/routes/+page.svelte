<script lang="ts">
  import { goto } from '$app/navigation';
  import { browser } from '$app/environment';
  import { onMount } from 'svelte';
  import { initializeAuth, getToken, isFirstRun } from '$api/client';

  /**
   * Determine where to send the user after auth initializes.
   *
   * Decision tree:
   *
   *  1. initializeAuth() — probes /health, reads /auth/status (_firstRun),
   *     restores saved token, attempts dev auto-login if VITE_DEV_EMAIL set.
   *
   *  2. Backend unreachable, no token:
   *       → /auth         (show login, disconnected banner visible)
   *
   *  3. Backend reachable, no users yet (_firstRun = true):
   *       → /auth         (show registration form)
   *
   *  4. Backend reachable, users exist, but no valid token:
   *       → /auth         (show login form)
   *
   *  5. Backend reachable, valid token, onboarding not complete:
   *       → /onboarding
   *
   *  6. Backend reachable, valid token, onboarding complete:
   *       → /app
   */
  async function resolveDestination(): Promise<'/app' | '/onboarding' | '/auth'> {
    await initializeAuth();

    // Case 3 — first install, no users in DB yet
    if (isFirstRun()) {
      return '/auth';
    }

    // Cases 2 & 4 — backend down or no valid token
    if (getToken() === null) {
      return '/auth';
    }

    // Cases 5 & 6 — authenticated; check onboarding state
    return isOnboardingComplete() ? '/app' : '/onboarding';
  }

  /** Check both localStorage keys used for onboarding state. */
  function isOnboardingComplete(): boolean {
    if (typeof localStorage === 'undefined') return false;
    if (localStorage.getItem('bizforge-onboarding-complete') === 'true') return true;
    try {
      const raw = localStorage.getItem('bizforge-onboarding');
      return raw ? (JSON.parse(raw) as { completed?: boolean }).completed === true : false;
    } catch {
      return false;
    }
  }

  onMount(async () => {
    if (!browser) return;
    const dest = await resolveDestination();
    goto(dest, { replaceState: true });
  });
</script>
