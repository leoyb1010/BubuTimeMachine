import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;

// MARK: - Live Activity 启停控制（对照 iOS Services/BubuActivityController.swift）
// iOS 用 ActivityKit 的 request/update/end 起一个灵动岛 / 锁屏实时活动，
// 全部做可用性与授权降级：用户未开启、系统不支持时所有方法安静 no-op，主流程零影响。
//
// NOTE: LiveActivity→实况窗
// HarmonyOS 的「实况窗 (Live View)」API 在当前 SDK 下尚不稳定/不确定，这里实现一个
// 等价的、可编译的控制器：用 @kit.NotificationKit 的「常驻通知 (ongoing notification)」
// 承担「录音中 / 胶囊倒计时」的持续可见提示——语义上等价于 iOS Live Activity 的
// 起(request)/止(end)。所有方法在通知不可用时静默降级，对齐 iOS 的 areActivitiesEnabled 守卫。

// iOS: enum kind { voiceRecording, capsuleCountdown }（来自 BubuActivityAttributes.kind）
enum BubuActivityKind {
  voiceRecording = 'voiceRecording',
  capsuleCountdown = 'capsuleCountdown'
}

// 录音 Live Activity 固定占用一个通知 id（对应 iOS「同一时刻只允许一个」voiceActivity 句柄）。
const VOICE_NOTIFICATION_ID = 9201;
// 胶囊倒计时通知 id。
const CAPSULE_NOTIFICATION_ID = 9202;

export class BubuActivityController {
  static readonly shared = new BubuActivityController();

  // iOS: private static var voiceActivity: Activity? —— 当前录音 Activity 句柄（同一时刻只允许一个）。
  // 这里以「是否有进行中的录音常驻通知」表达。
  private hasVoiceActivity: boolean = false;

  private constructor() {}

  // iOS: private static var isEnabled { ActivityAuthorizationInfo().areActivitiesEnabled }
  private async isEnabled(): Promise<boolean> {
    try {
      return await notificationManager.isNotificationEnabled();
    } catch (e) {
      return false;
    }
  }

  // MARK: 录音中

  // iOS: static func startVoiceRecording(childName:)
  // 开始录音时调用：起一个录音 Live Activity（这里为常驻通知）。
  async startVoiceRecording(childName: string): Promise<void> {
    // iOS: guard isEnabled, voiceActivity == nil else { return }
    if (this.hasVoiceActivity) return;
    if (!(await this.isEnabled())) return;
    try {
      const request: notificationManager.NotificationRequest = {
        id: VOICE_NOTIFICATION_ID,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            // iOS: title = "正在记录\(childName)的声音"
            title: `正在记录${childName}的声音`,
            text: '0:00'
          }
        },
        // 常驻：不可手动划掉，对齐 Live Activity 录音期间持续可见。
        isOngoing: true,
        isUnremovable: true,
        notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION
      };
      await notificationManager.publish(request);
      this.hasVoiceActivity = true;
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `起录音实况窗失败：${JSON.stringify(e)}`);
    }
  }

  // iOS: static func endVoiceRecording(elapsedText:)
  // 停止录音时调用：定格时长并结束 Activity。
  async endVoiceRecording(elapsedText: string): Promise<void> {
    // iOS: guard voiceActivity != nil else { return }
    if (!this.hasVoiceActivity) return;
    this.hasVoiceActivity = false;
    await this.endAll(BubuActivityKind.voiceRecording, elapsedText);
  }

  // iOS: private static func endAll(final:) async —— 结束全部进行中的录音 Activity。
  // 这里撤销对应常驻通知；elapsedText 仅用于对齐 iOS 的「定格时长」语义（通知撤销后不再展示）。
  private async endAll(kind: BubuActivityKind, elapsedText: string): Promise<void> {
    try {
      if (kind === BubuActivityKind.voiceRecording) {
        await notificationManager.cancel(VOICE_NOTIFICATION_ID);
      } else {
        await notificationManager.cancel(CAPSULE_NOTIFICATION_ID);
      }
    } catch (e) {
      // 通知已不存在：忽略。
    }
  }

  // MARK: 时间胶囊倒计时

  // iOS: static func startCapsuleCountdown(title:unlockAt:childName:)
  // 为临近解锁的时间胶囊起一个倒计时 Live Activity（这里为常驻通知）。
  async startCapsuleCountdown(title: string, unlockAt: number, childName: string): Promise<void> {
    // iOS: guard isEnabled, unlockAt > .now else { return }
    if (unlockAt <= Date.now()) return;
    if (!(await this.isEnabled())) return;
    try {
      const request: notificationManager.NotificationRequest = {
        id: CAPSULE_NOTIFICATION_ID,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: title,
            // 倒计时文案：对齐 iOS staleDate = unlockAt 的解锁时间提示。
            text: `${childName}的时间胶囊即将解锁`
          }
        },
        isOngoing: true,
        isUnremovable: false,
        notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION
      };
      await notificationManager.publish(request);
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `起胶囊倒计时实况窗失败：${JSON.stringify(e)}`);
    }
  }
}
