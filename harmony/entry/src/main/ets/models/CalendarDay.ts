export function startOfLocalDay(milliseconds: number): number {
  const date = new Date(milliseconds);
  return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
}
