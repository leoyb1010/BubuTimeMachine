import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const frame = await readFile(new URL('../entry/src/main/ets/view/PhotoFrameView.ets', import.meta.url), 'utf8');
const settings = await readFile(new URL('../entry/src/main/ets/view/SettingsView.ets', import.meta.url), 'utf8');
const config = await readFile(new URL('../entry/src/main/ets/services/ServerConfig.ets', import.meta.url), 'utf8');

test('手机相框模式用真实照片轮播、那年今日优先、可暂停并防熄屏', () => {
  assert.ok(frame.includes('fetchMediaForEntry'));
  assert.ok(frame.includes('priority.concat(PhotoFrameView.shuffled(rest))'));
  assert.ok(frame.includes("Button(this.paused ? '继续' : '暂停')"));
  assert.ok(frame.includes('setWindowKeepScreenOn'));
  assert.ok(frame.includes('AgeCalculator.ageDescription'));
  assert.ok(settings.includes("this.navRow('相框模式'"));
  assert.ok(config.includes('setPhotoFrameDwellSeconds'));
});
