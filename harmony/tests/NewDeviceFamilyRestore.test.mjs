import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const config = await readFile(new URL('../entry/src/main/ets/services/ServerConfig.ets', import.meta.url), 'utf8');
const account = await readFile(new URL('../entry/src/main/ets/view/AccountView.ets', import.meta.url), 'utf8');
const onboarding = await readFile(new URL('../entry/src/main/ets/view/OnboardingView.ets', import.meta.url), 'utf8');
const advanced = await readFile(new URL('../entry/src/main/ets/view/AdvancedSettingsView.ets', import.meta.url), 'utf8');
const sync = await readFile(new URL('../entry/src/main/ets/sync/SyncEngine.ets', import.meta.url), 'utf8');

test('鸿蒙新机内置与 iOS 相同的家庭服务器，只需登录不重建档案', () => {
  assert.ok(config.includes("defaultBaseURL: string = 'https://bubu-api.leoyuan.top'"));
  assert.ok(config.includes("defaultAIBaseURL: string = 'https://bubu-ai.leoyuan.top'"));
  assert.ok(account.includes("已登录，开始同步"));
  assert.ok(account.includes('SyncEngine.shared.start()'));
  assert.ok(onboarding.includes('已有 iOS 家庭档案？登录后全部恢复'));
  assert.ok(onboarding.includes('SyncEngine.shared.pullServerToLocalNow()'));
  assert.ok(onboarding.includes('AppDatabase.shared.fetchChildProfile()'));
});

test('高级配置保存前必须真实验证账号，不再误报正在同步', () => {
  assert.ok(advanced.includes('new AccountService().login'));
  assert.ok(advanced.includes('await SyncEngine.shared.syncNow(true)'));
  assert.ok(advanced.includes("snapshot.state === 'online'"));
  assert.ok(advanced.includes('snapshot.lastFailureReason'));
  assert.ok(!advanced.includes("this.statusText = '已保存，正在同步'"));
});

test('首轮同步先保留本机内容再拉家庭服务器，绝不清空本机', () => {
  const connect = sync.slice(sync.indexOf('private async connectAndSync'), sync.indexOf('// MARK: - 推'));
  assert.ok(connect.indexOf('await this.pushLocal()') < connect.indexOf('await this.pullRemote()'));
  assert.ok(!connect.includes('clearServerBackedData'));
});
