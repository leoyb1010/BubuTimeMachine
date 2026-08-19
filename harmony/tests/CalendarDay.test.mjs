import assert from 'node:assert/strict';
import test from 'node:test';
import { startOfLocalDay } from '../entry/src/main/ets/models/CalendarDay.ts';

test('生日归一化移除时分秒且保持本地年月日', () => {
  const raw = new Date(2024, 2, 5, 14, 37, 12).getTime();
  const normalized = new Date(startOfLocalDay(raw));
  assert.equal(normalized.getFullYear(), 2024);
  assert.equal(normalized.getMonth(), 2);
  assert.equal(normalized.getDate(), 5);
  assert.equal(normalized.getHours(), 0);
  assert.equal(normalized.getMinutes(), 0);
});
