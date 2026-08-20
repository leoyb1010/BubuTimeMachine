import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const growth = await readFile(new URL('../entry/src/main/ets/view/GrowthHomeView.ets', import.meta.url), 'utf8');

test('成长首页等全部事实读完后再发布 State，概览与四张卡数字一致', () => {
  const load = growth.slice(growth.indexOf('private async reload()'), growth.indexOf('private achieved()'));
  const lastFetch = load.indexOf('const firstTimes = await');
  assert.ok(lastFetch > 0);
  assert.ok(load.indexOf('this.milestones = milestones') > lastFetch);
  assert.ok(load.indexOf('this.measurements = measurements') > lastFetch);
  assert.ok(load.indexOf('this.health = health') > lastFetch);
  assert.ok(load.indexOf('this.vaccines = vaccines') > lastFetch);
  assert.ok(growth.includes('subtitle: () => string'));
  assert.ok(growth.includes('Text(subtitle())'));
});
