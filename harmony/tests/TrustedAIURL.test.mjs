import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const config = await readFile(new URL('../entry/src/main/ets/services/ServerConfig.ets', import.meta.url), 'utf8');
const ai = await readFile(new URL('../entry/src/main/ets/services/AIService.ets', import.meta.url), 'utf8');

test('携带家庭登录态的 AI 请求只允许同源 HTTPS 且拒绝 URL 凭据', () => {
  assert.ok(config.includes("candidate.protocol.toLowerCase() !== 'https:'"));
  assert.ok(config.includes('candidate.username.length > 0'));
  assert.ok(config.includes('candidate.password.length > 0'));
  assert.ok(config.includes('origins.includes(candidate.origin.toLowerCase())'));
  assert.ok(config.includes('this.isConfigured && this.trustedAIBaseURL.length > 0'));
});

test('AIService 每次请求只使用经过校验的 trustedAIBaseURL', () => {
  assert.ok(ai.includes('ServerConfig.shared.trustedAIBaseURL'));
  assert.ok(!ai.includes("ServerConfig.shared.aiBaseURLString.replace"));
});
