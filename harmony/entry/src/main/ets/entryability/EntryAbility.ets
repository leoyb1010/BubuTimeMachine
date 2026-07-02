import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppDatabase } from '../data/AppDatabase';
import { SyncEngine } from '../sync/SyncEngine';
import { VaccineLegacyMigrator } from '../sync/VaccineLegacyMigrator';
import { MediaStore } from '../services/MediaStore';
import { ServerConfig } from '../services/ServerConfig';
import { APIClient } from '../services/APIClient';
import { IosBaselineImporter } from '../bootstrap/IosBaselineImporter';

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

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    // 初始化本地数据库（RelationalStore 建表），相当于 iOS 装配 ModelContainer。
    try {
      await AppDatabase.shared.initialize(this.context);
      MediaStore.shared.initialize(this.context);
      APIClient.shared.initialize(this.context);
      await ServerConfig.shared.load(this.context);
      await IosBaselineImporter.runIfNeeded(this.context);
      await SyncEngine.shared.initialize(this.context); // 打开游标用 Preferences
      await VaccineLegacyMigrator.migrateIfNeeded(this.context); // 旧版疫苗打卡一次性迁移
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `初始化失败: ${JSON.stringify(e)}`);
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
  }

  onBackground(): void {
    // 进后台停轮询省电（对应 iOS .background → stopPolling）。
    SyncEngine.shared.stopPolling();
  }
}
