import SwiftData
import Foundation

// MARK: - Milestone（里程碑：会走路、第一次叫妈妈…强仪式感）
/// 可从预设模板库选，也可完全自定义。已达成/待达成都在成就墙呈现。
@Model
final class Milestone {
    @Attribute(.unique) var id: UUID
    var remoteId: String?
    var title: String                 // "第一次独立行走"
    var category: String              // 大运动/语言/社交/认知…
    var emoji: String = "🌟"          // 成就墙图标
    var detail: String?               // 描述/当时的故事
    var happenedAt: Date?             // nil = 尚未达成（待解锁）
    var ageDescription: String?       // "1岁11个月" 自动计算展示
    var isCustom: Bool = false        // 是否用户自定义（非预设）
    var ceremonyPlayed: Bool = false  // 是否已播放仪式动画
    var syncStateRaw: String = SyncState.local.rawValue
    var createdAt: Date
    var entry: Entry?

    /// 是否已达成。
    var isAchieved: Bool { happenedAt != nil }
    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .local }
        set { syncStateRaw = newValue.rawValue }
    }

    init(title: String, category: String, emoji: String = "🌟",
         happenedAt: Date? = nil, isCustom: Bool = false) {
        self.id = UUID()
        self.title = title
        self.category = category
        self.emoji = emoji
        self.happenedAt = happenedAt
        self.isCustom = isCustom
        self.createdAt = .now
    }
}

// MARK: - 里程碑预设库
/// 出厂内置的成长里程碑，按发展领域分类。用户可一键添加并标记达成。
struct MilestoneTemplate: Identifiable, Hashable, Sendable {
    let id = UUID()
    let title: String
    let category: String
    let emoji: String

    static let categories = ["大运动", "精细动作", "语言表达", "社交情感", "认知探索", "生活自理", "饮食成长", "睡眠作息", "健康护理", "外出旅行", "艺术音乐", "家庭关系"]

    static let presets: [MilestoneTemplate] = [
        // 大运动
        .init(title: "第一次抬头", category: "大运动", emoji: "🐣"),
        .init(title: "第一次趴着撑起胸口", category: "大运动", emoji: "💪"),
        .init(title: "第一次翻身", category: "大运动", emoji: "🔄"),
        .init(title: "第一次连续翻滚", category: "大运动", emoji: "🌀"),
        .init(title: "第一次独坐", category: "大运动", emoji: "🪑"),
        .init(title: "第一次从躺着坐起来", category: "大运动", emoji: "🙆"),
        .init(title: "第一次爬行", category: "大运动", emoji: "🐛"),
        .init(title: "第一次扶站", category: "大运动", emoji: "🧍"),
        .init(title: "第一次独立站立", category: "大运动", emoji: "🧍"),
        .init(title: "第一次扶着家具走", category: "大运动", emoji: "🛋️"),
        .init(title: "第一次独立行走", category: "大运动", emoji: "👣"),
        .init(title: "第一次小跑", category: "大运动", emoji: "🏃"),
        .init(title: "第一次双脚跳", category: "大运动", emoji: "🐇"),
        .init(title: "第一次踢球", category: "大运动", emoji: "⚽️"),
        .init(title: "第一次上下楼梯", category: "大运动", emoji: "🪜"),

        // 精细动作
        .init(title: "第一次抓握", category: "精细动作", emoji: "✋"),
        .init(title: "第一次双手递东西", category: "精细动作", emoji: "🤲"),
        .init(title: "第一次捏起小东西", category: "精细动作", emoji: "👌"),
        .init(title: "第一次拍手", category: "精细动作", emoji: "👏"),
        .init(title: "第一次挥手拜拜", category: "精细动作", emoji: "👋"),
        .init(title: "第一次自己拿勺", category: "精细动作", emoji: "🥄"),
        .init(title: "第一次自己翻书", category: "精细动作", emoji: "📖"),
        .init(title: "第一次搭积木", category: "精细动作", emoji: "🧱"),
        .init(title: "第一次叠高高", category: "精细动作", emoji: "🏗️"),
        .init(title: "第一次涂鸦", category: "精细动作", emoji: "🖍️"),
        .init(title: "第一次贴贴纸", category: "精细动作", emoji: "⭐️"),
        .init(title: "第一次穿珠子", category: "精细动作", emoji: "📿"),

        // 语言表达
        .init(title: "第一次咿呀学语", category: "语言表达", emoji: "🫧"),
        .init(title: "第一次叫妈妈", category: "语言表达", emoji: "🗣️"),
        .init(title: "第一次叫爸爸", category: "语言表达", emoji: "🗣️"),
        .init(title: "第一次叫姥姥", category: "语言表达", emoji: "👵"),
        .init(title: "第一次说自己的名字", category: "语言表达", emoji: "🌷"),
        .init(title: "第一次说不要", category: "语言表达", emoji: "🙅"),
        .init(title: "第一次说谢谢", category: "语言表达", emoji: "🙏"),
        .init(title: "第一次说完整句子", category: "语言表达", emoji: "💬"),
        .init(title: "第一次讲小故事", category: "语言表达", emoji: "📚"),
        .init(title: "第一次唱歌", category: "语言表达", emoji: "🎵"),
        .init(title: "第一次背儿歌", category: "语言表达", emoji: "🎶"),
        .init(title: "第一次问为什么", category: "语言表达", emoji: "❓"),

        // 社交情感
        .init(title: "第一次微笑", category: "社交情感", emoji: "😊"),
        .init(title: "第一次大笑", category: "社交情感", emoji: "😆"),
        .init(title: "第一次认生", category: "社交情感", emoji: "🫣"),
        .init(title: "第一次主动拥抱", category: "社交情感", emoji: "🤗"),
        .init(title: "第一次亲亲家人", category: "社交情感", emoji: "😘"),
        .init(title: "第一次安慰别人", category: "社交情感", emoji: "🫶"),
        .init(title: "第一次和小朋友玩", category: "社交情感", emoji: "🧒"),
        .init(title: "第一次分享玩具", category: "社交情感", emoji: "🧸"),
        .init(title: "第一次表达害怕", category: "社交情感", emoji: "🥺"),
        .init(title: "第一次表达喜欢", category: "社交情感", emoji: "💗"),
        .init(title: "第一次自己道歉", category: "社交情感", emoji: "🌱"),

        // 认知探索
        .init(title: "第一次盯着光影看", category: "认知探索", emoji: "✨"),
        .init(title: "第一次认出镜子里的自己", category: "认知探索", emoji: "🪞"),
        .init(title: "第一次找到藏起来的东西", category: "认知探索", emoji: "🔎"),
        .init(title: "第一次数数", category: "认知探索", emoji: "🔢"),
        .init(title: "第一次认颜色", category: "认知探索", emoji: "🌈"),
        .init(title: "第一次认形状", category: "认知探索", emoji: "🔺"),
        .init(title: "第一次拼拼图", category: "认知探索", emoji: "🧩"),
        .init(title: "第一次假装做饭", category: "认知探索", emoji: "🍳"),
        .init(title: "第一次认识动物", category: "认知探索", emoji: "🐶"),
        .init(title: "第一次分清大小", category: "认知探索", emoji: "⚖️"),
        .init(title: "第一次自己解决小问题", category: "认知探索", emoji: "💡"),

        // 生活自理
        .init(title: "第一次自己吃饭", category: "生活自理", emoji: "🍚"),
        .init(title: "第一次自己喝水", category: "生活自理", emoji: "🥤"),
        .init(title: "第一次自己脱袜子", category: "生活自理", emoji: "🧦"),
        .init(title: "第一次自己穿鞋", category: "生活自理", emoji: "👟"),
        .init(title: "第一次自己洗手", category: "生活自理", emoji: "🫧"),
        .init(title: "第一次自己刷牙", category: "生活自理", emoji: "🪥"),
        .init(title: "第一次配合洗澡", category: "生活自理", emoji: "🛁"),
        .init(title: "第一次戒纸尿裤", category: "生活自理", emoji: "🚽"),
        .init(title: "第一次自己收玩具", category: "生活自理", emoji: "🧺"),
        .init(title: "第一次自己选衣服", category: "生活自理", emoji: "👗"),

        // 饮食成长
        .init(title: "第一次喝奶以外的水", category: "饮食成长", emoji: "💧"),
        .init(title: "第一次吃米糊", category: "饮食成长", emoji: "🥣"),
        .init(title: "第一次吃蛋黄", category: "饮食成长", emoji: "🥚"),
        .init(title: "第一次吃水果泥", category: "饮食成长", emoji: "🍎"),
        .init(title: "第一次吃蔬菜泥", category: "饮食成长", emoji: "🥦"),
        .init(title: "第一次吃肉泥", category: "饮食成长", emoji: "🍖"),
        .init(title: "第一次尝试手指食物", category: "饮食成长", emoji: "🥕"),
        .init(title: "第一次自己啃玉米", category: "饮食成长", emoji: "🌽"),
        .init(title: "第一次吃面条", category: "饮食成长", emoji: "🍜"),
        .init(title: "第一次在外面吃饭", category: "饮食成长", emoji: "🍽️"),

        // 睡眠作息
        .init(title: "第一次睡整觉", category: "睡眠作息", emoji: "🌙"),
        .init(title: "第一次自己入睡", category: "睡眠作息", emoji: "😴"),
        .init(title: "第一次固定午睡", category: "睡眠作息", emoji: "🛌"),
        .init(title: "第一次在外面睡着", category: "睡眠作息", emoji: "🚗"),
        .init(title: "第一次不抱睡", category: "睡眠作息", emoji: "🌛"),
        .init(title: "第一次睡自己的小床", category: "睡眠作息", emoji: "🧸"),

        // 健康护理
        .init(title: "第一颗牙冒出来", category: "健康护理", emoji: "🦷"),
        .init(title: "第一次剪指甲很配合", category: "健康护理", emoji: "✂️"),
        .init(title: "第一次量身高体重", category: "健康护理", emoji: "📏"),
        .init(title: "第一次体检", category: "健康护理", emoji: "🩺"),
        .init(title: "第一次打疫苗很勇敢", category: "健康护理", emoji: "💉"),
        .init(title: "第一次发烧康复", category: "健康护理", emoji: "🌡️"),
        .init(title: "第一次看牙医", category: "健康护理", emoji: "🪥"),
        .init(title: "第一次自己擤鼻涕", category: "健康护理", emoji: "🤧"),

        // 外出旅行
        .init(title: "第一次出门散步", category: "外出旅行", emoji: "🚶"),
        .init(title: "第一次去公园", category: "外出旅行", emoji: "🌳"),
        .init(title: "第一次坐车", category: "外出旅行", emoji: "🚗"),
        .init(title: "第一次坐火车", category: "外出旅行", emoji: "🚄"),
        .init(title: "第一次坐飞机", category: "外出旅行", emoji: "✈️"),
        .init(title: "第一次看海", category: "外出旅行", emoji: "🌊"),
        .init(title: "第一次看雪", category: "外出旅行", emoji: "❄️"),
        .init(title: "第一次动物园", category: "外出旅行", emoji: "🦁"),
        .init(title: "第一次旅行过夜", category: "外出旅行", emoji: "🧳"),

        // 艺术音乐
        .init(title: "第一次跟着音乐摇摆", category: "艺术音乐", emoji: "💃"),
        .init(title: "第一次敲小鼓", category: "艺术音乐", emoji: "🥁"),
        .init(title: "第一次画圆圈", category: "艺术音乐", emoji: "⭕️"),
        .init(title: "第一次用颜料画画", category: "艺术音乐", emoji: "🎨"),
        .init(title: "第一次跳舞", category: "艺术音乐", emoji: "🩰"),
        .init(title: "第一次看绘本入迷", category: "艺术音乐", emoji: "📚"),
        .init(title: "第一次做手工", category: "艺术音乐", emoji: "✂️"),

        // 家庭关系
        .init(title: "第一次和妈妈自拍", category: "家庭关系", emoji: "🤳"),
        .init(title: "第一次和爸爸玩疯", category: "家庭关系", emoji: "👨"),
        .init(title: "第一次和姥姥聊天", category: "家庭关系", emoji: "👵"),
        .init(title: "第一次叫家人名字", category: "家庭关系", emoji: "🏠"),
        .init(title: "第一次参加家庭聚会", category: "家庭关系", emoji: "👨‍👩‍👧"),
        .init(title: "第一次给家人礼物", category: "家庭关系", emoji: "🎁"),
        .init(title: "第一次说我爱你", category: "家庭关系", emoji: "❤️"),
    ]
}
