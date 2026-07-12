# BubuTimeMachine 生图资产需求文档

日期：2026-07-04

## 1. 结论

当前 BubuTimeMachine 需要补充少量生图资产，但不需要大规模重画。

现有项目已经具备完整的 Bubu 表情体系、App Icon 变体和纸纹理资源。产品的核心内容是家庭真实记忆、宝宝照片、成长时光，因此不建议用 AI 生成图替代真实照片、成长电影素材或年鉴正文内容。

本次生图资产的定位是：

- 补充空状态插画。
- 补充功能入口氛围图。
- 补充时光胶囊、年鉴、AI Studio 等高仪式感页面的视觉资产。
- 尽量不改当前 UI 结构，只做资源层面的增强。

## 2. 现有资产判断

### 2.1 已经足够，不建议重做

项目已有以下资源，暂不建议重新生成或覆盖：

- Bubu 表情图：已有 20 个左右，覆盖开心、阅读、音乐、旅行、运动、睡觉、害羞、惊讶等状态。
- App Icon：已有 cream、birthday、lavender、sky、coral、mint、night、peach 等多套主题图标。
- 纸纹理：已有 `paper-grain.png`、`paper-fiber.png`、`paper-fiber-light.png`。
- 用户照片、缩略图、成长电影、年鉴正文：必须继续使用真实用户数据。

### 2.2 适合补充生图的位置

适合使用 AI 生图模型补充的资产主要集中在：

- 首次启动 / Onboarding 主视觉。
- 时光轴、相册、声音档案、“那年今日”等空状态。
- 时光胶囊封存和开启仪式。
- AI Studio 功能入口。
- 成长报告头图。
- 年鉴导出封面底图。

## 3. 总体风格要求

所有图片建议统一使用以下风格前缀，保证与当前 BubuTimeMachine 的奶油色、珊瑚粉、纸张质感一致。

```text
Premium warm parenting diary illustration for a mobile app called BubuTimeMachine. Soft macaron palette: cream #FFF7F1, coral rose #F28C9E, deep rose #E15C86, warm brown #5A3D34, peach, mint, sky blue and lavender accents. Cozy family memory atmosphere, tactile paper grain, rounded friendly shapes, subtle soft shadows, polished app-native illustration, clean composition, no text, no UI, no logos, no watermark, no photorealistic child, no real person, no scary medical feeling, no dominant neon purple AI glow.
```

通用负面要求：

```text
No text, no letters, no readable numbers, no watermark, no UI screenshot, no logo, no photorealistic baby, no real human face, no stock photo style, no harsh neon, no cyberpunk, no medical chart feeling, no cluttered composition, no low resolution, no plastic 3D toy look.
```

## 4. 文件命名与交付方式

建议先生成 PNG 主文件。交付给开发接入时，文件名直接使用下表中的命名。

iOS 使用 Asset Catalog：

```text
/Users/leoyuan/Desktop/leoworkspace/BubuTimeMachine/BubuTimeMachine/Resources/Assets.xcassets/<AssetName>.imageset/<AssetName>.png
```

鸿蒙使用 media 资源：

```text
/Users/leoyuan/Desktop/leoworkspace/BubuTimeMachine/harmony/entry/src/main/resources/base/media/<snake_case_name>.png
```

如果生图模型支持透明背景，空状态图优先使用透明背景 PNG；如果不支持，统一使用 `#FFF7F1` 奶油底。

## 5. P0 必须生成资产

### 5.1 BubuOnboardingHero

用途：首次启动 / 欢迎页主视觉。

尺寸：2048 x 2048。

iOS 目标路径：

```text
/Users/leoyuan/Desktop/leoworkspace/BubuTimeMachine/BubuTimeMachine/Resources/Assets.xcassets/BubuOnboardingHero.imageset/BubuOnboardingHero.png
```

鸿蒙目标路径：

```text
/Users/leoyuan/Desktop/leoworkspace/BubuTimeMachine/harmony/entry/src/main/resources/base/media/bubu_onboarding_hero.png
```

Prompt：

```text
Premium warm parenting diary illustration for a mobile app called BubuTimeMachine. Soft macaron palette: cream #FFF7F1, coral rose #F28C9E, deep rose #E15C86, warm brown #5A3D34, peach, mint, sky blue and lavender accents. Cozy family memory atmosphere, tactile paper grain, rounded friendly shapes, subtle soft shadows, polished app-native illustration, clean composition, no text, no UI, no logos, no watermark, no photorealistic child, no real person, no scary medical feeling, no dominant neon purple AI glow. A cozy magical memory room with an open baby diary, floating blank photo frames, a tiny warm time machine capsule, soft stars, ribbons, and paper keepsakes. Leave clean empty space near the top center for app title overlay. Full-bleed square composition, gentle depth.
```

### 5.2 BubuEmptyTimeline

用途：时光轴空状态。

尺寸：1024 x 1024。

iOS 目标路径：

```text
/Users/leoyuan/Desktop/leoworkspace/BubuTimeMachine/BubuTimeMachine/Resources/Assets.xcassets/BubuEmptyTimeline.imageset/BubuEmptyTimeline.png
```

鸿蒙目标路径：

```text
/Users/leoyuan/Desktop/leoworkspace/BubuTimeMachine/harmony/entry/src/main/resources/base/media/bubu_empty_timeline.png
```

Prompt：

```text
Premium warm parenting diary illustration for a mobile app called BubuTimeMachine. Soft macaron palette: cream #FFF7F1, coral rose #F28C9E, deep rose #E15C86, warm brown #5A3D34, peach, mint, sky blue and lavender accents. Cozy family memory atmosphere, tactile paper grain, rounded friendly shapes, subtle soft shadows, polished app-native illustration, clean composition, no text, no UI, no logos, no watermark, no photorealistic child, no real person, no scary medical feeling, no dominant neon purple AI glow. A blank warm timeline card waiting for the first memory, with a tiny camera, diary page, soft timestamp ribbon, small sparkles, and a gentle coral accent button-like glow. Centered empty-state illustration, simple background.
```

### 5.3 BubuEmptyAlbum

用途：相册 / 本机照片空状态。

尺寸：1024 x 1024。

iOS 目标路径：

```text
/Users/leoyuan/Desktop/leoworkspace/BubuTimeMachine/BubuTimeMachine/Resources/Assets.xcassets/BubuEmptyAlbum.imageset/BubuEmptyAlbum.png
```

鸿蒙目标路径：

```text
/Users/leoyuan/Desktop/leoworkspace/BubuTimeMachine/harmony/entry/src/main/resources/base/media/bubu_empty_album.png
```

Prompt：

```text
Premium warm parenting diary illustration for a mobile app called BubuTimeMachine. Soft macaron palette: cream #FFF7F1, coral rose #F28C9E, deep rose #E15C86, warm brown #5A3D34, peach, mint, sky blue and lavender accents. Cozy family memory atmosphere, tactile paper grain, rounded friendly shapes, subtle soft shadows, polished app-native illustration, clean composition, no text, no UI, no logos, no watermark, no photorealistic child, no real person, no scary medical feeling, no dominant neon purple AI glow. An empty family photo album spread with soft blank photo placeholders, rounded polaroid corners, a small camera, paper tape, tiny stars and peach-pink accents. Friendly, quiet, not sad. Centered illustration, no real photos.
```

### 5.4 BubuCapsuleSealed

用途：时光胶囊未开启 / 封存状态。

尺寸：1536 x 1536。

iOS 目标路径：

```text
/Users/leoyuan/Desktop/leoworkspace/BubuTimeMachine/BubuTimeMachine/Resources/Assets.xcassets/BubuCapsuleSealed.imageset/BubuCapsuleSealed.png
```

鸿蒙目标路径：

```text
/Users/leoyuan/Desktop/leoworkspace/BubuTimeMachine/harmony/entry/src/main/resources/base/media/bubu_capsule_sealed.png
```

Prompt：

```text
Premium warm parenting diary illustration for a mobile app called BubuTimeMachine. Soft macaron palette: cream #FFF7F1, coral rose #F28C9E, deep rose #E15C86, warm brown #5A3D34, peach, mint, sky blue and lavender accents. Cozy family memory atmosphere, tactile paper grain, rounded friendly shapes, subtle soft shadows, polished app-native illustration, clean composition, no text, no UI, no logos, no watermark, no photorealistic child, no real person, no scary medical feeling, no dominant neon purple AI glow. A sealed time capsule for a child's future self, like a warm memory box with a soft wax seal, floating letter pages, tiny stars, gentle golden light, subtle time-lock motif. Ceremonial but cozy, centered composition.
```

## 6. P1 建议生成资产

### 6.1 BubuCapsuleUnlock

用途：时光胶囊开启仪式。

尺寸：1536 x 1536。

iOS 目标路径：

```text
/Users/leoyuan/Desktop/leoworkspace/BubuTimeMachine/BubuTimeMachine/Resources/Assets.xcassets/BubuCapsuleUnlock.imageset/BubuCapsuleUnlock.png
```

鸿蒙目标路径：

```text
/Users/leoyuan/Desktop/leoworkspace/BubuTimeMachine/harmony/entry/src/main/resources/base/media/bubu_capsule_unlock.png
```

Prompt：

```text
Premium warm parenting diary illustration for a mobile app called BubuTimeMachine. Soft macaron palette: cream #FFF7F1, coral rose #F28C9E, deep rose #E15C86, warm brown #5A3D34, peach, mint, sky blue and lavender accents. Cozy family memory atmosphere, tactile paper grain, rounded friendly shapes, subtle soft shadows, polished app-native illustration, clean composition, no text, no UI, no logos, no watermark, no photorealistic child, no real person, no scary medical feeling, no dominant neon purple AI glow. The same warm memory time capsule opening with soft golden light, floating blank letters, tiny confetti sparks, gentle paper fragments, a feeling of rediscovering childhood memories. Magical but restrained.
```

### 6.2 BubuMagicRoomHero

用途：AI Studio 入口氛围图。

尺寸：2048 x 1536。

iOS 目标路径：

```text
/Users/leoyuan/Desktop/leoworkspace/BubuTimeMachine/BubuTimeMachine/Resources/Assets.xcassets/BubuMagicRoomHero.imageset/BubuMagicRoomHero.png
```

鸿蒙目标路径：

```text
/Users/leoyuan/Desktop/leoworkspace/BubuTimeMachine/harmony/entry/src/main/resources/base/media/bubu_magic_room_hero.png
```

Prompt：

```text
Premium warm parenting diary illustration for a mobile app called BubuTimeMachine. Soft macaron palette: cream #FFF7F1, coral rose #F28C9E, deep rose #E15C86, warm brown #5A3D34, peach, mint, sky blue and lavender accents. Cozy family memory atmosphere, tactile paper grain, rounded friendly shapes, subtle soft shadows, polished app-native illustration, clean composition, no text, no UI, no logos, no watermark, no photorealistic child, no real person, no scary medical feeling, no dominant neon purple AI glow. A cozy creative studio desk for turning family memories into stories: open storybook, small star projector, blank photo cards, soft magical sparkles, warm lamp glow, paper textures. No robot, no tech UI.
```

### 6.3 BubuYearbookCover

用途：年鉴 / 导出封面底图。

尺寸：2400 x 1600。

iOS 目标路径：

```text
/Users/leoyuan/Desktop/leoworkspace/BubuTimeMachine/BubuTimeMachine/Resources/Assets.xcassets/BubuYearbookCover.imageset/BubuYearbookCover.png
```

鸿蒙目标路径：

```text
/Users/leoyuan/Desktop/leoworkspace/BubuTimeMachine/harmony/entry/src/main/resources/base/media/bubu_yearbook_cover.png
```

Prompt：

```text
Premium warm parenting diary illustration for a mobile app called BubuTimeMachine. Soft macaron palette: cream #FFF7F1, coral rose #F28C9E, deep rose #E15C86, warm brown #5A3D34, peach, mint, sky blue and lavender accents. Cozy family memory atmosphere, tactile paper grain, rounded friendly shapes, subtle soft shadows, polished app-native illustration, clean composition, no text, no UI, no logos, no watermark, no photorealistic child, no real person, no scary medical feeling, no dominant neon purple AI glow. A premium printable family yearbook cover background, cream paper, subtle pressed flowers, tiny stars, photo corners, soft coral and mint accents, elegant blank center area for title overlay.
```

### 6.4 BubuGrowthReportHero

用途：成长报告空状态 / 头图。

尺寸：1536 x 1536。

iOS 目标路径：

```text
/Users/leoyuan/Desktop/leoworkspace/BubuTimeMachine/BubuTimeMachine/Resources/Assets.xcassets/BubuGrowthReportHero.imageset/BubuGrowthReportHero.png
```

鸿蒙目标路径：

```text
/Users/leoyuan/Desktop/leoworkspace/BubuTimeMachine/harmony/entry/src/main/resources/base/media/bubu_growth_report_hero.png
```

Prompt：

```text
Premium warm parenting diary illustration for a mobile app called BubuTimeMachine. Soft macaron palette: cream #FFF7F1, coral rose #F28C9E, deep rose #E15C86, warm brown #5A3D34, peach, mint, sky blue and lavender accents. Cozy family memory atmosphere, tactile paper grain, rounded friendly shapes, subtle soft shadows, polished app-native illustration, clean composition, no text, no UI, no logos, no watermark, no photorealistic child, no real person, no scary medical feeling, no dominant neon purple AI glow. A gentle growth report illustration with a small plant sprout, soft measuring marks, rounded chart lines, baby keepsake objects, stars, warm paper background. Emotional and calm, not medical or clinical, no numbers.
```

## 7. P2 可选资产

### 7.1 BubuVoiceArchiveEmpty

用途：声音档案空状态。

尺寸：1024 x 1024。

iOS 目标路径：

```text
/Users/leoyuan/Desktop/leoworkspace/BubuTimeMachine/BubuTimeMachine/Resources/Assets.xcassets/BubuVoiceArchiveEmpty.imageset/BubuVoiceArchiveEmpty.png
```

鸿蒙目标路径：

```text
/Users/leoyuan/Desktop/leoworkspace/BubuTimeMachine/harmony/entry/src/main/resources/base/media/bubu_voice_archive_empty.png
```

Prompt：

```text
Premium warm parenting diary illustration for a mobile app called BubuTimeMachine. Soft macaron palette: cream #FFF7F1, coral rose #F28C9E, deep rose #E15C86, warm brown #5A3D34, peach, mint, sky blue and lavender accents. Cozy family memory atmosphere, tactile paper grain, rounded friendly shapes, subtle soft shadows, polished app-native illustration, clean composition, no text, no UI, no logos, no watermark, no photorealistic child, no real person, no scary medical feeling, no dominant neon purple AI glow. A soft memory voice archive illustration with a tiny microphone, warm waveform ribbons, a small memory jar, paper notes, stars, and cozy coral accents. Centered empty-state asset.
```

### 7.2 BubuOnThisDayEmpty

用途：“那年今日”空状态。

尺寸：1024 x 1024。

iOS 目标路径：

```text
/Users/leoyuan/Desktop/leoworkspace/BubuTimeMachine/BubuTimeMachine/Resources/Assets.xcassets/BubuOnThisDayEmpty.imageset/BubuOnThisDayEmpty.png
```

鸿蒙目标路径：

```text
/Users/leoyuan/Desktop/leoworkspace/BubuTimeMachine/harmony/entry/src/main/resources/base/media/bubu_on_this_day_empty.png
```

Prompt：

```text
Premium warm parenting diary illustration for a mobile app called BubuTimeMachine. Soft macaron palette: cream #FFF7F1, coral rose #F28C9E, deep rose #E15C86, warm brown #5A3D34, peach, mint, sky blue and lavender accents. Cozy family memory atmosphere, tactile paper grain, rounded friendly shapes, subtle soft shadows, polished app-native illustration, clean composition, no text, no UI, no logos, no watermark, no photorealistic child, no real person, no scary medical feeling, no dominant neon purple AI glow. A gentle on-this-day memory illustration with a blank calendar page, circular time ribbon, tiny stars, moonlight, paper diary details, warm cream and coral palette. No readable dates, no numbers.
```

## 8. 推荐生成顺序

第一批建议只生成 P0 和 P1，共 8 张：

1. `BubuOnboardingHero`
2. `BubuEmptyTimeline`
3. `BubuEmptyAlbum`
4. `BubuCapsuleSealed`
5. `BubuCapsuleUnlock`
6. `BubuMagicRoomHero`
7. `BubuYearbookCover`
8. `BubuGrowthReportHero`

第二批再考虑 P2：

1. `BubuVoiceArchiveEmpty`
2. `BubuOnThisDayEmpty`

## 9. 验收标准

每张图生成后需要检查：

- 没有文字、数字、水印、Logo。
- 没有真实儿童或真实人脸。
- 没有替代用户真实记忆的照片感。
- 色彩接近当前 BubuTimeMachine 的奶油、珊瑚粉、暖棕、马卡龙体系。
- 图像主体清晰，边缘干净，移动端缩小后仍能识别。
- 有足够留白，方便 App 内覆盖标题、按钮或状态文案。
- 不要明显偏科技蓝紫、赛博风、医疗风或商业图库风。

## 10. 接入原则

后续接入时建议遵守：

- 只新增资源，不覆盖已有 Bubu 表情和 App Icon。
- iOS 和鸿蒙尽量使用同一套主视觉资源，保证跨平台一致。
- 空状态图优先作为辅助插画，不改变当前数据逻辑。
- 年鉴、成长电影、相册正文仍然只使用用户真实照片。
- 生图资源先作为静态 PNG 接入，暂不引入复杂动画或远程加载。
