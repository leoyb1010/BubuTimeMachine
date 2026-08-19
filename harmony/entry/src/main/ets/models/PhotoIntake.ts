export class PhotoIntakeState {
  static readonly discovered: string = 'discovered';
  static readonly queued: string = 'queued';
  static readonly accepted: string = 'accepted';
  static readonly ignored: string = 'ignored';
  static readonly failed: string = 'failed';
  static readonly deleted: string = 'deleted';
}

export interface PhotoIntakeCandidate {
  assetUri: string;
  displayName: string;
  createdAt: number;
  mediaType: number;
  width: number;
  height: number;
  duration: number;
  subtype: number;
  burstKey?: string;
  state: string;
  isLikelyChild: boolean;
}

export interface PhotoEventGroup {
  id: string;
  assetUris: string[];
  startedAt: number;
  endedAt: number;
  photoCount: number;
  videoCount: number;
  movingPhotoCount: number;
  likelyChildCount: number;
}

export function clusterPhotoCandidates(candidates: PhotoIntakeCandidate[],
                                       maximumTimeGapMs: number = 90 * 60 * 1000): PhotoEventGroup[] {
  const sorted = candidates.slice().sort((left: PhotoIntakeCandidate, right: PhotoIntakeCandidate): number => {
    return left.createdAt === right.createdAt
      ? left.assetUri.localeCompare(right.assetUri)
      : left.createdAt - right.createdAt;
  });
  if (sorted.length === 0) return [];

  const buckets: PhotoIntakeCandidate[][] = [[sorted[0]]];
  for (let index = 1; index < sorted.length; index += 1) {
    const candidate = sorted[index];
    const bucket = buckets[buckets.length - 1];
    const previous = bucket[bucket.length - 1];
    const sameBurst = previous.burstKey !== undefined && previous.burstKey === candidate.burstKey;
    const gap = Math.max(0, candidate.createdAt - previous.createdAt);
    const differentDay = new Date(previous.createdAt).toDateString() !== new Date(candidate.createdAt).toDateString();
    if (!sameBurst && (gap > maximumTimeGapMs || (differentDay && gap > 30 * 60 * 1000))) {
      buckets.push([candidate]);
    } else {
      bucket.push(candidate);
    }
  }

  return buckets.map(makeGroup).sort((left: PhotoEventGroup, right: PhotoEventGroup): number => {
    return right.startedAt - left.startedAt;
  });
}

function makeGroup(items: PhotoIntakeCandidate[]): PhotoEventGroup {
  const assetUris = items.map((item: PhotoIntakeCandidate): string => item.assetUri);
  return {
    id: stableGroupId(assetUris),
    assetUris,
    startedAt: items[0].createdAt,
    endedAt: items[items.length - 1].createdAt,
    photoCount: items.filter((item: PhotoIntakeCandidate): boolean => item.mediaType === 1).length,
    videoCount: items.filter((item: PhotoIntakeCandidate): boolean => item.mediaType === 2).length,
    movingPhotoCount: items.filter((item: PhotoIntakeCandidate): boolean => item.subtype === 3).length,
    likelyChildCount: items.filter((item: PhotoIntakeCandidate): boolean => item.isLikelyChild).length
  };
}

function stableGroupId(assetUris: string[]): string {
  const value = assetUris.slice().sort().join('\n');
  let hash = 2166136261;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return `photo-event-${(hash >>> 0).toString(16).padStart(8, '0')}`;
}
