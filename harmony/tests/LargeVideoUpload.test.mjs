import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const sync = await readFile(new URL('../entry/src/main/ets/sync/SyncEngine.ets', import.meta.url), 'utf8');
const model = await readFile(new URL('../entry/src/main/ets/models/Models.ets', import.meta.url), 'utf8');
const home = await readFile(new URL('../entry/src/main/ets/view/HomeView.ets', import.meta.url), 'utf8');

test('大视频始终流式上传原片，不以临时低码率代理冒充完整同步', () => {
  assert.ok(sync.includes("'media', m.id, fields, 'file', filePath, fileName"));
  assert.ok(!sync.includes('VideoUploadPreparer'));
  assert.ok(!sync.includes('uploadFileName'));
});

test('大视频上传失败保留原片、保持 failed 并显示明确同步原因', () => {
  assert.ok(model.includes('syncFailureReason?: string'));
  assert.ok(sync.includes('绝不以压缩代理冒充完整同步'));
  assert.ok(sync.includes('syncState: SyncState.failed'));
  assert.ok(home.includes('media.syncFailureReason'));
  assert.ok(home.includes('allMedia.filter((media: Media): boolean => media.syncState !== SyncState.synced)'));
});
