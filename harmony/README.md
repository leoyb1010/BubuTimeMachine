# 布布时光机 · 鸿蒙端（HarmonyOS NEXT / ArkTS）

iOS 端的鸿蒙原生重写。与 iOS **共用同一套自托管后端**（PocketBase + FastAPI），
客户端用 ArkTS / ArkUI 重写。本目录是一个**真实可编译的 DevEco 工程**。

---

## 编译基线

仓库提供不依赖 DevEco 自动生成 wrapper 的统一构建入口：

```
hvigor 6.26.1 + HarmonyOS 26.0.0 SDK + JBR 21
$ ./scripts/build-local.sh
> BUILD SUCCESSFUL
产物：entry/build/default/outputs/default/entry-default-unsigned.hap
```

当前工程已迁移到 HarmonyOS API 26：

- `build-profile.json5`: `compatibleSdkVersion/targetSdkVersion = 26.0.0`
- `AppScope/app.json5`: `minAPIVersion/targetAPIVersion = 26`

构建默认不带签名，避免把证书路径或口令提交到仓库。安装真机前在 DevEco 的 Project Structure 中配置本机自动签名。

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

### 已补齐（最终轮）

| 模块 | 状态 | 文件 |
|---|---|---|
| 自然语言一句话记录 | ✅ | AIService + HomeView 一句话条（AI 解析，离线降级原文） |
| 成长曲线图（Canvas 自绘） | ✅ | GrowthCurveView（健康页进入） |
| 服务卡片（≈iOS 小组件） | ✅ | BubuFormAbility + widget/pages/BubuCard + form_config.json |
| 智能照片收件箱 | 🟡 | Media Library 扫描 + 持久候选 + 事件分组 + 确认入库；后台扩展与人物识别待补 |
| 家庭问答 / 语义搜图 / 周报 | 🟡 | 已接自托管 AI 端点、真实出处和本地文字降级；待真机生产数据验收 |

### 🟡 / ⬜ 仍待续（长尾）

| 模块 | 状态 | 说明 |
|---|---|---|
| 同步引擎完整化 | 🟡 | 已通：轮询/启停/登录/推 Entry+Profile/拉取游标。**待补**：媒体文件上传下载、其余 collection 双向映射、冲突合并、待删队列。 |
| 疫苗表 UI | 🟡 | DAO 已就绪（vaccine_record + insert/fetch/markDone），列表 UI 待接。 |
| 实况窗（≈灵动岛）/ 意图（≈App Intents） | ⬜ | 鸿蒙 LiveView / InsightIntent，独立能力。 |
| 单元测试 | ⬜ | 对照 iOS WaveNTests。 |

---

## 在 DevEco Studio 里打开 / 继续

1. DevEco Studio → Open → 选 `harmony/` 目录。
2. 首次会提示同步依赖（File → Sync）。
3. 配置签名：File → Project Structure → Signing Configs → 勾选自动签名（需登录华为账号）。
4. 连真机/模拟器 → Run。
5. 首次进 App：首页点「建立布布的档案」填生日 → 即可记录、看时光轴。
6. 在设置 → 服务器中配置家庭服务地址与账号；不要把账号写入源码。

## 命令行编译（复现验证）

```bash
cd harmony
./scripts/build-local.sh
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

> 本机 DevEco 不在默认 `/Applications/DevEco-Studio.app` 时，通过
> `DEVECO_STUDIO_CONTENTS=/path/to/DevEco-Studio.app/Contents ./scripts/build-local.sh` 指定。

## 安全规则

- `build-profile.json5` 只保留无签名构建配置。
- 证书、私钥、口令和本机绝对路径不得提交到 Git。
- 运行 `./scripts/check-repository-hygiene.sh` 可在提交前执行同一套 CI 检查。
- 历史版本曾包含调试签名字段；旧签名必须在开发者后台作废并重新生成。

完整追平状态见 [`PARITY_MATRIX.md`](PARITY_MATRIX.md)。

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
