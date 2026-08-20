import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const view = await readFile(new URL('../entry/src/main/ets/view/AccountView.ets', import.meta.url), 'utf8');
const service = await readFile(new URL('../entry/src/main/ets/services/AccountService.ets', import.meta.url), 'utf8');
const config = await readFile(new URL('../entry/src/main/ets/services/ServerConfig.ets', import.meta.url), 'utf8');

test('已登录显示账号状态和安全操作，不把安全存储密码回填输入框', () => {
  assert.ok(view.includes('ServerConfig.shared.isConfigured ?'));
  assert.ok(view.includes("this.password = ''"));
  assert.ok(!view.includes('this.password = cfg.accountPassword'));
  assert.ok(view.includes("Button('家庭恢复码')"));
  assert.ok(view.includes("Button('修改密码')"));
});

test('退出登录必须确认且明确本机数据保留', () => {
  assert.ok(view.includes("title: '要退出这个账号吗？'"));
  assert.ok(view.includes('本机已有的照片和记录都会保留'));
});

test('修改密码先验证旧密码、授权 PATCH 自己记录并安全持久化新密码', () => {
  assert.ok(config.includes('accountRecordId'));
  assert.ok(service.includes('await this.authWithPassword(cfg.accountEmail, oldPassword)'));
  assert.ok(service.includes("await this.authorizedRequest('PATCH'"));
  assert.ok(service.includes('cfg.accountPassword = newPassword'));
  assert.ok(service.includes('await cfg.persistServer()'));
});
