import { workScheduler } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ServerConfig } from './ServerConfig';

const DOMAIN = 0x0000;

export class BackgroundSyncScheduler {
  static readonly workId: number = 61201;

  static ensureScheduled(): void {
    if (!ServerConfig.shared.isConfigured) return;
    const work: workScheduler.WorkInfo = {
      workId: BackgroundSyncScheduler.workId,
      bundleName: 'com.bubu.timemachine',
      abilityName: 'BackgroundSyncAbility',
      isPersisted: true,
      networkType: workScheduler.NetworkType.NETWORK_TYPE_ANY,
      isRepeat: true,
      repeatCycleTime: 20 * 60 * 1000
    };
    try {
      workScheduler.startWork(work);
    } catch (e) {
      hilog.warn(DOMAIN, 'Bubu', `后台同步任务注册失败: ${e instanceof Error ? e.message : JSON.stringify(e)}`);
    }
  }
}
