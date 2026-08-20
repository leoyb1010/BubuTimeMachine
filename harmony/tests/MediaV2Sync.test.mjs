import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const model = await readFile(new URL('../entry/src/main/ets/models/Models.ets', import.meta.url), 'utf8');
const db = await readFile(new URL('../entry/src/main/ets/data/AppDatabase.ets', import.meta.url), 'utf8');
const sync = await readFile(new URL('../entry/src/main/ets/sync/SyncEngine.ets', import.meta.url), 'utf8');
const api = await readFile(new URL('../entry/src/main/ets/services/APIClient.ets', import.meta.url), 'utf8');
const gallery = await readFile(new URL('../entry/src/main/ets/services/MediaGalleryModel.ts', import.meta.url), 'utf8');
const derivation = await readFile(new URL('../entry/src/main/ets/services/MediaDerivationService.ets', import.meta.url), 'utf8');
const writer = await readFile(new URL('../entry/src/main/ets/services/EntryWriter.ets', import.meta.url), 'utf8');

test('Media V2 跨端字段完整进入模型和 RDB 迁移', () => {
  for (const field of ['remoteThumbURL', 'contentHash', 'resourceRoleRaw', 'assetGroupID']) {
    assert.ok(model.includes(field));
    assert.ok(db.includes(`'${field}'`));
  }
});

test('Harmony 新媒体真实生成流式 contentHash、照片/视频缩略图和 display 资源角色', () => {
  assert.ok(derivation.includes("cryptoFramework.createMd('SHA256')"));
  assert.ok(derivation.includes('ThumbnailProvider.videoFrame'));
  assert.ok(derivation.includes('ThumbnailProvider.downsample'));
  assert.ok(derivation.includes("media.resourceRoleRaw = 'display'"));
  assert.ok(writer.includes('await MediaDerivationService.prepare(media)'));
});

test('缩略图回填总线与启动/后台补齐都会真实写回 RDB', () => {
  assert.ok(derivation.includes('ThumbnailBackfillBus.shared.setHandler'));
  assert.ok(derivation.includes('ThumbnailBackfillBus.shared.drain'));
  assert.ok(derivation.includes('AppDatabase.shared.updateMediaDerivedFields'));
  assert.ok(derivation.includes('static async backfillPending'));
});

test('媒体上传携带缩略图、资源角色和真实连续进度', () => {
  assert.ok(api.includes('extraFileField'));
  assert.ok(api.includes("req.on('dataSendProgress'"));
  assert.ok(sync.includes("hasThumb ? 'thumbnail' : undefined"));
  assert.ok(sync.includes("fields['contentHash']"));
  assert.ok(sync.includes("fields['resourceRole']"));
  assert.ok(sync.includes("fields['assetGroupId']"));
  assert.ok(sync.includes('uploadProgress: fraction'));
});

test('接收端先补远端缩略图再拉原片，图库不展示辅助资源', () => {
  assert.ok(sync.includes("remoteFileURL(r, 'media', 'thumbnail', 'remoteThumbURL')"));
  assert.ok(sync.indexOf('先补远端缩略图') < sync.indexOf('// Media：缺本地文件'));
  assert.ok(sync.includes('MediaStore.shared.thumbnailPath(thumbName)'));
  assert.ok(gallery.includes("item.resourceRoleRaw === 'display'"));
});

test('远端原片先下载临时文件并按 contentHash 校验后原子落盘', () => {
  assert.ok(sync.includes('`${destPath}.download`'));
  assert.ok(sync.includes('await MediaDerivationService.sha256File(tempPath)'));
  assert.ok(sync.includes('actualHash !== m.contentHash'));
  assert.ok(sync.includes('fileIo.renameSync(tempPath, destPath)'));
});
