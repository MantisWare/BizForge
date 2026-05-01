// src/lib/stores/organizations.svelte.ts
import type {
  Organization,
  OrganizationMembership,
  OrganizationCreateRequest,
} from "$api/types";
import { organizations as orgsApi } from "$api/client";
import { toastStore } from "./toasts.svelte";

class OrganizationsStore {
  organizations = $state<Organization[]>([]);
  current = $state<Organization | null>(null);
  members = $state<OrganizationMembership[]>([]);
  loading = $state(false);
  error = $state<string | null>(null);

  totalCount = $derived(this.organizations.length);

  async fetchOrganizations(): Promise<void> {
    console.log("[bizforge:orgs] Fetching organizations...");
    this.loading = true;
    try {
      this.organizations = await orgsApi.list();
      this.error = null;
      console.log(`[bizforge:orgs] Loaded ${this.organizations.length} organization(s)`);
      if (!this.current && this.organizations.length > 0) {
        this.current = this.organizations[0];
      }
    } catch (e) {
      const msg = (e as Error).message;
      this.error = msg;
      console.error(`[bizforge:orgs] Fetch failed: ${msg}`);
      if (!msg.includes("not_found") && !msg.includes("unauthorized")) {
        toastStore.error("Failed to load organizations", msg);
      }
    } finally {
      this.loading = false;
    }
  }

  /** Ensure at least one org exists; create a default if needed, then select it. */
  async ensureDefault(): Promise<void> {
    await this.fetchOrganizations();
    if (this.organizations.length === 0) {
      const name = "My Organization";
      const slug = name
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "-")
        .replace(/^-|-$/g, "");
      const created = await this.createOrganization({ name, slug });
      if (created) this.current = created;
    }
  }

  async createOrganization(
    data: OrganizationCreateRequest,
  ): Promise<Organization | null> {
    this.loading = true;
    try {
      const created = await orgsApi.create(data);
      this.organizations = [created, ...this.organizations];
      this.error = null;
      toastStore.success("Organization created", data.name);
      return created;
    } catch (e) {
      const msg = (e as Error).message;
      this.error = msg;
      toastStore.error("Failed to create organization", msg);
      return null;
    } finally {
      this.loading = false;
    }
  }

  async fetchMembers(organizationId: string): Promise<void> {
    this.loading = true;
    try {
      this.members = await orgsApi.members(organizationId);
      this.error = null;
    } catch (e) {
      const msg = (e as Error).message;
      this.error = msg;
      if (!msg.includes("not_found") && !msg.includes("unauthorized")) {
        toastStore.error("Failed to load members", msg);
      }
    } finally {
      this.loading = false;
    }
  }

  async selectOrganization(id: string): Promise<void> {
    try {
      const org = await orgsApi.get(id);
      this.current = org;
      this.error = null;
    } catch (e) {
      const msg = (e as Error).message;
      this.error = msg;
      if (!msg.includes("not_found") && !msg.includes("unauthorized")) {
        toastStore.error("Failed to load organization", msg);
      }
    }
  }

  setCurrent(org: Organization | null): void {
    this.current = org;
  }

  getById(id: string): Organization | null {
    return this.organizations.find((o) => o.id === id) ?? null;
  }
}

export const organizationsStore = new OrganizationsStore();
