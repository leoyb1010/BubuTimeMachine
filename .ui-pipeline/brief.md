# UI Brief

## Outcome

- User-visible outcome: iOS 主产品升级为更轻、更系统化的家庭档案；iPad 不是放大的 iPhone，而是可变侧栏、宽屏密度和多窗口工作区。
- Success signal: iPhone/iPad 同一事实库下完成记录、回看、搜索和详情；关键路径有自动化与多尺寸截图证据。

## Users and situation

- Primary users: 日常快速记录的父母，以及需要大字、低认知负担路径的长辈。
- Job to be done: 几秒留下照片/声音/文字，可靠同步，数年后仍能按时间和语义找到。
- Environment and devices: iPhone 为主；iPad 全屏、横竖屏、分屏与多窗口是一等平台。

## Scope

- In scope: 原生 Tab/侧栏、记录入口、首页收敛、时光详情、SwiftData 查询、SpeechAnalyzer、Spotlight/App Entity、iPad Widget、XCUITest、iOS 27 渐进增强。
- Out of scope: 本轮不重写数据库/同步/加密格式；不引入第三方 UI、图片或状态管理依赖；不把未安装的 Xcode 27 当成已验证。

## Facts and constraints

- Product facts: SwiftData 是唯一事实源；PocketBase 是同步层；真实照片、声音、日期和成长事实是设计材料。
- Technical constraints: 当前 Xcode 26.6 / iOS 26.5；deployment target 26.0；iOS 27 分支必须编译器+系统双门禁。
- Accessibility / localization: 中文优先；VoiceOver、Dynamic Type、深色、高对比、减少动态；系统搜索必须可关闭并清除本机索引。

## References

- Product plan: `docs/IOS_NEXT_WAVE_UPGRADE_PLAN_2026-08-29.md`。
- Official direction: Apple 2026 SwiftUI、SwiftData、App Intents、Foundation Models、SpeechAnalyzer。
