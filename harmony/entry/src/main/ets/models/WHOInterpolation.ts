export interface PercentileBand {
  month: number;
  p3: number;
  p15: number;
  p50: number;
  p85: number;
  p97: number;
}

export function interpolatePercentileBand(table: PercentileBand[], month: number): PercentileBand | undefined {
  if (table.length === 0) return undefined;
  const exact = table.find((band: PercentileBand): boolean => band.month === month);
  if (exact) return exact;
  const lower = table.filter((band: PercentileBand): boolean => band.month < month).pop();
  const upper = table.find((band: PercentileBand): boolean => band.month > month);
  if (!lower) return table[0];
  if (!upper) return table[table.length - 1];
  const fraction = (month - lower.month) / (upper.month - lower.month);
  const lerp = (left: number, right: number): number => left + (right - left) * fraction;
  return {
    month,
    p3: lerp(lower.p3, upper.p3),
    p15: lerp(lower.p15, upper.p15),
    p50: lerp(lower.p50, upper.p50),
    p85: lerp(lower.p85, upper.p85),
    p97: lerp(lower.p97, upper.p97)
  };
}
