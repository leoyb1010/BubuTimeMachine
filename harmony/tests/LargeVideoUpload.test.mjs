import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const preparer = await readFile(new URL('../entry/src/main/ets/services/VideoUploadPreparer.ets', import.meta.url), 'utf8');
const sync = await readFile(new URL('../entry/src/main/ets/sync/SyncEngine.ets', import.meta.url), 'utf8');
const model = await readFile(new URL('../entry/src/main/ets/models/Models.ets', import.meta.url), 'utf8');
const home = await readFile(new URL('../entry/src/main/ets/view/HomeView.ets', import.meta.url), 'utf8');

test('超过 96MB 的视频先走原生 AVTranscoder 压缩再上传并清理临时文件', () => {
  assert.ok(preparer.includes('media.createAVTranscoder()'));
  assert.ok(preparer.includes('MediaStore.publicUploadSoftLimitBytes'));
  assert.ok(preparer.includes('videoBitrate: 900000'));
  assert.ok(preparer.includes('audioBitrate: 64000'));
  assert.ok(sync.includes('await VideoUploadPreparer.prepare'));
  assert.ok(sync.includes('VideoUploadPreparer.cleanup(prepared)'));
});

test('压缩后仍过大或格式不支持会保留原片并显示明确同步原因', () => {
  assert.ok(model.includes('syncFailureReason?: string'));
  assert.ok(sync.includes('系统压缩后仍过大或格式不受支持'));
  assert.ok(home.includes('media.syncFailureReason'));
  assert.ok(home.includes('allMedia.filter((media: Media): boolean => media.syncState !== SyncState.synced)'));
});
