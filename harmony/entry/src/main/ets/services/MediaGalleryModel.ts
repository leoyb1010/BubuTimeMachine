export interface GalleryEntryLike {
  id: string;
  happenedAt: number;
}

export interface GalleryMediaLike {
  id: string;
  entryId: string;
  createdAt: number;
}

export function buildTimelineMediaSequence<T extends GalleryMediaLike>(
  allMedia: T[], entries: GalleryEntryLike[]): T[] {
  const entryTimes = new Map<string, number>();
  for (const entry of entries) entryTimes.set(entry.id, entry.happenedAt);
  return allMedia
    .filter((item: T): boolean => entryTimes.has(item.entryId))
    .slice()
    .sort((a: T, b: T): number => {
      const timeDiff = (entryTimes.get(b.entryId) ?? 0) - (entryTimes.get(a.entryId) ?? 0);
      return timeDiff !== 0 ? timeDiff : a.createdAt - b.createdAt;
    });
}

export function resolveInitialGalleryIndex<T extends { id: string }>(items: T[], initialId: string): number {
  const index = items.findIndex((item: T): boolean => item.id === initialId);
  return index >= 0 ? index : 0;
}
