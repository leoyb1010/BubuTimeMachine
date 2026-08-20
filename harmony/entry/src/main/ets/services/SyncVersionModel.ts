export function remoteVersionIsNewer(remoteValue: unknown, localValue: unknown): boolean {
  if (typeof remoteValue !== 'string' || typeof localValue !== 'string') return false;
  const remote = Date.parse(remoteValue.includes('T') ? remoteValue : remoteValue.replace(' ', 'T'));
  const local = Date.parse(localValue.includes('T') ? localValue : localValue.replace(' ', 'T'));
  return Number.isFinite(remote) && Number.isFinite(local) && remote > local;
}
