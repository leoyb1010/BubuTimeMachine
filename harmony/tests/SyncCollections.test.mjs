import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const source = await readFile(new URL('../entry/src/main/ets/sync/SyncEngine.ets', import.meta.url), 'utf8');
const apiSource = await readFile(new URL('../entry/src/main/ets/services/APIClient.ets', import.meta.url), 'utf8');

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

test('增量同步使用服务器 updated 并传播软删除墓碑', () => {
  assert.ok(apiSource.includes('&sort=updated'));
  assert.ok(apiSource.includes("clauses.push(`(updated>'"));
  assert.ok(apiSource.includes("clauses.push('(isDeleted=true)')"));
  assert.ok(source.includes('fetchDeletedTombstones(collection, cursor)'));
  assert.ok(source.includes('removeRemoteTombstones(collection, tombstones)'));
  assert.ok(source.includes('server_updated_cursor_migration_v1'));
  assert.ok(apiSource.includes('activeRecordBody(body, existing === null)'));
  assert.ok(apiSource.includes('activeRecordFields(fields, !isPatch)'));
});
