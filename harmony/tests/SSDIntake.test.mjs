import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const ai = await readFile(new URL('../entry/src/main/ets/services/AIService.ets', import.meta.url), 'utf8');
const api = await readFile(new URL('../entry/src/main/ets/services/APIClient.ets', import.meta.url), 'utf8');
const home = await readFile(new URL('../entry/src/main/ets/view/HomeView.ets', import.meta.url), 'utf8');
const view = await readFile(new URL('../entry/src/main/ets/view/SSDIntakeView.ets', import.meta.url), 'utf8');

test('移动硬盘候选复用家庭登录态，并保留核对时间、确认和忽略闭环', () => {
  assert.ok(api.includes('async accessToken(): Promise<string>'));
  assert.ok(ai.includes("'Authorization': `Bearer ${token}`"));
  assert.ok(ai.includes("'intake/candidates'"));
  assert.ok(ai.includes("'intake/candidates/update'"));
  assert.ok(ai.includes("'intake/confirm'"));
  assert.ok(ai.includes("'intake/cancel'"));
  assert.ok(home.includes('this.ssdCandidateCard()'));
  assert.ok(home.includes('SSDIntakeView'));
  assert.ok(view.includes('showDatePickerDialog'));
  assert.ok(view.includes('updateIntakeCandidate'));
  assert.ok(view.includes('confirmIntakeCandidate'));
  assert.ok(view.includes('cancelIntakeCandidate'));
  assert.ok(view.includes('不会删除原文件'));
});
