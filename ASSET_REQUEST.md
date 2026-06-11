# 布布时光机 · 美术资产需求（交付清单）

> 给负责出图/出声的 agent 或设计师。本 App 是"高级育儿日记本"质感的家庭传家产品，
> 北极星：温暖、高级、姥姥能用、给 18 岁的女儿看的庄重感。**禁止任何第三方库依赖，资产直接进 Asset Catalog / Bundle。**
> 现有主题色板见下方「主题色参考」。

---

## A. 8 张 App 图标（每套主题一枚 + 生日月专属）

**规格：**
- 每枚提供 1024×1024 PNG（无圆角、无 alpha 透明、sRGB），App 会自动套圆角。
- 命名：`AppIcon-coral` / `AppIcon-sky` / `AppIcon-mint` / `AppIcon-lavender` / `AppIcon-peach` / `AppIcon-night` / `AppIcon-cream` / `AppIcon-birthday`。
- 风格统一：**同一个"布布"吉祥物形象**（圆脸、两个小揪揪的婴幼儿，参考现有 BubuMascot 表情体系），居中，背景用对应主题的主色→辅色柔和径向渐变。
- 图标元素克制：吉祥物头像 + 极简点缀（如珊瑚主题加一缕暖光，星夜主题加几颗星，生日款加彩带/小皇冠）。**不要文字、不要复杂场景。**
- 风格基调：手绘绘本质感、低饱和、暖、圆润；不要扁平 material、不要 3D 渲染、不要赛博/科技感。

**每枚的主题氛围：**
| 文件 | 主色调 | 氛围 |
|---|---|---|
| AppIcon-coral | 珊瑚粉 #F28C9E + 暖黄 #F2B705 | 默认款，温暖晨光 |
| AppIcon-sky | 天蓝 #5B8DEF + 浅蓝 #73C2FB | 晴空、通透 |
| AppIcon-mint | 薄荷绿 #5BB98C + 浅绿 #9BE0C0 | 清新、春天 |
| AppIcon-lavender | 薰衣草紫 #8E7CC3 + 浅紫 #C3B1E1 | 安静、梦幻 |
| AppIcon-peach | 蜜桃 #FF9F8E + 浅桃 #FFD3C2 | 柔软、奶感 |
| AppIcon-night | 深紫底 #2B2A3D + 金 #F2B705 | 星夜、睡前，吉祥物闭眼睡颜 |
| AppIcon-cream | 棕墨 #8A6B52 + 米 #C2A079 | 复古绘本、纸感 |
| AppIcon-birthday | 珊瑚 + 彩带多色 | 生日，吉祥物戴小皇冠/有彩带 |

---

## B. 纸纹纹理（2 张可平铺 PNG）

**规格：**
- 128×128 px PNG，**必须四边可无缝平铺（tileable）**，sRGB。
- 命名：`paper-grain.png`（细颗粒噪点）/ `paper-fiber.png`（纤维纸纹）。
- **极淡**：纹理本身近乎中灰，App 端会以 `opacity 0.03–0.05 + blendMode(.multiply)` 叠加。所以纹理对比度要低、不能有明显方向性或重复图案感。
- grain：细沙颗粒，均匀、随机。
- fiber：手工纸纤维丝，轻微长短交错的浅纹理。
- 另需一张反相版本给深色主题：`paper-fiber-light.png`（亮噪点，用于深色背景 `.screen` 叠加）。

---

## C. 声音文件（5 个 .caf，每个 ≤ 50KB）

**规格：**
- 格式 `.caf`（Core Audio Format）或 `.m4a`，单声道，≤ 50KB，时长 0.2–1.5s。
- 命名 + 氛围：
  | 文件 | 时刻 | 声音设计 |
  |---|---|---|
  | `sfx-save.caf` | 保存成功 | 轻快"啵"一声，气泡感、明亮、不刺耳 |
  | `sfx-seal.caf` | 时间胶囊封存 | "咔哒"盖章/封蜡声，有分量感 |
  | `sfx-unlock.caf` | 时间胶囊开启 | 一串温柔风铃/八音盒上行音，0.8–1.2s |
  | `sfx-milestone.caf` | 里程碑点亮 | 短促上行琶音（3–4 个音），喜悦 |
  | `sfx-birthday.caf` | 生日彩蛋 | 一小段欢快铃铛/口琴，1–1.5s |
- 整体风格：**温柔、童趣、不电子、不突兀**，音量适中（会走 ambient 通道、跟随静音键、默认关闭）。
- 不要语音、不要版权音乐采样，纯音效/合成音即可。

---

## 主题色参考（hex）
珊瑚 #F28C9E / 暖黄 #F2B705 / 天蓝 #5B8DEF / 薄荷 #5BB98C / 薰衣草 #8E7CC3 / 蜜桃 #FF9F8E / 星夜底 #2B2A3D / 奶油棕 #8A6B52

## 交付方式
- 图标 PNG 放 `BubuTimeMachine/Assets.xcassets/`（每个建一个 `.appiconset`，或先给散图我来接）。
- 纸纹/声音放 `BubuTimeMachine/Resources/`（散文件即可，我负责进工程）。
