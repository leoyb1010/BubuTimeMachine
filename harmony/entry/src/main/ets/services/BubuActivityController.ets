import { notificationManager } from '@kit.NotificationKit';
import { liveViewManager } from '@kit.LiveViewKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const VOICE_ID = 9201;
const CAPSULE_ID = 9202;
const SLEEP_ID = 9203;
const MAX_ALIVE_SECONDS = 28800;

export class BubuActivityController {
  static readonly shared = new BubuActivityController();
  private activeLiveViews: Set<number> = new Set<number>();
  private constructor() {}

  async startVoiceRecording(childName: string): Promise<void> {
    if (this.activeLiveViews.has(VOICE_ID)) return;
    const title = `正在记录${childName}的声音`;
    if (await this.startTimerLiveView(VOICE_ID, title, '录音中', 0, false, MAX_ALIVE_SECONDS)) return;
    await this.publishFallback(VOICE_ID, title, '0:00', true);
  }

  async endVoiceRecording(elapsedText: string): Promise<void> {
    await this.stop(VOICE_ID, '录音已收好', elapsedText);
  }

  async startSleepTimer(childName: string, startedAt: number): Promise<void> {
    const elapsedMs = Math.max(0, Date.now() - startedAt);
    const title = `${childName}睡着啦`;
    if (await this.startTimerLiveView(SLEEP_ID, title, '哄睡计时', elapsedMs, false, MAX_ALIVE_SECONDS)) return;
    await this.publishFallback(SLEEP_ID, title, '回到布布时光机点“醒啦”即可记好', true);
  }

  async endSleepTimer(elapsedText: string): Promise<void> {
    await this.stop(SLEEP_ID, '睡眠已记下', elapsedText);
  }

  async startCapsuleCountdown(title: string, unlockAt: number, childName: string): Promise<void> {
    const remaining = unlockAt - Date.now();
    if (remaining <= 0 || remaining > MAX_ALIVE_SECONDS * 1000) return;
    const liveTitle = title.trim().length > 0 ? title.trim() : `${childName}的时间胶囊`;
    if (await this.startTimerLiveView(CAPSULE_ID, liveTitle, '即将解锁', remaining, true,
      Math.max(15, Math.ceil(remaining / 1000)))) return;
    await this.publishFallback(CAPSULE_ID, liveTitle, `${childName}的时间胶囊即将解锁`, false);
  }

  async endCapsuleCountdown(): Promise<void> {
    await this.stop(CAPSULE_ID, '时间胶囊可以开启了', '现在就去看看');
  }

  private async startTimerLiveView(id: number, title: string, content: string, time: number,
                                   isCountdown: boolean, aliveTime: number): Promise<boolean> {
    try {
      if (!(await liveViewManager.isLiveViewEnabled())) return false;
      try {
        await liveViewManager.getActiveLiveView(id);
        this.activeLiveViews.add(id);
        return true;
      } catch (e) {}
      const result = await liveViewManager.startLiveView(
        this.timerLiveView(id, title, content, time, isCountdown, 1, 1, aliveTime));
      if (result.resultCode !== 0) return false;
      this.activeLiveViews.add(id);
      return true;
    } catch (e) {
      // 1003500005 表示尚未获 TIMER 场景权益；主流程自动降级到通知。
      hilog.warn(DOMAIN, 'Bubu', `Live View 不可用，降级通知: ${JSON.stringify(e)}`);
      return false;
    }
  }

  private async stop(id: number, title: string, finalText: string): Promise<void> {
    if (!this.activeLiveViews.has(id)) {
      try {
        await liveViewManager.getActiveLiveView(id);
        this.activeLiveViews.add(id);
      } catch (e) {}
    }
    if (this.activeLiveViews.has(id)) {
      try {
        const result = await liveViewManager.stopLiveView(
          this.timerLiveView(id, title, finalText, 0, false, -1, 2, 60));
        if (result.resultCode === 0) this.activeLiveViews.delete(id);
      } catch (e) {
        this.activeLiveViews.delete(id);
      }
    }
    try { await notificationManager.cancel(id); } catch (e) {}
  }

  private timerLiveView(id: number, title: string, content: string, time: number,
                        isCountdown: boolean, status: number, sequence: number,
                        aliveTime: number): liveViewManager.LiveView {
    return {
      id,
      event: 'TIMER',
      sequence,
      isMute: true,
      lifeCycleMode: liveViewManager.LifeCycleMode.STOP_BY_APP,
      timer: { time, isCountdown, isPaused: status < 0 },
      liveViewData: {
        primary: {
          title,
          content: [{ text: status < 0 ? content : '${placeholder.timer}', textColor: '#FF5A3D34' }],
          keepTime: status < 0 ? 60 : 0,
          aliveTime: Math.min(MAX_ALIVE_SECONDS, Math.max(15, aliveTime))
        },
        capsule: {
          type: liveViewManager.CapsuleType.CAPSULE_TYPE_TIMER,
          status,
          content,
          time,
          isCountdown,
          isPaused: status < 0,
          backgroundColor: '#FFF28C9E'
        }
      }
    };
  }

  private async publishFallback(id: number, title: string, text: string, ongoing: boolean): Promise<void> {
    try {
      if (!(await notificationManager.isNotificationEnabled())) return;
      const request: notificationManager.NotificationRequest = {
        id,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: { title, text }
        },
        isOngoing: ongoing,
        isUnremovable: ongoing,
        notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION
      };
      await notificationManager.publish(request);
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `持续状态提示失败: ${JSON.stringify(e)}`);
    }
  }
}
