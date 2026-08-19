import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const model = await readFile(new URL('../entry/src/main/ets/models/Models.ets', import.meta.url), 'utf8');
const database = await readFile(new URL('../entry/src/main/ets/data/AppDatabase.ets', import.meta.url), 'utf8');
const sync = await readFile(new URL('../entry/src/main/ets/sync/SyncEngine.ets', import.meta.url), 'utf8');
const detail = await readFile(new URL('../entry/src/main/ets/view/EntryDetailView.ets', import.meta.url), 'utf8');
const builder = await readFile(new URL('../entry/src/main/ets/view/StoryChapter.ets', import.meta.url), 'utf8');
const story = await readFile(new URL('../entry/src/main/ets/view/BubuStoryView.ets', import.meta.url), 'utf8');

test('成长绘本由用户主动收录的 Entry 驱动并跨设备同步', () => {
  assert.ok(model.includes('inStorybook?: boolean'));
  assert.ok(database.includes("addColumnIfMissing('entry', 'inStorybook'"));
  assert.ok(sync.includes("'inStorybook': e.inStorybook === true"));
  assert.ok(sync.includes("e.inStorybook = SyncEngine.rBool(r, 'inStorybook')"));
  assert.ok(detail.includes("this.entry.inStorybook ? '移出绘本' : '收进绘本'"));
  assert.ok(builder.includes('entry.inStorybook === true'));
  assert.ok(story.includes('fetchEntries(false)'));
  assert.ok(!story.includes('fetchMilestones'));
});

test('绘本正文优先第一人称且封面优先真实照片', () => {
  assert.ok(builder.includes('entry.firstPersonNote'));
  assert.ok(story.includes('photo.thumbnailFileName'));
  assert.ok(story.includes('Image(ch.photoFileName)'));
});
