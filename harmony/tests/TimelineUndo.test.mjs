import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const timeline = await readFile(new URL('../entry/src/main/ets/view/TimelineView.ets', import.meta.url), 'utf8');
const database = await readFile(new URL('../entry/src/main/ets/data/AppDatabase.ets', import.meta.url), 'utf8');

test('时光卡长按菜单提供分享和删除，软删除后 3.5 秒内可撤销并重新同步', () => {
  assert.ok(timeline.includes('bindContextMenu(this.entryMenu(entry), ResponseType.LongPress)'));
  assert.ok(timeline.includes("content: '分享这一刻'"));
  assert.ok(timeline.includes("content: '删除记录'"));
  assert.ok(timeline.includes('}, 3500)'));
  assert.ok(timeline.includes("Text('撤销')"));
  assert.ok(timeline.includes('AppDatabase.shared.restoreEntry(id)'));
  assert.ok(timeline.includes('SyncEngine.shared.start()'));
  assert.ok(database.includes('async restoreEntry(id: string)'));
  assert.ok(database.includes('isArchived: 0'));
  assert.ok(database.includes('editedAt: Date.now()'));
});
