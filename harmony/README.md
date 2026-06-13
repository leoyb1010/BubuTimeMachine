# 布布时光机 · 鸿蒙端（HarmonyOS NEXT / ArkTS）

iOS 端的鸿蒙原生重写。与 iOS **共用同一套自托管后端**（PocketBase + FastAPI），
客户端用 ArkTS / ArkUI 重写。本目录是一个**真实可编译的 DevEco 工程**。

---

## ✅ 编译验证（已通过）

用本机 DevEco 工具链实测通过：

```
hvigor 6.26.1 + HarmonyOS SDK API 26 + JBR 21
$ ./hvigorw assembleHap --mode module -p product=default
> BUILD SUCCESSFUL
产物：entry/build/default/outputs/default/entry-default-unsigned.hap (~272KB)
ArkTS 编译 0 error。
```

> 本机无华为开发者证书/真机，**未签名、未上真机**。真机运行需在 DevEco 配签名。

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

### 🟡 / ⬜ 待续（诚实标注，**尚未实现**）

| 模块 | 状态 | 说明 |
|---|---|---|
| 同步引擎完整化 | 🟡 | 已通：30s 轮询/前后台启停/登录/推 Entry+Profile/拉取游标。**待补**：媒体文件上传下载、其余 10 个 collection 双向映射、冲突合并细节、待删队列。iOS `SyncEngine.swift`(1183 行) 是范本，按同一模式补。 |
| 媒体（H6） | ⬜ | 录音(AVRecorder)、拍照(Camera Kit)、相册(Photo Picker Kit)、缩略图、波形。需权限链路。 |
| 健康/里程碑/胶囊/相册/AI Studio（H7） | ⬜ | 数据模型已就绪，UI 页面待写。里程碑/胶囊数据驱动，相对快；健康成长曲线鸿蒙无官方图表，可能自绘。 |
| 系统集成（H8） | ⬜ | 服务卡片(≈小组件)、实况窗(≈灵动岛)、意图框架(≈App Intents)。独立 module，需共享数据。 |
| 视觉打磨 | ⬜ | 按 HarmonyOS Design 精修材质/动效（不照抄 Apple）。 |
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
