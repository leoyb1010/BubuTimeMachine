export function schoolDayLabel(start: number | undefined, now: number = Date.now()): string {
  if (start === undefined || !Number.isFinite(start) || start <= 0) return '';
  const first = new Date(start);
  const today = new Date(now);
  const firstDay = Date.UTC(first.getFullYear(), first.getMonth(), first.getDate());
  const currentDay = Date.UTC(today.getFullYear(), today.getMonth(), today.getDate());
  const difference = Math.round((currentDay - firstDay) / 86_400_000);
  if (difference < 0) return `还有 ${-difference} 天上幼儿园`;
  if (difference === 0) return '今天是上幼儿园第一天';
  return `上幼儿园第 ${difference + 1} 天`;
}
