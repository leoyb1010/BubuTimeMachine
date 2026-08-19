import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppDatabase } from '../data/AppDatabase';
import { APIClient } from '../services/APIClient';
import { MediaStore } from '../services/MediaStore';
import { ServerConfig } from '../services/ServerConfig';
import { SyncEngine } from '../sync/SyncEngine';

const DOMAIN = 0x0000;

export default class BackgroundSyncAbility extends WorkSchedulerExtensionAbility {
  async onWorkStart(work: workScheduler.WorkInfo): Promise<void> {
    try {
      await AppDatabase.shared.initialize(this.context);
      MediaStore.shared.initialize(this.context);
      APIClient.shared.initialize(this.context);
      await ServerConfig.shared.load(this.context);
      await SyncEngine.shared.initialize(this.context);
      await SyncEngine.shared.syncNow(false);
      hilog.info(DOMAIN, 'Bubu', `后台同步完成 workId=${work.workId}`);
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `后台同步失败: ${e instanceof Error ? e.message : JSON.stringify(e)}`);
    }
  }

  onWorkStop(work: workScheduler.WorkInfo): void {
    hilog.info(DOMAIN, 'Bubu', `后台同步被系统停止 workId=${work.workId}`);
  }
}
