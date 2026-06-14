// MARK: - 设计 token（对照 iOS DesignSystem/BubuTheme.swift 暖色系马卡龙）
// 「高级育儿日记本」质感的统一来源：柔和色板、字号阶梯、圆角、阴影、口语文案、渐变。
// 适老化是一等公民：字号偏大、对比充足、留白舒展。
// 纯常量（plain class static），可在任意上下文引用。
//
// 兼容性：保留旧有 BubuColor / BubuRadius / bubuCardCol 导出（大量 view 直接 import）。
// 旧值 primary='#F28C9E' 沿用主题 coral 主色，与 iOS BubuTheme.Color.primary(#F2789F) 略有出入，
// 为不破坏既有 view 的视觉一致性，此处保持 #F28C9E（与 ThemeManager 默认 coral 主题一致）。

// MARK: 色板（柔和、温暖、低饱和）——对照 iOS BubuTheme.Color
export class BubuColor {
  // —— 旧有导出（保持不变，勿删）——
  static readonly primary = '#F28C9E';        // 珊瑚粉（主色）
  static readonly warmBrown = '#5A3D34';      // 暖棕（文字/标题）ink
  static readonly cream = '#FFF7F1';          // 奶油底
  static readonly card = '#FFFFFF';           // 卡片底
  static readonly secondaryText = '#A98D82';  // 次要文字 ink2
  static readonly success = '#8CB894';        // 柔绿

  // —— 新增完整 token（对照 iOS）——
  /// 强调深色端 deeprose：主按钮渐变尾色 / 凸起记录键。
  static readonly deepRose = '#E15C86';
  /// 次奶油底 cream2：选中态 / 嵌套层底。
  static readonly cream2 = '#FCEDE4';
  /// 页面背景（奶油基底，略带粉调）。
  static readonly background = '#FFF7F1';
  /// 稍高一层的卡片底（浅色与 card 相同；深色另算）。
  static readonly elevatedCard = '#FFFFFF';
  /// 轻填充，用于未选中 chip / 文本框。
  static readonly softFill = '#F5E8E0';
  /// 分隔线。
  static readonly hairline = '#DBCCC2';
  static readonly danger = '#DB3B47';
  /// 暖橙（同步重试中 / 需要注意）。禁止页面裸写 orange。
  static readonly warning = '#ED9E3B';
  /// 柔蓝（AI 处理中 / 信息提示）。禁止页面裸写 blue。
  static readonly info = '#5C8CCC';

  // MARK: 马卡龙副色板（记忆色相 / 渐变 / 星座盘星点）
  static readonly peach  = '#FFD3BE';
  static readonly pink   = '#FFC2D6';
  static readonly lav    = '#DCC9FF';
  static readonly mint   = '#BFEBD3';
  static readonly butter = '#FFE2A0';
  static readonly sky    = '#C4E4FF';

  // MARK: 深色模式备用文字色（对照 ThemedBackground 中的取色）
  static readonly darkPrimaryText = '#F5F0E8';
  static readonly darkSecondaryText = '#B8B2C8';
  static readonly darkCard = '#33324A';

  /// 由色相（0–360）生成一抹柔和马卡龙色（对照 iOS BubuTheme.Color.hue / 设计稿 HUE()）。
  /// HarmonyOS 颜色字符串需 hex；这里以 HSB→RGB 转换返回 '#RRGGBB'。
  static hue(h: number, lightness: number = 0.86, saturation: number = 0.90): string {
    return hsbToHex((h % 360 + 360) % 360, saturation, lightness);
  }
}

// MARK: 字号阶梯（偏大，适老；马卡龙加重标题字）——对照 iOS BubuTheme.Font
export class BubuFont {
  static readonly hugeTitle = 34;
  static readonly title = 26;
  static readonly headline = 21;
  static readonly body = 18;
  static readonly caption = 15;

  // 字重（ArkUI FontWeight 枚举对照）
  static readonly weightHeavy = FontWeight.Bolder;   // .heavy
  static readonly weightBold = FontWeight.Bold;
  static readonly weightMedium = FontWeight.Medium;
  static readonly weightRegular = FontWeight.Regular;
}

// MARK: 圆角（马卡龙更圆润）——对照 iOS BubuTheme.Radius
export class BubuRadius {
  // —— 旧有导出（保持不变，勿删）——
  static readonly card = 28;   // 旧值 20 → 对齐 iOS 28（更圆润）
  static readonly small = 16;  // 旧值 14 → 对齐 iOS 16
  // —— 新增 ——
  static readonly button = 28;
}

// MARK: 间距——对照 iOS BubuTheme.Spacing
export class BubuSpacing {
  static readonly section = 28;
  static readonly item = 16;
}

// MARK: 口语文案常量（错误永不报代码，永不吓人）——对照 iOS BubuTheme.Copy
export class BubuCopy {
  static readonly recordNow = '记录此刻';
  static readonly speakToBubu = '直接说给布布听';
  static readonly emptyTimeline = '还没有记录呢\n点上面的「记录此刻」，留住布布的第一个瞬间吧';
  static readonly saving = '正在保存…';
  static readonly savedLocally = '已经存在手机里啦';
}

// MARK: 阴影 token——对照 iOS bubuCardShadow（暖玫瑰投影，比纯黑更通透柔和）
// 颜色 rgb(0.71,0.47,0.43) ≈ #B57870，alpha 0.20 → #33B57870。
export class BubuShadow {
  static readonly cardColor = '#33B57870';
  static readonly cardRadius = 14;
  static readonly cardOffsetY = 8;
  // 主按钮深玫瑰投影（对照 bubuPrimaryButton）：deepRose 0.45 → #73E15C86。
  static readonly buttonColor = '#73E15C86';
  static readonly buttonRadius = 12;
  static readonly buttonOffsetY = 6;
}

// MARK: 渐变 token——对照 iOS BubuTheme.Gradient
// ArkUI linearGradient colors: [[color, stop]...]，angle 135 ≈ topLeading→bottomTrailing。
export class BubuGradient {
  static readonly angleTopLeadingToBottomTrailing = 135;
  /// 主按钮：rose → deeprose。
  static readonly primaryButtonColors: Array<[ResourceColor, number]> = [
    [BubuColor.primary, 0.0],
    [BubuColor.deepRose, 1.0]
  ];
  /// Hero 卡：peach → pink → lav。
  static readonly heroColors: Array<[ResourceColor, number]> = [
    [BubuColor.peach, 0.0],
    [BubuColor.pink, 0.5],
    [BubuColor.lav, 1.0]
  ];
}

// MARK: - 卡片样式（对照 iOS bubuCardShadow）。按压反馈交给各组件的 clickEffect。
@Extend(Column)
export function bubuCardCol() {
  .backgroundColor(BubuColor.card)
  .borderRadius(BubuRadius.card)
  .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
}

// MARK: - 颜色工具（对照 iOS Color hex / mix）

/// HSB(0..360, 0..1, 0..1) → '#RRGGBB'。对照 SwiftUI Color(hue:saturation:brightness:)。
export function hsbToHex(h: number, s: number, b: number): string {
  const c: number = b * s;
  const x: number = c * (1 - Math.abs(((h / 60) % 2) - 1));
  const m: number = b - c;
  let r: number = 0;
  let g: number = 0;
  let bl: number = 0;
  if (h < 60) { r = c; g = x; bl = 0; }
  else if (h < 120) { r = x; g = c; bl = 0; }
  else if (h < 180) { r = 0; g = c; bl = x; }
  else if (h < 240) { r = 0; g = x; bl = c; }
  else if (h < 300) { r = x; g = 0; bl = c; }
  else { r = c; g = 0; bl = x; }
  return rgbToHex((r + m) * 255, (g + m) * 255, (bl + m) * 255);
}

/// 把 hex 颜色向另一 hex 混合 fraction（0..1），纯 sRGB 线性插值。
/// 对照 iOS Color.mix(with:by:)：表面色按主题做 5–8% 偏移。
export function mixHex(a: string, b: string, fraction: number): string {
  const f: number = Math.min(Math.max(fraction, 0), 1);
  const ca = hexToRgb(a);
  const cb = hexToRgb(b);
  return rgbToHex(
    ca.r + (cb.r - ca.r) * f,
    ca.g + (cb.g - ca.g) * f,
    ca.b + (cb.b - ca.b) * f
  );
}

interface RgbTriple { r: number; g: number; b: number; }

function hexToRgb(hex: string): RgbTriple {
  let s: string = hex.replace('#', '');
  if (s.length === 8) { s = s.substring(2); } // 丢弃前缀 alpha（#AARRGGBB 习惯）
  const num: number = parseInt(s, 16);
  return {
    r: (num >> 16) & 0xff,
    g: (num >> 8) & 0xff,
    b: num & 0xff
  };
}

function rgbToHex(r: number, g: number, b: number): string {
  const ri: number = Math.round(Math.min(Math.max(r, 0), 255));
  const gi: number = Math.round(Math.min(Math.max(g, 0), 255));
  const bi: number = Math.round(Math.min(Math.max(b, 0), 255));
  const h: (n: number) => string = (n: number): string => {
    const str: string = n.toString(16);
    return str.length === 1 ? '0' + str : str;
  };
  return '#' + h(ri) + h(gi) + h(bi);
}
