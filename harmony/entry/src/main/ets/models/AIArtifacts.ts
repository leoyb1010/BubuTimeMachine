export interface QAContextRecord {
  id: string;
  dateText: string;
  ageText: string;
  text: string;
}

export interface QAAnswer {
  answer: string;
  usedIds: string[];
}

export interface SemanticSearchHit {
  assetId: string;
  entryLocalId: string;
  mediaRecordId: string;
  capturedAt: string;
  score: number;
  reason: string;
}

export interface SemanticSearchResponse {
  query: string;
  modelVersion: string;
  hits: SemanticSearchHit[];
}

export interface ArtifactSourceReference {
  sourceId: string;
  collection: string;
  recordId: string;
  localId: string;
  happenedAt: string;
  title: string;
  excerpt: string;
  kind: string;
}

export interface WeeklyReportSection {
  kind: string;
  title: string;
  text: string;
  sourceIds: string[];
}

export interface WeeklyReport {
  id: string;
  artifactKey: string;
  status: string;
  title: string;
  summary: string;
  weekStart: string;
  weekEnd: string;
  generatedAt: string;
  modelVersion: string;
  contentHash: string;
  sections: WeeklyReportSection[];
  sourceRefs: ArtifactSourceReference[];
}

export interface SoundRingClip {
  sourceId: string;
  photoSourceId: string;
  ageYears: number;
  kind: string;
  title: string;
  recordedAt: string;
  transcript: string;
  durationSeconds: number;
  startSeconds: number;
  endSeconds: number;
}

export interface SoundRing {
  id: string;
  artifactKey: string;
  status: string;
  title: string;
  summary: string;
  generatedAt: string;
  modelVersion: string;
  originalDurationSeconds: number;
  renderedDurationSeconds: number;
  attempts: number;
  error: string;
  narrator: string;
  voiceCloning: boolean;
  hasAudio: boolean;
  clips: SoundRingClip[];
  sourceRefs: ArtifactSourceReference[];
  contentHash: string;
}

export function decodeQAAnswer(value: Record<string, Object>): QAAnswer {
  return {
    answer: stringValue(value, 'answer'),
    usedIds: stringArray(value['used_ids'])
  };
}

export function decodeSemanticSearch(value: Record<string, Object>): SemanticSearchResponse {
  return {
    query: stringValue(value, 'query'),
    modelVersion: stringValue(value, 'model_version'),
    hits: objectArray(value['hits']).map((hit: Record<string, Object>): SemanticSearchHit => ({
      assetId: stringValue(hit, 'asset_id'),
      entryLocalId: stringValue(hit, 'entry_local_id'),
      mediaRecordId: stringValue(hit, 'media_record_id'),
      capturedAt: stringValue(hit, 'captured_at'),
      score: numberValue(hit, 'score'),
      reason: stringValue(hit, 'reason')
    }))
  };
}

export function decodeWeeklyReport(value: Record<string, Object>): WeeklyReport {
  return {
    id: stringValue(value, 'id'),
    artifactKey: stringValue(value, 'artifact_key'),
    status: stringValue(value, 'status'),
    title: stringValue(value, 'title'),
    summary: stringValue(value, 'summary'),
    weekStart: stringValue(value, 'week_start'),
    weekEnd: stringValue(value, 'week_end'),
    generatedAt: stringValue(value, 'generated_at'),
    modelVersion: stringValue(value, 'model_version'),
    contentHash: stringValue(value, 'content_hash'),
    sections: objectArray(value['sections']).map((section: Record<string, Object>): WeeklyReportSection => ({
      kind: stringValue(section, 'kind'),
      title: stringValue(section, 'title'),
      text: stringValue(section, 'text'),
      sourceIds: stringArray(section['sourceIds'])
    })),
    sourceRefs: objectArray(value['source_refs']).map((source: Record<string, Object>): ArtifactSourceReference => ({
      sourceId: stringValue(source, 'source_id'),
      collection: stringValue(source, 'collection'),
      recordId: stringValue(source, 'record_id'),
      localId: stringValue(source, 'local_id'),
      happenedAt: stringValue(source, 'happened_at'),
      title: stringValue(source, 'title'),
      excerpt: stringValue(source, 'excerpt'),
      kind: stringValue(source, 'kind')
    }))
  };
}

export function decodeSoundRing(value: Record<string, Object>): SoundRing {
  return {
    id: stringValue(value, 'id'),
    artifactKey: stringValue(value, 'artifact_key'),
    status: stringValue(value, 'status'),
    title: stringValue(value, 'title'),
    summary: stringValue(value, 'summary'),
    generatedAt: stringValue(value, 'generated_at'),
    modelVersion: stringValue(value, 'model_version'),
    originalDurationSeconds: numberValue(value, 'original_duration_seconds'),
    renderedDurationSeconds: numberValue(value, 'rendered_duration_seconds'),
    attempts: numberValue(value, 'attempts'),
    error: stringValue(value, 'error'),
    narrator: stringValue(value, 'narrator'),
    voiceCloning: booleanValue(value, 'voice_cloning'),
    hasAudio: booleanValue(value, 'has_audio'),
    clips: objectArray(value['clips']).map((clip: Record<string, Object>): SoundRingClip => ({
      sourceId: stringValue(clip, 'source_id'),
      photoSourceId: stringValue(clip, 'photo_source_id'),
      ageYears: numberValue(clip, 'age_years'),
      kind: stringValue(clip, 'kind'),
      title: stringValue(clip, 'title'),
      recordedAt: stringValue(clip, 'recorded_at'),
      transcript: stringValue(clip, 'transcript'),
      durationSeconds: numberValue(clip, 'duration_seconds'),
      startSeconds: numberValue(clip, 'start_seconds'),
      endSeconds: numberValue(clip, 'end_seconds')
    })),
    sourceRefs: objectArray(value['source_refs']).map((source: Record<string, Object>): ArtifactSourceReference => ({
      sourceId: stringValue(source, 'source_id'),
      collection: stringValue(source, 'collection'),
      recordId: stringValue(source, 'record_id'),
      localId: stringValue(source, 'local_id'),
      happenedAt: stringValue(source, 'happened_at'),
      title: stringValue(source, 'title'),
      excerpt: stringValue(source, 'excerpt'),
      kind: stringValue(source, 'kind')
    })),
    contentHash: stringValue(value, 'content_hash')
  };
}

function stringValue(value: Record<string, Object>, key: string): string {
  const raw = value[key];
  return typeof raw === 'string' ? raw : '';
}

function numberValue(value: Record<string, Object>, key: string): number {
  const raw = value[key];
  return typeof raw === 'number' ? raw : 0;
}

function booleanValue(value: Record<string, Object>, key: string): boolean {
  return value[key] === true;
}

function stringArray(value: Object | undefined): string[] {
  if (!Array.isArray(value)) return [];
  return (value as Object[]).filter((item: Object): boolean => typeof item === 'string')
    .map((item: Object): string => item as string);
}

function objectArray(value: Object | undefined): Record<string, Object>[] {
  if (!Array.isArray(value)) return [];
  return (value as Object[]).filter((item: Object): boolean => {
    return typeof item === 'object' && item !== null && !Array.isArray(item);
  }).map((item: Object): Record<string, Object> => item as Record<string, Object>);
}
