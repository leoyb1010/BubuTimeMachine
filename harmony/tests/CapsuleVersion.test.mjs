import assert from 'node:assert/strict';
import test from 'node:test';
import { capsuleVersion, requireCapsuleVersion, rememberCapsuleVersion } from '../entry/src/main/ets/services/security/CapsuleVersion.ts';

test('已知 v3 的胶囊拒绝 v2/v1 载荷和元数据降级', () => {
  const v3 = new Uint8Array(Buffer.from('BTC3payload'));
  const v2 = new Uint8Array(Buffer.from('BTC2payload'));
  assert.equal(capsuleVersion(v3), 3);
  assert.doesNotThrow(() => requireCapsuleVersion(v3, 3));
  assert.throws(() => requireCapsuleVersion(v2, 3), /加密版本不一致/);
  assert.throws(() => requireCapsuleVersion(new Uint8Array([1, 2]), 3));
  assert.equal(rememberCapsuleVersion(3, 0), 3);
  assert.equal(rememberCapsuleVersion(3, 2), 3);
  assert.equal(rememberCapsuleVersion(undefined, 3), 3);
});

test('未知版本仍兼容历史胶囊，但不会降低已记录版本', () => {
  const legacy = new Uint8Array([1, 2, 3, 4]);
  assert.doesNotThrow(() => requireCapsuleVersion(legacy, 0));
  assert.equal(rememberCapsuleVersion(3, NaN), 3);
});
