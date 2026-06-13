import { util } from '@kit.ArkTS';
import { AppDatabase } from '../data/AppDatabase';
import { Entry, FeedEvent, Media } from '../models/Models';
import { SyncState, FamilyRole, Mood, MediaType } from '../models/Enums';
import { relationalStore } from '@kit.ArkData';

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
    await AppDatabase.shared.insertEntry(entry);

    // 家庭动态（对齐 iOS：记录后写一条 FeedEvent）
    const store = AppDatabase.shared.raw;
    if (store) {
      const ev: relationalStore.ValuesBucket = {
        id: util.generateRandomUUID(true),
        kind: 'entryCreated',
        actorRole: role,
        summary: `记录了：${trimmed}`,
        targetLocalId: id,
        happenedAt: now
      };
      await store.insert('feed_event', ev);
    }
    return id;
  }

  // 带一张照片的记录：photoFileName 为已落沙盒的相对文件名（MediaStore.copyIntoStore 返回）。
  static async entryWithPhoto(note: string, photoFileName: string | null, role: FamilyRole, mood?: Mood): Promise<string> {
    const now = Date.now();
    const id = util.generateRandomUUID(true);
    const trimmed = note.trim();
    const entry: Entry = {
      id: id,
      happenedAt: now,
      authorRole: role,
      note: trimmed.length === 0 ? undefined : trimmed,
      moodRaw: mood,
      syncState: SyncState.local,
      isArchived: false,
      createdAt: now
    };
    await AppDatabase.shared.insertEntry(entry);

    if (photoFileName) {
      const media: Media = {
        id: util.generateRandomUUID(true),
        entryId: id,
        typeRaw: MediaType.photo,
        localFileName: photoFileName,
        aiTags: [],
        createdAt: now
      };
      await AppDatabase.shared.insertMedia(media);
    }

    const store = AppDatabase.shared.raw;
    if (store) {
      const ev: relationalStore.ValuesBucket = {
        id: util.generateRandomUUID(true),
        kind: 'entryCreated',
        actorRole: role,
        summary: trimmed.length > 0 ? `记录了：${trimmed}` : '记录了布布的一个新瞬间',
        targetLocalId: id,
        happenedAt: now
      };
      await store.insert('feed_event', ev);
    }
    return id;
  }
}
