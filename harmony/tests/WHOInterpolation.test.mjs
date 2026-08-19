import assert from 'node:assert/strict';
import test from 'node:test';
import { interpolatePercentileBand } from '../entry/src/main/ets/models/WHOInterpolation.ts';

test('WHO 百分位在关键月龄之间按月份线性插值', () => {
  const table = [
    { month: 24, p3: 80, p15: 83, p50: 86, p85: 90, p97: 93 },
    { month: 36, p3: 88, p15: 91, p50: 96, p85: 100, p97: 104 }
  ];
  const band = interpolatePercentileBand(table, 30);
  assert.equal(band.p3, 84);
  assert.equal(band.p50, 91);
  assert.equal(band.month, 30);
});

test('超出表格范围时夹到首尾关键点', () => {
  const table = [{ month: 0, p3: 1, p15: 2, p50: 3, p85: 4, p97: 5 }];
  assert.equal(interpolatePercentileBand(table, -1).month, 0);
  assert.equal(interpolatePercentileBand(table, 99).month, 0);
});
