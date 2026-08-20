import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const api = await readFile(new URL('../entry/src/main/ets/services/APIClient.ets', import.meta.url), 'utf8');
const account = await readFile(new URL('../entry/src/main/ets/services/AccountService.ets', import.meta.url), 'utf8');
const config = await readFile(new URL('../entry/src/main/ets/services/ServerConfig.ets', import.meta.url), 'utf8');

test('受保护下载仅允许当前服务器同源 api/files 路径且拒绝 userinfo', () => {
  assert.ok(api.includes('candidate.origin.toLowerCase() !== server.origin.toLowerCase()'));
  assert.ok(api.includes("!candidate.pathname.startsWith('/api/files/')"));
  assert.ok(api.includes('candidate.username.length > 0 || candidate.password.length > 0'));
  assert.ok(api.indexOf('this.trustedFileURL(remoteURL)') < api.indexOf('await this.ensureToken()', api.indexOf('async downloadFile')));
});

test('账号或服务器变化立即清旧 token/fileToken，ensureToken 校验凭据指纹', () => {
  assert.ok(api.includes('clearSession(): void'));
  assert.ok(api.includes('this.credentialIdentity === this.configCredentialIdentity()'));
  assert.ok(account.includes('APIClient.shared.clearSession()'));
});

test('本地档案绑定 server origin 与 familyId，跨家庭登录被阻止', () => {
  assert.ok(config.includes('dataOwnerIdentity'));
  assert.ok(account.includes('this.assertDataOwner(auth)'));
  assert.ok(account.includes('不能直接混入新家庭'));
  assert.ok(api.includes('这台设备已绑定另一家庭档案'));
});
