import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const exporter = await readFile(new URL('../entry/src/main/ets/services/media/ShareCardExporter.ets', import.meta.url), 'utf8');
const sheet = await readFile(new URL('../entry/src/main/ets/view/ShareCardSheet.ets', import.meta.url), 'utf8');
const detail = await readFile(new URL('../entry/src/main/ets/view/EntryDetailView.ets', import.meta.url), 'utf8');
const timeline = await readFile(new URL('../entry/src/main/ets/view/TimelineView.ets', import.meta.url), 'utf8');
const share = await readFile(new URL('../entry/src/main/ets/services/ShareService.ets', import.meta.url), 'utf8');

test('分享卡支持竖版、方版和有真实双图时的那年今日', () => {
  for (const layout of ['portrait', 'square', 'thenNow']) assert.ok(exporter.includes(`${layout} = '${layout}'`));
  assert.ok(exporter.includes('drawImageRectWithSrc'));
  assert.ok(exporter.includes("format: 'image/png'"));
  assert.ok(sheet.includes('currentPhotoPath.length > 0 && this.thenPhotoPath.length > 0'));
});

test('卡面隐私字段受限并通过 Share Kit 分享图片', () => {
  assert.ok(!exporter.includes('birthday'));
  assert.ok(!exporter.includes('location'));
  assert.ok(!exporter.includes('latitude'));
  assert.ok(share.includes("'general.image'"));
  assert.ok(detail.includes("Button('分享这一刻')"));
  assert.ok(timeline.includes('bindContextMenu(this.entryMenu(entry), ResponseType.LongPress)'));
});
