// MARK: - 主题管理（对照 iOS DesignSystem/ThemeManager.swift）
// 一套完整的视觉主题：不止主色辅色，而是「渗进每个像素」的完整语义包。
// 卡片/填充/发丝线色相、首页 mesh 控制点、强调渐变、纸纹与水印都由主题决定。
// 持久化到 preferences（对照 iOS UserDefaults），全局单例注入。

import { preferences } from '@kit.ArkData';
import type { common } from '@kit.AbilityKit';
import { mixHex, BubuColor } from './BubuTheme';

// MARK: 背景样式（对照 iOS BackgroundStyle）
export enum BackgroundStyleKind { solid = 'solid', gradient = 'gradient' }

export class BackgroundStyle {
  kind: BackgroundStyleKind;
  colorA: string;   // solid 用 colorA；gradient 用 colorA→colorB
  colorB: string;

  constructor(kind: BackgroundStyleKind, a: string, b: string) {
    this.kind = kind;
    this.colorA = a;
    this.colorB = b;
  }

  static solid(hex: string): BackgroundStyle {
    return new BackgroundStyle(BackgroundStyleKind.solid, hex, hex);
  }

  static gradient(a: string, b: string): BackgroundStyle {
    return new BackgroundStyle(BackgroundStyleKind.gradient, a, b);
  }
}

// MARK: 纸纹（对照 iOS PaperTexture）
export enum PaperTexture { none = 'none', grain = 'grain', fiber = 'fiber' }

// MARK: 首页背景模式（对照 iOS HeroBackgroundMode）
export enum HeroBackgroundMode { theme = '主题背景', photo = '布布照片' }

// MARK: - 主题定义（对照 iOS BubuThemeDefinition）
export class BubuThemeDefinition {
  readonly id: string;
  readonly name: string;
  readonly primaryHex: string;
  readonly secondaryHex: string;
  readonly backgroundStyle: BackgroundStyle;
  /// 卡片/softFill/hairline 偏移基色：表面色统一向它做 5–8% 偏移。
  readonly surfaceTintHex: string;
  /// 首页 hero 区 mesh 渐变控制点颜色（4–6 个）。
  readonly meshPalette: string[];
  /// 主按钮/进度环的强调渐变对。
  readonly accentStartHex: string;
  readonly accentEndHex: string;
  readonly paperTexture: PaperTexture;
  /// tab bar 选中色（null 则用 primary）。
  readonly tabTintHex: string | null;

  constructor(
    id: string, name: string, primaryHex: string, secondaryHex: string,
    backgroundStyle: BackgroundStyle, surfaceTintHex: string, meshPalette: string[],
    accentStartHex: string, accentEndHex: string, paperTexture: PaperTexture,
    tabTintHex: string | null
  ) {
    this.id = id;
    this.name = name;
    this.primaryHex = primaryHex;
    this.secondaryHex = secondaryHex;
    this.backgroundStyle = backgroundStyle;
    this.surfaceTintHex = surfaceTintHex;
    this.meshPalette = meshPalette;
    this.accentStartHex = accentStartHex;
    this.accentEndHex = accentEndHex;
    this.paperTexture = paperTexture;
    this.tabTintHex = tabTintHex;
  }

  get primary(): string { return this.primaryHex; }
  get secondary(): string { return this.secondaryHex; }
  get surfaceTint(): string { return this.surfaceTintHex; }
  /// tab bar 选中色（null → primary）。
  get tabTint(): string { return this.tabTintHex ?? this.primaryHex; }
  /// 背景是否偏暗（决定文字用浅色还是深色）。
  get isDark(): boolean { return this.id === 'night'; }

  /// 强调渐变颜色对（[start, end]）。供 linearGradient 使用。
  get accentGradientColors(): Array<[ResourceColor, number]> {
    return [[this.accentStartHex, 0.0], [this.accentEndHex, 1.0]];
  }

  // MARK: 全部主题（对照 iOS BubuThemeDefinition.all，8 套）
  static readonly all: BubuThemeDefinition[] = [
    new BubuThemeDefinition('coral', '珊瑚暖阳', '#F28C9E', '#F2B705',
      BackgroundStyle.gradient('#FFF5F0', '#FDEDE6'), '#F28C9E',
      ['#FFE3D5', '#FFD0C2', '#FFC2A8', '#FFB59E', '#FFE8C2', '#FFF5EC'],
      '#F28C9E', '#F2B705', PaperTexture.grain, null),
    new BubuThemeDefinition('sky', '晴空蓝', '#5B8DEF', '#73C2FB',
      BackgroundStyle.gradient('#F0F6FF', '#E6F0FD'), '#5B8DEF',
      ['#DCEBFF', '#C8DEFF', '#B5D4FF', '#A8CBFB', '#D6F0FF', '#EEF6FF'],
      '#5B8DEF', '#73C2FB', PaperTexture.grain, null),
    new BubuThemeDefinition('mint', '薄荷绿', '#5BB98C', '#9BE0C0',
      BackgroundStyle.gradient('#F0FBF5', '#E6F7EE'), '#5BB98C',
      ['#D8F3E5', '#C2EDD6', '#AEE6C8', '#9BE0C0', '#D6F5EC', '#EEFBF4'],
      '#5BB98C', '#9BE0C0', PaperTexture.grain, null),
    new BubuThemeDefinition('lavender', '薰衣草', '#8E7CC3', '#C3B1E1',
      BackgroundStyle.gradient('#F6F2FF', '#EFE8FD'), '#8E7CC3',
      ['#EAE2FB', '#DCD0F5', '#CFC0EF', '#C3B1E1', '#E8DEFB', '#F4EFFE'],
      '#8E7CC3', '#C3B1E1', PaperTexture.grain, null),
    new BubuThemeDefinition('peach', '蜜桃粉', '#FF9F8E', '#FFD3C2',
      BackgroundStyle.gradient('#FFF4F0', '#FFE9E2'), '#FF9F8E',
      ['#FFE3DA', '#FFD6C8', '#FFC8B8', '#FFBBA8', '#FFE8D8', '#FFF4EE'],
      '#FF9F8E', '#FFD3C2', PaperTexture.grain, null),
    new BubuThemeDefinition('night', '星夜', '#F2B705', '#F28C9E',
      BackgroundStyle.gradient('#2B2A3D', '#1E1D2B'), '#8E7CC3',
      ['#2B2A3D', '#322F47', '#3A3656', '#28304D', '#3D3358', '#222134'],
      '#F2B705', '#F28C9E', PaperTexture.fiber, '#F2B705'),
    new BubuThemeDefinition('cream', '奶油绘本', '#8A6B52', '#C2A079',
      BackgroundStyle.gradient('#FBF6EC', '#F4EADB'), '#C2A079',
      ['#F4EAD9', '#EFE0C9', '#E8D4B5', '#E0C9A3', '#F2E8D6', '#FBF6EC'],
      '#8A6B52', '#C2A079', PaperTexture.fiber, '#8A6B52'),
    new BubuThemeDefinition('dusk', '晚霞', '#F2748C', '#8E6FC9',
      BackgroundStyle.gradient('#FFF0F3', '#F3ECFD'), '#C46FA8',
      ['#FFD7DF', '#FFC2D0', '#F2A8C2', '#D98ABF', '#B57CD6', '#8E6FC9'],
      '#F2748C', '#8E6FC9', PaperTexture.grain, '#C46FA8'),
  ];

  static readonly defaultTheme: BubuThemeDefinition = BubuThemeDefinition.all[0];

  static byId(id: string): BubuThemeDefinition {
    return BubuThemeDefinition.all.find(t => t.id === id) ?? BubuThemeDefinition.defaultTheme;
  }
}

// MARK: - 主题管理器（对照 iOS @Observable ThemeManager）
// 持有当前主题、首页背景偏好，持久化到 preferences。@Observed 供 view 订阅。
@Observed
export class ThemeManager {
  static readonly shared: ThemeManager = new ThemeManager();

  private static readonly storeName = 'bubu_theme';
  private static readonly themeKey = 'bubu.theme.id';
  private static readonly heroKey = 'bubu.theme.heroMode';

  private store: preferences.Preferences | null = null;
  currentThemeId: string = BubuThemeDefinition.defaultTheme.id;
  heroModeRaw: string = HeroBackgroundMode.theme;

  // 在 Ability 启动时调用一次，注入 context 完成初始化与回读。
  initialize(context: common.UIAbilityContext): void {
    if (this.store) return;
    try {
      this.store = preferences.getPreferencesSync(context, { name: ThemeManager.storeName });
      this.currentThemeId =
        this.store.getSync(ThemeManager.themeKey, BubuThemeDefinition.defaultTheme.id) as string;
      this.heroModeRaw =
        this.store.getSync(ThemeManager.heroKey, HeroBackgroundMode.theme as string) as string;
    } catch (e) {
      this.store = null;
    }
  }

  get theme(): BubuThemeDefinition {
    return BubuThemeDefinition.byId(this.currentThemeId);
  }

  get heroMode(): HeroBackgroundMode {
    return this.heroModeRaw === HeroBackgroundMode.photo
      ? HeroBackgroundMode.photo : HeroBackgroundMode.theme;
  }

  set heroMode(m: HeroBackgroundMode) {
    this.heroModeRaw = m;
    this.persist(ThemeManager.heroKey, m);
  }

  /// 选择主题并持久化（对照 iOS select）。动效切换交由 view 用 animateTo 包裹。
  select(theme: BubuThemeDefinition): void {
    this.currentThemeId = theme.id;
    this.persist(ThemeManager.themeKey, theme.id);
    // NOTE: HarmonyOS 桌面图标随主题切换机制不同，见 AppIconManager.ets。
  }

  private persist(key: string, value: string): void {
    const p = this.store;
    if (!p) return;
    try {
      p.putSync(key, value);
      p.flush();
    } catch (e) {
      // 持久化失败静默：不影响当次会话使用。
    }
  }

  // MARK: 主题渗透表面色（对照 iOS AppEnvironment 扩展，Wave J §2.1）
  /// 卡片底：基础卡片色向主题 surfaceTint 偏移 ~6%。
  get themedCard(): string {
    return mixHex(BubuColor.card, this.theme.surfaceTint, this.theme.isDark ? 0.05 : 0.06);
  }
  /// 轻填充（未选中 chip / 文本框）：偏移 ~8%。
  get themedSoftFill(): string {
    return mixHex(BubuColor.softFill, this.theme.surfaceTint, 0.08);
  }
  /// 发丝线：偏移 ~8%。
  get themedHairline(): string {
    return mixHex(BubuColor.hairline, this.theme.surfaceTint, 0.08);
  }
  /// 主文字色：深色主题用奶白，浅色主题用暖棕。
  get primaryTextColor(): string {
    return this.theme.isDark ? BubuColor.darkPrimaryText : BubuColor.warmBrown;
  }
  get secondaryTextColor(): string {
    return this.theme.isDark ? BubuColor.darkSecondaryText : BubuColor.secondaryText;
  }
  get cardColor(): string {
    return this.theme.isDark ? BubuColor.darkCard : BubuColor.card;
  }
}
