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

// MARK: - 应用入口 Ability
// 对应 iOS BubuTimeMachineApp：启动时初始化数据库（建表/迁移）并拉起首页。
const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'Bubu', 'EntryAbility onCreate');
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

    // 其余服务失败可降级，不影响已安全打开的本地数据库。
    try {
      WidgetRefresher.initialize(this.context);
      AppDatabase.shared.setDataChangeListener((): void => { WidgetRefresher.requestRefresh(); });
      WidgetRefresher.requestRefresh();
      MediaStore.shared.initialize(this.context);
      PhotoIntakeService.shared.initialize(this.context);
      APIClient.shared.initialize(this.context);
      AIService.shared.initialize(this.context);
      await ServerConfig.shared.load(this.context);
      await AppDatabase.shared.normalizeChildBirthday();
      await SyncEngine.shared.initialize(this.context); // 打开游标用 Preferences
      await ReminderScheduler.shared.refreshIfEnabled(ServerConfig.shared.dailyReminderEnabled);
      BackgroundSyncScheduler.ensureScheduled();
      await VaccineLegacyMigrator.migrateIfNeeded(this.context); // 旧版疫苗打卡一次性迁移
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `可选服务初始化失败，保持离线可用: ${JSON.stringify(e)}`);
    }

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
  }

  onBackground(): void {
    // 进后台停轮询省电（对应 iOS .background → stopPolling）。
    SyncEngine.shared.stopPolling();
    BackgroundSyncScheduler.ensureScheduled();
  }
}
