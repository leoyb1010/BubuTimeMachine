import SwiftUI

/// Native, data-driven illustrations: empty data remains empty, never a decorative fake metric.
struct SchoolPanel<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content
    @Environment(AppEnvironment.self) private var env
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(BubuTheme.Font.body.weight(.bold))
                .foregroundStyle(env.theme.theme.textAccent)
            content
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: BubuTheme.Radius.md).stroke(env.theme.theme.primary.opacity(0.12), lineWidth: 1))
    }
}

struct SchoolMealsPanel: View {
    let report: SchoolDailyReport
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let icons = ["🍞", "🍚", "🍎", "🍪"]
    var body: some View {
        SchoolPanel(title: "一天四餐", symbol: "fork.knife") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize >= .xxLarge ? 2 : 4), spacing: 14) {
                ForEach(Array(SchoolReportField.meals.enumerated()), id: \.offset) { index, field in
                    let meal = SchoolMeal(report[field])
                    let fraction = SchoolVisualValue.fraction(meal.amount)
                    VStack(spacing: 7) {
                        ZStack {
                            Circle().fill(BubuTheme.Color.background)
                            Circle().stroke(env.theme.theme.primary.opacity(0.14), lineWidth: 5)
                            if let fraction {
                                Circle().trim(from: 0, to: fraction)
                                    .stroke(env.theme.theme.primary.gradient, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                    .animation(reduceMotion ? nil : BubuMotion.quick, value: fraction)
                            }
                            Text(icons[index]).font(.system(size: 30)).opacity(meal.amount.isEmpty ? 0.4 : 1)
                                .accessibilityHidden(true)
                        }.frame(width: 60, height: 60).padding(.vertical, 3)
                        Text(meal.amount.isEmpty ? "未记录" : meal.amount)
                            .font(.system(.subheadline, design: .rounded).weight(.bold)).monospacedDigit().lineLimit(2)
                        Text(field.rawValue).font(.system(.caption, design: .rounded).weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(meal.rating.isEmpty ? "未填" : meal.rating) · \(meal.speed.isEmpty ? "未填" : meal.speed)")
                            .font(.caption2).foregroundStyle(BubuTheme.Color.secondaryText)
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .background(env.theme.theme.surfaceTint.opacity(0.1), in: Capsule())
                        if !meal.notes.isEmpty {
                            Text(meal.notes.joined(separator: "；")).font(.caption2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }.frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct SchoolMilkPanel: View {
    let report: SchoolDailyReport
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        SchoolPanel(title: "喝奶", symbol: "waterbottle") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                ForEach(Array([SchoolReportField.milkFirst, .milkSecond].enumerated()), id: \.offset) { index, field in
                    HStack(alignment: .top, spacing: 8) {
                        Text("🍼").font(.system(size: 30)).opacity(report[field].isEmpty ? 0.35 : 1).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("第\(index + 1)次").font(.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                            Text(report[field].isEmpty ? "未记录" : report[field])
                                .font(BubuTheme.Font.caption.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(10).frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                        .background(env.theme.theme.surfaceTint.opacity(report[field].isEmpty ? 0.04 : 0.1), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.sm))
                }
            }
            if !report[.milk].isEmpty { Text(report[.milk]).font(BubuTheme.Font.caption) }
        }
    }
}

struct SchoolNapPanel: View {
    let report: SchoolDailyReport
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        SchoolPanel(title: "午睡", symbol: "moon.zzz.fill") {
            HStack(spacing: 12) {
                if !typeSize.isAccessibilitySize { BubuMascotBadge(size: 56, expression: .sleeping, isAlive: false) }
                VStack(spacing: 8) {
                    if let nap = SchoolVisualValue.nap(report[.nap]) {
                        Text(nap.duration).font(BubuTheme.Font.body.weight(.bold)).monospacedDigit()
                        HStack(spacing: 8) {
                            Text(nap.start).font(BubuTheme.Font.caption.weight(.semibold)).monospacedDigit()
                            Circle().fill(env.theme.theme.primary).frame(width: 6, height: 6)
                            Capsule().fill(env.theme.theme.primary.opacity(0.35)).frame(height: 3)
                            Circle().fill(env.theme.theme.primary).frame(width: 6, height: 6)
                            Text(nap.end).font(BubuTheme.Font.caption.weight(.semibold)).monospacedDigit()
                        }
                    } else {
                        Text(report[.nap].isEmpty ? "午睡时间未记录" : report[.nap]).font(BubuTheme.Font.body)
                    }
                    Label(report[.napQuality].isEmpty ? "品质未记录" : report[.napQuality], systemImage: "moon.stars")
                        .font(.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                }.frame(maxWidth: .infinity)
            }
            .padding(12).background(BubuTheme.Color.lav.opacity(0.16), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.sm))
        }
    }
}

struct SchoolTemperaturePanel: View {
    let report: SchoolDailyReport
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        SchoolPanel(title: "体温", symbol: "thermometer.medium") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: typeSize.isAccessibilitySize ? 1 : 3), spacing: 8) {
                ForEach(Array([SchoolReportField.temperatureAM, .temperatureNoon, .temperaturePM].enumerated()), id: \.offset) { index, field in
                    VStack(spacing: 6) {
                        Image(systemName: index == 2 ? "moon.stars.fill" : "sun.max.fill")
                            .symbolRenderingMode(.palette).foregroundStyle(env.theme.theme.textAccent, env.theme.theme.primary)
                            .font(.title3).frame(width: 36, height: 36)
                            .background(env.theme.theme.surfaceTint.opacity(0.12), in: Circle()).accessibilityHidden(true)
                        Text(["早", "中", "晚"][index]).font(.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                        Text(report[field].isEmpty ? "未记录" : report[field])
                            .font(BubuTheme.Font.body.weight(.semibold)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity).padding(.vertical, 6)
                }
            }
        }
    }
}
