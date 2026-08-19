import assert from 'node:assert/strict';
import test from 'node:test';
import {
  SYNC_BASE_INTERVAL_MS,
  SYNC_MAX_INTERVAL_MS,
  syncBackoffIntervalMs
} from '../entry/src/main/ets/sync/SyncBackoff.ts';

test('同步失败按 30 秒到 8 分钟指数退避并封顶', () => {
  assert.equal(SYNC_BASE_INTERVAL_MS, 30_000);
  assert.equal(SYNC_MAX_INTERVAL_MS, 480_000);
  assert.deepEqual(
    [-1, 0, 1, 2, 3, 4, 5, 99].map(syncBackoffIntervalMs),
    [30_000, 30_000, 60_000, 120_000, 240_000, 480_000, 480_000, 480_000]
  );
});
