import { AbilityConstant, Configuration, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppDatabase } from '../data/AppDatabase';
import { SyncEngine } from '../sync/SyncEngine';
import { VaccineLegacyMigrator } from '../sync/VaccineLegacyMigrator';
import { MediaStore } from '../services/MediaStore';
import { ServerConfig } from '../services/ServerConfig';
import { APIClient } from '../services/APIClient';
import { PhotoIntakeService } from '../services/PhotoIntakeService';
import { AIService } from '../services/AIService';
import '../intent/OpenBubuIntent';
import '../intent/RecordMomentIntent';
import { BackgroundSyncScheduler } from '../services/BackgroundSyncScheduler';
import { ThemeManager } from '../theme/ThemeManager';
import { ReminderScheduler } from '../services/ReminderScheduler';
import { WidgetRefresher } from '../theme/WidgetRefresher';
import { WeeklyReportNotifier } from '../services/WeeklyReportNotifier';
import { MotionPreference } from '../theme/MotionPreference';
import { BubuSound } from '../theme/BubuSound';
import { CapsuleCrypto } from '../services/security/CapsuleCrypto';
import { MediaDerivationService } from '../services/MediaDerivationService';

// MARK: - 应用入口 Ability
// 对应 iOS BubuTimeMachineApp：启动时初始化数据库（建表/迁移）并拉起首页。
const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'Bubu', 'EntryAbility onCreate');
    this.handleReminderWant(want);
    this.handleEntryLink(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.handleReminderWant(want);
    this.handleEntryLink(want);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'Bubu', 'EntryAbility onDestroy');
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    ThemeManager.shared.updateSystemColorMode(newConfig.colorMode);
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    // 数据库是硬门槛：失败时保留原文件并进入保护页，绝不挂载正常写入/同步/新人引导。
    try {
      await AppDatabase.shared.initialize(this.context);
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `数据库初始化失败，进入数据保护页: ${JSON.stringify(e)}`);
      windowStage.loadContent('pages/DataProtectionPage', (err) => {
        if (err.code) hilog.error(DOMAIN, 'Bubu', `数据保护页加载失败: ${JSON.stringify(err)}`);
      });
      return;
    }

    // 可选能力分别隔离降级：一个失败不得连带跳过后续同步、迁移或后台任务。
    await this.runOptional('界面偏好', async (): Promise<void> => {
      WidgetRefresher.initialize(this.context);
      MotionPreference.initialize(this.context);
      BubuSound.initialize(this.context);
      AppDatabase.shared.setDataChangeListener((): void => { WidgetRefresher.requestRefresh(); });
      WidgetRefresher.requestRefresh();
    });
    await this.runOptional('胶囊密文自检', async (): Promise<void> => {
      await CapsuleCrypto.verifyGoldenVectors();
      AppStorage.setOrCreate('bubuCryptoSelfTest', true);
    });
    await this.runOptional('媒体与照片收件箱', async (): Promise<void> => {
      MediaStore.shared.initialize(this.context);
      MediaDerivationService.initialize();
      await MediaDerivationService.backfillPending();
      PhotoIntakeService.shared.initialize(this.context);
    });
    await this.runOptional('服务器配置', async (): Promise<void> => {
      APIClient.shared.initialize(this.context);
      AIService.shared.initialize(this.context);
      await ServerConfig.shared.load(this.context);
    });
    await this.runOptional('本地数据归一化', async (): Promise<void> => {
      await AppDatabase.shared.normalizeChildBirthday();
      await VaccineLegacyMigrator.migrateIfNeeded(this.context);
    });
    await this.runOptional('同步引擎', async (): Promise<void> => {
      await SyncEngine.shared.initialize(this.context); // 打开游标用 Preferences
    });
    await this.runOptional('系统提醒', async (): Promise<void> => {
      await ReminderScheduler.shared.refreshIfEnabled(ServerConfig.shared.dailyReminderEnabled);
    });
    await this.runOptional('周报通知', async (): Promise<void> => {
      await WeeklyReportNotifier.checkLatest(this.context);
    });
    await this.runOptional('后台任务', async (): Promise<void> => {
      BackgroundSyncScheduler.ensureScheduled();
    });

    windowStage.loadContent('pages/RootPage', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'Bubu', `loadContent 失败: ${JSON.stringify(err)}`);
        return;
      }
      hilog.info(DOMAIN, 'Bubu', '首页加载成功');
    });
  }

  onForeground(): void {
    // 回前台补一轮同步（对应 iOS scenePhase .active → syncEngine.start）。
    SyncEngine.shared.start();
    ReminderScheduler.shared.refreshIfEnabled(ServerConfig.shared.dailyReminderEnabled).catch((error: Error) => {
      hilog.error(DOMAIN, 'Bubu', `刷新提醒失败: ${error.message}`);
    });
    WeeklyReportNotifier.checkLatest(this.context).catch((error: Error) => {
      hilog.warn(DOMAIN, 'Bubu', `检查周报失败: ${error.message}`);
    });
  }

  onBackground(): void {
    // 进后台停轮询省电（对应 iOS .background → stopPolling）。
    SyncEngine.shared.stopPolling();
    BackgroundSyncScheduler.ensureScheduled();
  }

  private handleReminderWant(want: Want): void {
    const value = want.parameters?.['bubuReminderDraft'];
    if (typeof value !== 'string' || value.trim().length === 0) return;
    // 仅预填并打开确认页，绝不从通知点击直接写家庭档案。
    AppStorage.setOrCreate('bubuIntentDraft', value.trim());
  }

  private handleEntryLink(want: Want): void {
    const raw = want.uri ?? '';
    const prefix = 'bubutime://entry/';
    if (!raw.startsWith(prefix)) return;
    const entryId = decodeURIComponent(raw.substring(prefix.length));
    if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/.test(entryId)) return;
    AppStorage.setOrCreate('bubuOpenEntryId', entryId);
  }

  private async runOptional(name: string, task: () => Promise<void>): Promise<void> {
    try {
      await task();
    } catch (error) {
      if (name === '胶囊密文自检') AppStorage.setOrCreate('bubuCryptoSelfTest', false);
      hilog.error(DOMAIN, 'Bubu', `${name}初始化失败，其他能力继续: ${JSON.stringify(error)}`);
    }
  }
}
