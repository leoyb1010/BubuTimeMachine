import Foundation

// MARK: - 每日一问（Wave K §4.3）
/// 让「不知道记什么」消失：本地题库按布布月龄分桶，以日期为种子轮换，全家同一天看到同一题。
/// 零后端、零 AI 依赖。
enum DailyQuestion {

    /// 按月龄分桶的问题库（宁少勿滥，覆盖常见成长阶段）。
    private static let infant: [String] = [   // 0–12 月
        "今天布布最像哪种小动物？",
        "她今天发出的最可爱的声音是什么？",
        "今天她盯着什么看了好久？",
        "她今天第一次尝了什么味道？",
        "今天谁把她逗笑了，怎么逗的？",
        "她今天睡得香吗，什么姿势？",
        "今天她的小手抓住了什么不肯放？",
        "她今天最讨厌的瞬间是什么？",
    ]
    private static let toddler: [String] = [  // 13–36 月
        "她今天发明了什么新词？",
        "今天她最得意的一件事是什么？",
        "她现在最讨厌什么？",
        "今天她模仿了谁，像不像？",
        "她今天最坚持要做的事是什么？",
        "今天她说的哪句话把你逗乐了？",
        "她今天交了新朋友吗，叫什么？",
        "今天她最舍不得放下的玩具是哪个？",
    ]
    private static let child: [String] = [    // 37 月以上
        "她今天问了什么让你答不上来的问题？",
        "今天她的梦想是什么（可能每天都变）？",
        "她今天最骄傲的作品是什么？",
        "今天她说了什么暖心的话？",
        "她今天最害怕又最想挑战的是什么？",
        "今天她最想和谁一起玩？",
        "她今天学会了什么新本领？",
        "今天她做了什么小大人的事？",
    ]

    /// 取「今天」的问题：先按月龄选桶，再以当天日期为种子在桶内轮换。
    static func todays(birthday: Date?, on date: Date = .now) -> String {
        let bank = bucket(birthday: birthday, on: date)
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return bank[abs(day) % bank.count]
    }

    private static func bucket(birthday: Date?, on date: Date) -> [String] {
        guard let birthday else { return toddler }
        let months = Calendar.current.dateComponents([.month], from: birthday, to: date).month ?? 0
        switch months {
        case ..<13: return infant
        case 13..<37: return toddler
        default: return child
        }
    }
}
