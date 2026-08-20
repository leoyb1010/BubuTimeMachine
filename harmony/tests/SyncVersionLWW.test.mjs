import assert from 'node:assert/strict';
import test from 'node:test';
import { remoteVersionIsNewer } from '../entry/src/main/ets/services/SyncVersionModel.ts';
import { readFile } from 'node:fs/promises';

const api = await readFile(new URL('../entry/src/main/ets/services/APIClient.ets', import.meta.url), 'utf8');
const sync = await readFile(new URL('../entry/src/main/ets/sync/SyncEngine.ets', import.meta.url), 'utf8');

test('远端 clientUpdatedAt 严格较新时阻止旧设备覆盖', () => {
  assert.equal(remoteVersionIsNewer('2026-08-20 10:00:00.000Z', '2026-08-20 09:59:59.999Z'), true);
  assert.equal(remoteVersionIsNewer('2026-08-20T10:00:00.000Z', '2026-08-20T10:00:00.000Z'), false);
  assert.equal(remoteVersionIsNewer(undefined, '2026-08-20T10:00:00Z'), false);
});

test('JSON 和 multipart upsert 都执行 LWW，调用方传真实业务编辑时间', () => {
  assert.ok(api.match(/remoteVersionIsNewer/g)?.length >= 2);
  assert.ok(api.includes("existing['_bubuRemoteNewer'] = true"));
  assert.ok(api.includes('skippedRemoteNewer: true'));
  assert.ok(sync.includes('new Date(v.updatedAt || v.createdAt)'));
  assert.ok(sync.includes('new Date(g.updatedAt || g.createdAt)'));
  assert.ok(sync.includes('new Date(e.editedAt ?? e.createdAt)'));
});
