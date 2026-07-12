# 布布时光机 · v1.2 计划：更新记录 + 独立账号 + 小组件美化

> 三个需求的现状分析 + 实施计划。**本文档只分析与规划，不含任何代码改动。**
> 基线：iOS `main`，版本 1.1.9 (build 2026061303)。

---

## 需求一：应用内「版本更新记录」+ 版本号 + 更新弹窗

### 现状
- 版本号在 `project.yml`（`MARKETING_VERSION 1.1.9` / `CURRENT_PROJECT_VERSION`），**App 内任何地方都没显示**。
- 没有更新记录（changelog），每次更新只在 git commit 里，容易乱。
- 没有「更新了什么」的弹窗。

### 目标
1. 设置页底部显示**当前版本号**（如 `v1.1.9 (2026061303)`）。
2. 一个**更新记录页**：按版本倒序列出每版的更新点，随时可查。
3. 升级后**首次启动自动弹窗**：展示本版更新了什么 + 版本号，「知道了」关闭，记住已读不再弹。

### 方案
| 部分 | 做法 |
|---|---|
| 版本号读取 | `Bundle.main` 读 `CFBundleShortVersionString` + `CFBundleVersion`，封装成 `AppVersion` 工具 |
| Changelog 数据源 | 新增 `Changelog.swift`：一个静态数组 `[ReleaseNote]`（版本号 / 日期 / 标题 / 要点[]）。**手写维护**，每次发版加一条。结构化、永不乱。 |
| 更新记录页 | 新增 `WhatsNewView.swift`：List 按版本倒序，每版一个卡片（暖色卡 + 要点列表）。设置页加「更新记录」入口。 |
| 升级弹窗 | App 启动比对 `UserDefaults` 里「上次见过的版本」与当前版本，不一致则弹 `WhatsNewSheet`（只展示最新一版），关闭后写入当前版本。`.sheet` 呈现，首启或全新安装可选择不弹。 |
| 设置页版本行 | 设置页底部「关于」区：版本号 + 「更新记录 ›」+（可选）「布布时光机 · 给布布的成长礼物」 |

### 涉及文件（新增为主，改动小）
- 新增 `Models/Changelog.swift`（数据）
- 新增 `Features/Settings/WhatsNewView.swift`（页面 + 弹窗）
- 新增 `DesignSystem/AppVersion.swift`（版本号工具）
- 改 `Features/Settings/SettingsView.swift`（加版本行 + 入口）
- 改 `App/BubuTimeMachineApp.swift` 或 `RootView`（启动判断是否弹窗）

### 风险
- 极低。纯展示 + UserDefaults 标记，不碰数据/同步。
- 维护纪律：发版时记得在 `Changelog.swift` 加一条（可在文档里立个规矩）。

---

## 需求二：固定服务器信息 + 独立账号系统

### 现状（关键）
- **服务器地址已经是固定默认值**：`ServerConfig.defaultBaseURL = "https://bubu-api.leoyuan.top"`，首次启动即填入（ServerConfig.swift:101/116）。
- 当前「账号」其实是**家庭共享一个 PocketBase 账号**（`users/auth-with-password`）+ 本地角色切换（爸爸/妈妈/姥姥）。`accountEmail`/`accountPassword` 存 UserDefaults + Keychain。
- 设置页可以手填服务器地址/账号/密码 —— 对终端用户来说太技术、易填错。
- Onboarding 没有真正的注册/登录，只建了「家庭成员」本地记录。

### 你的目标拆成两件事
1. **固定服务器** —— 把地址写死进 App，用户不用、也不能改。
2. **独立账号系统** —— 每个家庭/用户有自己的账号，数据隔离。

### 方案 A：固定服务器（低风险，先做）
| 做法 | 说明 |
|---|---|
| 写死 baseURL | `ServerConfig` 把 `baseURLString` 改成**常量**（不再从 UserDefaults 读写、不可改），或保留可改但**设置页隐藏地址输入框**（仅 Debug 下可见）。 |
| 设置页 | 移除/隐藏「服务器地址」输入框；普通用户只看到账号相关。 |
| 好处 | 用户零配置，连不上的概率大降；你长期用这台 mini 当服务器，地址稳定。 |

> ⚠️ 注意：写死后若将来换服务器，需发新版。建议保留一个「高级设置（Debug/长按隐藏入口）」能改地址，兜底。

### 方案 B：独立账号系统（中等工程，核心改造）
这是真正的重头。现状是「全家共享一个账号」，要变成「**注册/登录 → 每账号独立数据**」。

**B-1 账号能力（PocketBase users collection）**
| 能力 | 现状 | 要做 |
|---|---|---|
| 登录 | ✅ auth-with-password 已有 | 包一个友好的登录页 |
| 注册 | ❌ 无 | 调 PocketBase `POST /api/collections/users/records` 创建账号 + 自动登录 |
| 找回密码 | ❌ 无 | PocketBase request-password-reset（可选，二期） |
| 登出 / 切换账号 | ❌ 无 | 清 Keychain + 本地数据隔离 |
| Token 持久化/刷新 | 🟡 部分 | auth refresh，避免频繁重登 |

**B-2 数据隔离（关键，决定架构）**
当前所有 collection（entries/media/childprofile…）是**全家共享**的。独立账号后要决定隔离粒度：
- **方案 B-2a「一账号一家庭」**：每个账号是一个家庭，数据按 `owner`(user id) 过滤。服务端每个 collection 加 `owner` 字段 + List/View 规则 `owner = @request.auth.id`。**推荐**，符合「家庭私密记录」定位。
- **方案 B-2b「家庭 = 多账号共享」**：引入 `family` 概念，多个用户账号属于同一 family，数据按 family 隔离。更复杂，适合「爸爸妈妈各自登录、共享布布」。**更贴合你们多人记录的现状**，但工程量大。

**B-3 客户端流程改造**
- Onboarding 改为：**注册/登录** → 建布布档案 → 进主界面。
- 未登录拦截：没登录只能看本地，登录后才同步。
- 角色（爸爸/妈妈/姥姥）保留，作为「同一家庭内的署名身份」。

**B-4 服务端改造（PocketBase）**
- users collection 开放注册（或邀请制）。
- 各业务 collection 加 `owner`/`family` 字段 + 访问规则（迁移脚本，类似已有的 `add_client_updated_at`）。
- ⚠️ **现有数据迁移**：当前共享数据要归属到某个账号，需一次性 backfill。

### 独立账号的难点与决策点（需你拍板）
1. **隔离粒度**：B-2a（一账号一家庭，简单）还是 B-2b（家庭多账号共享，贴合现状但复杂）？
2. **注册开放度**：任何人可注册？还是邀请码/家庭码加入（防陌生人注册占用你服务器）？
3. **现有数据归属**：你们现在的记录迁到哪个新账号下？
4. **隐私**：自托管服务器 + 真账号，密码/数据安全要求更高（HTTPS 已有，密码走 Keychain）。

### 建议节奏
- **先做方案 A（固定服务器）** —— 1 次小改动，立刻提升易用性。
- **账号系统分两步**：① 先做「注册 + 登录页 + Token 持久化」（不改隔离，仍共享数据，纯改善入口体验）；② 再做「数据隔离 + 服务端 owner 规则 + 数据迁移」（重头，需你定隔离粒度）。

---

## 需求三：小组件美化 + 显示布布头像

### 现状
- 小组件数据 `BubuWidgetData.BubuSnapshot` 字段：name / ageText / daysSinceBirth / daysUntilBirthday / **recentPhotoFileName**（已读最近照片，但卡片没用上）。
- **没有读 `avatarMediaFileName`（布布头像）**。
- 视图（`BubuWidgets.swift`）：Small/Medium/Circular/Rectangular，都只有 SF Symbol + 文字，**无头像、无照片、设计朴素**。

### 目标
- 小组件显示**布布头像**（圆形/圆角）。
- 整体更美观、更高级：背景质感、照片/头像、层次。

### 方案
| family | 现状 | 升级 |
|---|---|---|
| `.systemSmall` | 图标+名字+年龄 | **左上圆形头像** + 名字 + 年龄 + 第N天；暖色渐变背景 |
| `.systemMedium` | 文字+生日大数字 | **头像 + 名字/年龄** 左，生日倒计时环 右；或用最近照片做背景 + 玻璃层叠信息 |
| `.systemLarge`（新增）| 无 | 大头像/最近照片 + 身份卡式信息（最接近 App 内身份卡的高级感） |
| `.accessoryCircular` | 倒计时环 | 不变（锁屏空间小） |
| `.accessoryRectangular` | 年龄行 | 可加迷你头像 |

**数据层**：`BubuSnapshot` 加 `avatarFileName`；`loadSnapshot()` 读 `profile.avatarMediaFileName`；`photoData(fileName:)` 已能从共享容器读图（头像同理）。
**视图层**：用 `Image(uiImage:)` 读头像数据 → `.clipShape(Circle())` + 描边 + 阴影；背景用 `LinearGradient` 暖色（对齐 App 身份卡的渐变质感）。
**前置依赖**：头像文件在 App Group 共享容器里小组件才读得到 —— App Group 已就绪（v1.1.9 做的），头像保存路径要确认在共享容器（大概率已是）。

### 涉及文件
- 改 `BubuWidgets/BubuWidgetData.swift`（加 avatarFileName + 读取）
- 改 `BubuWidgets/BubuWidgets.swift`（各 family 视图加头像 + 美化）

### 风险
- 低。小组件独立 extension，不影响主 App。需真机验证（小组件预览/桌面添加）。

---

## 三个需求的优先级与节奏建议

| 优先级 | 需求 | 工程量 | 风险 | 建议 |
|---|---|---|---|---|
| 🥇 P1 | 需求一：更新记录 + 版本号 + 弹窗 | 小 | 极低 | 先做，立竿见影、防混乱 |
| 🥇 P1 | 需求三：小组件头像 + 美化 | 小 | 低 | 一起做，独立模块 |
| 🥈 P2 | 需求二·A：固定服务器（隐藏地址输入） | 极小 | 低 | 顺手做 |
| 🥉 P3 | 需求二·B：独立账号系统 | **大** | 中高 | 单独立项，需先拍板隔离粒度/注册开放度/数据迁移 |

> 建议先一口气做 **P1+P2（更新记录、小组件美化、固定服务器）** —— 都是低风险、体验立竿见影；**独立账号（P3）单独做**，因为它涉及服务端改造 + 数据迁移 + 你要先决定隔离粒度，是个需要你参与决策的中型项目。

---

## 需要你拍板的决策点（做之前确认）

**需求一**
- 升级弹窗：每次升级都弹，还是只在「大版本」弹？（建议：每次都弹最新一版，1 秒看完）

**需求二（账号）**
- 隔离粒度：**一账号一家庭**（简单）还是 **家庭多账号共享布布**（贴合你们多人记录现状，但复杂）？
- 注册方式：开放注册 / 邀请码 / 家庭码？（防陌生人占用你的 mini 服务器）
- 现有共享数据归属到哪个账号？

**需求三**
- 小组件是否要新增 `.systemLarge`（大尺寸、最能体现高级感）？

---

*本文档基于 main 分支 1.1.9 代码实测生成，未改动任何代码。*
