import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const model = await readFile(new URL('../entry/src/main/ets/view/CaptureModel.ets', import.meta.url), 'utf8');
const sheet = await readFile(new URL('../entry/src/main/ets/view/QuickCaptureSheet.ets', import.meta.url), 'utf8');

test('移除照片视频、删除语音、关闭草稿和新开草稿都会清理未提交文件', () => {
  assert.ok(model.includes('if (removed?.fileName) MediaStore.shared.deleteMedia(removed.fileName)'));
  assert.ok(model.includes('if (this.pendingVoiceFileName) MediaStore.shared.deleteMedia(this.pendingVoiceFileName)'));
  assert.ok(model.includes('discardDraft(): void'));
  assert.ok(model.includes('startQuickCapture(prefillNote: string = \'\'): void {\n    this.discardDraft()'));
  assert.ok(sheet.includes('this.model.discardDraft()'));
});

test('事务成功后只转移媒体所有权并清引用，不误删正式文件', () => {
  const success = model.slice(model.indexOf('this.lastSavedEntryID = id'), model.indexOf('return true;', model.indexOf('this.lastSavedEntryID = id')));
  assert.ok(!success.includes('deleteMedia'));
  assert.ok(!success.includes('clearPendingVoice()'));
  assert.ok(success.includes('this.pendingVoiceFileName = null'));
});
