import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const home = await readFile(new URL('../entry/src/main/ets/view/HomeView.ets', import.meta.url), 'utf8');
const routes = await readFile(new URL('../entry/src/main/ets/view/HomeDestinations.ets', import.meta.url), 'utf8');
const growth = await readFile(new URL('../entry/src/main/ets/view/GrowthHomeView.ets', import.meta.url), 'utf8');

test('首页直接显示待收照片并进入真实收件箱', () => {
  assert.ok(routes.includes('photoInbox'));
  assert.ok(home.includes('PhotoIntakeService.shared.cachedGroups()'));
  assert.ok(home.includes("this.navigate(HomeRoute.photoInbox)"));
  assert.ok(home.includes('PhotoInboxView({'));
});

test('首页显示未同步原片数且可直达同步中心', () => {
  assert.ok(home.includes('this.pendingMediaCount = allMedia.filter'));
  assert.ok(home.includes('项原片待回家'));
  assert.ok(home.includes('this.navigate(HomeRoute.syncCenter)'));
});

test('成长 Tab 的任一子页先返回成长根页，不直接退出 App', () => {
  assert.ok(growth.includes("@Watch('syncBackHandler') route"));
  assert.ok(growth.includes("BackDispatcher.shared.register('growth-home'"));
  assert.ok(growth.includes("this.route = ''"));
  assert.ok(growth.includes("BackDispatcher.shared.unregister('growth-home')"));
});
