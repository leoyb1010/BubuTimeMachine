import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const share = await readFile(new URL('../entry/src/main/ets/services/ShareService.ets', import.meta.url), 'utf8');
const moduleJson = await readFile(new URL('../entry/src/main/module.json5', import.meta.url), 'utf8');
const ability = await readFile(new URL('../entry/src/main/ets/entryability/EntryAbility.ets', import.meta.url), 'utf8');
const home = await readFile(new URL('../entry/src/main/ets/view/HomeView.ets', import.meta.url), 'utf8');
const thumb = await readFile(new URL('../entry/src/main/ets/components/MediaThumbnail.ets', import.meta.url), 'utf8');

test('Share Kit 支持纯文本与可直达具体 Entry 的 hyperlink 双记录', () => {
  assert.ok(share.includes("utd: 'general.plain-text'"));
  assert.ok(share.includes("utd: 'general.hyperlink'"));
  assert.ok(share.includes('bubutime://entry/'));
  assert.ok(share.includes('data.addRecord'));
});

test('EntryAbility 注册并处理冷启动和 onNewWant 深链，Home 精确打开目标记录', () => {
  assert.ok(moduleJson.includes('ohos.want.action.viewData'));
  assert.ok(moduleJson.includes('"scheme": "bubutime"'));
  assert.ok(ability.includes('this.handleEntryLink(want)'));
  assert.ok(home.includes("@StorageLink('bubuOpenEntryId')"));
  assert.ok(home.includes('this.selectedEntry = entry'));
});

test('通用媒体缩略图校验真实文件并遵循系统减少动态', () => {
  assert.ok(thumb.includes('store.thumbnailExists(thumb)'));
  assert.ok(thumb.includes('if (BubuMotion.reduced) return'));
});
