import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const app = await readFile(new URL('../AppScope/app.json5', import.meta.url), 'utf8');
const config = await readFile(new URL('../entry/src/main/ets/services/ServerConfig.ets', import.meta.url), 'utf8');
const changelog = await readFile(new URL('../entry/src/main/ets/models/Changelog.ets', import.meta.url), 'utf8');

test('鸿蒙安装清单、运行时版本和更新记录按自身发布基线保持一致', async () => {
  const baselines = JSON.parse(await readFile(new URL('../release-baselines.json', import.meta.url), 'utf8'));
  const { version, build } = baselines.harmony;
  assert.ok(app.includes(`"versionCode": ${build}`));
  assert.ok(app.includes(`"versionName": "${version}"`));
  assert.ok(config.includes(`versionName: string = '${version}'`));
  assert.ok(config.includes(`versionCode: string = '${build}'`));
  assert.ok(changelog.includes(`version: '${version}'`));
  assert.equal(baselines.parityVerified, false, '版本一致不能代替功能追平验收');
});
