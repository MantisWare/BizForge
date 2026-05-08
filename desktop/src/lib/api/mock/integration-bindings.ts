import type { IntegrationBinding, IntegrationBindingOwner } from "../types";

let bindingsState: IntegrationBinding[] = [];

export function getIntegrationBindings(
  ownerType?: IntegrationBindingOwner,
  ownerId?: string,
): IntegrationBinding[] {
  if (ownerType !== undefined && ownerId !== undefined) {
    return bindingsState.filter(
      (b) => b.owner_type === ownerType && b.owner_id === ownerId,
    );
  }
  return bindingsState;
}

export function createIntegrationBinding(
  ownerType: IntegrationBindingOwner,
  ownerId: string,
  provider: string,
  integrationId: string,
  integrationName: string,
  configOverrides?: Record<string, unknown>,
): IntegrationBinding {
  const existing = bindingsState.find(
    (b) => b.owner_type === ownerType && b.owner_id === ownerId && b.provider === provider,
  );
  if (existing !== undefined) {
    existing.integration_id = integrationId;
    existing.integration_name = integrationName;
    existing.config_overrides = configOverrides ?? {};
    existing.integration_status = "connected";
    return existing;
  }

  const binding: IntegrationBinding = {
    id: `ib-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    owner_type: ownerType,
    owner_id: ownerId,
    provider,
    integration_id: integrationId,
    integration_name: integrationName,
    integration_status: "connected",
    config_overrides: configOverrides ?? {},
    enabled: true,
    inherited_from: null,
    created_at: new Date().toISOString(),
  };

  bindingsState.push(binding);
  return binding;
}

export function deleteIntegrationBinding(id: string): boolean {
  const idx = bindingsState.findIndex((b) => b.id === id);
  if (idx === -1) return false;
  bindingsState.splice(idx, 1);
  return true;
}

export function deleteIntegrationBindingByOwnerAndProvider(
  ownerType: IntegrationBindingOwner,
  ownerId: string,
  provider: string,
): boolean {
  const idx = bindingsState.findIndex(
    (b) => b.owner_type === ownerType && b.owner_id === ownerId && b.provider === provider,
  );
  if (idx === -1) return false;
  bindingsState.splice(idx, 1);
  return true;
}
