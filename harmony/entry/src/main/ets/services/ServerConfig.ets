import { preferences } from '@kit.ArkData';
import type { common } from '@kit.AbilityKit';
import { ALL_FAMILY_ROLES, FamilyRole, isElderRole } from '../models/Enums';
import { KeychainStore } from './security/KeychainStore';
import { url } from '@kit.ArkTS';

// MARK: - 服务器配置（对照 iOS ServerConfig）
// 存 Preferences：Base URL、当前身份、布布名字、账号。决定连真实 PocketBase 还是离线。
export class ServerConfig {
  static readonly shared = new ServerConfig();
  static readonly versionName: string = '2.11.0';
  static readonly versionCode: string = '2026081901';
  static readonly defaultBaseURL: string = '';
  static readonly defaultAIBaseURL: string = '';
  static readonly baseURLPlaceholder: string = 'https://你的服务器地址:8090';
  static readonly aiBaseURLPlaceholder: string = 'https://你的AI服务地址:8000';
  private store: preferences.Preferences | null = null;
  private static readonly passwordAssetKey: string = 'server.accountPassword';
  private static readonly aiKeyAssetKey: string = 'server.aiAPIKey';

  baseURLString: string = ServerConfig.defaultBaseURL;
  accountEmail: string = '';
  accountPassword: string = '';
  accountRecordId: string = '';
  dataOwnerIdentity: string = '';
  currentRoleRaw: string = FamilyRole.mama;
  childName: string = '布布';
  aiBaseURLString: string = ServerConfig.defaultAIBaseURL;
  aiAPIKey: string = '';
  aiEnabled: boolean = false;
  semanticSearchEnabled: boolean = false;
  dailyReminderEnabled: boolean = false;
  photoInboxBackgroundEnabled: boolean = false;
  simpleModeEnabled: boolean = false;
  roleBeforeElderRaw: string = '';
  sleepStartedAt: number = 0;
  timelineSortModeRaw: string = 'capture';
  photoFrameDwellSeconds: number = 8;

  private constructor() {}

  async load(context: common.Context): Promise<void> {
    await KeychainStore.migrateLegacyPreferences(context);
    this.store = await preferences.getPreferences(context, 'bubu_server_config');
    this.baseURLString = await this.getStr('baseURL', ServerConfig.defaultBaseURL);
    this.accountEmail = await this.getStr('email', '');
    const legacyPassword = await this.getStr('password', '');
    this.accountRecordId = await this.getStr('accountRecordId', '');
    this.dataOwnerIdentity = await this.getStr('dataOwnerIdentity', '');
    this.currentRoleRaw = await this.getStr('role', FamilyRole.mama);
    this.childName = await this.getStr('childName', '布布');
    this.aiBaseURLString = await this.getStr('aiBaseURL', ServerConfig.defaultAIBaseURL);
    const legacyAIKey = await this.getStr('aiAPIKey', '');
    this.aiEnabled = await this.getBool('aiEnabled', false);
    this.semanticSearchEnabled = await this.getBool('semanticSearchEnabled', false);
    this.dailyReminderEnabled = await this.getBool('dailyReminderEnabled', false);
    this.photoInboxBackgroundEnabled = await this.getBool('photoInboxBackgroundEnabled', false);
    this.simpleModeEnabled = await this.getBool('simpleModeEnabled', isElderRole(this.currentRole));
    this.roleBeforeElderRaw = await this.getStr('roleBeforeElder', '');
    this.sleepStartedAt = await this.getNum('sleepStartedAt', 0);
    this.timelineSortModeRaw = await this.getStr('timelineSortMode', 'capture');
    this.photoFrameDwellSeconds = await this.getNum('photoFrameDwellSeconds', 8);
    this.accountPassword = this.secureValue(ServerConfig.passwordAssetKey, legacyPassword);
    this.aiAPIKey = this.secureValue(ServerConfig.aiKeyAssetKey, legacyAIKey);
    await this.clearLegacySecrets();
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
    return this.aiEnabled && this.isConfigured && this.trustedAIBaseURL.length > 0;
  }

  get trustedAIBaseURL(): string {
    const candidate = this.cleanString(this.aiBaseURLString).replace(/\/+$/, '');
    if (candidate.length === 0) return '';
    return ServerConfig.isTrustedAIURL(candidate, this.cleanString(this.baseURLString), ServerConfig.defaultAIBaseURL)
      ? candidate : '';
  }

  // AI 请求可能携带家庭服务器 Bearer，只允许 HTTPS 且与家庭服务器或构建内置 AI 同源。
  static isTrustedAIURL(candidateRaw: string, serverRaw: string, packagedRaw: string): boolean {
    try {
      const candidate = new url.URL(candidateRaw);
      if (candidate.protocol.toLowerCase() !== 'https:' || candidate.username.length > 0 || candidate.password.length > 0) {
        return false;
      }
      const origins: string[] = [];
      if (serverRaw.trim().length > 0) origins.push(new url.URL(serverRaw).origin.toLowerCase());
      if (packagedRaw.trim().length > 0) origins.push(new url.URL(packagedRaw).origin.toLowerCase());
      return origins.includes(candidate.origin.toLowerCase());
    } catch (e) {
      return false;
    }
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

  async setSimpleModeEnabled(value: boolean): Promise<void> {
    this.simpleModeEnabled = value;
    await this.putBool('simpleModeEnabled', value);
    AppStorage.setOrCreate('bubuSimpleMode', value);
  }

  async setChildName(name: string): Promise<void> {
    this.childName = name;
    await this.put('childName', name);
  }

  async setSleepStartedAt(value: number): Promise<void> {
    this.sleepStartedAt = value;
    if (!this.store) return;
    await this.store.put('sleepStartedAt', value);
    await this.store.flush();
  }

  async setTimelineSortMode(value: string): Promise<void> {
    this.timelineSortModeRaw = value === 'recorded' ? 'recorded' : 'capture';
    await this.put('timelineSortMode', this.timelineSortModeRaw);
  }

  async setPhotoFrameDwellSeconds(value: number): Promise<void> {
    const allowed = [5, 8, 15, 30];
    this.photoFrameDwellSeconds = allowed.includes(value) ? value : 8;
    if (!this.store) return;
    await this.store.put('photoFrameDwellSeconds', this.photoFrameDwellSeconds);
    await this.store.flush();
  }

  // 持久化服务器配置（地址/账号/密码）。
  async persistServer(): Promise<void> {
    this.persistSecret(ServerConfig.passwordAssetKey, this.accountPassword);
    this.persistSecret(ServerConfig.aiKeyAssetKey, this.aiAPIKey);
    await this.clearLegacySecrets();
    await this.put('baseURL', this.baseURLString);
    await this.put('email', this.accountEmail);
    await this.put('accountRecordId', this.accountRecordId);
    await this.put('dataOwnerIdentity', this.dataOwnerIdentity);
    await this.put('aiBaseURL', this.aiBaseURLString);
    await this.putBool('aiEnabled', this.aiEnabled);
    await this.putBool('semanticSearchEnabled', this.semanticSearchEnabled);
  }

  async setDailyReminderEnabled(value: boolean): Promise<void> {
    this.dailyReminderEnabled = value;
    await this.putBool('dailyReminderEnabled', value);
  }

  async setPhotoInboxBackgroundEnabled(value: boolean): Promise<void> {
    this.photoInboxBackgroundEnabled = value;
    await this.putBool('photoInboxBackgroundEnabled', value);
  }

  async logout(): Promise<void> {
    this.accountEmail = '';
    this.accountPassword = '';
    this.accountRecordId = '';
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

  private async getNum(key: string, def: number): Promise<number> {
    if (!this.store) return def;
    const value = await this.store.get(key, def);
    return typeof value === 'number' && Number.isFinite(value) ? value : def;
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

  private secureValue(assetKey: string, legacyValue: string): string {
    const current = KeychainStore.string(assetKey);
    if (current !== null) return current;
    const migrated = this.cleanString(legacyValue);
    if (migrated.length > 0) KeychainStore.set(migrated, assetKey);
    return migrated;
  }

  private persistSecret(assetKey: string, value: string): void {
    const cleaned = this.cleanString(value);
    if (cleaned.length > 0) {
      KeychainStore.set(cleaned, assetKey);
    } else {
      KeychainStore.delete(assetKey);
    }
  }

  private async clearLegacySecrets(): Promise<void> {
    if (!this.store) return;
    await this.store.delete('password');
    await this.store.delete('aiAPIKey');
    await this.store.flush();
  }

  private cleanString(value: Object | string | null | undefined, def: string = ''): string {
    return typeof value === 'string' ? value.trim() : def;
  }
}
