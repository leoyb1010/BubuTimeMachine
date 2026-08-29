# UI Proof

## Verification scope

- Release level: Level 3（家庭长期数据 + iPhone/iPad）。
- Runtime baseline: Xcode 26.6 / iOS 26.5 Simulator；iOS 27 API 仅编译器门控，待 Xcode 27 shadow build。
- Devices: iPhone 17 Pro、iPad Pro 13-inch；iPad 横屏由 XCUITest 设置 orientation。

## Evidence

- Build: iPhone 17 Pro simulator build succeeded after native Tab, SpeechAnalyzer, Spotlight and responsive changes.
- Unit: 157 项 / 27 套件全绿，包含系统搜索路由/陈旧索引清理、归档统计和 multipart 文件名安全回归。
- UI: UI 数据库与已有模拟器档案隔离；iPhone 5 条 XCUITest（iPad 专属横屏用例按预期跳过）；iPad 5 条全部通过，包含 Spotlight 隐私开关反转；iPhone 17e 核心记录流通过。
- Screenshots: `/tmp/BubuIOS27Evidence/` 保留 baseline 与迭代截图；真实家庭 PII 不提交仓库。
- Accessibility: 记录入口有稳定 identifier/label；系统搜索默认关闭，可在设置中启用并清除索引。
- Performance: 首页由全量 `@Query` 改成最近 12 条 + COUNT/日期范围查询；远程/同步协议未重写。

## Snapshot decisions

- Accepted: 原生系统 Tab、手机 Living Cover、平板宽屏完整身份卡、移除 AI 悬浮球、记录面板 900pt 收口。
- Rejected: iPad 底部空 accessory；已改为宽屏禁用，记录由首页主动作与展开侧栏提供。

## Finish state

**PASS** — Debug clean build、Release build、157 单测、iPhone/iPad/紧凑 iPhone UI Test、iPad 横屏、深浅色/大字号与主要路由截图均通过。Spotlight 索引串行清理、上传边界和独立 UI 数据库已完成二次回归。iOS 27 专属分支仍需 Xcode 27 shadow build；这不会影响当前 iOS 26 正式路径。
