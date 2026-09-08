import { accessibility } from '@kit.AccessibilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { common } from '@kit.AbilityKit';
import { BubuMotion } from './BubuMotion';

// API 23+ 原生减少动态设置，支持运行中立即响应，并在 Ability 结束时解除订阅。
export class MotionPreference {
  private static listening: boolean = false;
  private static readonly onChanged = (reduced: boolean): void => {
    BubuMotion.setReducedMotion(reduced);
    AppStorage.setOrCreate('bubuReduceMotion', reduced);
  };

  static initialize(context: common.Context): void {
    try {
      MotionPreference.onChanged(accessibility.isAnimationReduceEnabledSync());
      if (!MotionPreference.listening) {
        accessibility.onAnimationReduceStateChange(MotionPreference.onChanged);
        MotionPreference.listening = true;
      }
    } catch (error) {
      MotionPreference.onChanged(true);
      hilog.warn(0x0000, 'Bubu', '无法读取动态偏好，已使用减少动态模式');
    }
  }

  static dispose(): void {
    if (!MotionPreference.listening) return;
    try { accessibility.offAnimationReduceStateChange(MotionPreference.onChanged); }
    catch (error) { hilog.warn(0x0000, 'Bubu', '动态偏好监听释放失败'); }
    MotionPreference.listening = false;
  }
}
