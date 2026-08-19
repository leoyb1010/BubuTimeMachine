import { preferences } from '@kit.ArkData';
import type { common } from '@kit.AbilityKit';
import { ALL_FAMILY_ROLES, FamilyRole, isElderRole } from '../models/Enums';

// MARK: - 服务器配置（对照 iOS ServerConfig）
// 存 Preferences：Base URL、当前身份、布布名字、账号。决定连真实 PocketBase 还是离线。
export class ServerConfig {
  static readonly shared = new ServerConfig();
  static readonly versionName: string = '1.2.0';
  static readonly versionCode: string = '2026061312';
  static readonly defaultBaseURL: string = '';
  static readonly defaultAIBaseURL: string = '';
  static readonly baseURLPlaceholder: string = 'https://你的服务器地址:8090';
  static readonly aiBaseURLPlaceholder: string = 'https://你的AI服务地址:8000';
  private store: preferences.Preferences | null = null;

  baseURLString: string = ServerConfig.defaultBaseURL;
  accountEmail: string = '';
  accountPassword: string = '';
  currentRoleRaw: string = FamilyRole.mama;
  childName: string = '布布';
  aiBaseURLString: string = ServerConfig.defaultAIBaseURL;
  aiAPIKey: string = '';
  aiEnabled: boolean = false;
  simpleModeEnabled: boolean = false;
  roleBeforeElderRaw: string = '';

  private constructor() {}

  async load(context: common.Context): Promise<void> {
    this.store = await preferences.getPreferences(context, 'bubu_server_config');
    this.baseURLString = await this.getStr('baseURL', ServerConfig.defaultBaseURL);
    this.accountEmail = await this.getStr('email', '');
    this.accountPassword = await this.getStr('password', '');
    this.currentRoleRaw = await this.getStr('role', FamilyRole.mama);
    this.childName = await this.getStr('childName', '布布');
    this.aiBaseURLString = await this.getStr('aiBaseURL', ServerConfig.defaultAIBaseURL);
    this.aiAPIKey = await this.getStr('aiAPIKey', '');
    this.aiEnabled = await this.getBool('aiEnabled', false);
    this.simpleModeEnabled = await this.getBool('simpleModeEnabled', isElderRole(this.currentRole));
    this.roleBeforeElderRaw = await this.getStr('roleBeforeElder', '');
    AppStorage.setOrCreate('bubuSimpleMode', this.simpleModeEnabled);
  }

  get currentRole(): FamilyRole {
    return (this.currentRoleRaw as FamilyRole) ?? FamilyRole.mama;
  }

  get isConfigured(): boolean {
    return this.cleanString(this.baseURLString).length > 0
      && this.cleanString(this.accountEmail).length > 0
      && this.cleanString(this.accountPassword).length > 0;
  }

  get isAIConfigured(): boolean {
    return this.aiEnabled && this.cleanString(this.aiBaseURLString).length > 0;
  }

  async setRole(role: FamilyRole): Promise<void> {
    if (isElderRole(role)) {
      if (!isElderRole(this.currentRole)) this.roleBeforeElderRaw = this.currentRole;
      this.simpleModeEnabled = true;
    } else {
      this.simpleModeEnabled = false;
    }
    this.currentRoleRaw = role;
    await this.put('role', role);
    await this.put('roleBeforeElder', this.roleBeforeElderRaw);
    await this.putBool('simpleModeEnabled', this.simpleModeEnabled);
    AppStorage.setOrCreate('bubuSimpleMode', this.simpleModeEnabled);
  }

  async exitSimpleMode(): Promise<void> {
    const previous = ALL_FAMILY_ROLES.includes(this.roleBeforeElderRaw as FamilyRole)
      ? this.roleBeforeElderRaw as FamilyRole : FamilyRole.mama;
    this.simpleModeEnabled = false;
    this.currentRoleRaw = previous;
    await this.put('role', previous);
    await this.putBool('simpleModeEnabled', false);
    AppStorage.setOrCreate('bubuSimpleMode', false);
  }

  async setChildName(name: string): Promise<void> {
    this.childName = name;
    await this.put('childName', name);
  }

  // 持久化服务器配置（地址/账号/密码）。
  async persistServer(): Promise<void> {
    await this.put('baseURL', this.baseURLString);
    await this.put('email', this.accountEmail);
    await this.put('password', this.accountPassword);
    await this.put('aiBaseURL', this.aiBaseURLString);
    await this.put('aiAPIKey', this.aiAPIKey);
    await this.putBool('aiEnabled', this.aiEnabled);
  }

  async logout(): Promise<void> {
    this.accountEmail = '';
    this.accountPassword = '';
    await this.persistServer();
  }

  private async getStr(key: string, def: string): Promise<string> {
    if (!this.store) return def;
    const value = await this.store.get(key, def);
    return this.cleanString(value, def);
  }

  private async getBool(key: string, def: boolean): Promise<boolean> {
    if (!this.store) return def;
    const value = await this.store.get(key, def);
    return typeof value === 'boolean' ? value : def;
  }

  private async put(key: string, value: string): Promise<void> {
    if (!this.store) return;
    await this.store.put(key, this.cleanString(value));
    await this.store.flush();
  }

  private async putBool(key: string, value: boolean): Promise<void> {
    if (!this.store) return;
    await this.store.put(key, value);
    await this.store.flush();
  }

  private cleanString(value: Object | string | null | undefined, def: string = ''): string {
    return typeof value === 'string' ? value.trim() : def;
  }
}
