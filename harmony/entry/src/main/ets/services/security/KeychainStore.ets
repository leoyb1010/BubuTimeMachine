import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import type { BusinessError } from '@kit.BasicServicesKit';
import { preferences } from '@kit.ArkData';
import type { common } from '@kit.AbilityKit';

// MARK: - KeychainStore（对照 iOS Services/Security/KeychainStore.swift）
// 使用 HarmonyOS Asset Store 保存密码、令牌和胶囊恢复码。Asset Store 由系统加密保护，
// 不再把敏感值明文落到 Preferences。普通条目仅限本机；icloud* 条目使用鸿蒙可信设备同步语义。
export class KeychainStore {
  private static readonly namespace: string = 'com.bubu.timemachine.';
  private static readonly legacyStoreName: string = 'com.bubu.timemachine.keychain';
  private static readonly recoveryKey: string = 'bubu.capsule.recoveryCode.v3';

  // 从旧版 Preferences 伪钥匙串迁移胶囊恢复码。仅在安全写入成功后擦除旧明文。
  static async migrateLegacyPreferences(context: common.Context): Promise<void> {
    const legacy = await preferences.getPreferences(context, KeychainStore.legacyStoreName);
    const legacyKey = KeychainStore.recoveryKey + '.icloud';
    const value = await legacy.get(legacyKey, '');
    const recoveryCode = typeof value === 'string' ? value.trim() : '';
    if (recoveryCode.length > 0 && KeychainStore.icloudString(KeychainStore.recoveryKey) === null) {
      KeychainStore.setICloud(recoveryCode, KeychainStore.recoveryKey);
    }
    await legacy.delete(legacyKey);
    await legacy.flush();
  }

  static string(key: string): string | null {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, KeychainStore.bytes(KeychainStore.alias(key)));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const results = asset.querySync(query);
      if (results.length === 0) return null;
      const secret = results[0].get(asset.Tag.SECRET);
      if (!(secret instanceof Uint8Array) || secret.length === 0) return null;
      return util.TextDecoder.create('utf-8').decodeToString(secret);
    } catch (error) {
      const businessError = error as BusinessError;
      if (businessError.code === asset.ErrorCode.NOT_FOUND) return null;
      throw new Error(`Asset Store query failed (${businessError.code}): ${businessError.message}`);
    }
  }

  static set(value: string, key: string): void {
    KeychainStore.store(value, key, asset.SyncType.NEVER);
  }

  static delete(key: string): void {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, KeychainStore.bytes(KeychainStore.alias(key)));
    try {
      asset.removeSync(query);
    } catch (error) {
      const businessError = error as BusinessError;
      if (businessError.code !== asset.ErrorCode.NOT_FOUND) {
        throw new Error(`Asset Store remove failed (${businessError.code}): ${businessError.message}`);
      }
    }
  }

  static icloudString(key: string): string | null {
    return KeychainStore.string(key + '.trusted');
  }

  static setICloud(value: string, key: string): void {
    KeychainStore.store(value, key + '.trusted', asset.SyncType.TRUSTED_DEVICE);
  }

  private static store(value: string, key: string, syncType: asset.SyncType): void {
    const attributes: asset.AssetMap = new Map();
    attributes.set(asset.Tag.SECRET, KeychainStore.bytes(value));
    attributes.set(asset.Tag.ALIAS, KeychainStore.bytes(KeychainStore.alias(key)));
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    attributes.set(asset.Tag.AUTH_TYPE, asset.AuthType.NONE);
    attributes.set(asset.Tag.SYNC_TYPE, syncType);
    attributes.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    asset.addSync(attributes);
  }

  private static alias(key: string): string {
    return KeychainStore.namespace + key;
  }

  private static bytes(value: string): Uint8Array {
    return util.TextEncoder.create('utf-8').encodeInto(value);
  }
}
