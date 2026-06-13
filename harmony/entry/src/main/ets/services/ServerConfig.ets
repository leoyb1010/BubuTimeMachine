import { preferences } from '@kit.ArkData';
import type { common } from '@kit.AbilityKit';
import { FamilyRole } from '../models/Enums';

// MARK: - 服务器配置（对照 iOS ServerConfig）
// 存 Preferences：Base URL、当前身份、布布名字、账号。决定连真实 PocketBase 还是离线。
export class ServerConfig {
  static readonly shared = new ServerConfig();
  private store: preferences.Preferences | null = null;

  // 默认值（与 iOS 对齐，用户在设置页改）
  baseURLString: string = '';
  accountEmail: string = '';
  accountPassword: string = '';
  currentRoleRaw: string = FamilyRole.mama;
  childName: string = '布布';

  private constructor() {}

  async load(context: common.UIAbilityContext): Promise<void> {
    this.store = await preferences.getPreferences(context, 'bubu_server_config');
    this.baseURLString = await this.getStr('baseURL', '');
    this.accountEmail = await this.getStr('email', '');
    this.currentRoleRaw = await this.getStr('role', FamilyRole.mama);
    this.childName = await this.getStr('childName', '布布');
  }

  get currentRole(): FamilyRole {
    return (this.currentRoleRaw as FamilyRole) ?? FamilyRole.mama;
  }

  get isConfigured(): boolean {
    return this.baseURLString.length > 0 && this.accountEmail.length > 0;
  }

  async setRole(role: FamilyRole): Promise<void> {
    this.currentRoleRaw = role;
    await this.put('role', role);
  }

  async setChildName(name: string): Promise<void> {
    this.childName = name;
    await this.put('childName', name);
  }

  private async getStr(key: string, def: string): Promise<string> {
    if (!this.store) return def;
    return (await this.store.get(key, def)) as string;
  }

  private async put(key: string, value: string): Promise<void> {
    if (!this.store) return;
    await this.store.put(key, value);
    await this.store.flush();
  }
}
