// MARK: - 首页 Hero 网格背景（对照 iOS DesignSystem/BubuMeshHero.swift，Wave J §2.2）
// iOS 18+ 用原生 MeshGradient（3×3 控制点取主题 meshPalette）渲染静态柔和渐变。
// HarmonyOS 无 MeshGradient——用多层 radialGradient 色球叠加近似「网格柔光」效果：
// 取 meshPalette 前若干色，分布在四角/中心做径向柔光，叠出自然不对称的马卡龙渐变。
// 静态渲染，零每帧成本（对照 iOS 性能纪律：不再 TimelineView 持续重绘）。

@Component
export struct BubuMeshHero {
  colors: string[] = [];

  // 取色（不足时循环填充，保证至少 6 个铺满）。
  private padded(): string[] {
    if (this.colors.length === 0) {
      return ['#FFFFFF', '#FFFFFF', '#FFFFFF', '#FFFFFF', '#FFFFFF', '#FFFFFF'];
    }
    const out: string[] = [];
    for (let i = 0; i < 6; i++) { out.push(this.colors[i % this.colors.length]); }
    return out;
  }

  build() {
    Stack() {
      // 底色：第一个控制点色铺满。
      Column().width('100%').height('100%').backgroundColor(this.padded()[0])
      // 多层径向柔光叠加，控制点固定偏移（对照 iOS 静态相位的非对称网格）。
      this.glow(this.padded()[1], '10%', '8%', '70%')
      this.glow(this.padded()[2], '88%', '14%', '64%')
      this.glow(this.padded()[3], '20%', '78%', '60%')
      this.glow(this.padded()[4], '82%', '82%', '66%')
      this.glow(this.padded()[5], '52%', '48%', '58%')
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }

  // 把 #RRGGBB 转成全透明 #00RRGGBB（ArkUI 颜色为 #AARRGGBB）。
  private transparent(hex: string): string {
    return '#00' + hex.replace('#', '');
  }

  // 单个径向柔光色球：用 radialGradient（中心实、边缘透明）+ blur 模拟 mesh 控制点。
  @Builder
  private glow(color: string, x: string, y: string, size: string) {
    Circle()
      .width(size)
      .height(size)
      .radialGradient({
        center: ['50%', '50%'],
        radius: '50%',
        colors: [[color, 0.0], [this.transparent(color), 1.0]]   // 中心实 → 边缘透明
      })
      .blur(30)
      .position({ x: x, y: y })
  }
}
