import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const viewer = await readFile(new URL('../entry/src/main/ets/components/MediaViewer.ets', import.meta.url), 'utf8');

test('照片查看器使用真正双击缩放而不是单击近似', () => {
  assert.ok(viewer.includes('TapGesture({ count: 2 })'));
  assert.ok(viewer.includes('PinchGesture()'));
  assert.ok(!viewer.includes('以单击在缩放态间切换近似'));
});
