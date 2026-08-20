import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const service = await readFile(new URL('../entry/src/main/ets/services/VoiceTranscriptionService.ets', import.meta.url), 'utf8');
const detail = await readFile(new URL('../entry/src/main/ets/view/EntryDetailView.ets', import.meta.url), 'utf8');
const archive = await readFile(new URL('../entry/src/main/ets/view/VoiceArchiveView.ets', import.meta.url), 'utf8');
const background = await readFile(new URL('../entry/src/main/ets/background/BackgroundSyncAbility.ets', import.meta.url), 'utf8');

test('普通 VoiceNote 和 VoiceMemo 保存后异步转写并标记待同步', () => {
  assert.ok(detail.includes('VoiceTranscriptionService.transcribeVoiceNote(voice)'));
  assert.ok(archive.includes('VoiceTranscriptionService.transcribeVoiceMemo(memo)'));
  assert.ok(service.includes('note.transcript = text'));
  assert.ok(service.includes('memo.transcript = text'));
  assert.ok(service.match(/syncState = SyncState\.local/g)?.length >= 2);
});

test('前台和后台每轮最多补写 4 条，坏文件三次后跳过', () => {
  assert.ok(service.includes('static async backfillPending(limit: number = 4)'));
  assert.ok(service.includes('private static readonly maxFailures = 3'));
  assert.ok(background.includes('VoiceTranscriptionService.backfillPending(4)'));
  assert.ok(service.includes('bubu_transcription_failures'));
});
