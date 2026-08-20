import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const api = await readFile(new URL('../entry/src/main/ets/services/APIClient.ets', import.meta.url), 'utf8');
const sync = await readFile(new URL('../entry/src/main/ets/sync/SyncEngine.ets', import.meta.url), 'utf8');

test('前台建立 PocketBase SSE、解析 PB_CONNECT 并提交全集合订阅', () => {
  assert.ok(api.includes("requestInStream(`${this.baseURL}/api/realtime`"));
  assert.ok(api.includes("header: { 'Accept': 'text/event-stream' }"));
  assert.ok(api.includes("eventName === 'PB_CONNECT'"));
  assert.ok(api.includes("this.request('POST', '/api/realtime'"));
  assert.ok(api.includes("'growthmeasurements', 'timecapsules'"));
});

test('任一实时事件只触发现有幂等 syncNow，断线 2s 到 60s 退避且后台关闭', () => {
  assert.ok(sync.includes('APIClient.shared.startRealtime'));
  assert.ok(sync.includes('this.syncNow(false)'));
  assert.ok(sync.includes('APIClient.shared.stopRealtime()'));
  assert.ok(api.includes('Math.min(backoffMs * 2, 60000)'));
});
