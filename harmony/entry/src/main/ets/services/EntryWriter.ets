import { util } from '@kit.ArkTS';
import { AppDatabase } from '../data/AppDatabase';
import { Entry, FeedEvent, Media, VoiceNote } from '../models/Models';
import { SyncState, FamilyRole, Mood, MediaType } from '../models/Enums';
import { MediaStore } from './MediaStore';
import { MediaDerivationService } from './MediaDerivationService';

// MARK: - 无 UI 记录写入层（对照 iOS Services/EntryWriter.swift）
// 供首页、意图、服务卡片复用：写一条文字瞬间 → Entry + FeedEvent，离线优先落本地。
export class EntryWriter {
  static async quickTextEntry(note: string, role: FamilyRole, mood?: Mood): Promise<string> {
    const trimmed = note.trim();
    if (trimmed.length === 0) {
      throw new Error('记录内容是空的');
    }
    const now = Date.now();
    const id = util.generateRandomUUID(true);
    const entry: Entry = {
      id: id,
      happenedAt: now,
      authorRole: role,
      note: trimmed,
      moodRaw: mood,
      syncState: SyncState.local,
      isArchived: false,
      createdAt: now
    };
    const feed: FeedEvent = {
      id: util.generateRandomUUID(true), kind: 'entryCreated', actorRole: role,
      summary: `记录了：${trimmed}`, targetLocalId: id, happenedAt: now,
      syncState: SyncState.local, createdAt: now
    };
    await AppDatabase.shared.insertEntryAggregate(entry, [], null, feed);
    return id;
  }

  // 带照片/视频/语音的记录：文件名为已落沙盒的相对名。voiceFileName/voiceDuration 可选。
  static async entryWithPhoto(note: string, photoFileName: string | string[] | null, role: FamilyRole,
                              mood?: Mood, voiceFileName?: string | null, voiceDuration?: number,
                              videoFileNames: string[] = [], happenedAt: number = Date.now(),
                              locationName?: string, latitude?: number, longitude?: number): Promise<string> {
    const now = Date.now();
    const id = util.generateRandomUUID(true);
    const trimmed = note.trim();
    const entry: Entry = {
      id: id,
      happenedAt,
      authorRole: role,
      note: trimmed.length === 0 ? undefined : trimmed,
      moodRaw: mood,
      locationName,
      latitude,
      longitude,
      syncState: SyncState.local,
      isArchived: false,
      createdAt: now
    };
    const photoFileNames: string[] = Array.isArray(photoFileName)
      ? photoFileName
      : (photoFileName ? [photoFileName] : []);
    const mediaItems: Media[] = [];
    for (const name of photoFileNames) {
      const media: Media = {
        id: util.generateRandomUUID(true),
        entryId: id,
        typeRaw: MediaType.photo,
        localFileName: name,
        uploadProgress: 0,
        syncState: SyncState.local,
        aiTags: [],
        createdAt: now
      };
      await MediaDerivationService.prepare(media);
      mediaItems.push(media);
    }

    for (const videoFileName of videoFileNames) {
      const media: Media = {
        id: util.generateRandomUUID(true),
        entryId: id,
        typeRaw: MediaType.video,
        localFileName: videoFileName,
        uploadProgress: 0,
        syncState: SyncState.local,
        aiTags: [],
        createdAt: now
      };
      await MediaDerivationService.prepare(media);
      mediaItems.push(media);
    }

    let voice: VoiceNote | null = null;
    if (voiceFileName) {
      voice = {
        id: util.generateRandomUUID(true),
        entryId: id,
        localFileName: voiceFileName,
        durationSeconds: voiceDuration ?? 0,
        authorRole: role,
        waveformSamples: [],
        syncState: SyncState.local,
        createdAt: now
      };
    }
    const feed: FeedEvent = {
      id: util.generateRandomUUID(true), kind: 'entryCreated', actorRole: role,
      summary: trimmed.length > 0 ? `记录了：${trimmed}` : '记录了布布的一个新瞬间',
      targetLocalId: id, happenedAt: now, syncState: SyncState.local, createdAt: now
    };
    try {
      await AppDatabase.shared.insertEntryAggregate(entry, mediaItems, voice, feed);
    } catch (error) {
      for (const name of photoFileNames) MediaStore.shared.deleteMedia(name);
      for (const name of videoFileNames) MediaStore.shared.deleteMedia(name);
      for (const media of mediaItems) {
        if (media.thumbnailFileName) MediaStore.shared.deleteThumbnail(media.thumbnailFileName);
      }
      if (voiceFileName) MediaStore.shared.deleteMedia(voiceFileName);
      throw error instanceof Error ? error : new Error(JSON.stringify(error));
    }
    return id;
  }
}
