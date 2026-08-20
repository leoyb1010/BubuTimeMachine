import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const db = await readFile(new URL('../entry/src/main/ets/data/AppDatabase.ets', import.meta.url), 'utf8');
const sync = await readFile(new URL('../entry/src/main/ets/sync/SyncEngine.ets', import.meta.url), 'utf8');
const api = await readFile(new URL('../entry/src/main/ets/services/APIClient.ets', import.meta.url), 'utf8');

test('语音、评论、健康和胶囊回写都使用单步 upsert，不再先删后插', () => {
  for (const table of ['voice_note', 'comment', 'health_record', 'time_capsule']) {
    const line = db.split('\n').find((value) => value.includes(`insert('${table}'`));
    assert.ok(line?.includes('ON_CONFLICT_REPLACE'), `${table} 必须 upsert`);
  }
  assert.ok(!sync.includes('DELETE FROM voice_note'));
  assert.ok(!sync.includes('DELETE FROM comment'));
  assert.ok(!sync.includes('deleteCapsule(c.id)'));
  assert.ok(!sync.includes('deleteHealth(h.id)'));
});

test('远端 localId 拒绝引号和控制字符，查询失败不会伪装成不存在再 POST', () => {
  assert.ok(sync.includes('/^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/.test(candidate)'));
  const findStart = api.indexOf('async findByLocalId(');
  const findEnd = api.indexOf('// MARK: 文件 URL', findStart);
  const method = api.slice(findStart, findEnd);
  assert.ok(!method.includes('catch'));
  assert.ok(method.includes('await this.request'));
});
