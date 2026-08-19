# Design Direction

## Chosen direction

- Subject-grounded concept: 温暖家庭绘本 × 清晰成长档案。
- Distinctive signature: 布布吉祥物、马卡龙层级色、照片优先卡片与轻量仪式动效。
- Reason selected: 延续 iOS 已验证的产品识别，不在追平过程中引入第二套视觉语言。

## System

- Typography: 系统字体，标题强调，长辈模式提高字号和行高。
- Color and surfaces: 复用 `BubuTheme.ets`，深浅色均保持文字对比。
- Grid and spacing: 复用现有间距阶梯；仅面向 HarmonyOS 手机，窄屏单列、普通手机双列能力卡。
- Shape and borders: 复用马卡龙卡片圆角与轻描边。
- Iconography and imagery: 使用鸿蒙系统图标语义和现有布布资源，不用 emoji 作为正式功能图标。
- Density: 默认舒适；长辈模式减少同屏操作与次级信息。

## Components and tokens

- Existing component source: `harmony/entry/src/main/ets/theme` 与 `components`。
- Components to reuse: MacaronComponents、BubuIdentityCard、MediaThumbnail、BubuGlassTabBar。
- New components justified: 仅为 iOS 新能力且现有组件无法表达的真实状态新增。
- Token changes: 先对齐现有 token，禁止页面级散落魔法值。

## Motion budget

- Primary motion engine: ArkUI 原生动画。
- Functional transitions: 页面进入、保存成功、同步/上传状态和胶囊解锁。
- Dominant effect, if any: 每页最多一个布布仪式动效。
- Reduced-motion behavior: 尊重系统减少动效，退化为淡入和即时状态更新。

## State matrix

| Surface | Loading | Empty | Error | Success | Disabled | Long content | Responsive |
|---|---|---|---|---|---|---|---|
| 核心记录与时光轴 | 骨架屏 | 布布空状态 | 可重试错误 | 明确保存/同步状态 | 阻止重复提交 | 文本折行不截断 | 手机宽度内自适应 |
