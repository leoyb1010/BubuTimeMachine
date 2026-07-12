# CLAUDE.md

## 项目定位
布布时光机：给女儿布布做的成长记录/时光机 App。原生 SwiftUI + SwiftData，离线优先、自托管、隐私至上，覆盖 iPhone + iPad + Apple Watch(含表盘复杂功能)。真正的用户是未来 18 岁的布布。

## 技术栈与 Target
- Swift 6.0，SWIFT_STRICT_CONCURRENCY=complete，默认 MainActor 隔离；iOS 26.0 / watchOS 11.0
- 工程由 xcodegen 生成：**改工程配置只改 `project.yml`，然后 `xcodegen generate`**（直接改 pbxproj 会被覆盖）
- Target（见 project.yml）：
  - `BubuTimeMachine`（iOS App，com.bubu.timemachine，App Group `group.com.bubu.timemachine`）
  - `BubuWidgetsExtension`（iOS 小组件，复用主 App Models/共享层源文件）
  - `BubuWatch`（watchOS App，`com.bubu.timemachine.watchkitapp`，App Group `group.com.bubu.timemachine.watch`，不用 SwiftData，靠 WatchConnectivity + 本地快照）
  - `BubuWatchWidgets`（表盘复杂功能/Smart Stack）
  - `BubuTimeMachineTests`（单元测试）
- 后端脚手架在 `server/`（PocketBase + FastAPI/DeepSeek），App 默认不配服务器、AI 默认关闭

## 常用命令
```bash
xcodegen generate   # 改 project.yml 或增删文件后必跑

# clean build（验证一律 clean，增量会缓存误报；目标零 error 零 warning）
xcodebuild -project BubuTimeMachine.xcodeproj -scheme BubuTimeMachine \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  clean build 2>&1 | grep -E ": error:|BubuTimeMachine.*: warning:|BUILD SUCCEEDED|BUILD FAILED" | sort -u

# 单元测试（BubuTimeMachine scheme 挂了 BubuTimeMachineTests）
xcodebuild -project BubuTimeMachine.xcodeproj -scheme BubuTimeMachine \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# 跑模拟器 + 截图
APP=$(find ~/Library/Developer/Xcode/DerivedData/BubuTimeMachine-*/Build/Products/Debug-iphonesimulator -name "BubuTimeMachine.app" -maxdepth 1 | head -1)
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null
xcrun simctl install "iPhone 17 Pro" "$APP"
xcrun simctl launch "iPhone 17 Pro" com.bubu.timemachine -uitest-seed -uitest-settings
sleep 4 && xcrun simctl io "iPhone 17 Pro" screenshot /tmp/shot.png
# 截图后 uninstall 清掉，保证首启引导干净
```

## 模拟器视觉验证（DEBUG 启动参数）
GUI 无法脚本点击，用启动参数直达页面（定义在 `App/BubuTimeMachineApp.swift` 与 `RootTabView.swift`，仅 DEBUG 生效）：
- `-uitest-seed`：注入布布档案 + 成员 + 记录 + 里程碑 + 胶囊，跳过引导
- `-uitest-tab N`：直达第 N 个 tab（0记录/1时光轴/2里程碑/3AI工坊/4时间胶囊）
- 直达页面：`-uitest-capsule` / `-uitest-growth` / `-uitest-diary` / `-uitest-settings` / `-uitest-voice` / `-uitest-export` / `-uitest-timeline` / `-uitest-ai` / `-uitest-movie` / `-uitest-report` / `-uitest-capture` / `-uitest-simple`
- 手表端：bundle id `com.bubu.timemachine.watchkitapp`，App Group `group.com.bubu.timemachine.watch`；可用 `xcrun simctl` 往手表模拟器 App Group 容器注入 plist 快照数据后截图验证（本地有专用模拟器 `BubuWatchSim`）

## 当前路线图
来源一：`/Users/leoyuan/Desktop/布布时光机_下一波升级计划.md`
- 零操作记录：相册自动挂载（端侧人脸匹配当天布布照片，一键收进）、通知直接回复「今日一问」、Action Button 按住即录
- 布布问答（RAG）：三年记录变成能对话的记忆，服务端检索 + DeepSeek 组织答案（本波最大创新）
- 姥姥模式：极简大字大按钮 + Dynamic Type 收尾
- 多设备：iPad/旧手机相框模式、Apple TV、CarPlay（依赖家庭推送底座）

来源二：`/Users/leoyuan/Desktop/布布时光机_下一轮计划_手表进阶.md`
- 原生表盘平台不允许；替代三层：Complications + Smart Stack + `.watchface` 分享（"布布表盘"合法形态）
- v1.3 发版全家更新（服务端墓碑删除已生效，旧版必须换）
- 手表补齐：概览页布布头像缩略图、打卡即时进「最近」、录音中断恢复、手表 App Shortcuts
- 家庭推送底座：mini 自托管 ntfy + PocketBase hook
- 每批出口：clean build + 测试全绿 → 模拟器/真机截图核验 → 中文 commit → push → 装机

## 注意事项
- 截图含真实 PII（布布生日、身份证等字段），**对外分享前必须高斯模糊脱敏**
- 数据外发（同步/AI）必须用户显式开启，默认全离线；人脸/图片分析一律端侧
