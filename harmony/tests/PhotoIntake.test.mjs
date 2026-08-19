import assert from 'node:assert/strict';
import test from 'node:test';
import {
  PhotoIntakeState,
  clusterPhotoCandidates
} from '../entry/src/main/ets/models/PhotoIntake.ts';

function candidate(uri, createdAt, mediaType = 1, subtype = 0, burstKey = undefined) {
  return {
    assetUri: uri,
    displayName: uri,
    createdAt,
    mediaType,
    width: 100,
    height: 100,
    duration: 0,
    subtype,
    burstKey,
    state: PhotoIntakeState.discovered,
    isLikelyChild: false
  };
}

test('照片按 90 分钟和自然日分组，连拍不拆散', () => {
  const base = Date.parse('2026-08-19T10:00:00+08:00');
  const groups = clusterPhotoCandidates([
    candidate('a', base),
    candidate('b', base + 20 * 60_000, 1, 3, 'burst-1'),
    candidate('c', base + 3 * 60 * 60_000, 2),
    candidate('d', base + 26 * 60 * 60_000)
  ]);
  assert.equal(groups.length, 3);
  assert.deepEqual(groups.map(group => group.assetUris), [['d'], ['c'], ['a', 'b']]);
  assert.equal(groups[1].videoCount, 1);
  assert.equal(groups[2].movingPhotoCount, 1);
});

test('相同候选集合产生稳定事件 id', () => {
  const now = Date.now();
  const left = clusterPhotoCandidates([candidate('b', now + 1), candidate('a', now)])[0];
  const right = clusterPhotoCandidates([candidate('a', now), candidate('b', now + 1)])[0];
  assert.equal(left.id, right.id);
});
