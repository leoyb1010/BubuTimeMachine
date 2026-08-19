import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const config = await readFile(new URL('../entry/src/main/ets/services/ServerConfig.ets', import.meta.url), 'utf8');
const simple = await readFile(new URL('../entry/src/main/ets/view/SimpleModeView.ets', import.meta.url), 'utf8');
const root = await readFile(new URL('../entry/src/main/ets/pages/RootPage.ets', import.meta.url), 'utf8');

test('长辈身份自动进入三动作简单模式并可恢复原身份', () => {
  assert.ok(config.includes('isElderRole(role)'));
  assert.ok(config.includes('roleBeforeElderRaw'));
  assert.ok(config.includes('exitSimpleMode'));
  assert.ok(root.includes("@StorageLink('bubuSimpleMode')"));
  for (const title of ['拍一张', '说一段', '看布布']) assert.ok(simple.includes(`'${title}'`));
  assert.ok(simple.includes('EntryWriter.entryWithPhoto'));
});
