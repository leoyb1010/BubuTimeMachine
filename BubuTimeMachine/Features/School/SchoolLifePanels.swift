import SwiftUI

enum SchoolPalette {
    static let coral = Color(red: 0.97, green: 0.47, blue: 0.51)
    static let orange = Color(red: 1, green: 0.61, blue: 0.35)
    static let green = Color(red: 0.51, green: 0.74, blue: 0.40)
    static let violet = Color(red: 0.62, green: 0.55, blue: 0.90)
    static let ink = BubuTheme.Color.warmBrown
    static let secondary = BubuTheme.Color.secondaryText
    static let mealColors = [coral, orange, green, coral]
}

struct SchoolPanel<Content: View>: View {
    let title: String
    let symbol: String
    var subtitle = ""
    var accent: Color = SchoolPalette.coral
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(accent)
                Text(title).font(.system(.headline, design: .rounded).weight(.bold)).foregroundStyle(SchoolPalette.ink)
                Spacer(minLength: 0)
                if !typeSize.isAccessibilitySize && !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(SchoolPalette.secondary).lineLimit(1).minimumScaleFactor(0.85)
                    Image(systemName: "heart.fill").font(.system(size: 11)).foregroundStyle(SchoolPalette.coral.opacity(0.7))
                }
            }
            content
        }
        .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
        .background(BubuTheme.Color.card.opacity(0.88), in: RoundedRectangle(cornerRadius: 23))
    }
}

struct SchoolMealsPanel: View {
    let report: SchoolDailyReport
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    private let images = ["SchoolBreakfast", "SchoolLunch", "SchoolFruit", "SchoolSnack"]
    var body: some View {
        SchoolPanel(title: "一天四餐", symbol: "fork.knife", subtitle: "好好吃饭，长大有力量") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize >= .xxLarge ? 2 : 4), spacing: 12) {
                ForEach(Array(SchoolReportField.meals.enumerated()), id: \.offset) { index, field in
                    let meal = SchoolMeal(report[field])
                    let fraction = SchoolVisualValue.fraction(meal.amount)
                    let color = SchoolPalette.mealColors[index]
                    VStack(spacing: 5) {
                        ZStack(alignment: .bottom) {
                            Image(images[index]).resizable().scaledToFit().padding(7)
                                .opacity(meal.amount.isEmpty ? 0.45 : 1).accessibilityHidden(true)
                            Text(meal.amount.isEmpty ? "未记录" : meal.amount)
                                .font(.system(.subheadline, design: .rounded).weight(.bold)).monospacedDigit()
                                .foregroundStyle(colorScheme == .dark ? SchoolPalette.ink : (index == 2 ? Color(red: 0.25, green: 0.51, blue: 0.23) : Color(red: 0.65, green: 0.26, blue: 0.27))).padding(.horizontal, 4)
                                .background(BubuTheme.Color.card.opacity(0.93), in: Capsule()).padding(.bottom, 10)
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            Circle().stroke(color.opacity(0.16), lineWidth: 5)
                            if let fraction {
                                Circle().trim(from: 0, to: fraction)
                                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                            }
                        }.padding(3)
                        Text(field.rawValue).font(.system(.caption, design: .rounded).weight(.semibold))
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Text("\(meal.rating.isEmpty ? "未填" : meal.rating) · \(meal.speed.isEmpty ? "未填" : meal.speed)")
                            .font(.system(size: 10)).foregroundStyle(SchoolPalette.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 3)
                            .background(color.opacity(0.10), in: Capsule())
                        if !meal.notes.isEmpty { Text(meal.notes.joined(separator: "；")).font(.caption2) }
                    }.frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct SchoolMilkPanel: View {
    let report: SchoolDailyReport
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        SchoolPanel(title: "喝奶", symbol: "waterbottle", subtitle: "营养满满，快乐成长", accent: .blue) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 8) {
                ForEach(Array([SchoolReportField.milkFirst, .milkSecond].enumerated()), id: \.offset) { index, field in
                    let raw = report[field]
                    let volumeRange = raw.range(of: #"\d+(?:\.\d+)?\s*(?:ml|mL|ML|毫升)"#, options: .regularExpression)
                    let volume = volumeRange.map { String(raw[$0]) }
                    let detail = volumeRange.map { raw.replacingCharacters(in: $0, with: "") } ?? raw
                    HStack(spacing: 8) {
                        Image("SchoolBottle").resizable().scaledToFit().frame(width: 36, height: 52)
                            .saturation(raw.isEmpty ? 0 : 1).opacity(raw.isEmpty ? 0.35 : 1).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("第\(index + 1)次").font(.system(size: 10, weight: .semibold))
                            Text(raw.isEmpty ? "未记录" : (volume ?? "已记录"))
                                .font(.system(.headline, design: .rounded).weight(.bold)).monospacedDigit()
                            if !raw.isEmpty {
                                Text(detail).font(.system(size: 9)).foregroundStyle(SchoolPalette.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(7).frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
                        .background((raw.isEmpty ? SchoolPalette.violet : SchoolPalette.orange).opacity(0.07), in: RoundedRectangle(cornerRadius: 17))
                        .accessibilityElement(children: .combine)
                }
            }
            if !report[.milk].isEmpty { Text(report[.milk]).font(BubuTheme.Font.caption) }
        }
    }
}

struct SchoolNapPanel: View {
    let report: SchoolDailyReport
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        SchoolPanel(title: "午睡", symbol: "moon.stars.fill", subtitle: "充足的睡眠，让宝贝更有活力", accent: SchoolPalette.violet) {
            VStack(spacing: -2) {
                if let nap = SchoolVisualValue.nap(report[.nap]) {
                    HStack(spacing: 8) {
                        if !typeSize.isAccessibilitySize { Image("SchoolMoon").resizable().scaledToFit().frame(width: 36, height: 40).scaleEffect(1.3).accessibilityHidden(true) }
                        endpoint(nap.start, caption: "午睡开始")
                        VStack(spacing: 8) {
                            Text(nap.duration).font(.caption.weight(.bold)).lineLimit(1).minimumScaleFactor(0.8)
                            HStack(spacing: 0) {
                                Circle().frame(width: 7, height: 7)
                                Rectangle().frame(height: 2)
                                Circle().frame(width: 7, height: 7)
                            }.foregroundStyle(SchoolPalette.violet.opacity(0.7))
                        }.frame(maxWidth: .infinity)
                        endpoint(nap.end, caption: "午睡结束")
                        if !typeSize.isAccessibilitySize { Image("SchoolSun").resizable().scaledToFit().frame(width: 36, height: 40).accessibilityHidden(true) }
                    }
                } else {
                    Text(report[.nap].isEmpty ? "午睡时间未记录" : report[.nap]).font(.subheadline)
                }
                Label("睡眠质量：" + (report[.napQuality].isEmpty ? "未记录" : report[.napQuality]), systemImage: "face.smiling.fill")
                    .font(.system(size: 11, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 4)
                    .background(BubuTheme.Color.card.opacity(0.55), in: Capsule())
            }.foregroundStyle(SchoolPalette.violet)
                .padding(.horizontal, 8).padding(.vertical, 5).frame(maxWidth: .infinity)
                .background(SchoolPalette.violet.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
        }
    }
    private func endpoint(_ time: String, caption: String) -> some View {
        VStack(spacing: 3) {
            Text(time).font(.system(.subheadline, design: .rounded).weight(.bold)).monospacedDigit().foregroundStyle(SchoolPalette.ink)
            Text(caption).font(.system(size: 9))
        }
    }
}

struct SchoolTemperaturePanel: View {
    let report: SchoolDailyReport
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        SchoolPanel(title: "体温", symbol: "thermometer.medium", subtitle: "身体棒棒，开心每一天") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: typeSize.isAccessibilitySize ? 1 : 3), spacing: 8) {
                ForEach(Array([SchoolReportField.temperatureAM, .temperatureNoon, .temperaturePM].enumerated()), id: \.offset) { index, field in
                    HStack(spacing: 5) {
                        Image(index == 2 ? "SchoolMoon" : "SchoolSun").resizable().scaledToFit().frame(width: 33, height: 36).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(["早", "中", "晚"][index]).font(.system(size: 10))
                            Text(report[field].isEmpty ? "未记录" : report[field].replacingOccurrences(of: "°C", with: "°"))
                                .font(.system(.subheadline, design: .rounded).weight(.semibold)).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }.frame(maxWidth: .infinity).padding(.vertical, 9).padding(.horizontal, 5)
                        .background((index == 2 ? SchoolPalette.violet : SchoolPalette.green).opacity(0.08), in: Capsule())
                        .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
