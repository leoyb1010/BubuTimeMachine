export const SYNC_CURSOR_OVERLAP_MS: number = 60_000;

export function laterServerTimestamp(current: string | undefined, candidate: string | undefined): string | undefined {
  if (candidate === undefined || Number.isNaN(Date.parse(candidate))) return current;
  if (current === undefined || Number.isNaN(Date.parse(current))) return candidate;
  return Date.parse(candidate) > Date.parse(current) ? candidate : current;
}

export function overlappedServerCursor(serverUpdated: string): string {
  const parsed = Date.parse(serverUpdated);
  if (Number.isNaN(parsed)) return serverUpdated;
  return new Date(parsed - SYNC_CURSOR_OVERLAP_MS).toISOString();
}
