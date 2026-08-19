import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const scheduler = await readFile(new URL('../entry/src/main/ets/services/BackgroundSyncScheduler.ets', import.meta.url), 'utf8');
const ability = await readFile(new URL('../entry/src/main/ets/background/BackgroundSyncAbility.ets', import.meta.url), 'utf8');
const moduleConfig = await readFile(new URL('../entry/src/main/module.json5', import.meta.url), 'utf8');

test('后台任务在联网时恢复同一套同步引擎', () => {
  assert.ok(scheduler.includes('NetworkType.NETWORK_TYPE_ANY'));
  assert.ok(scheduler.includes('isPersisted: true'));
  assert.ok(ability.includes('SyncEngine.shared.syncNow(false)'));
  assert.ok(moduleConfig.includes('"type": "workScheduler"'));
});

test('当前产品范围只声明鸿蒙手机', () => {
  assert.ok(moduleConfig.includes('"deviceTypes": ["phone"]'));
  assert.ok(!moduleConfig.includes('"tablet"'));
});
