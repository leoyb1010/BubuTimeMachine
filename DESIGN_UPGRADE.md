# 布布时光机 · 视觉 / UI / 动效升级方案

> 更新于 2026-06-10。基于当前代码（Wave A–H + 深度 review 落地后）的真实状态盘点 + 下一阶段升级路线。
> 设计北极星不变：**「高级育儿日记本」的质感 + 姥姥能用的清晰 + 给 18 岁布布看的庄重感**。

---

## 0. 现状盘点（已有的资产，升级要在这之上做，不要推翻）

| 资产 | 位置 | 状态 |
|---|---|---|
| 设计 token（色板/字阶/圆角/间距/文案） | `DesignSystem/BubuTheme.swift` | ✅ 完整，全部动态色适配深色模式 |
| 6 套可切换主题（珊瑚暖阳/晴空蓝/薄荷绿/薰衣草/蜜桃粉/星夜） | `DesignSystem/ThemeManager.swift` | ✅ 切换带 `.smooth(0.4)` 过渡 |
| iOS 26 Liquid Glass 统一封装 | `DesignSystem/BubuLiquidGlass.swift` | ✅ `bubuGlassSurface` / `bubuGlassButton`，含 fallback |
| 布布表情贴纸 ×20（与 logo 同系插画） | `DesignSystem/BubuExpression.swift` + Assets | ✅ 已有心情→贴纸映射 |
| 适老大按钮（不拦截滚动 + 按压缩放） | `DesignSystem/BigButton.swift` | ✅ |
| 仪式动画（触觉反馈 + 二段星光 + reduceMotion） | `DesignSystem/CeremonyAnimation.swift` | ✅ 本轮已升级 |
| Ken Burns 播放器（ImageIO 降采样 + 邻片预载 + 缩放平移 + reduceMotion） | `Features/AIStudio/GrowthMoviePlayer.swift` | ✅ 本轮已升级 |
| 中文日期统一格式 | `DesignSystem/BubuDateFormat.swift` | ✅ 全局 zh_CN |
| 波形组件 / 流式标签 / 媒体查看器 / 心情选择器 | `DesignSystem/Components/` | ✅ 可用，待动效打磨 |

**结论**：地基是好的。升级的主题词不是「重做」，而是 **统一、呼吸感、仪式感** 三件事。

---

## 1. 设计原则（升级期间的三条裁决标准）

1. **一眼妈妈味，绝不科技味**：暖色、圆体、插画、口语文案。任何看起来像「后台管理系统」或「AI 产品」的元素都要改（如生硬的 LabeledContent 列表、英文术语）。
2. **姥姥优先**：触达目标 ≥ 44pt（主要动作 ≥ 56pt）、正文 ≥ 18pt、对比度 ≥ 4.5:1、永不依赖颜色单独传达状态、所有动效必须有 reduceMotion 降级。
3. **庄重时刻要慢，日常操作要快**：时间胶囊开启、里程碑点亮、年度电影是「典礼」——动效可以长到 1–2s；记录、保存、切 tab 是「日常」——一切反馈 ≤ 0.3s。

---

## 2. 视觉升级

### 2.1 色彩（P1）
- **主题不止换主色**：当前 6 套主题只换 `primary/secondary/背景渐变`，卡片、softFill、hairline 仍是固定暖棕系——薄荷绿/晴空蓝主题下卡片仍偏粉米色，套色不彻底。
  → `BubuThemeDefinition` 增加 `surfaceTintHex`，`BubuTheme.Color.card/softFill/hairline` 在主题色相上做 5–8% 的偏移（用 `Color.mix(_:with:by:)`）。
- **语义色补全**：现有 success/danger，缺 `warning`（同步重试中）与 `info`（AI 处理中）。补两枚低饱和暖色 token，禁止页面里再出现裸写的 `.orange/.blue`。
- **星夜主题独立审一遍**：`ThemedBackground` 在系统深色下直接用动态 background，但「浅色系统 + 星夜主题」组合里 `#2B2A3D` 渐变上的次要文字 `#B8B2C8` 对比度刚过线，建议提到 `#C9C4DB`。

### 2.2 插画与品牌（P0——性价比最高的一项）
20 个布布表情贴纸是最稀缺的资产，当前只用在 mascot 角标和心情映射，**用得太省**：
- **空状态全面插画化**：时光轴空态已用 `BubuMascotBadge`，但里程碑/AI 工坊/胶囊/成长之声的空态还是 SF Symbol。每个空态配一个语义贴纸 + 一句口语文案（`.bye` 留给"暂无"，`.cheer` 留给"快完成"，`.thinking` 留给 AI 处理中）。
- **加载状态拟人化**：AI 等待时用 `.thinking` 贴纸 + 轻微上下浮动（2s 循环,`±4pt`），替代系统 ProgressView。
- **成就时刻**：里程碑仪式动画中央的 `star.circle.fill` 换成 `.yeah` / `.cheer` 贴纸（按里程碑类别选），系统图标的庄重感不如自家 IP。
- **App 图标季节化**（远期）：生日月专属图标，`alternate app icons` 即可。

### 2.3 字体与排版（P1）
- 数字场景（年龄天数、倒计时、统计卡）统一 `.monospacedDigit()`，跳动时不抖宽度。
- 首页大年龄「1岁7个月」用 `fontWidth(.expanded)` + 字重对比（数字 bold、单位 regular），现在整串同字重，缺层级。
- 信件正文（胶囊揭开页）已用 serif，**把第一人称日记也统一为 serif**——"布布写的字"应该有一致的笔迹感。

### 2.4 图标语言（P2）
全 App 是 SF Symbols，无问题；但 tab bar 五个图标视觉重量不均（`wand.and.stars` 比 `heart.circle.fill` 轻很多）。统一用 `.fill` 变体 + 相同 optical size，选中态加 `symbolEffect(.bounce, value: selection)`。

---

## 3. UI 升级（按页面）

### 3.1 首页 · 记录此刻（P0）
现状（见 `screenshots_xhs/01_home.png`）已好，三个升级点：
- **统计卡可点**：「11 个瞬间 / 4 张照片 / 151 天后生日」目前是死卡片，点击应分别跳时光轴、媒体网格、生日倒计时详情。卡片加按压缩放（同 BigButtonStyle）。
- **「那年今日」上首页**：通知里有、首页没有。在「最近的瞬间」上方加一张可横滑的回忆卡（去年今天的照片 + 年龄角标），这是日记类产品留存最强的钩子。
- **同步状态胶囊化**：顶部「本地已保存」横幅信息密度低，改成导航栏下的一颗小胶囊（图标 + 四字文案），点开才展开详情;同步进行中时胶囊内放微型进度环。

### 3.2 时光轴（P0）
- **月份头加年龄锚点**：现在只有「2026年6月」，加一行小字「布布 1岁7个月」——翻旧记录时,年龄比日期更有感。
- **卡片层级**：`TimelineEntryCard` 的心情 emoji、作者标签、时间挤在一行,改为「媒体大图 > 文字 > 元信息」三层,元信息整体降一级灰度。
- **滚动年份指示器**（P1）：右侧细滚动条拖动时浮出「2025 · 1岁」气泡（`ScrollPosition` + overlay 实现）。
- **入场动效**：卡片首次出现 `opacity 0→1 + y偏移 12→0`,`spring(response:0.4)`,延迟按索引 ×0.05 错开（仅首屏前 6 张,reduceMotion 关闭）。

### 3.3 时间胶囊（P0——产品的灵魂页面,值得最贵的动效预算）
- **锁定卡倒计时活起来**：「还要等 17 年」是死文案，改为实时翻牌倒计时（年/天两级即可，`TimelineView(.periodic)` 驱动），最后 24 小时进入「即将开启」状态：卡片缓慢呼吸发光（`shadow` 半径 8→16 循环,3s）。
- **开启典礼三幕制**（现状两幕：bounce 信封 → 内容浮现）：
  1. **封蜡破裂**：信封贴纸 + 蜡封图形,点击后蜡封碎裂粒子（`CAEmitterLayer`,20 粒,0.6s）+ `UIImpactFeedbackGenerator(.heavy)`;
  2. **时光回溯**：背景从当前主题色渐变回「封存当天」的色温,字幕淡入「这封信等了你 6 年 142 天」（写信日期是现成的）;
  3. **信纸展开**：信纸从信封中向上抽出（`matchedGeometryEffect`）,正文逐段淡入,serif 字体,行间距拉开。
  全程 ~2.5s,可点击跳过,reduceMotion 直接定格到第三幕。
- **写信页**：封存按钮按下后加「封蜡盖章」微动效（按钮变圆章,缩放 1→1.15→1 + 成功触觉）,替代直接 dismiss——封存应该有「咔哒」一下的确定感。

### 3.4 里程碑（P1）
- 已点亮卡片加**点亮日期角标**和金色细描边;待点亮的灰卡 hover/按压时预览彩色（提示"这个可以点亮"）。
- 进度环动效：进入页面时从 0 动画到当前值（1s,`easeOut`）,而不是直接定格。
- 仪式动画中央图标换布布贴纸（见 2.2）。

### 3.5 AI 工坊（P1）
- **名字改掉**：「AI 工坊」对姥姥是噪音,建议「布布的故事」（tab 同步改）。
- 第一人称日记的打字机动效保留,但**补一个「布布正在想」前置态**（thinking 贴纸浮动 1s）再开始打字,掩盖网络延迟。
- 生成失败的降级文案已口语化,但视觉上仍是红字——改成 `.shy` 贴纸 +「布布想不出来,过会儿再试试」。

### 3.6 设置（P2）
- 系统 Form 风格与全 App 暖色卡片割裂。低成本方案:`scrollContentBackground(.hidden)` 已做,再给每个 Section 套 `bubuGlassSurface`,字段行高提到 52pt。
- 服务器/AI 配置对普通家庭成员是噪音,折叠进「高级 · 自托管」二级页,默认只露「身份切换 / 布布档案 / 主题 / 提醒 / 导出」。

### 3.7 引导页（P2）
三步引导文案好,但纯静态。第 1 步加布布贴纸轮播（3 个表情,2s 轮换淡入淡出）;选生日后立即实时预览「布布已来到世界 N 天」——让数据第一次"活"给用户看。

---

## 4. 动效系统（统一规范,新建 `DesignSystem/BubuMotion.swift`）

### 4.1 Motion tokens（全 App 只允许这五种曲线）

```swift
enum BubuMotion {
    /// 日常反馈：按压、选中、chip 切换
    static let quick   = Animation.spring(response: 0.25, dampingFraction: 0.85)
    /// 页面内元素入场/布局变化
    static let gentle  = Animation.spring(response: 0.4,  dampingFraction: 0.8)
    /// 主题切换、模式切换等全局变化
    static let smooth  = Animation.smooth(duration: 0.4)
    /// 典礼感：胶囊开启、里程碑点亮（允许 0.8–2.5s）
    static let ceremony = Animation.spring(response: 0.6, dampingFraction: 0.75)
    /// 循环呼吸：等待、即将解锁的胶囊
    static let breathe = Animation.easeInOut(duration: 3).repeatForever(autoreverses: true)
}
```

落地方式：grep 全部裸写的 `.spring(`/`.easeInOut(`/`.snappy`,替换为 token;新代码 review 时裸曲线一律打回。

### 4.2 触觉反馈映射表（与动效成对出现）

| 时刻 | Haptic | 现状 |
|---|---|---|
| 保存记录成功 | `.success` notification | ❌ 待加（`CaptureModel.flashSaved`） |
| 里程碑点亮 / 第一次确认 | `.success` | ✅ 已加（CeremonyAnimation） |
| 胶囊封存「盖章」 | `.impact(.medium)` | ❌ 待加 |
| 胶囊开启「破封」 | `.impact(.heavy)` + 0.3s 后 `.success` | ❌ 待加 |
| 心情/表情选中 | `.selection` | ❌ 待加（MoodPicker） |
| 删除确认 | `.warning` | ❌ 待加 |
| 录音开始/结束 | `.impact(.light)` ×1 / ×2 | ❌ 待加（VoiceComponents） |

统一封装 `BubuHaptics.swift`（enum + 静态方法）,禁止散落直建 generator。

### 4.3 转场
- 详情页:时光轴卡片 → `EntryDetailView` 用 iOS 18+ `navigationTransition(.zoom(sourceID:in:))`,照片无缝放大,这是相册类 App 的「正确手感」。**P0,一行 API 的事**。
- Sheet 类（写信/快速记录）保持系统默认,不做花活。

### 4.4 微交互清单（每个 ≤ 半天）
- [ ] 保存成功的 `savedFlash`:从纯文字横幅 → 贴纸 `.yeah` 弹入（scale 0.5→1 spring）+ success haptic
- [ ] 波形录音条:录制中波形柱用 `phaseAnimator` 加渐变流光
- [ ] 统计卡数字变化用 `contentTransition(.numericText())`
- [ ] tab 切换图标 `symbolEffect(.bounce)`
- [ ] 下拉刷新同步时,导航栏小胶囊里的进度环旋转
- [ ] 心情选中的 emoji 弹跳一次（scale 1→1.25→1,quick）

### 4.5 reduceMotion 总则
- 循环动画（呼吸/浮动/流光）→ 完全移除
- 入场位移 → 仅保留透明度淡入
- 典礼动效 → 直接定格终态,保留 haptic
- 已合规:CeremonyAnimation、GrowthMoviePlayer;**新增动效必须带 `@Environment(\.accessibilityReduceMotion)` 分支才算完成**。

---

## 5. 优先级与排期建议

| 批次 | 内容 | 预估 |
|---|---|---|
| **P0（一周）** | 贴纸空状态全覆盖 · 统计卡可点 · 那年今日上首页 · zoom 转场 · 胶囊倒计时活化 + 开启三幕制 · BubuMotion/BubuHaptics 两个文件落地 | 视觉收益最大的一批 |
| **P1（第二周）** | 主题套色彻底化 · 时光轴月份年龄锚点/卡片层级/入场动效 · 里程碑进度环与点亮预览 · AI 工坊更名 + 等待态 · monospacedDigit 清扫 | |
| **P2（机动）** | 设置页玻璃化 + 高级项折叠 · 引导页活化 · tab 图标统一 · 滚动年份指示器 · 季节图标 | |

**验收标准**（每批完成时过一遍）：
1. clean build 零警告,既有 7 个单元测试全过;
2. 开「减弱动态效果」走一遍全流程,无循环动画残留;
3. 深色模式 + 星夜主题 + 浅色 ×6 主题截图各一轮,无「浅底浅字」;
4. 给姥姥的两个硬指标:首页到「保存一条记录」≤ 3 次点击,任何页面的主动作按钮 ≥ 56pt。

---

## 6. 明确不做的事

- ❌ 不引入 Lottie/第三方动画库——SwiftUI + CAEmitter 够用,少一个依赖就少一个 30 年后的考古难题;
- ❌ 不做毛玻璃滥用——Liquid Glass 只用于「浮在内容上」的控件（输入框/工具条/小胶囊）,卡片主体保持实色,保证适老对比度;
- ❌ 不做跟手视差/陀螺仪效果——晕动症不友好,与「日记本」气质不符;
- ❌ 暗色模式不另设第七主题——星夜就是暗色答案,降低组合爆炸。
