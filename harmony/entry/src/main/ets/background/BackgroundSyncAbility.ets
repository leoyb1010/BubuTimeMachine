import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppDatabase } from '../data/AppDatabase';
import { APIClient } from '../services/APIClient';
import { MediaStore } from '../services/MediaStore';
import { ServerConfig } from '../services/ServerConfig';
import { SyncEngine } from '../sync/SyncEngine';
import { PhotoIntakeService } from '../services/PhotoIntakeService';
import { WeeklyReportNotifier } from '../services/WeeklyReportNotifier';
import { AIService } from '../services/AIService';
import { MediaDerivationService } from '../services/MediaDerivationService';
import { VoiceTranscriptionService } from '../services/VoiceTranscriptionService';

const DOMAIN = 0x0000;

export default class BackgroundSyncAbility extends WorkSchedulerExtensionAbility {
  async onWorkStart(work: workScheduler.WorkInfo): Promise<void> {
    try {
      await AppDatabase.shared.initialize(this.context);
      MediaStore.shared.initialize(this.context);
      MediaDerivationService.initialize();
      await MediaDerivationService.backfillPending(12);
      PhotoIntakeService.shared.initialize(this.context);
      APIClient.shared.initialize(this.context);
      AIService.shared.initialize(this.context);
      await ServerConfig.shared.load(this.context);
      VoiceTranscriptionService.initialize(this.context);
      await SyncEngine.shared.initialize(this.context);
      if (ServerConfig.shared.isConfigured) await SyncEngine.shared.syncNow(false);
      await VoiceTranscriptionService.backfillPending(4);
      if (ServerConfig.shared.photoInboxBackgroundEnabled) {
        await PhotoIntakeService.shared.scanRecent(14, false);
      }
      await WeeklyReportNotifier.checkLatest(this.context);
      hilog.info(DOMAIN, 'Bubu', `后台同步完成 workId=${work.workId}`);
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `后台同步失败: ${e instanceof Error ? e.message : JSON.stringify(e)}`);
    }
  }

  onWorkStop(work: workScheduler.WorkInfo): void {
    hilog.info(DOMAIN, 'Bubu', `后台同步被系统停止 workId=${work.workId}`);
  }
}
