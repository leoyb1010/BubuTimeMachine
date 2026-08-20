import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const timeline = await readFile(new URL('../entry/src/main/ets/view/TimelineView.ets', import.meta.url), 'utf8');

test('时光封面按真实媒体比例显示并夹在 0.8 到 1.9，旧数据回退 1.5', () => {
  assert.ok(timeline.includes('photo.width! / photo.height!'));
  assert.ok(timeline.includes('Math.max(0.8, Math.min(1.9'));
  assert.ok(timeline.includes('.aspectRatio(this.coverAspect(entry))'));
  assert.ok(timeline.includes("return this.photoAspectMap.get(entry.id) ?? 1.5"));
  assert.ok(!timeline.includes(".width('100%').height(178).objectFit(ImageFit.Cover)"));
});
