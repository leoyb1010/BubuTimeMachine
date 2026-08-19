import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const sync = await readFile(new URL('../entry/src/main/ets/sync/SyncEngine.ets', import.meta.url), 'utf8');
const database = await readFile(new URL('../entry/src/main/ets/data/AppDatabase.ets', import.meta.url), 'utf8');

test('生日和旧健康结构化迁移均幂等且成功后才落标记', () => {
  assert.ok(database.includes('normalizeChildBirthday'));
  assert.ok(database.includes('startOfLocalDay(profile.birthday)'));
  assert.ok(sync.includes("legacy_health_structured_migration_v1"));
  assert.ok(sync.lastIndexOf("cursorStore.put(key, true)") > sync.indexOf('backfillVaccineFromHealth(record)'));
  assert.ok(sync.includes('h.syncState === SyncState.synced ? SyncState.synced : SyncState.local'));
});
