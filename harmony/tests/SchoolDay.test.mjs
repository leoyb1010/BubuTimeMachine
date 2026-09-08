import assert from 'node:assert/strict';
import test from 'node:test';
import { schoolDayLabel } from '../entry/src/main/ets/models/SchoolDay.ts';
test('入园日期按本地自然日计数，未设置不显示', () => {
  const start = new Date(2026, 8, 10).getTime();
  assert.equal(schoolDayLabel(start, new Date(2026, 8, 8, 23).getTime()), '还有 2 天上幼儿园');
  assert.equal(schoolDayLabel(start, new Date(2026, 8, 10, 22).getTime()), '今天是上幼儿园第一天');
  assert.equal(schoolDayLabel(start, new Date(2026, 8, 11).getTime()), '上幼儿园第 2 天');
  assert.equal(schoolDayLabel(undefined), '');
  assert.equal(schoolDayLabel(0), '');
});
