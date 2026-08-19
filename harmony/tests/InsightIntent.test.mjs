import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const source = await readFile(new URL('../entry/src/main/ets/intent/OpenBubuIntent.ets', import.meta.url), 'utf8');

test('鸿蒙系统意图可在前台打开布布时光机', () => {
  assert.ok(source.includes("intentName: 'BubuOpenApp'"));
  assert.ok(source.includes('UI_ABILITY_FOREGROUND'));
  assert.ok(source.includes("abilityName: 'EntryAbility'"));
});
