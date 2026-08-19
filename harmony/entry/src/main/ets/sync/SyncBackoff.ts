export const SYNC_BASE_INTERVAL_MS: number = 30_000;
export const SYNC_MAX_INTERVAL_MS: number = 480_000;

export function syncBackoffIntervalMs(failures: number): number {
  if (failures <= 0) return SYNC_BASE_INTERVAL_MS;
  const exponent = Math.min(Math.trunc(failures), 4);
  return Math.min(SYNC_BASE_INTERVAL_MS * Math.pow(2, exponent), SYNC_MAX_INTERVAL_MS);
}
