import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const library = await readFile(new URL('../entry/src/main/ets/services/MediaLibraryService.ets', import.meta.url), 'utf8');
const share = await readFile(new URL('../entry/src/main/ets/services/ShareService.ets', import.meta.url), 'utf8');

test('照片和视频保存使用系统确认框，分享区分 image/video UTD', () => {
  assert.ok(library.includes('showAssetsCreationDialog'));
  assert.ok(library.includes('PhotoType.VIDEO'));
  assert.ok(library.includes('PhotoType.IMAGE'));
  assert.ok(share.includes("isVideo ? 'general.video' : 'general.image'"));
});
