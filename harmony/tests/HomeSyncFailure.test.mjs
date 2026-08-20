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

test('同步状态包含全表 pendingCount，在线但有失败时不误报全部对齐', async () => {
  const engine = await readFile(new URL('../entry/src/main/ets/sync/SyncEngine.ets', import.meta.url), 'utf8');
  const center = await readFile(new URL('../entry/src/main/ets/view/SyncCenterView.ets', import.meta.url), 'utf8');
  const db = await readFile(new URL('../entry/src/main/ets/data/AppDatabase.ets', import.meta.url), 'utf8');
  assert.ok(engine.includes('pendingCount: number'));
  assert.ok(engine.includes('await this.refreshPendingCount()'));
  assert.ok(db.includes('async countPendingSync()'));
  assert.ok(center.includes("this.pendingCount === 0 ? '已经同步好了'"));
  assert.ok(center.includes('部分内容尚未传完'));
});
