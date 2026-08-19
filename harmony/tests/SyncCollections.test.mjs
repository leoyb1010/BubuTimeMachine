import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const source = await readFile(new URL('../entry/src/main/ets/sync/SyncEngine.ets', import.meta.url), 'utf8');

test('成长之声覆盖推送、拉取、文件下载、镜像清理和游标', () => {
  for (const contract of [
    'await this.pushVoiceMemos()',
    "pullCollection('voicememos'",
    "uploadFile(\n            'voicememos'",
    "remoteFileURL(r, 'voicememos', 'file')",
    "seen('voicememos')",
    "'voicenotes', 'voicememos', 'timecapsules'"
  ]) {
    assert.ok(source.includes(contract), `缺少成长之声同步契约：${contract}`);
  }
});
