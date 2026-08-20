import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const sync = await readFile(new URL('../entry/src/main/ets/sync/SyncEngine.ets', import.meta.url), 'utf8');
const db = await readFile(new URL('../entry/src/main/ets/data/AppDatabase.ets', import.meta.url), 'utf8');

test('服务器存在历史重复档案时选完整度最高且更新的 iOS 档案', () => {
  assert.ok(sync.includes('private static profileRecordScore'));
  assert.ok(sync.includes('private static isBetterProfile'));
  assert.ok(sync.includes("name !== '布布'"));
  assert.ok(sync.includes("rStr(r, 'bloodType')"));
  assert.ok(sync.includes("rFileName(r, 'avatar')"));
});

test('完整远端档案原子替换新机占位档案，本地始终只有一个 ChildProfile', () => {
  assert.ok(sync.includes('AppDatabase.shared.replaceChildProfile(profile)'));
  assert.ok(db.includes('async replaceChildProfile'));
  assert.ok(db.includes("transaction.delete(new relationalStore.RdbPredicates('child_profile'))"));
  assert.ok(db.includes("transaction.insert('child_profile'"));
  assert.ok(db.includes('await transaction.commit()'));
});
