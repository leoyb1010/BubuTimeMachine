# 2.23.0 TestFlight 候选检查

检查日期：2026-10-21（上海）。开发基线：`d99c63e / 2.22.0`；本轮候选：`2.23.0 (2026102101)`。最终已生成通过本地深度签名校验的 App Store 分发 IPA；尚未上传或发布。

本轮未提取或展示私钥、口令、App Store Connect API key，也没有上传构建或邀请测试者。初始签名检查为只读；随后使用现有Xcode账号请求自动补齐分发配置，以进行本地导出。主任务的第 3 次完整 `build-for-testing`、441 项 Unit，以及 iPhone 课程入口/筛选 UI 旅程已通过；这些证据来自本轮资源/版本更新前的生成工程。iPad、后端联调、generic Archive 与分发验证需以主任务最终日志为准。

## 版本与现有发布规范

- `project.yml` 已更新 `MARKETING_VERSION=2.23.0`、`CURRENT_PROJECT_VERSION=2026102101`。主 App、iOS Widget、照片后台扩展、Watch App、Watch Widget 的 Info.plist 都引用这两个变量，未另写不一致的版本。
- `Changelog.swift` 顶部、README、FastAPI 源码版本与 `harmony/release-baselines.json` 的 iOS 基准已同步。HarmonyOS 仍为 `2.15.0 (2026091201)`，`parityVerified=false`；对应 README 和能力矩阵明确新增能力仍待真机验证。
- `2.23.0` 符合当前营销版本格式；`2026102101` 是递增的单整数 build string，符合当前公开的 CFBundleVersion 格式说明。当前文档与旧归档文档的位数描述不同，因此不凭历史文档宣布该候选无效，也不把本地格式检查当成 ASC 接受证明。尚需核对 ASC 中是否已使用该版本/build，并执行 Archive Validate。[CFBundleVersion](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion)、[构建标识与上传](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)。
- 本机工具链为 Xcode 27.1（27A9275）；Apple 2026-10-15 的说明已列出 Xcode 27.1 对 App Store 与内外部 TestFlight 的支持。[ASC 发布说明](https://developer.apple.com/help/app-store-connect/release-notes/)。
- 仓库既有门禁来自 `.github/workflows/ci.yml`：重复源码检查、clean build、Unit、iPhone/iPad 用户路径、源码零 warning、后端及跨端合同检查。现有 `scripts/install-iphone-wifi.sh` 只构建并覆盖安装真机 Debug 包，不是 TestFlight 发布脚本。
- 延续 `docs/RELEASE_2.14.0.md` 的数据保护原则：保持 bundle ID、App Group 与原有存储，不卸载清数据；不把开发签名包或签名材料提交公开仓库。

## 分发签名状态（初始检查与最终结果）

最终结果：使用现有开发者账号的自动配置导出成功，五个bundle均为Apple Distribution签名，App Store描述文件包含App Group，get-task-allow关闭。IPA在非FileProvider临时目录解包后通过codesign深度严格验证。以下证书/profile表记录的是导出前的初始状态。

本机找到 3 个与项目团队匹配的有效 Apple Development 签名身份，证书有效至 2027-06-07；未找到 Apple Distribution 或 iPhone Distribution 签名身份。现有开发签名可用，不代表分发签名链已完成。

| Bundle ID | 本机 App Store 型 profile | 本机开发型 profile |
| --- | --- | --- |
| `com.bubu.timemachine` | 有，2027-06-08 到期 | 有 |
| `com.bubu.timemachine.widgets` | 有，2027-06-08 到期 | 有 |
| `com.bubu.timemachine.photo-upload` | 未发现 | 有 |
| `com.bubu.timemachine.watchkitapp` | 未发现 | 有 |
| `com.bubu.timemachine.watchkitapp.widgets` | 未发现 | 有 |

App Store 型判断依据为 `get-task-allow=false`、无设备清单、非企业全设备、`beta-reports-active=true`；只记录当前本机缓存状态，未查询 Developer Portal。所有匹配 profile 的团队均与项目一致。未在当前仓库或同项目原始检出目录找到可直接复用的 ExportOptions.plist。

- [x] 现有账户Automatic分发导出成功；此前没有本地Distribution identity并不代表无法由Xcode完成分发配置。
- [x] 五个bundle均已取得对应App Store分发描述文件、App Group权益与Apple Distribution签名链；bundle ID保持不变。
- [ ] 核对 ASC 应用记录、开发者协议状态、上传权限和候选 build 是否重复；本轮未读取这些账号状态。

首次本地导出已实际失败：主App与iOS Widget的缓存App Store profile缺少App Group能力/权益；Watch、Watch Widget及PhotoUpload缺少App Store profile。随后以 `-allowProvisioningUpdates` 使用现有账号补齐配置，本地 `destination=export` 导出成功。没有执行上传。

当前 Xcode 的 `-exportOptionsPlist` 帮助支持 `method=app-store-connect`。建议先设置 `destination=export`、`signingStyle=automatic`、`manageAppVersionAndBuildNumber=false`，使本地导出保留已核对的版本，不意外执行上传。`teamID` 取项目现有值。家人若通过外部 TestFlight 测试，不应将包限定为 `testFlightInternalTestingOnly=true`；外部测试按 ASC 流程完成所需 Beta App Review。[TestFlight 流程](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)。

## 已补齐的 required-reason 隐私声明

每个分发 bundle 都新增自己的 `PrivacyInfo.xcprivacy`。`project.yml` 显式将其加入 Resources，同时从目录自动收集项排除，避免重复拷贝。声明只覆盖实际所用 required-reason API；没有通过空的 collected-data 数组宣称“不收集任何数据”。

reason 逐项核对 Apple 当前官方说明：CA92.1 对应本应用偏好；1C8F.1 对应同 App Group 的偏好；C617.1 对应应用/组容器内文件元数据；E174.1 对应写文件前容量判断并产生用户可见行为。未申报未发现的启动时间、键盘或第三方 SDK 包装用途。[官方 API 类别与允许用途](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)。

| Target / manifest | 声明 | 源码依据与用途 |
| --- | --- | --- |
| `BubuTimeMachine/PrivacyInfo.xcprivacy` | UserDefaults：CA92.1、1C8F.1；FileTimestamp：C617.1；DiskSpace：E174.1 | `ServerConfig.swift`、`SharedDefaults.swift` 的本机/共享偏好；`SoundRingView.swift:963` 按容器内缓存时间淘汰；`ArchiveExporter.swift:172` 在空间不足时中止导出并给出可见错误 |
| `BubuWidgets/PrivacyInfo.xcprivacy` | UserDefaults：CA92.1、1C8F.1 | target 实际编入 `BubuSchema.swift:36` 的 standard 健康标志及 `SharedDefaults.swift:287`、`WidgetWallpaper.swift:122` 的 App Group 偏好 |
| `BubuWatch/PrivacyInfo.xcprivacy` | UserDefaults：1C8F.1；FileTimestamp：C617.1 | `WatchSnapshotStore.swift:10` 共享快照；`WatchPhotoStore.swift:67` 读取组容器照片修改时间做 LRU |
| `BubuWatchWidgets/PrivacyInfo.xcprivacy` | UserDefaults：1C8F.1；FileTimestamp：C617.1 | target 同样编入 WatchSnapshotStore / WatchPhotoStore，表盘使用同一组容器 |
| `BubuPhotoUpload/PrivacyInfo.xcprivacy` | `NSPrivacyAccessedAPITypes=[]` | 检查 `BackgroundUploadExtension.swift`、其共享 `BubuStorage.swift` / `PhotoIntakeStore.swift`，未发现官方列出的 required-reason 调用；不推测添加用途 |

已完成：五份 plist 可解析；类别与 reason code 对照官方 DocC 数据验证；XcodeGen spec 中每 target 仅一个显式 manifest 资源；五份 Info.plist 的版本变量一致。正式包仍需检查资源确实进入各 `.app/.appex`，静态 spec 通过不能代替打包验证。Apple 要求在实际使用 API 的 bundle 中提供对应声明。[声明要求](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)、[资源打包要求](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk)。

- [x] 正常开发签名generic Archive成功；五个bundle的PrivacyInfo.xcprivacy、2.23.0/2026102101一致，codesign --verify --deep --strict通过。分发签名仍是独立门禁。
- [ ] 完成 Xcode Organizer 的隐私报告与 Validate，不忽略 manifest 或 required-reason 诊断。
- [ ] 根据实际家庭服务/Gemini 数据流核对 App Privacy 与隐私政策；不能继续宣称新分析完全离线。
- [ ] 核对时间胶囊等加密功能的 ASC 出口合规问卷。当前主 Info.plist 未填写 ITSAppUsesNonExemptEncryption，本轮未猜填该值。

## 本轮提交范围与私有产物

应提交：原生学习入口、解析客户端/缓存、播放器和素材准备修复、时光过滤查询、相应 Swift 测试；`server/ai/learning` 的生产代码与 Web 运行端、服务器合同测试、合成 Web 测试；部署示例、`.env.example` 的配置说明、版本基准、五份隐私声明和本文。

不应提交：真实视频/照片/录音、分析响应、家庭档案、服务端数据目录、运行日志、截图、XCResult、IPA/Archive、临时签名配置、`.p8/.p12/.mobileprovision`、实际 `.env` 或 Python 缓存。

- [x] `git ls-files work` 为空；主任务已在 `.gitignore` 加入 `/work/`，`work/learning-web-proof/*.png` 当前被忽略。
- [x] 根 `.gitignore` 已排除 `__pycache__/`、`*.py[cod]`、`.pytest_cache/`；HTTP测试已移到 `server/ai/tests/learning`，纳入现有CI。
- [x] 显式路径暂存并检查：97个源码/测试/文档文件；真实媒体、SQLite、缓存、实际.env、签名私密材料和构建产物均未入Git。
- [x] `harmony/tests/PlatformVersionConsistency.test.mjs` 通过：project.yml、Changelog 顶部和 iOS baseline 一致，Harmony 自身版本与 `parityVerified=false` 保持真实。

## 交给主任务的剩余门禁

1. 保留已通过的 441 项 Unit 和 iPhone UI 证据；本次资源/版本调整补做 VersionParity、隐私资源及 Archive 检查，无需无理由重跑全套 Unit。后端/Web 合同门禁仍记录主任务的实际结果。
2. 重新生成工程后做真实 iOS Release generic Archive；不把模拟器产物或 `CODE_SIGNING_ALLOWED=NO` 的构建用作分发包。
3. DerivedData/Archive 放在 `/private/tmp` 等非 Documents/FileProvider 路径。本轮已实证 Documents 下生成的 BubuPhotoUpload.appex 被附加 FinderInfo，导致 codesign 失败；不要为此清理用户原件或全仓属性。
4. 确认正式包的两个构建时服务入口为项目批准的 HTTPS 地址，不带 CI 的 `bubu-test.invalid`。部署学习 API、Gemini/第二大脑适配与自动任务，并完成正确家庭、错误家庭、无来源、失败重试和停止任务的验证。
5. 真机验收首次 Bearer→HttpOnly Cookie、账号切换不残留旧解析、来源 hash 变化、时间码播放、图片/视频/语音筛选、日期范围、三种排序、未同步结果和断网状态。
6. 在妈妈/姥姥实际 iPhone 上确认系统满足现有最低要求，并验证打开当天、找历史、暂停与返回；iPad 横屏和大字不能仅以编译通过替代体验。火火兔是否可运行网页仍是独立真机门禁，不据安卓内核直接宣布支持。
7. 验证旧数据覆盖升级：保持原容器、原件与草稿；本轮没有修改 SwiftData Model/schema。停用学习/自动同步任务时保留已发布事实与家庭原件，不删除数据目录作为回退。
8. 最终候选 Archive 经分发签名与 Apple Validate 通过后，才由主任务执行已授权的上传流程；完成 ASC processing、加密问卷、测试分组与必要审核后，才能报告“TestFlight 可安装”。

发布证据应记录候选提交、Archive/IPA 哈希、实际 bundle 版本、签名/Validate 结果、ASC build 处理状态和真实设备回读。源码版本、可用证书、成功上传和测试者能安装是四件不同的事。
