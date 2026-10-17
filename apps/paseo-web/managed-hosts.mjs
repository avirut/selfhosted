// Paseo 0.11.2 stores this registry through AsyncStorage's localStorage adapter.
export const REGISTRY_KEY = '@paseo:daemon-registry';
export const MANAGED_KEY = '@kroacnet:paseo-managed-hosts';

export function validateConfiguration(config) {
  if (config?.version !== 1 || !Array.isArray(config.hosts)) {
    throw new Error('Invalid host configuration');
  }
  const seen = new Set();
  for (const host of config.hosts) {
    const offer = host?.offer;
    if (!host?.name || typeof host.name !== 'string' || host.name.length > 80 ||
        offer?.v !== 2 || !/^srv_[A-Za-z0-9_-]+$/.test(offer.serverId) ||
        typeof offer.daemonPublicKeyB64 !== 'string' ||
        !/^[A-Za-z0-9+/]{43}=$/.test(offer.daemonPublicKeyB64) ||
        offer.relay?.useTls !== true ||
        !/^[A-Za-z0-9.-]+:[0-9]{1,5}$/.test(offer.relay.endpoint) ||
        seen.has(offer.serverId)) {
      throw new Error('Invalid or duplicate configured host');
    }
    seen.add(offer.serverId);
  }
  return config;
}

export function reconcileHosts(existing, config, previousManaged = []) {
  validateConfiguration(config);
  if (!Array.isArray(existing) || existing.some(host =>
    !host || typeof host.serverId !== 'string' || !Array.isArray(host.connections)) ||
      !Array.isArray(previousManaged) || previousManaged.some(id => typeof id !== 'string')) {
    throw new Error('Invalid saved host list');
  }
  const currentIds = new Set(config.hosts.map(host => host.offer.serverId));
  const retiredIds = new Set(previousManaged.filter(id => !currentIds.has(id)));
  const next = existing.filter(host => !retiredIds.has(host.serverId));
  const now = new Date().toISOString();
  for (const { name, offer } of config.hosts) {
    const connection = {
      id: `relay:wss:${offer.relay.endpoint}`,
      type: 'relay',
      relayEndpoint: offer.relay.endpoint,
      useTls: true,
      daemonPublicKeyB64: offer.daemonPublicKeyB64,
    };
    const index = next.findIndex(host => host.serverId === offer.serverId);
    const previous = index < 0 ? null : next[index];
    // Keep local passwords, appearance and alternate connections; central names
    // and relay identity win. Never copy a browser/client private key.
    const profile = {
      ...(previous ?? {}),
      serverId: offer.serverId,
      label: name,
      connections: [connection, ...(previous?.connections ?? []).filter(item => item.id !== connection.id)],
      preferredConnectionId: previous?.preferredConnectionId ?? connection.id,
      createdAt: previous?.createdAt ?? now,
      updatedAt: now,
    };
    if (index < 0) next.push(profile);
    else next[index] = profile;
  }
  return next;
}

export function applyConfiguration(storage, config) {
  const existing = JSON.parse(storage.getItem(REGISTRY_KEY) ?? '[]');
  const previousManaged = JSON.parse(storage.getItem(MANAGED_KEY) ?? '[]');
  const next = reconcileHosts(existing, config, previousManaged);
  // Validate everything before either write. Storage failure stops app startup
  // instead of silently discarding existing connections.
  storage.setItem(REGISTRY_KEY, JSON.stringify(next));
  storage.setItem(MANAGED_KEY, JSON.stringify(config.hosts.map(host => host.offer.serverId)));
  return next;
}
