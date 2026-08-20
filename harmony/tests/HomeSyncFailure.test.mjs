import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const home = await readFile(new URL('../entry/src/main/ets/view/HomeView.ets', import.meta.url), 'utf8');
const routes = await readFile(new URL('../entry/src/main/ets/view/HomeDestinations.ets', import.meta.url), 'utf8');

test('首页无条件浮出同步失败原因，可一键清零退避重试并直达同步中心', () => {
  assert.ok(home.includes('snapshot.lastFailureReason'));
  assert.ok(home.includes("'同步遇到问题'"));
  assert.ok(home.includes("? '重试' : '查看'"));
  assert.ok(home.includes('SyncEngine.shared.syncNow(true)'));
  assert.ok(home.includes('this.navigate(HomeRoute.syncCenter)'));
  assert.ok(home.includes('SyncCenterView'));
  assert.ok(routes.includes('syncCenter'));
});
