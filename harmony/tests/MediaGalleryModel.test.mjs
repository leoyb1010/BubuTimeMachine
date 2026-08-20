import assert from 'node:assert/strict';
import test from 'node:test';
import {
  buildTimelineMediaSequence,
  resolveInitialGalleryIndex
} from '../entry/src/main/ets/services/MediaGalleryModel.ts';

test('跨记录媒体按时光倒序、同记录内按创建时间正序，并排除已归档记录媒体', () => {
  const entries = [
    { id: 'new', happenedAt: 300 },
    { id: 'old', happenedAt: 100 }
  ];
  const media = [
    { id: 'old-photo', entryId: 'old', createdAt: 1 },
    { id: 'new-second', entryId: 'new', createdAt: 2 },
    { id: 'archived', entryId: 'hidden', createdAt: 1 },
    { id: 'new-first', entryId: 'new', createdAt: 1 }
  ];
  assert.deepEqual(buildTimelineMediaSequence(media, entries).map(item => item.id), [
    'new-first', 'new-second', 'old-photo'
  ]);
});

test('初始照片位于首中末均精确定位，缺失时安全回到首项', () => {
  const items = [{ id: 'a' }, { id: 'b' }, { id: 'c' }];
  assert.equal(resolveInitialGalleryIndex(items, 'a'), 0);
  assert.equal(resolveInitialGalleryIndex(items, 'b'), 1);
  assert.equal(resolveInitialGalleryIndex(items, 'c'), 2);
  assert.equal(resolveInitialGalleryIndex(items, 'missing'), 0);
});
