import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const ability = await readFile(new URL('../entry/src/main/ets/entryability/EntryAbility.ets', import.meta.url), 'utf8');
const sync = await readFile(new URL('../entry/src/main/ets/sync/SyncEngine.ets', import.meta.url), 'utf8');

test('生产启动不再自动导入或覆盖特定家庭的 iOS 基准数据', () => {
  assert.ok(!ability.includes('IosBaselineImporter'));
  assert.ok(!ability.includes('runIfNeeded'));
});

test('重新核对服务器只重置游标并幂等合并，绝不先清空本机', () => {
  const start = sync.indexOf('async pullServerToLocalNow()');
  const end = sync.indexOf('async forceUploadAllLocalData', start);
  const method = sync.slice(start, end);
  assert.ok(method.includes('await this.resetCursors()'));
  assert.ok(method.includes('await this.pullRemote()'));
  assert.ok(!method.includes('clearServerBackedData'));
  assert.ok(!method.includes('pruneLocalToServerMirror'));
  assert.ok(!method.includes('serverMirrorMode = true'));
});

test('生产运行代码不再保留清空全部业务表的 emergency API', () => {
  assert.ok(!sync.includes('repairServerFilesWithoutClearingNow'));
  assert.ok(!sync.includes('shouldProtectIosBaselineFromServerPull'));
  assert.ok(!sync.includes('clearServerBackedData'));
});

test('首次登录走先推本地再拉远端的正常双向同步，不进入镜像恢复', () => {
  const syncNow = sync.slice(sync.indexOf('async syncNow('), sync.indexOf('async pullServerToLocalNow()'));
  assert.ok(!syncNow.includes('isServerBaselineReady'));
  const connect = sync.slice(sync.indexOf('private async connectAndSync()'), sync.indexOf('// MARK: - 推'));
  assert.ok(connect.indexOf('await this.pushLocal()') < connect.indexOf('await this.pullRemote()'));
});
