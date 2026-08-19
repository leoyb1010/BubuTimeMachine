import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const app = await readFile(new URL('../AppScope/app.json5', import.meta.url), 'utf8');
const config = await readFile(new URL('../entry/src/main/ets/services/ServerConfig.ets', import.meta.url), 'utf8');
const changelog = await readFile(new URL('../entry/src/main/ets/models/Changelog.ets', import.meta.url), 'utf8');

test('鸿蒙安装清单、运行时版本和更新记录统一追平 iOS 2.11.0', () => {
  assert.ok(app.includes('"versionCode": 2026081901'));
  assert.ok(app.includes('"versionName": "2.11.0"'));
  assert.ok(config.includes("versionName: string = '2.11.0'"));
  assert.ok(config.includes("versionCode: string = '2026081901'"));
  assert.ok(changelog.includes("version: '2.11.0'"));
});
