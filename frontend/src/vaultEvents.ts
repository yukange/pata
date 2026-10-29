/**
 * Utility for filtering vault:changed events by entity type.
 */

export interface VaultChangeEventPayload {
  op?: string;
  path?: string;
  entity_id?: string;
  type?: string;
}

/**
 * Checks whether a vault:changed event matches any of the accepted entity types.
 * Returns true if:
 * 1. The event payload is missing or has no type (fallback for general rescan or untyped events)
 * 2. The event type is 'error' or op is 'error' (vault error affects overall state)
 * 3. The event type matches one of the acceptedTypes.
 */
export function matchesVaultEventType(
  ev: unknown,
  acceptedTypes: string[]
): boolean {
  const payload = (ev as { data?: VaultChangeEventPayload } | undefined)?.data;
  if (!payload || !payload.type) {
    return true;
  }
  if (payload.type === 'error' || payload.op === 'error') {
    return true;
  }
  return acceptedTypes.includes(payload.type);
}
