import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const root = new URL('../entry/src/main/ets/', import.meta.url);
const permission = await readFile(new URL('services/PermissionService.ets', root), 'utf8');
const recorder = await readFile(new URL('services/AudioRecorder.ets', root), 'utf8');
const location = await readFile(new URL('services/LocationService.ets', root), 'utf8');
const intake = await readFile(new URL('services/PhotoIntakeService.ets', root), 'utf8');
const capture = await readFile(new URL('view/QuickCaptureSheet.ets', root), 'utf8');

test('API 26 手机权限请求后用 accessToken 权威复查，不读取不可用的 authResults', () => {
  assert.ok(permission.includes('GET_BUNDLE_INFO_WITH_APPLICATION'));
  assert.ok(permission.includes('checkAccessToken(tokenId, permission)'));
  assert.ok(!permission.includes('.authResults'));
  for (const source of [recorder, location, intake, capture]) {
    assert.ok(source.includes('PermissionService.request'));
    assert.ok(!source.includes('.authResults'));
  }
});
