import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const detail = await readFile(new URL('../entry/src/main/ets/view/EntryDetailView.ets', import.meta.url), 'utf8');
const timeline = await readFile(new URL('../entry/src/main/ets/view/TimelineView.ets', import.meta.url), 'utf8');
const config = await readFile(new URL('../entry/src/main/ets/services/ServerConfig.ets', import.meta.url), 'utf8');

test('记录详情可修改日期和时间并标记待同步', () => {
  assert.ok(detail.includes('showDatePickerDialog'));
  assert.ok(detail.includes('showTimePickerDialog'));
  assert.ok(detail.includes('happenedAt: this.draftHappenedAt'));
  assert.ok(detail.includes('syncState: SyncState.local'));
});

test('时光轴可在拍摄时间和记录时间之间切换并持久化', () => {
  assert.ok(timeline.includes("this.sortModeRaw === 'recorded' ? entry.createdAt : entry.happenedAt"));
  assert.ok(timeline.includes('ServerConfig.shared.setTimelineSortMode'));
  assert.ok(config.includes("timelineSortModeRaw = await this.getStr('timelineSortMode', 'capture')"));
});
