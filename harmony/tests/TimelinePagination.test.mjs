import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const database = await readFile(new URL('../entry/src/main/ets/data/AppDatabase.ets', import.meta.url), 'utf8');
const timeline = await readFile(new URL('../entry/src/main/ets/view/TimelineView.ets', import.meta.url), 'utf8');

test('时光轴使用 RDB limit/offset 真分页并在触底时续载', () => {
  assert.ok(database.includes('fetchEntriesPage'));
  assert.ok(database.includes('pred.limitAs'));
  assert.ok(database.includes('pred.offsetAs'));
  assert.ok(timeline.includes('onScrollEdge'));
  assert.ok(timeline.includes('this.loadMore()'));
  assert.ok(timeline.includes('this.entries.length'));
});

test('搜索时扩展到全库，清空搜索后恢复分页窗口', () => {
  assert.ok(timeline.includes('const all = await AppDatabase.shared.fetchEntries(false)'));
  assert.ok(timeline.includes('await this.reload()'));
});
