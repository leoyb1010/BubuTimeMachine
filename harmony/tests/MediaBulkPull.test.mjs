import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const sync = await readFile(new URL('../entry/src/main/ets/sync/SyncEngine.ets', import.meta.url), 'utf8');

test('数千媒体首轮拉取先批量建索引，不逐条查 Entry 和 Media', () => {
  const start = sync.indexOf('private async pullMedia()');
  const end = sync.indexOf('private static applyMedia', start);
  const body = sync.slice(start, end);
  assert.ok(body.includes('AppDatabase.shared.fetchAllMedia()'));
  assert.ok(body.includes('AppDatabase.shared.fetchEntries(true)'));
  assert.ok(body.includes('new Map<string, Media>()'));
  assert.ok(body.includes('new Set<string>()'));
  assert.ok(!body.includes('fetchMediaForEntry(entryLocalId)'));
  assert.ok(!body.includes('this.findEntry(entryLocalId)'));
});

test('拉取失败日志保留 Error message，不再只打印空对象', () => {
  assert.ok(sync.includes('SyncEngine.errorText(e)'));
  assert.ok(!sync.includes('`拉取 ${collection} 失败，下轮补拉: ${JSON.stringify(e)}`'));
});
