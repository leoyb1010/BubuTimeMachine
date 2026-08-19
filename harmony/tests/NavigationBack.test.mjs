import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const root = new URL('../entry/src/main/ets/', import.meta.url);
const rootPage = await readFile(new URL('pages/RootPage.ets', root), 'utf8');
const home = await readFile(new URL('view/HomeView.ets', root), 'utf8');
const timeline = await readFile(new URL('view/TimelineView.ets', root), 'utf8');
const studio = await readFile(new URL('view/AIStudioView.ets', root), 'utf8');
const milestones = await readFile(new URL('view/MilestonesView.ets', root), 'utf8');
const settings = await readFile(new URL('view/SettingsView.ets', root), 'utf8');
const detail = await readFile(new URL('view/EntryDetailView.ets', root), 'utf8');

test('系统侧滑先按导航深度返回上一界面，Root 不再越级切回首页', () => {
  assert.ok(rootPage.includes("@StorageLink('bubuNavigationDepth')"));
  assert.ok(rootPage.includes('if (this.navigationDepth > 0 || !this.tabBarVisible)'));
  const nestedBlock = rootPage.slice(rootPage.indexOf('if (this.navigationDepth > 0'));
  assert.ok(nestedBlock.indexOf('this.backSignal = this.backSignal + 1') < nestedBlock.indexOf('this.selection !== 0'));
  assert.ok(!nestedBlock.slice(0, nestedBlock.indexOf('this.selection !== 0')).includes('this.tabBarVisible = true'));
});

test('各主 Tab、设置二级页和详情弹层统一声明并消费导航深度', () => {
  for (const source of [home, timeline, studio, milestones, settings, detail]) {
    assert.ok(source.includes("@StorageLink('bubuNavigationDepth')"));
    assert.ok(source.includes('syncNavigationDepth'));
  }
  assert.ok(settings.includes('this.navigationDepth !== 2'));
  assert.ok(detail.includes('this.navigationDepth !== 2'));
  assert.ok(detail.includes('this.viewingMediaID = null'));
});
