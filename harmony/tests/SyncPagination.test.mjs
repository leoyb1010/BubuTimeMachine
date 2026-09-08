import assert from 'node:assert/strict';
import test from 'node:test';
import { collectSyncPages } from '../entry/src/main/ets/sync/SyncPagination.ts';

const stamp = '2026-09-08 00:00:00.123Z';
const rows = (count) => Array.from({ length: count }, (_, n) => ({ id: String(n).padStart(15, '0'), updated: stamp }));

test('同毫秒 401 条记录及墓碑完整跨页', async () => {
  for (const isDeleted of [false, true]) {
    const data = rows(401).map(row => ({ ...row, isDeleted }));
    let requests = 0;
    const result = await collectSyncPages(undefined, async (updated, id) => {
      requests++;
      return data.filter(row => !updated || row.updated > updated || (row.updated === updated && row.id > id)).slice(0, 200);
    });
    assert.equal(result.length, 401);
    assert.equal(new Set(result.map(row => row.id)).size, 401);
    assert.equal(requests, 3);
  }
});

test('翻页期间首行更新不会造成后页跳行，保留其最新版本', async () => {
  const data = rows(400);
  let page = 0;
  const result = await collectSyncPages(undefined, async (updated, id) => {
    if (++page === 2) data[0] = { ...data[0], updated: '2026-09-08 00:00:01.000Z', note: 'new' };
    return data.filter(row => !updated || row.updated > updated || (row.updated === updated && row.id > id))
      .sort((a, b) => a.updated.localeCompare(b.updated) || a.id.localeCompare(b.id)).slice(0, 200);
  });
  assert.equal(result.length, 400);
  assert.equal(result[0].note, 'new');
});

test('缺字段、重复页及安全上限不能伪装完整结果', async () => {
  await assert.rejects(collectSyncPages(undefined, async () => [{ id: 'missing-date' }]), /updated/);
  await assert.rejects(collectSyncPages(undefined, async () => rows(200)), /分页顺序/);
  await assert.rejects(collectSyncPages(undefined, async () => rows(200), 1), /安全上限/);
});
