import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const settings = await readFile(new URL('../entry/src/main/ets/view/SettingsView.ets', import.meta.url), 'utf8');
const config = await readFile(new URL('../entry/src/main/ets/services/ServerConfig.ets', import.meta.url), 'utf8');
const sync = await readFile(new URL('../entry/src/main/ets/view/SyncCenterView.ets', import.meta.url), 'utf8');

test('任意身份都可手动开启或退出简洁长辈模式并持久化', () => {
  assert.ok(settings.includes("Text('简洁长辈模式')"));
  assert.ok(settings.includes('ServerConfig.shared.setSimpleModeEnabled(value)'));
  assert.ok(config.includes('async setSimpleModeEnabled'));
  assert.ok(config.includes("AppStorage.setOrCreate('bubuSimpleMode', value)"));
});

test('同步中心真实读取上次导出时间，超过 90 天提醒并直达全量导出', () => {
  assert.ok(sync.includes("store.get('bubu.lastExportAt'"));
  assert.ok(sync.includes('days > 90'));
  assert.ok(sync.includes("Button('现在导出一份完整档案')"));
  assert.ok(settings.includes('onOpenExport: () => { this.showSyncCenter = false; this.showExport = true; }'));
});
