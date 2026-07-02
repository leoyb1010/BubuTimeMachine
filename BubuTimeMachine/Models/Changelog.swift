import Foundation

// MARK: - 版本更新记录
/// 结构化的更新日志。每次发版在 `all` 顶部加一条 `ReleaseNote`，
/// 设置页「更新记录」按此展示，升级后弹窗展示最新一条。永不靠记忆、不会乱。
struct ReleaseNote: Identifiable {
    var id: String { version }
    let version: String     // 营销版本号，如 "1.2.0"
    let date: String        // 发布日期 "2026-06-13"
    let title: String       // 一句话主题
    let highlights: [String]// 更新要点
}

enum Changelog {
    /// 倒序维护：最新版本放最前。
    static let all: [ReleaseNote] = [
        ReleaseNote(
            version: "1.2.0",
            date: "2026-06-13",
            title: "家人各自登录 · 桌面小组件更好看",
            highlights: [
                "新增「更新记录」：每次更新都能在设置里查看，升级后自动告诉你更新了什么",
                "家人可以各自登录，署名更清楚；新账号由家里服务器后台创建",
                "服务器已内置，不用再手动填地址，装上即用",
                "桌面小组件加上了布布的头像，支持小/中/大三种尺寸，更精致",
                "设置页底部显示当前版本号"
            ]
        ),
        ReleaseNote(
            version: "1.1.9",
            date: "2026-06-13",
            title: "更丝滑 · 系统级集成 · 性别血型补全",
            highlights: [
                "ProMotion 设备解锁 120Hz，操作更跟手丝滑",
                "桌面/锁屏小组件、灵动岛、控制中心、Siri 全面接入",
                "可在档案里填写性别、血型，身份卡翻面查看",
                "修复上传背景照片把页面撑变形的问题",
                "记录保存、里程碑点亮等动效升级"
            ]
        )
    ]

    /// 最新一版（升级弹窗用）。
    static var latest: ReleaseNote? { all.first }
}
