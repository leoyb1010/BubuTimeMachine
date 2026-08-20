import { settings } from '@kit.BasicServicesKit';
import type { common } from '@kit.AbilityKit';
import { BubuMotion } from './BubuMotion';

// 读取系统动画时长/转场缩放。任一为 0 时按“减少动态效果”处理并镜像给 ArkUI 组件。
export class MotionPreference {
  static initialize(context: common.Context): void {
    const duration = Number(settings.getValueSync(context, settings.display.ANIMATOR_DURATION_SCALE, '1'));
    const transition = Number(settings.getValueSync(context, settings.display.TRANSITION_ANIMATION_SCALE, '1'));
    const reduced = duration === 0 || transition === 0;
    BubuMotion.setReducedMotion(reduced);
    AppStorage.setOrCreate('bubuReduceMotion', reduced);
  }
}
