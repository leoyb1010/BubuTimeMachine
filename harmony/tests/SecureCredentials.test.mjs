import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const keychain = await readFile(new URL('../entry/src/main/ets/services/security/KeychainStore.ets', import.meta.url), 'utf8');
const config = await readFile(new URL('../entry/src/main/ets/services/ServerConfig.ets', import.meta.url), 'utf8');

test('密码、令牌和胶囊恢复码使用系统 Asset Store，不再使用 Preferences 伪装钥匙串', () => {
  assert.ok(keychain.includes("import { asset } from '@kit.AssetStoreKit'"));
  assert.ok(keychain.includes('asset.querySync'));
  assert.ok(keychain.includes('asset.addSync'));
  assert.ok(keychain.includes('asset.removeSync'));
  assert.ok(keychain.includes('asset.Accessibility.DEVICE_FIRST_UNLOCKED'));
  assert.ok(keychain.includes('asset.SyncType.TRUSTED_DEVICE'));
  assert.ok(!keychain.includes('.put('));
  assert.ok(!keychain.includes('.putSync('));
});

test('服务器配置迁移旧明文凭据，成功写入安全存储后删除旧字段', () => {
  assert.ok(config.includes('await KeychainStore.migrateLegacyPreferences(context)'));
  assert.ok(config.includes("this.getStr('password', '')"));
  assert.ok(config.includes("this.getStr('aiAPIKey', '')"));
  assert.ok(config.includes('this.secureValue(ServerConfig.passwordAssetKey, legacyPassword)'));
  assert.ok(config.includes('this.secureValue(ServerConfig.aiKeyAssetKey, legacyAIKey)'));
  assert.ok(config.includes("await this.store.delete('password')"));
  assert.ok(config.includes("await this.store.delete('aiAPIKey')"));
  assert.ok(!config.includes("await this.put('password'"));
  assert.ok(!config.includes("await this.put('aiAPIKey'"));
});

test('历史胶囊恢复码先写入 Asset Store 再擦除旧明文', () => {
  const secureWrite = keychain.indexOf('KeychainStore.setICloud(recoveryCode, KeychainStore.recoveryKey)');
  const legacyDelete = keychain.indexOf('await legacy.delete(legacyKey)');
  assert.ok(secureWrite >= 0 && legacyDelete > secureWrite);
  assert.ok(keychain.includes("const legacyKey = KeychainStore.recoveryKey + '.icloud'"));
});

test('新保存与退出登录只写入或删除安全凭据', () => {
  assert.ok(config.includes('this.persistSecret(ServerConfig.passwordAssetKey, this.accountPassword)'));
  assert.ok(config.includes('this.persistSecret(ServerConfig.aiKeyAssetKey, this.aiAPIKey)'));
  assert.ok(config.includes('KeychainStore.set(cleaned, assetKey)'));
  assert.ok(config.includes('KeychainStore.delete(assetKey)'));
});
