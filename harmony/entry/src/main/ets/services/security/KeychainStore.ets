import { preferences } from '@kit.ArkData';
import type { common } from '@kit.AbilityKit';

// MARK: - KeychainStore（对照 iOS Services/Security/KeychainStore.swift）
// iOS 用 Security/Keychain 保存家庭服务器密码、时间胶囊 v3 恢复码等敏感配置。
// HarmonyOS 无逐字对应的 iCloud Keychain；这里用 @ohos.data.preferences 持久化做等价实现：
//   - string/set/delete            ←→ 本机 Keychain（device-only）
//   - icloudString/setICloud       ←→ iOS 的 kSecAttrSynchronizable（iCloud 同步钥匙串）
// HarmonyOS 侧无跨设备自动同步语义，icloud* 仅做命名空间隔离（account 加 ".icloud" 后缀），
// 行为上等价于「本机持久」。失败时静默降级为空，避免影响离线使用——与 iOS 一致。
// NOTE: 如需真正的硬件级安全存储，可替换为 @ohos.security.asset assetStore；
//       preferences 在 API 可用性上更稳，作为忠实端口的可编译落点。
export class KeychainStore {
  private static readonly storeName: string = 'com.bubu.timemachine.keychain';
  private static prefs: preferences.Preferences | null = null;

  // 在 Ability 启动时调用一次，注入 context 完成初始化。
  static initialize(context: common.UIAbilityContext): void {
    if (KeychainStore.prefs) return;
    try {
      KeychainStore.prefs = preferences.getPreferencesSync(context, { name: KeychainStore.storeName });
    } catch (e) {
      KeychainStore.prefs = null;
    }
  }

  // MARK: 本机条目（对照 device-only Keychain）
  static string(key: string): string | null {
    const p = KeychainStore.prefs;
    if (!p) return null;
    try {
      const v = p.getSync(key, '') as string;
      return v.length === 0 ? null : v;
    } catch (e) {
      return null;
    }
  }

  static set(value: string, key: string): void {
    const p = KeychainStore.prefs;
    if (!p) return;
    try {
      p.putSync(key, value);
      p.flush();
    } catch (e) {
      // 静默降级
    }
  }

  static delete(key: string): void {
    const p = KeychainStore.prefs;
    if (!p) return;
    try {
      p.deleteSync(key);
      p.flush();
    } catch (e) {
      // 静默降级
    }
  }

  // MARK: iCloud 同步钥匙串（对照 kSecAttrSynchronizable）
  // 与本机条目命名空间隔离（key 加 ".icloud" 后缀），避免冲突——与 iOS 一致。
  static icloudString(key: string): string | null {
    return KeychainStore.string(key + '.icloud');
  }

  static setICloud(value: string, key: string): void {
    KeychainStore.set(value, key + '.icloud');
  }
}
