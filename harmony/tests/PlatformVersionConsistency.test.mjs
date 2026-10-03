import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const app = JSON.parse(await readFile(new URL('../AppScope/app.json5', import.meta.url), 'utf8')).app;
const config = await readFile(new URL('../entry/src/main/ets/services/ServerConfig.ets', import.meta.url), 'utf8');
const changelog = await readFile(new URL('../entry/src/main/ets/models/Changelog.ets', import.meta.url), 'utf8');
const baselines = JSON.parse(await readFile(new URL('../release-baselines.json', import.meta.url), 'utf8'));

test('HarmonyOS 安装清单、运行时与更新记录保持自身版本一致', () => {
  assert.equal(app.versionName, baselines.harmony.version);
  assert.equal(String(app.versionCode), baselines.harmony.build);
  assert.ok(config.includes(`versionName: string = '${app.versionName}'`));
  assert.ok(config.includes(`versionCode: string = '${app.versionCode}'`));
  assert.equal(changelog.match(/version: '([^']+)'/)[1], app.versionName);
});

test('双端差异按真实发布基线登记，不以改版本号伪造功能追平', async () => {
  const ios = await readFile(new URL('../../project.yml', import.meta.url), 'utf8');
  const iosChangelog = await readFile(new URL('../../BubuTimeMachine/Models/Changelog.swift', import.meta.url), 'utf8');
  assert.equal(ios.match(/MARKETING_VERSION: "([^"]+)"/)[1], baselines.ios.version);
  assert.equal(ios.match(/CURRENT_PROJECT_VERSION: "([^"]+)"/)[1], baselines.ios.build);
  assert.equal(iosChangelog.match(/version: "([^"]+)"/)[1], baselines.ios.version);
  assert.equal(baselines.parityVerified, false);
  const matrix = await readFile(new URL('../PARITY_MATRIX.md', import.meta.url), 'utf8');
  for (const version of [baselines.ios.version, baselines.harmony.version]) assert.ok(matrix.includes(version));
  assert.ok(matrix.includes('需要真机'));
});
