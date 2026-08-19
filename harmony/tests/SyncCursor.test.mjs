import assert from 'node:assert/strict';
import test from 'node:test';
import { laterServerTimestamp, overlappedServerCursor } from '../entry/src/main/ets/sync/SyncCursor.ts';

test('游标只取服务器 updated 最大值并回退 60 秒', () => {
  const older = '2026-08-19T07:00:00.000Z';
  const newer = '2026-08-19T07:05:00.000Z';
  assert.equal(laterServerTimestamp(undefined, older), older);
  assert.equal(laterServerTimestamp(older, newer), newer);
  assert.equal(laterServerTimestamp(newer, older), newer);
  assert.equal(overlappedServerCursor(newer), '2026-08-19T07:04:00.000Z');
});
