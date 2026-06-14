// MARK: - 触觉反馈统一封装（对照 iOS DesignSystem/BubuHaptics.swift）
// iOS 用 UINotification/Impact/SelectionFeedbackGenerator；HarmonyOS 用 @kit.SensorServiceKit vibrator。
// 触觉与动效成对出现，语义化调用，方便全局调整强度。
// NOTE: HarmonyOS 无逐一对应的「成功/警告/选择」通知触感，这里用预置 effectId
//       与短/中/长时长振动近似映射。需 ohos.permission.VIBRATE 权限。

import { vibrator } from '@kit.SensorServiceKit';

export class BubuHaptics {
  // 预置振动效果（系统内置 effectId，近似映射 iOS 各反馈风格）。
  private static readonly EFFECT_HARD = 'haptic.clock.timer';   // 较强反馈
  private static readonly EFFECT_SOFT = 'haptic.notice.success'; // 柔和反馈

  /// 保存成功、里程碑点亮、胶囊解密成功。对照 iOS notification(.success)。
  static success(): void {
    BubuHaptics.preset(BubuHaptics.EFFECT_SOFT, () => BubuHaptics.duration(60));
  }

  /// 删除确认、操作有风险。对照 iOS notification(.warning)。
  static warning(): void {
    BubuHaptics.duration(40);
    // 二段轻顿，近似 warning 的双击触感。
    setTimeout(() => BubuHaptics.duration(40), 90);
  }

  /// 心情/表情/选项选中。对照 iOS selectionChanged()。
  static selection(): void {
    BubuHaptics.duration(20);
  }

  /// 轻触：录音开始等。对照 iOS impact(.light)。
  static tapLight(): void {
    BubuHaptics.duration(25);
  }

  /// 中等：胶囊封存「盖章」。对照 iOS impact(.medium)。
  static stamp(): void {
    BubuHaptics.duration(45);
  }

  /// 重击：胶囊开启「破封」。对照 iOS impact(.heavy)。
  static breakSeal(): void {
    BubuHaptics.preset(BubuHaptics.EFFECT_HARD, () => BubuHaptics.duration(80));
  }

  // 优先用预置 effect；不支持则回落到时长振动。失败静默——触感是锦上添花。
  private static preset(effectId: string, fallback: () => void): void {
    try {
      vibrator.startVibration(
        { type: 'preset', effectId: effectId, count: 1 },
        { id: 0, usage: 'notification' }
      ).catch(() => fallback());
    } catch (e) {
      fallback();
    }
  }

  private static duration(ms: number): void {
    try {
      vibrator.startVibration(
        { type: 'time', duration: ms },
        { id: 0, usage: 'notification' }
      ).catch(() => {});
    } catch (e) {
      // 静默
    }
  }
}
