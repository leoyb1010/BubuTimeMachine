import SwiftData
import SwiftUI

// MARK: - 布布身份卡（首页小档案）
/// 首页顶部约 110–120pt 的小档案：大头像（柔光环）+ 圆体名字 + 年龄 / 第 N 天 + 2 个信息小签
/// （生日倒计时、最新身高体重或星座）。轻点翻面看性别 / 血型 / 星座 / 出生地。
/// - 只读本机已有数据：ChildProfile、GrowthMeasurement（统一走 GrowthMeasurementResolver）。
/// - 字号最小 12pt；卡面用动态马卡龙柔面（深色压暗同色相 + 米白字），文字对比度两种模式都 ≥ 4.5:1。
/// - 信息小签用流式布局，大字号时自动换行；翻面在 90° 侧立时换面，减少动态效果时直接切换。
struct BubuIdentityCard: View {
    let profile: ChildProfile
    let theme: BubuThemeDefinition
    let mediaStore: MediaStore

    /// 翻面状态由首页持有，避免 iPad 宽屏父布局刷新时把卡片重建回正面。
    @Binding var isFlipped: Bool
    /// 当前绕 Y 轴的角度：0 正对；翻面时先转到 90° 侧立、换面，再从 -90° 转回 0。
    @State private var turn: Double = 0
    @State private var avatar: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query private var measurements: [GrowthMeasurement]

    init(profile: ChildProfile, theme: BubuThemeDefinition, mediaStore: MediaStore, isFlipped: Binding<Bool>) {
        self.profile = profile
        self.theme = theme
        self.mediaStore = mediaStore
        self._isFlipped = isFlipped
    }

    private static let shape = RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous)

    private func cardFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        BubuTheme.Font.scaled(size, weight: weight, design: .rounded, cap: .extraExtraExtraLarge)
    }

    // MARK: 数据

    private var ageText: String {
        AgeCalculator.ageDescription(birthday: profile.birthday, at: .now)
    }

    private var daysText: String {
        "第 \(AgeCalculator.daysSinceBirth(birthday: profile.birthday)) 天"
    }

    /// 生日月：与 AppIconManager.apply(isBirthdayMonth:) 同一条规则，图标与卡片徽章联动。
    private var isBirthdayMonth: Bool {
        Calendar.current.component(.month, from: .now)
            == Calendar.current.component(.month, from: profile.birthday)
    }

    private var birthdayChipText: String {
        let days = AgeCalculator.daysUntilNextBirthday(birthday: profile.birthday)
        return days == 0 ? "今天生日" : "生日还有 \(days) 天"
    }

    private var constellation: String {
        let c = Calendar.current.dateComponents([.month, .day], from: profile.birthday)
        let month = c.month ?? 1, day = c.day ?? 1
        let cuts = [20, 19, 21, 20, 21, 22, 23, 23, 23, 24, 23, 22]
        let names = ["摩羯", "水瓶", "双鱼", "白羊", "金牛", "双子", "巨蟹", "狮子", "处女", "天秤", "天蝎", "射手", "摩羯"]
        return names[day < cuts[month - 1] ? month - 1 : month] + "座"
    }

    /// 最新身高 / 体重（任一存在即显示），没有实测就返回 nil。
    private var growthText: String? {
        func fmt(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...1))) }
        let height = GrowthMeasurementResolver.latestValue(.height, from: measurements).map { "\(fmt($0)) cm" }
        let weight = GrowthMeasurementResolver.latestValue(.weight, from: measurements).map { "\(fmt($0)) kg" }
        let parts = [height, weight].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: 主体

    var body: some View {
        Group {
            if isFlipped { back } else { front }
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Self.shape)
        .onTapGesture { flip() }
        .accessibilityIdentifier("home.identity-card")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isFlipped
            ? "布布身份卡背面，\(backSummary)，轻点翻回正面"
            : "布布身份卡，\(profile.name)，\(ageText)，\(daysText)，\(frontChipSummary)，轻点翻面查看性别、血型、出生地")
        .accessibilityValue(isFlipped ? "背面" : "正面")
        .overlay(alignment: .topTrailing) { flipButton }
        .background { decorativeBackground }
        .clipShape(Self.shape)
        .overlay { Self.shape.stroke(BubuTheme.Color.hairline.opacity(0.45), lineWidth: 0.7) }
        .bubuCardShadow()
        .rotation3DEffect(.degrees(turn), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .bubuSensoryFeedback(.impact(weight: .light), trigger: isFlipped)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .task(id: profile.avatarMediaFileName) { await loadAvatar() }
    }

    private var flipButton: some View {
        Button(action: flip) {
            Image(systemName: isFlipped ? "arrow.uturn.left" : "arrow.triangle.2.circlepath")
                .font(cardFont(13, weight: .bold))
                .foregroundStyle(BubuTheme.Color.primaryInk)
                .frame(width: 32, height: 32)
                .background(BubuTheme.Color.elevatedCard.opacity(0.85), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(4)
        .accessibilityIdentifier("home.identity-card.flip")
        .accessibilityLabel(isFlipped ? "翻回身份卡正面" : "翻看身份卡背面")
    }

    private func flip() {
        guard !reduceMotion else {
            isFlipped.toggle()
            return
        }
        withAnimation(BubuMotion.quick, completionCriteria: .logicallyComplete) {
            turn = 90
        } completion: {
            isFlipped.toggle()
            turn = -90
            withAnimation(BubuMotion.gentle) { turn = 0 }
        }
    }

    // MARK: 正面

    private var front: some View {
        HStack(alignment: .center, spacing: 14) {
            avatarView
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(profile.name)
                        .font(cardFont(23, weight: .heavy))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if isBirthdayMonth {
                        Text("生日月")
                            .font(cardFont(12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(theme.actionFill, in: Capsule())
                    }
                }
                .padding(.trailing, 34)   // 给右上角翻面按钮留位
                Text("\(Text(ageText).fontWeight(.bold).foregroundStyle(BubuTheme.Color.warmBrown)) · \(daysText)")
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .font(cardFont(15, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.numericText())
                FlowLayout(spacing: 6) {
                    chip(symbol: "gift.fill", text: birthdayChipText)
                    if let growthText {
                        chip(symbol: "ruler.fill", text: growthText)
                    } else {
                        chip(symbol: "sparkles", text: constellation)
                    }
                }
            }
        }
    }

    private func chip(symbol: String?, emoji: String? = nil, text: String) -> some View {
        HStack(spacing: 4) {
            if let emoji {
                Text(emoji).font(cardFont(12))
            } else if let symbol {
                Image(systemName: symbol)
                    .font(cardFont(12, weight: .bold))
                    .foregroundStyle(BubuTheme.Color.primaryInk)
            }
            Text(text)
                .font(cardFont(13, weight: .semibold))
                .foregroundStyle(BubuTheme.Color.warmBrown)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(BubuTheme.Color.elevatedCard.opacity(0.78), in: Capsule())
        .overlay { Capsule().stroke(BubuTheme.Color.hairline.opacity(0.35), lineWidth: 0.5) }
    }

    private var frontChipSummary: String {
        [birthdayChipText, growthText ?? constellation].joined(separator: "，")
    }

    // MARK: 背面

    private var back: some View {
        VStack(alignment: .leading, spacing: 0) {
            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    fact("性别", profile.gender)
                    fact("血型", profile.bloodType)
                    fact("星座", constellation)
                }
                GridRow {
                    fact("出生地", profile.birthPlace)
                    fact("生日", profile.birthday.formatted(.dateTime.month().day()))
                    if let highlight = backHighlight {
                        fact(highlight.label, highlight.value)
                    } else {
                        fact("小名", nil)
                    }
                }
            }
            .padding(.trailing, 36)   // 给右上角翻面按钮留位
        }
    }

    private func fact(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(cardFont(12, weight: .semibold))
                .foregroundStyle(BubuTheme.Color.secondaryText)
            Text(value?.isEmpty == false ? value! : "未填写")
                .font(cardFont(15, weight: .bold))
                .foregroundStyle(BubuTheme.Color.warmBrown)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(BubuTheme.Color.elevatedCard.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: BubuTheme.Radius.xs, style: .continuous))
    }

    /// 第六格：上学了印上学天数，否则印小名。
    private var backHighlight: (label: String, value: String)? {
        if let school = AgeCalculator.schoolDescription(schoolStartDate: profile.schoolStartDate) {
            return ("幼儿园", school)
        }
        if let nickname = profile.nickname, !nickname.isEmpty { return ("小名", nickname) }
        return nil
    }

    private var backSummary: String {
        func value(_ v: String?) -> String { v?.isEmpty == false ? v! : "未填写" }
        return "性别\(value(profile.gender))，血型\(value(profile.bloodType))，\(constellation)，出生地\(value(profile.birthPlace))"
    }

    // MARK: 头像

    private var avatarView: some View {
        Group {
            if let avatar {
                Image(uiImage: avatar).resizable().scaledToFill()
            } else {
                BubuMascotBadge(size: 56, expression: .happy)
            }
        }
        .frame(width: 64, height: 64)
        .background(BubuTheme.Color.cream)
        .clipShape(Circle())
        .padding(3)
        .background(BubuTheme.Color.elevatedCard, in: Circle())
        .padding(3)
        .background {
            Circle().fill(AngularGradient(
                colors: [BubuTheme.Color.primary.opacity(0.75), BubuTheme.Color.butter,
                         BubuTheme.Color.pink, BubuTheme.Color.lav, BubuTheme.Color.primary.opacity(0.75)],
                center: .center))
        }
        .shadow(color: BubuTheme.Color.primary.opacity(0.22), radius: 8, y: 3)
        .overlay(alignment: .topTrailing) {
            BubuSparkle(size: 14, color: BubuTheme.Color.butter, animated: !reduceMotion)
                .offset(x: 2, y: -2)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .bottomLeading) {
            BubuSparkle(size: 9, color: BubuTheme.Color.pink, animated: !reduceMotion, delay: 0.6)
                .offset(x: -2, y: 0)
                .accessibilityHidden(true)
        }
    }

    private func loadAvatar() async {
        guard let name = profile.avatarMediaFileName else { avatar = nil; return }
        let url = mediaStore.mediaURL(for: name)
        avatar = await HomeImageDecoder.decode(file: url, maxPixel: 200)
    }

    // MARK: 装饰底

    /// 不透明底 + 动态马卡龙柔面（浅=粉→奶黄，深=压暗同色相）+ 柔光圆斑 + 点阵 + 星点。
    /// 装饰只用低透明度，文字仍落在 warmBrown / secondaryText 可读的范围里。
    private var decorativeBackground: some View {
        ZStack {
            BubuTheme.Color.elevatedCard
            LinearGradient(
                colors: [
                    BubuTheme.Color.pinkSurface.opacity(0.8),
                    BubuTheme.Color.heroSurfaceMid.opacity(0.5),
                    BubuTheme.Color.butterSurface.opacity(0.75),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)
            Canvas { ctx, size in
                let step: CGFloat = 13
                for x in stride(from: size.width * 0.45, through: size.width, by: step) {
                    for y in stride(from: 6, through: size.height, by: step) {
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2.2, height: 2.2)),
                                 with: .color(BubuTheme.Color.heroSurfaceHighlight.opacity(0.55)))
                    }
                }
            }
            .mask(LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .leading, endPoint: .trailing))
        }
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(BubuTheme.Color.heroSurfaceHighlight.opacity(0.45))
                .frame(width: 150, height: 150)
                .blur(radius: 6)
                .offset(x: 50, y: -70)
        }
        .overlay(alignment: .bottomLeading) {
            Circle()
                .fill(BubuTheme.Color.heroSurfaceHighlight.opacity(0.35))
                .frame(width: 110, height: 110)
                .blur(radius: 8)
                .offset(x: -40, y: 55)
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(alignment: .bottom, spacing: 10) {
                BubuSparkle(size: 8, color: BubuTheme.Color.butter, animated: !reduceMotion, delay: 0.3)
                BubuSparkle(size: 13, color: BubuTheme.Color.pink, animated: !reduceMotion, delay: 0.9)
            }
            .padding(.trailing, 18)
            .padding(.bottom, 12)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
