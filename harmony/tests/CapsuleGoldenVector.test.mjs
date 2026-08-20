import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import test from 'node:test';
import {
  CAPSULE_GOLDEN_PLAIN, CAPSULE_GOLDEN_RECOVERY, CAPSULE_GOLDEN_SALT,
  CAPSULE_GOLDEN_UNLOCK_MS, CAPSULE_GOLDEN_V2_BASE64, CAPSULE_GOLDEN_V3_BASE64
} from '../entry/src/main/ets/services/CapsuleGoldenVectors.ts';
import { readFile } from 'node:fs/promises';

function decrypt(base64, version, material) {
  const blob = Buffer.from(base64, 'base64');
  assert.equal(blob.subarray(0, 4).toString(), version);
  const nonce = blob.subarray(4, 16);
  const body = blob.subarray(16);
  const key = crypto.createHash('sha256').update(material).digest();
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, nonce);
  decipher.setAuthTag(body.subarray(body.length - 16));
  return Buffer.concat([decipher.update(body.subarray(0, -16)), decipher.final()]).toString();
}

test('独立 Node AES-GCM 可解 iOS/Harmony 共用 BTC3 固定向量', () => {
  const material = `${CAPSULE_GOLDEN_RECOVERY}|${CAPSULE_GOLDEN_SALT}|bubu-time-capsule-v3`;
  assert.equal(decrypt(CAPSULE_GOLDEN_V3_BASE64, 'BTC3', material), CAPSULE_GOLDEN_PLAIN);
});

test('独立 Node AES-GCM 可解 iOS/Harmony 共用 BTC2 固定向量', () => {
  const canonical = new Date(CAPSULE_GOLDEN_UNLOCK_MS).toISOString().replace(/\.000Z$/, 'Z');
  const material = `${canonical}|${CAPSULE_GOLDEN_SALT}|bubu-time-capsule-v2`;
  assert.equal(decrypt(CAPSULE_GOLDEN_V2_BASE64, 'BTC2', material), CAPSULE_GOLDEN_PLAIN);
});

test('Harmony 启动调用真实 CryptoFramework 解密自检', async () => {
  const source = await readFile(new URL('../entry/src/main/ets/services/security/CapsuleCrypto.ets', import.meta.url), 'utf8');
  const ability = await readFile(new URL('../entry/src/main/ets/entryability/EntryAbility.ets', import.meta.url), 'utf8');
  assert.ok(source.includes('static async verifyGoldenVectors'));
  assert.ok(source.includes('CapsuleCrypto.shared.decryptV3'));
  assert.ok(source.includes('CapsuleCrypto.shared.decrypt(v2'));
  assert.ok(ability.includes('await CapsuleCrypto.verifyGoldenVectors()'));
});
