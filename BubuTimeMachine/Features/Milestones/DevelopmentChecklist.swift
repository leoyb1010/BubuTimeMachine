import SwiftUI
import SwiftData

// MARK: - 发育参考清单（CDC「Learn the Signs. Act Early.」2022 版）
/// 静态参考清单：按 CDC 2022 修订版各月龄清单逐条翻译，不增删临床判断。
/// CDC 说明：清单列的是大多数孩子（75% 及以上）到这个月龄能做到的事。
/// 勾选只存在本机 UserDefaults（按条目 id），不改任何数据模型。

nonisolated enum DevDomain: String, CaseIterable, Sendable, Identifiable {
    case social, language, cognitive, movement
    var id: String { rawValue }
    var title: String {
        switch self {
        case .social: "社交 / 情绪"
        case .language: "语言 / 沟通"
        case .cognitive: "认知（学习、思考、解决问题）"
        case .movement: "运动 / 身体发育"
        }
    }
    var symbol: String {
        switch self {
        case .social: "heart.fill"
        case .language: "bubble.left.and.bubble.right.fill"
        case .cognitive: "lightbulb.fill"
        case .movement: "figure.walk"
        }
    }
}

nonisolated struct DevChecklistItem: Identifiable, Sendable, Hashable {
    let id: String
    let domain: DevDomain
    let text: String
    /// 和第二大脑确认过的“第一次”做粗匹配的关键词（中英文都收）。
    let keywords: [String]
}

nonisolated struct DevChecklistBand: Identifiable, Sendable, Hashable {
    let months: Int
    let items: [DevChecklistItem]
    var id: Int { months }
    var title: String {
        months % 12 == 0 ? "\(months / 12) 岁" : "\(months) 个月"
    }
}

nonisolated enum DevelopmentChecklist {
    static let bandMonths = [12, 15, 18, 24, 30, 36, 48, 60]

    /// 当前要看的清单：正在走向的那一档（月龄 ≤ 档位的最小一档），超过 60 个月就停在 60。
    static func currentBandIndex(ageMonths: Int) -> Int {
        bandMonths.firstIndex { ageMonths <= $0 } ?? bandMonths.count - 1
    }

    /// 上一档、当前、下一档（边界时少一档）。
    static func visibleBands(ageMonths: Int) -> [DevChecklistBand] {
        let current = currentBandIndex(ageMonths: ageMonths)
        let range = max(0, current - 1)...min(bands.count - 1, current + 1)
        return Array(bands[range])
    }

    static func matches(_ item: DevChecklistItem, texts: [String]) -> Bool {
        guard !item.keywords.isEmpty else { return false }
        return texts.contains { text in
            let lowered = text.lowercased()
            return item.keywords.contains { lowered.contains($0.lowercased()) }
        }
    }

    private static func make(_ months: Int, _ groups: [(DevDomain, [(String, [String])])]) -> DevChecklistBand {
        var items: [DevChecklistItem] = []
        for (domain, entries) in groups {
            for (index, entry) in entries.enumerated() {
                items.append(DevChecklistItem(id: "cdc\(months)-\(domain.rawValue)-\(index + 1)",
                                              domain: domain, text: entry.0, keywords: entry.1))
            }
        }
        return DevChecklistBand(months: months, items: items)
    }

    static let bands: [DevChecklistBand] = [
        make(12, [
            (.social, [("和你玩游戏，比如“拍手歌”（pat-a-cake）", ["拍手歌", "pat-a-cake"])]),
            (.language, [
                ("会挥手“拜拜”", ["拜拜", "挥手", "wave", "bye"]),
                ("会叫“妈妈”“爸爸”或别的专属称呼", ["叫妈妈", "叫爸爸", "mama", "dada"]),
                ("听得懂“不”（你说“不”时会稍停一下或停下来）", []),
            ]),
            (.cognitive, [
                ("会把东西放进容器，比如把积木放进杯子", ["放进", "put in"]),
                ("会去找看着你藏起来的东西，比如毯子下面的玩具", ["找到藏", "躲猫猫", "peekaboo"]),
            ]),
            (.movement, [
                ("能扶着东西站起来", ["扶站", "pull to stand"]),
                ("能扶着家具走", ["扶着家具", "cruising"]),
                ("你扶着杯子时，能用没有盖子的杯子喝水", ["杯子喝水", "open cup"]),
                ("能用拇指和食指捏起东西，比如小块食物", ["捏起", "pincer"]),
            ]),
        ]),
        make(15, [
            (.social, [
                ("玩的时候模仿别的小朋友，比如看到别的孩子从容器里拿玩具，也跟着拿", []),
                ("把自己喜欢的东西拿给你看", []),
                ("高兴时会拍手", ["拍手", "clap"]),
                ("抱抱毛绒娃娃或别的玩具", ["抱娃娃", "hug toy"]),
                ("对你表达亲昵（抱抱、依偎或亲亲）", ["亲亲", "拥抱", "kiss", "hug"]),
            ]),
            (.language, [
                ("除了“妈妈”“爸爸”，尝试说一两个词，比如用“ba”表示球、“da”表示狗", ["说话", "first word"]),
                ("你说出熟悉物品的名字时，会去看它", []),
                ("能听从“手势 + 话语”的指令，比如你伸出手说“把玩具给我”，会把玩具递给你", []),
                ("会用手指着要东西，或用手指求助", ["指东西", "point"]),
            ]),
            (.cognitive, [
                ("尝试用正确的方式使用东西，比如电话、杯子或书", []),
                ("能把至少两个小物件叠起来，比如积木", ["积木", "叠高", "stack", "block"]),
            ]),
            (.movement, [
                ("能自己走几步", ["走路", "迈步", "walk", "first step"]),
                ("会用手指拿东西自己吃", ["手指食物", "finger food"]),
            ]),
        ]),
        make(18, [
            (.social, [
                ("会走开一点，但会回头确认你就在附近", []),
                ("用手指指给你看有趣的东西", ["point"]),
                ("伸出手让你帮她洗手", ["洗手", "wash hand"]),
                ("和你一起看几页书", ["看书", "绘本", "book"]),
                ("你给她穿衣服时会帮忙，比如把胳膊伸进袖子、抬起脚", []),
            ]),
            (.language, [
                ("除了“妈妈”“爸爸”，尝试说三个或更多的词", []),
                ("不用手势也能听懂一步指令，比如你说“给我”，会把玩具递给你", []),
            ]),
            (.cognitive, [
                ("模仿你做家务，比如用扫帚扫地", ["扫地", "家务", "sweep", "chore"]),
                ("用简单的方式玩玩具，比如推小汽车", ["推小车", "toy car"]),
            ]),
            (.movement, [
                ("不扶任何人或东西就能走路", ["独立行走", "自己走", "walk"]),
                ("会涂鸦", ["涂鸦", "scribble"]),
                ("能用没有盖子的杯子喝水，有时会洒", ["杯子喝水", "open cup"]),
                ("用手指自己吃东西", ["自己吃", "self-feed"]),
                ("尝试用勺子", ["勺", "spoon"]),
                ("不用帮忙就能爬上爬下沙发或椅子", ["爬上", "climb"]),
            ]),
        ]),
        make(24, [
            (.social, [
                ("注意到别人受伤或难过，比如有人哭时会停下来或露出难过的样子", ["安慰", "comfort"]),
                ("在新情况里会看你的脸色，决定自己怎么反应", []),
            ]),
            (.language, [
                ("你问“小熊在哪儿？”时，会指出书里的东西", []),
                ("至少能把两个词连起来说，比如“还要奶”", ["两个词", "two words"]),
                ("你让她指身体部位时，至少能指出两个", ["身体部位", "body part"]),
                ("除了挥手和用手指，还会用更多手势，比如飞吻或点头表示“是”", ["飞吻", "点头", "blow a kiss", "nod"]),
            ]),
            (.cognitive, [
                ("一只手拿着东西、另一只手操作，比如拿着容器把盖子打开", []),
                ("尝试按玩具上的开关、旋钮或按钮", ["按钮", "button", "switch"]),
                ("同时玩不止一个玩具，比如把玩具食物放在玩具盘子上", ["过家家", "pretend"]),
            ]),
            (.movement, [
                ("会踢球", ["踢球", "kick"]),
                ("会跑", ["跑步", "小跑", "会跑"]),
                ("能走（不是爬）上几级台阶，扶不扶都可以", ["台阶", "楼梯", "stairs"]),
                ("会用勺子吃饭", ["勺", "spoon"]),
            ]),
        ]),
        make(30, [
            (.social, [
                ("在别的小朋友旁边玩，有时也会一起玩", ["和小朋友玩", "play with"]),
                ("会说“看我！”来展示自己能做什么", []),
                ("你说“收拾时间到了”时，能跟着简单的日常流程，比如帮忙收玩具", ["收玩具", "clean up"]),
            ]),
            (.language, [
                ("会说大约 50 个词", []),
                ("能把两个或更多词连起来说，其中有一个动作词，比如“狗狗跑”", []),
                ("你指着书问“这是什么？”时，能说出名字", []),
                ("会说“我”“我们”这类词", []),
            ]),
            (.cognitive, [
                ("会用东西假装，比如把积木当食物喂娃娃", ["假装", "过家家", "pretend"]),
                ("会简单地解决问题，比如站上小凳子去够东西", []),
                ("能听懂两步指令，比如“把玩具放下，然后关上门”", []),
                ("至少认识一种颜色，比如你问“哪个是红色？”时，能指出红色蜡笔", ["颜色", "color"]),
            ]),
            (.movement, [
                ("会用手拧东西，比如转门把手、拧开盖子", ["拧", "twist"]),
                ("能自己脱掉一些衣服，比如宽松的裤子或敞开的外套", ["脱衣", "脱裤", "undress"]),
                ("能双脚离地跳起来", ["双脚跳", "jump"]),
                ("你读书给她听时，能一页一页地翻书", ["翻书", "turn page"]),
            ]),
        ]),
        make(36, [
            (.social, [
                ("你离开后（比如送去托育时），10 分钟内能平静下来", ["入园", "幼儿园"]),
                ("会注意到别的小朋友，并加入他们一起玩", ["和小朋友玩", "play with"]),
            ]),
            (.language, [
                ("能和你对话，至少来回两轮", []),
                ("会问“谁”“什么”“哪里”或“为什么”，比如“妈妈在哪儿？”", ["为什么", "why"]),
                ("被问到时，能说出图片或书里正在发生的动作，比如“跑”“吃”“玩”", []),
                ("被问到时，能说出自己的名字", ["名字", "own name"]),
                ("大部分时候，说话能让别人听懂", []),
            ]),
            (.cognitive, [
                ("你示范后，能画一个圆", ["画圆", "circle"]),
                ("你提醒后，会避开烫的东西，比如炉子", []),
            ]),
            (.movement, [
                ("能把东西串起来，比如大珠子或通心粉", ["穿珠", "串珠", "bead"]),
                ("能自己穿上一些衣服，比如宽松的裤子或外套", ["穿衣", "穿裤", "dress"]),
                ("会用叉子", ["叉子", "fork"]),
            ]),
        ]),
        make(48, [
            (.social, [
                ("玩的时候会假装成别的角色（老师、超级英雄、小狗）", ["角色扮演", "假装", "pretend"]),
                ("身边没有小朋友时，会要求去找小朋友玩，比如“我可以去找小明玩吗？”", []),
                ("会安慰受伤或难过的人，比如抱抱正在哭的朋友", ["安慰", "comfort"]),
                ("会避开危险，比如在游乐场不从很高的地方往下跳", []),
                ("喜欢当“小帮手”", ["帮忙", "helper"]),
                ("会根据所在场合调整行为（比如礼拜场所、图书馆、游乐场）", []),
            ]),
            (.language, [
                ("能说四个或更多词的句子", ["句子", "sentence"]),
                ("能说出歌曲、故事或童谣里的一些词", ["儿歌", "童谣", "唱歌", "song", "rhyme"]),
                ("能讲一件当天发生的事，比如“我踢足球了”", []),
                ("能回答简单问题，比如“外套是干什么用的？”“蜡笔是干什么用的？”", []),
            ]),
            (.cognitive, [
                ("能说出几种物品的颜色", ["颜色", "color"]),
                ("能说出熟悉的故事接下来会发生什么", []),
                ("能画出有三个或更多身体部位的人", ["画人", "draw a person"]),
            ]),
            (.movement, [
                ("大多数时候能接住大球", ["接球", "catch"]),
                ("在大人看着时，能自己盛饭或倒水", ["倒水", "pour"]),
                ("能解开一些纽扣", ["纽扣", "扣子", "button"]),
                ("用手指和拇指握蜡笔或铅笔（不是攥着拳头握）", ["握笔", "pencil", "crayon"]),
            ]),
        ]),
        make(60, [
            (.social, [
                ("和别的小朋友玩游戏时，会遵守规则或轮流", ["轮流", "take turns"]),
                ("会为你唱歌、跳舞或表演", ["唱歌", "跳舞", "表演", "sing", "dance"]),
                ("会在家做简单的家务，比如配对袜子、饭后收拾桌子", ["家务", "chore"]),
            ]),
            (.language, [
                ("能讲一个听来的或自己编的故事，里面至少有两件事，比如小猫被困在树上，消防员救了它", ["讲故事", "story"]),
                ("你读完或讲完故事后，能回答关于故事的简单问题", []),
                ("能把对话聊下去，来回超过三轮", []),
                ("会用或能听出简单的押韵（比如英文的 bat–cat、ball–tall）", ["押韵", "rhyme"]),
            ]),
            (.cognitive, [
                ("能数到 10", ["数数", "count"]),
                ("你指着 1 到 5 之间的数字时，能说出其中一些", ["数字", "number"]),
                ("会用表示时间的词，比如“昨天”“明天”“早上”“晚上”", []),
                ("做活动时能专注 5–10 分钟，比如听故事或做手工（看屏幕不算）", ["手工", "craft"]),
                ("能写出自己名字里的一些字母", ["写名字", "write name"]),
                ("你指着字母时，能认出其中一些", ["字母", "letter"]),
            ]),
            (.movement, [
                ("能扣上一些纽扣", ["纽扣", "扣子", "button"]),
                ("能单脚跳", ["单脚跳", "hop"]),
            ]),
        ]),
    ]
}

// MARK: - 勾选存储（UserDefaults，按条目 id）

nonisolated enum DevChecklistTicks {
    static let key = "growth.devChecklist.ticks.v1"
    static func decode(_ raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }
    static func encode(_ ids: Set<String>) -> String { ids.sorted().joined(separator: ",") }
}

private func ageInMonths(_ birthday: Date?) -> Int? {
    guard let birthday else { return nil }
    let cal = Calendar.current
    return max(0, cal.dateComponents([.month], from: cal.startOfDay(for: birthday), to: cal.startOfDay(for: .now)).month ?? 0)
}

// MARK: - 成长页卡片

struct DevelopmentChecklistCard: View {
    @Query private var profiles: [ChildProfile]
    @AppStorage(DevChecklistTicks.key) private var ticksRaw = ""

    var body: some View {
        let age = ageInMonths(profiles.first?.birthday) ?? 12
        let band = DevelopmentChecklist.bands[DevelopmentChecklist.currentBandIndex(ageMonths: age)]
        let ticks = DevChecklistTicks.decode(ticksRaw)
        let done = band.items.filter { ticks.contains($0.id) }.count
        let progress = band.items.isEmpty ? 0 : Double(done) / Double(band.items.count)
        NavigationLink { DevelopmentChecklistView() } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(BubuTheme.Color.mintSurface, lineWidth: 6)
                    Circle().trim(from: 0, to: progress)
                        .stroke(BubuTheme.Color.success, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(BubuMotion.gentle, value: progress)
                    Image(systemName: "checklist")
                        .font(BubuTheme.Font.body.weight(.bold))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text("发育参考清单")
                        .font(BubuTheme.Font.headline)
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Text("\(band.title)清单 · 已勾 \(done)/\(band.items.count) · 仅供参考")
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(BubuTheme.Font.caption.weight(.bold))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
            .padding(16)
            .background(BubuTheme.Color.mintSurface.opacity(0.6),
                        in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
            .bubuCardShadow()
        }
        .buttonStyle(BubuPressableStyle())
    }
}

// MARK: - 清单页

struct DevelopmentChecklistView: View {
    @Query private var profiles: [ChildProfile]
    @Query(sort: \Milestone.createdAt, order: .reverse) private var milestones: [Milestone]
    @AppStorage(DevChecklistTicks.key) private var ticksRaw = ""
    @State private var selectedMonths: Int?
    @State private var tickTrigger = 0
    @Namespace private var chipNamespace

    private var ageMonths: Int { ageInMonths(profiles.first?.birthday) ?? 12 }
    private var bands: [DevChecklistBand] { DevelopmentChecklist.visibleBands(ageMonths: ageMonths) }
    private var currentMonths: Int {
        DevelopmentChecklist.bandMonths[DevelopmentChecklist.currentBandIndex(ageMonths: ageMonths)]
    }
    private var band: DevChecklistBand {
        bands.first { $0.months == (selectedMonths ?? currentMonths) } ?? bands[0]
    }
    private var ticks: Set<String> { DevChecklistTicks.decode(ticksRaw) }

    /// 第二大脑确认过、已在本机点亮的“第一次”（里程碑备注以「来自第二大脑」开头）。
    private var brainTexts: [String] {
        milestones
            .filter { $0.isAchieved && ($0.detail?.hasPrefix(BrainFirstMilestoneWriter.notePrefix) ?? false) }
            .map { $0.title + " " + ($0.detail ?? "") }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BubuTheme.Spacing.l) {
                disclaimerBanner.entranceEffect(index: 0)
                bandPicker.entranceEffect(index: 1)
                progressHeader.entranceEffect(index: 2)
                ForEach(Array(DevDomain.allCases.enumerated()), id: \.element) { index, domain in
                    let items = band.items.filter { $0.domain == domain }
                    if !items.isEmpty {
                        domainSection(domain, items: items).entranceEffect(index: 3 + index)
                    }
                }
                sourceNote
            }
            .padding()
            .bubuContentColumn()
            .animation(BubuMotion.gentle, value: band.months)
        }
        .background(BubuThemedBackground().ignoresSafeArea())
        .navigationTitle("发育参考清单")
        .navigationBarTitleDisplayMode(.inline)
        .bubuSensoryFeedback(.selection, trigger: tickTrigger)
    }

    private var disclaimerBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(BubuTheme.Color.deepRose)
            VStack(alignment: .leading, spacing: 4) {
                Text("仅供参考，不是诊断")
                    .font(BubuTheme.Font.body.weight(.bold))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text("清单列的是大多数孩子（75% 及以上）到这个月龄能做到的事。每个孩子节奏不同，没勾上不代表有问题；如果有担心，请和儿科医生聊聊。")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BubuTheme.Color.butterSurface, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
    }

    private var bandPicker: some View {
        HStack(spacing: 8) {
            ForEach(bands) { b in
                let selected = b.months == band.months
                Button {
                    withAnimation(BubuMotion.quick) { selectedMonths = b.months }
                } label: {
                    VStack(spacing: 1) {
                        Text(b.title)
                            .font(BubuTheme.Font.body.weight(.bold))
                        Text(b.months == currentMonths ? "现在" : (b.months < currentMonths ? "上一阶段" : "下一阶段"))
                            .font(BubuTheme.Font.caption)
                    }
                    .foregroundStyle(selected ? Color.white : BubuTheme.Color.warmBrown)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background {
                        if selected {
                            Capsule().fill(BubuTheme.Color.primary)
                                .matchedGeometryEffect(id: "chip", in: chipNamespace)
                        } else {
                            Capsule().fill(BubuTheme.Color.card)
                        }
                    }
                }
                .buttonStyle(BubuPressableStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .bubuSensoryFeedback(.selection, trigger: band.months)
    }

    private var progressHeader: some View {
        let done = band.items.filter { ticks.contains($0.id) }.count
        return HStack(spacing: 12) {
            BubuMascotBadge(size: 44, expression: done == band.items.count ? .cheer : .happy)
            VStack(alignment: .leading, spacing: 4) {
                Text("布布现在 \(ageMonths) 个月 · 这是\(band.title)清单")
                    .font(BubuTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                ProgressView(value: Double(done), total: Double(max(band.items.count, 1)))
                    .tint(BubuTheme.Color.primary)
                    .animation(BubuMotion.gentle, value: done)
                Text("已经看到 \(done) / \(band.items.count) 项")
                    .font(BubuTheme.Font.body.weight(.bold))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                    .contentTransition(.numericText())
            }
        }
        .padding(14)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
    }

    private func surface(_ domain: DevDomain) -> Color {
        switch domain {
        case .social: BubuTheme.Color.pinkSurface
        case .language: BubuTheme.Color.skySurface
        case .cognitive: BubuTheme.Color.lavSurface
        case .movement: BubuTheme.Color.peachSurface
        }
    }

    private func domainSection(_ domain: DevDomain, items: [DevChecklistItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(domain.title, systemImage: domain.symbol)
                .font(BubuTheme.Font.headline)
                .foregroundStyle(BubuTheme.Color.warmBrown)
                .padding(.bottom, 4)
            ForEach(items) { item in row(item) }
        }
        .padding(14)
        .background(surface(domain).opacity(0.55), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
    }

    private func row(_ item: DevChecklistItem) -> some View {
        let checked = ticks.contains(item.id)
        let seen = DevelopmentChecklist.matches(item, texts: brainTexts)
        return Button {
            var set = ticks
            if checked { set.remove(item.id) } else { set.insert(item.id) }
            withAnimation(BubuMotion.quick) { ticksRaw = DevChecklistTicks.encode(set) }
            tickTrigger += 1
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(checked ? BubuTheme.Color.primary : BubuTheme.Color.secondaryText.opacity(0.5))
                    .symbolEffect(.bounce, value: checked)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.text)
                        .font(BubuTheme.Font.body)
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if seen {
                        Label("第二大脑里见过", systemImage: "sparkles")
                            .font(BubuTheme.Font.caption.weight(.semibold))
                            .foregroundStyle(BubuTheme.Color.deepRose)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(BubuTheme.Color.card.opacity(0.8), in: Capsule())
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? .isSelected : [])
        .accessibilityHint(checked ? "点一下取消勾选" : "点一下勾选，表示已经看到")
    }

    private var sourceNote: some View {
        Text("参考：美国 CDC「Learn the Signs. Act Early.」发育里程碑清单（2022 修订版），中文为家庭自译。勾选只保存在这台手机上。")
            .font(BubuTheme.Font.caption)
            .foregroundStyle(BubuTheme.Color.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
