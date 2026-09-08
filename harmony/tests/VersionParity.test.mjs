import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const app = await readFile(new URL('../AppScope/app.json5', import.meta.url), 'utf8');
const config = await readFile(new URL('../entry/src/main/ets/services/ServerConfig.ets', import.meta.url), 'utf8');
const changelog = await readFile(new URL('../entry/src/main/ets/models/Changelog.ets', import.meta.url), 'utf8');

test('双端安装清单、运行时版本和更新记录保持一致', async () => {
  const ios = await readFile(new URL('../../project.yml', import.meta.url), 'utf8');
  const version = ios.match(/MARKETING_VERSION: "([^"]+)"/)[1];
  const build = ios.match(/CURRENT_PROJECT_VERSION: "([^"]+)"/)[1];
  assert.ok(app.includes(`"versionCode": ${build}`));
  assert.ok(app.includes(`"versionName": "${version}"`));
  assert.ok(config.includes(`versionName: string = '${version}'`));
  assert.ok(config.includes(`versionCode: string = '${build}'`));
  assert.ok(changelog.includes(`version: '${version}'`));
});
