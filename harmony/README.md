# 布布时光机 · 鸿蒙端（HarmonyOS NEXT / ArkTS）

iOS 端的鸿蒙原生重写。与 iOS **共用同一套自托管后端**（PocketBase + FastAPI），
客户端用 ArkTS / ArkUI 重写。本目录是一个**真实可编译的 DevEco 工程**。

---

## ✅ 编译验证（已通过）

用本机 DevEco 工具链实测通过：

```
hvigor 6.26.1 + HarmonyOS SDK + JBR 21
$ ./hvigorw assembleHap --mode module -p product=default
> BUILD SUCCESSFUL
产物：entry/build/default/outputs/default/entry-default-unsigned.hap (~319KB)
ArkTS 编译 0 error。
```

当前工程目标已对齐本机 DevEco 模拟器 `Pura X Max 6.1.1(24)`：

- `build-profile.json5`: `compatibleSdkVersion/targetSdkVersion = 6.1.1(24)`
- `AppScope/app.json5`: `minAPIVersion/targetAPIVersion = 24`

> DevEco 绿色 Run 若报 `00401019`，通常是 DevEco 当前编译 SDK 的 releaseType 与模拟器 releaseType 预检不一致。底层 `hdc install` 可正常安装启动；也可以在 DevEco SDK Manager 安装与模拟器匹配的 HarmonyOS 6.1.1(API 24) Release 编译 SDK。

---

## 模块完成度

| 模块 | 状态 | 文件 |
|---|---|---|
| 工程骨架/配置/入口 | ✅ 完成 | `AppScope/`、`entry/src/main/module.json5`、`EntryAbility.ets` |
| 枚举（同步态/媒体/角色/心情） | ✅ 完成（值对齐 iOS） | `models/Enums.ets` |
| 数据模型（15 实体） | ✅ 完成 | `models/Models.ets` |
| 年龄计算 | ✅ 完成（逐行对照 iOS） | `models/AgeCalculator.ets` |
| 本地库 RelationalStore + DAO | ✅ 核心完成（Entry/ChildProfile/建表全量） | `data/AppDatabase.ets` |
| 网络层（PocketBase REST） | ✅ 核心完成（鉴权/upsert/增量拉取） | `services/APIClient.ets`、`DTOs.ets` |
| 服务器配置（Preferences） | ✅ 完成 | `services/ServerConfig.ets` |
| 无 UI 写入层 | ✅ 完成 | `services/EntryWriter.ets` |
| 同步引擎 | 🟡 骨架（推送 Entry/Profile + 拉取游标已通；见下） | `sync/SyncEngine.ets` |
| 5 Tab 根导航 | ✅ 完成 | `pages/RootPage.ets` |
| 首页仪表盘 + 身份卡 | ✅ 完成 | `view/HomeView.ets`、`IdentityCard.ets` |
| 记录流程（文字） | ✅ 完成（走 EntryWriter） | `view/HomeView.ets` |
| 时光轴 | ✅ 完成（数据驱动列表） | `view/TimelineView.ets` |
| 布布档案编辑（性别/血型 Picker） | ✅ 完成（对齐 iOS） | `view/ChildProfileView.ets` |
| 主题 token | ✅ 完成 | `theme/BubuTheme.ets` |

### 已补齐（后续轮次）

| 模块 | 状态 | 文件 |
|---|---|---|
| 记录：拍照/选图 | ✅ | HomeView + MediaStore + PhotoViewPicker |
| 记录：录音 | ✅ | AudioRecorder(AVRecorder) + EntryWriter.entryWithPhoto(voice) |
| 时光轴照片显示 + 详情页 | ✅ | TimelineView + EntryDetailView（大图/删除） |
| 照片墙 | ✅ | AlbumView |
| 健康（7类记录） | ✅ | HealthHomeView |
| 里程碑墙（10预置可点亮） | ✅ | MilestonesView |
| 时间胶囊（写信/解锁日） | ✅ | CapsuleView |
| 布布的故事（AI入口） | ✅ | AIStudioView |
| 设置（身份/服务器/同步） | ✅ | SettingsView |
| 家庭成员管理 | ✅ | MembersView |
| 身份卡翻面（性别/血型/出生地） | ✅ | IdentityCard（rotate 动画） |
| UI/动效 | ✅ | clickEffect 按压、列表入场 transition、身份卡渐变质感 |

### 🟡 / ⬜ 仍待续

| 模块 | 状态 | 说明 |
|---|---|---|
| 同步引擎完整化 | 🟡 | 已通：30s 轮询/前后台启停/登录/推 Entry+Profile/拉取游标。**待补**：媒体文件上传下载、其余 collection 双向映射、冲突合并、待删队列。 |
| 自然语言一句话记录 | ⬜ | iOS 的 /parse-natural-capture AI 解析。 |
| 疫苗表 / 成长曲线图 | ⬜ | 健康子模块（曲线需自绘）。 |
| 系统集成（H8） | ⬜ | 服务卡片(≈小组件)、实况窗(≈灵动岛)、意图框架(≈App Intents)。独立 module。 |
| 单元测试 | ⬜ | 对照 iOS WaveNTests。 |

---

## 在 DevEco Studio 里打开 / 继续

1. DevEco Studio → Open → 选 `harmony/` 目录。
2. 首次会提示同步依赖（File → Sync）。
   - ⚠️ `hvigor/hvigor-config.json5` 里依赖指向了**本机 DevEco 路径**（命令行编译需要）。
     在 DevEco 里打开时若报路径问题，删掉该文件的 `dependencies` 两行让 DevEco 用内置版本即可。
3. 配置签名：File → Project Structure → Signing Configs → 勾选自动签名（需登录华为账号）。
4. 连真机/模拟器 → Run。
5. 首次进 App：首页点「建立布布的档案」填生日 → 即可记录、看时光轴。
6. 配服务器同步：（待加设置页 UI）目前 `ServerConfig` 默认空，可在 `ServerConfig.ets` 临时填
   `baseURLString`/`accountEmail`/`accountPassword` 测试，或后续补设置页。

## 命令行编译（复现验证）

```bash
cd harmony
export NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node
export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk
export JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home
export PATH="$NODE_HOME/bin:$JAVA_HOME/bin:$PATH"
./hvigorw assembleHap --mode module -p product=default --no-daemon
```

## 一键安装到当前鸿蒙模拟器

先在 DevEco 启动模拟器，确认 `hdc list targets` 能看到目标，然后：

```bash
cd harmony
./scripts/run-on-harmony-device.sh
```

如有多个设备，可指定目标：

```bash
./scripts/run-on-harmony-device.sh 127.0.0.1:5555
```

> `hvigorw` / `hvigorw.js` / `hvigor/hvigor-wrapper.js` / `local.properties` 已 gitignore，
> 每台机器从 DevEco 生成（或 DevEco 打开工程时自动补）。

---

## 架构对照（iOS → 鸿蒙）

| iOS | 鸿蒙 |
|---|---|
| SwiftUI | ArkUI（ArkTS 声明式） |
| SwiftData @Model | RelationalStore + interface 模型 |
| ModelContainer | AppDatabase 单例 |
| URLSession + Codable | @ohos.net.http + interface DTO |
| UserDefaults/@AppStorage | Preferences |
| SyncEngine | SyncEngine（同协议、同游标 clientUpdatedAt） |
| EntryWriter（无 UI 写入） | EntryWriter（同语义） |

**后端零改动**：PocketBase collection / API 契约 / clientUpdatedAt 增量游标全部沿用。
