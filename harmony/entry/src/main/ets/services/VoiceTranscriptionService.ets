import { preferences } from '@kit.ArkData';
import type { common } from '@kit.AbilityKit';
import { AppDatabase } from '../data/AppDatabase';
import { VoiceMemo, VoiceNote } from '../models/Models';
import { SyncState } from '../models/Enums';
import { AIService } from './AIService';
import { MediaStore } from './MediaStore';

export class VoiceTranscriptionService {
  private static context: common.Context | null = null;
  private static readonly maxFailures = 3;

  static initialize(context: common.Context): void { VoiceTranscriptionService.context = context; }

  static async transcribeVoiceNote(note: VoiceNote): Promise<void> {
    if (!AIService.shared.isConfigured || !note.localFileName || note.transcript?.trim()) return;
    if (!(await VoiceTranscriptionService.canAttempt(`note_${note.id}`))) return;
    try {
      const text = (await AIService.shared.transcribe(MediaStore.shared.fullPath(note.localFileName))).trim();
      if (text.length === 0) throw new Error('转写结果为空');
      note.transcript = text;
      note.syncState = SyncState.local;
      await AppDatabase.shared.insertVoiceNote(note);
      await VoiceTranscriptionService.clearFailure(`note_${note.id}`);
    } catch (e) {
      await VoiceTranscriptionService.recordFailure(`note_${note.id}`);
    }
  }

  static async transcribeVoiceMemo(memo: VoiceMemo): Promise<void> {
    if (!AIService.shared.isConfigured || !memo.localFileName || memo.transcript?.trim()) return;
    if (!(await VoiceTranscriptionService.canAttempt(`memo_${memo.id}`))) return;
    try {
      const text = (await AIService.shared.transcribe(MediaStore.shared.fullPath(memo.localFileName))).trim();
      if (text.length === 0) throw new Error('转写结果为空');
      memo.transcript = text;
      memo.syncState = SyncState.local;
      await AppDatabase.shared.insertVoiceMemo(memo);
      await VoiceTranscriptionService.clearFailure(`memo_${memo.id}`);
    } catch (e) {
      await VoiceTranscriptionService.recordFailure(`memo_${memo.id}`);
    }
  }

  static async backfillPending(limit: number = 4): Promise<void> {
    if (!AIService.shared.isConfigured) return;
    let processed = 0;
    const entries = await AppDatabase.shared.fetchEntries(true);
    for (const entry of entries) {
      for (const note of await AppDatabase.shared.fetchVoiceForEntry(entry.id)) {
        if (processed >= limit) return;
        if (!note.transcript?.trim() && note.localFileName) {
          await VoiceTranscriptionService.transcribeVoiceNote(note);
          processed += 1;
        }
      }
    }
    for (const memo of await AppDatabase.shared.fetchVoiceMemos()) {
      if (processed >= limit) return;
      if (!memo.transcript?.trim() && memo.localFileName) {
        await VoiceTranscriptionService.transcribeVoiceMemo(memo);
        processed += 1;
      }
    }
  }

  private static async canAttempt(key: string): Promise<boolean> {
    const store = await VoiceTranscriptionService.failureStore();
    if (!store) return false;
    const value = await store.get(key, 0);
    return typeof value !== 'number' || value < VoiceTranscriptionService.maxFailures;
  }

  private static async recordFailure(key: string): Promise<void> {
    const store = await VoiceTranscriptionService.failureStore();
    if (!store) return;
    const value = await store.get(key, 0);
    await store.put(key, (typeof value === 'number' ? value : 0) + 1);
    await store.flush();
  }

  private static async clearFailure(key: string): Promise<void> {
    const store = await VoiceTranscriptionService.failureStore();
    if (!store) return;
    await store.delete(key);
    await store.flush();
  }

  private static async failureStore(): Promise<preferences.Preferences | null> {
    if (!VoiceTranscriptionService.context) return null;
    return await preferences.getPreferences(VoiceTranscriptionService.context, 'bubu_transcription_failures');
  }
}
