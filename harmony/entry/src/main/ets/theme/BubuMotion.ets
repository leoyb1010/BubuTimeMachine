// MARK: - 动效 token（对照 iOS DesignSystem/BubuMotion.swift）
// 全 App 只允许这几种曲线节奏——动效节奏是品牌的一部分，必须统一。
// SwiftUI 用 Animation.spring(response:dampingFraction:)；ArkUI 用 animateTo({duration, curve})。
// 弹簧用 curves.springMotion(response, damping) 近似；duration 取经验近似（response≈感知时长）。
//
// 用法：animateTo(BubuMotion.quick, () => { this.x = ... });
//       或 .animation(BubuMotion.gentle) 链式修饰。

import { curves } from '@kit.ArkUI';

// AnimateParam 由 @ohos.arkui 全局提供（动画参数）。
export class BubuMotion {
  /// 日常反馈：按压、选中、chip 切换（≤0.3s 内完成感知）。spring(0.25,0.85)。
  static readonly quick: AnimateParam = {
    duration: 250,
    curve: curves.springMotion(0.25, 0.85)
  };
  /// 页面内元素入场 / 布局变化。spring(0.4,0.8)。
  static readonly gentle: AnimateParam = {
    duration: 400,
    curve: curves.springMotion(0.4, 0.8)
  };
  /// 主题切换、模式切换等全局变化。smooth(0.4)。
  static readonly smooth: AnimateParam = {
    duration: 400,
    curve: Curve.Smooth
  };
  /// 典礼感：胶囊开启、里程碑点亮（允许 0.8–2.5s）。spring(0.6,0.75)。
  static readonly ceremony: AnimateParam = {
    duration: 600,
    curve: curves.springMotion(0.6, 0.75)
  };
  /// 循环呼吸：等待、即将解锁的胶囊。easeInOut 3s 往返。
  /// 注意：reduceMotion 时调用方必须整段移除（不要 playMode 往返）。
  static readonly breathe: AnimateParam = {
    duration: 3000,
    curve: Curve.EaseInOut,
    iterations: -1,
    playMode: PlayMode.Alternate
  };
  /// 等待浮动（±4pt，2s 循环往返）。对照 iOS bubuFloating。
  static readonly floating: AnimateParam = {
    duration: 2000,
    curve: Curve.EaseInOut,
    iterations: -1,
    playMode: PlayMode.Alternate
  };

  // MARK: 关键标量（供组件直接引用）
  /// 统一按压缩放比例（对照 BubuPressableStyle）。
  static readonly pressScale: number = 0.97;
  /// 大按钮按压缩放（对照 BigButtonStyle）。
  static readonly bigButtonPressScale: number = 0.98;
  /// 首屏入场上移量（pt）。
  static readonly entranceOffsetY: number = 12;
  /// 入场错峰单格延迟（ms），最多累计 5 格。
  static readonly entranceStaggerMs: number = 50;
  static readonly entranceMaxIndex: number = 5;

  /// 入场延迟（对照 iOS BubuMotion.gentle.delay(min(index,5)*0.05)）。
  static entranceDelay(index: number): number {
    return Math.min(index, BubuMotion.entranceMaxIndex) * BubuMotion.entranceStaggerMs;
  }
}
