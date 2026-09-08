# UI Proof

## Verification scope

- Release level: Level 3（家庭长期数据 + iPhone/iPad）。
- Runtime baseline: Xcode 26.6 / iOS 26.5 Simulator；iOS 27 API 仅编译器门控，待 Xcode 27 shadow build。
- Devices: iPhone 17 Pro、iPad Pro 13-inch；iPad 横屏由 XCUITest 设置 orientation。

## Evidence

- Build: iPhone 17 Pro simulator build succeeded after native Tab, SpeechAnalyzer, Spotlight and responsive changes.
- Unit: 157 项 / 27 套件全绿，包含系统搜索路由/陈旧索引清理、归档统计和 multipart 文件名安全回归。
- UI: iPhone 5 条 XCUITest 通过（iPad 专属横屏用例按预期跳过）；iPad 5 条全部通过。身份卡测试会断言完整卡与独立翻面按钮存在，正面 → 背面 → 正面状态均可达。
- Screenshots: 标准字号 iPhone 正反面保存在 `/tmp/bubu-identity-standard-final.*`；iPad 正反面与横屏证据保存在最终 xcresult 附件。真实家庭 PII 不提交仓库。
- Accessibility: 身份卡和翻面控制有稳定 identifier/label/value；减少动态效果下关闭入场、3D 动画和镜面高光；系统搜索默认关闭，可在设置中启用并清除索引。
- Performance: 首页由全量 `@Query` 改成最近 12 条 + COUNT/日期范围查询；远程/同步协议未重写。

## Snapshot decisions

- Accepted: 原生系统 Tab、iPhone/iPad 完整双面身份卡、独立稳定的翻面控制、移除 AI 悬浮球、记录面板 900pt 收口。
- Rejected: iPad 底部空 accessory；已改为宽屏禁用，记录由首页主动作与展开侧栏提供。

## Finish state

**PASS** — 2.12.2 Debug clean build 与 Release build 均为零 error/零 warning；157 单测、iPhone 5 项 UI 测试、iPad 5 项 UI 测试、iPad 横屏和身份卡双面截图均通过。标准字号与无障碍大字号都核验过，完整身份卡没有裁切；iOS 27 专属分支仍需未来 Xcode 27 shadow build，这不影响当前 iOS 26 正式路径。


## 2026-09-08 · 2.14.0

- iPhone/iPad 的根导航、身份卡翻面、记录入口、时光搜索、深链、隐私开关实际渲染和 XCUITest 通过。
- 首页文字、日期和导航使用可读强调色；8 套主题的文字色/白字按钮对比测试达到 4.5。
- 记录页去掉重复的大引导卡，照片/视频/文字/语音入口与正文输入更早出现。
- 本轮数据库、同步和加密加固由用户另行明确授权，已单独完成备份/迁移/真机验收。
- 截图与 xcresult 为本机验收材料，未向公开仓库上传真实家庭截图。
- Finish: PASS（已测试的平台和页面范围）；本记录不表示未测试的未来版本或每个外围页面均无缺陷。
