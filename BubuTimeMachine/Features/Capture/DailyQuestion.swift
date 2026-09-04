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

    /// 上幼儿园之后的题库。
    ///
    /// 这一桶和上面三桶有个根本区别：**问题是问布布本人的，不是问家长的。**
    /// 家长照着念，记录她的原话。
    ///
    /// 为什么必须换口径：入园之后家长每天只看得见早晚那几个小时，白天六成的清醒时间
    /// 是空白。再问家长「今天她最得意的一件事是什么」，家长也不知道——他不在场。
    /// 而 18 年后最值钱的从来不是家长的转述，是她三岁时自己怎么说话。
    private static let kindergarten: [String] = [
        "今天谁和你一起玩？你们玩了什么？",
        "今天老师教了什么歌？唱一句给我听好不好？",
        "今天午饭吃了什么？好吃吗？",
        "今天有小朋友不开心吗？他为什么不开心？",
        "今天你帮了谁？",
        "今天在幼儿园，什么事情最好玩？",
        "今天有没有什么事情让你有一点点害怕？",
        "今天老师夸你了吗？夸你什么？",
        "睡午觉的时候你在想什么？",
        "今天你最想把哪件事讲给妈妈听？",
        "今天你学会了一个新的什么？",
        "幼儿园里你最喜欢待的地方是哪儿？",
        "今天有人和你分享东西吗？",
        "今天你有没有想家？什么时候想的？",
        "今天你说过最长的一句话是什么？",
        "明天你最想在幼儿园做什么？",
        "今天有什么事情你觉得不公平吗？",
        "你们班谁最好笑？他做了什么？",
        "今天你自己做成了什么事？",
        "老师今天讲了什么故事？讲的是谁？",
        "今天你有没有和谁说悄悄话？",
        "今天什么时候你觉得最开心？",
        "今天有没有你不想做但还是做了的事？",
        "如果明天可以带一样东西去幼儿园，你带什么？",
    ]

    /// 取「今天」的问题：先选桶，再以当天日期为种子在桶内轮换。
    /// 全家同一天看到同一题（种子只跟日期走）。
    static func todays(birthday: Date?, schoolStartDate: Date? = nil, on date: Date = .now) -> String {
        let bank = bucket(birthday: birthday, schoolStartDate: schoolStartDate, on: date)
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return bank[abs(day) % bank.count]
    }

    /// 已经开学就一律走幼儿园桶——入园是内容模型的分水岭，比月龄更能决定该问什么。
    /// 没填入园日期时保持原来的月龄分桶，行为不变。
    private static func bucket(birthday: Date?, schoolStartDate: Date?, on date: Date) -> [String] {
        if let start = schoolStartDate,
           AgeCalculator.daysSinceSchoolStart(start, at: date) != nil {
            return kindergarten
        }
        guard let birthday else { return toddler }
        let months = Calendar.current.dateComponents([.month], from: birthday, to: date).month ?? 0
        switch months {
        case ..<13: return infant
        case 13..<37: return toddler
        default: return child
        }
    }
}
