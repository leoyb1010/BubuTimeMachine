import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const ability = await readFile(new URL('../entry/src/main/ets/entryability/EntryAbility.ets', import.meta.url), 'utf8');
const page = await readFile(new URL('../entry/src/main/ets/pages/DataProtectionPage.ets', import.meta.url), 'utf8');
const pages = await readFile(new URL('../entry/src/main/resources/base/profile/main_pages.json', import.meta.url), 'utf8');

test('数据库初始化失败只进入独立保护页且不会继续挂载 RootPage', () => {
  const dbStart = ability.indexOf('await AppDatabase.shared.initialize(this.context)');
  const protection = ability.indexOf("windowStage.loadContent('pages/DataProtectionPage'", dbStart);
  const earlyReturn = ability.indexOf('return;', protection);
  const root = ability.indexOf("windowStage.loadContent('pages/RootPage'", earlyReturn);
  assert.ok(dbStart >= 0 && protection > dbStart && earlyReturn > protection && root > earlyReturn);
  assert.ok(pages.includes('pages/DataProtectionPage'));
});

test('保护页明确不删除、不重建、不同步并劝阻卸载', () => {
  assert.ok(page.includes('没有删除、重建或覆盖原文件'));
  assert.ok(page.includes('没有启动同步'));
  assert.ok(page.includes('不要卸载 App'));
  assert.ok(!page.includes("from '../data/AppDatabase'"));
  assert.ok(!page.includes("from '../sync/SyncEngine'"));
});
