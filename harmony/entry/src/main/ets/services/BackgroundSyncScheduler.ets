import { workScheduler } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ServerConfig } from './ServerConfig';

const DOMAIN = 0x0000;

export class BackgroundSyncScheduler {
  static readonly workId: number = 61201;
  static readonly photoWorkId: number = 61202;

  static ensureScheduled(): void {
    try {
      if (ServerConfig.shared.isConfigured) {
        workScheduler.startWork({
          workId: BackgroundSyncScheduler.workId,
          bundleName: 'com.bubu.timemachine', abilityName: 'BackgroundSyncAbility',
          isPersisted: true, networkType: workScheduler.NetworkType.NETWORK_TYPE_ANY,
          isRepeat: true, repeatCycleTime: 20 * 60 * 1000
        });
      }
      if (ServerConfig.shared.photoInboxBackgroundEnabled) {
        workScheduler.startWork({
          workId: BackgroundSyncScheduler.photoWorkId,
          bundleName: 'com.bubu.timemachine', abilityName: 'BackgroundSyncAbility',
          isPersisted: true, isRepeat: true, repeatCycleTime: 20 * 60 * 1000
        });
      }
    } catch (e) {
      hilog.warn(DOMAIN, 'Bubu', `后台同步任务注册失败: ${e instanceof Error ? e.message : JSON.stringify(e)}`);
    }
  }
}
