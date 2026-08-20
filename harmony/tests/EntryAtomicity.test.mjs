import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const db = await readFile(new URL('../entry/src/main/ets/data/AppDatabase.ets', import.meta.url), 'utf8');
const writer = await readFile(new URL('../entry/src/main/ets/services/EntryWriter.ets', import.meta.url), 'utf8');

test('Entry、Media、Voice 和 Feed 使用同一个 RDB Transaction 原子提交', () => {
  assert.ok(db.includes('async insertEntryAggregate'));
  assert.ok(db.includes('await store.createTransaction()'));
  assert.ok(db.includes("await transaction.insert('entry'"));
  assert.ok(db.includes("await transaction.insert('media'"));
  assert.ok(db.includes("await transaction.insert('voice_note'"));
  assert.ok(db.includes("await transaction.insert('feed_event'"));
  assert.ok(db.includes('await transaction.commit()'));
  assert.ok(db.includes('await transaction.rollback()'));
});

test('聚合保存失败会清理本轮照片、视频和语音文件，避免半条记录和孤儿', () => {
  assert.ok(writer.includes('await AppDatabase.shared.insertEntryAggregate'));
  assert.ok(writer.includes('for (const name of photoFileNames) MediaStore.shared.deleteMedia(name)'));
  assert.ok(writer.includes('for (const name of videoFileNames) MediaStore.shared.deleteMedia(name)'));
  assert.ok(writer.includes('if (voiceFileName) MediaStore.shared.deleteMedia(voiceFileName)'));
});
