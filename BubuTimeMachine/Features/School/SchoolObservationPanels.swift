import SwiftUI

struct SchoolBehaviorPanel: View {
    let report: SchoolDailyReport
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dynamicTypeSize) private var typeSize
    private let symbols = ["face.smiling.fill", "star.fill", "person.2.fill"]
    private let colors = [SchoolPalette.coral, SchoolPalette.green, SchoolPalette.violet]
    var body: some View {
        SchoolPanel(title: "在园表现", symbol: "leaf.fill", subtitle: "用爱陪伴，见证每一次成长", accent: SchoolPalette.green) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: typeSize.isAccessibilitySize ? 1 : 3), spacing: 10) {
                ForEach(Array([SchoolReportField.mood, .participation, .peers].enumerated()), id: \.offset) { index, field in
                    VStack(spacing: 8) {
                        HStack(spacing: 7) {
                            Image(systemName: symbols[index]).font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(.white).frame(width: 35, height: 35)
                                .background(colors[index], in: Circle()).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(["精神", "参与", "互动"][index]).font(.system(size: 10))
                                Text(report[field].isEmpty ? "未记录" : report[field])
                                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Text(meaning(field)).font(.system(size: 9)).foregroundStyle(SchoolPalette.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 10).padding(.horizontal, 3)
                        .background(colors[index].opacity(0.12), in: RoundedRectangle(cornerRadius: 17))
                        .accessibilityElement(children: .combine).accessibilityIdentifier("school.behavior." + field.rawValue)
                }
            }
            if !report[.specialBehavior].isEmpty { SchoolObservationText(title: "特殊行为", value: report[.specialBehavior], symbol: "sparkle") }
        }
    }
    private func meaning(_ field: SchoolReportField) -> String {
        switch (field, report[field]) {
        case (.mood, "佳"): "精神状态不错"
        case (.participation, "主动"): "主动参与各项活动"
        case (.peers, "佳"): "和小伙伴互动良好"
        default: report[field].isEmpty ? "等待老师的记录" : "按老师原表记录"
        }
    }
}

struct SchoolBodyPanel: View {
    let report: SchoolDailyReport
    var body: some View {
        SchoolPanel(title: "身体与外观", symbol: "figure.child") {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "tshirt.fill").font(.system(size: 36)).foregroundStyle(BubuTheme.Color.lav)
                    .padding(10).background(BubuTheme.Color.lav.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    SchoolObservationText(title: "身体状况", value: report[.health], symbol: "heart")
                    SchoolObservationText(title: "身体外观", value: report[.appearance], symbol: "sparkles")
                }
            }
            DisclosureGroup("部位与具体情形") {
                VStack(alignment: .leading, spacing: 10) {
                    SchoolObservationText(title: "受伤部位与情形", value: report[.injury], symbol: "bandage")
                    SchoolObservationText(title: "其他外观情况", value: report[.appearanceOther], symbol: "text.bubble")
                }.padding(.top, 8)
            }.font(BubuTheme.Font.caption).frame(minHeight: 44)
        }
    }
}

struct SchoolBowelPanel: View {
    let report: SchoolDailyReport
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        SchoolPanel(title: "排便", symbol: "list.clipboard") {
            Label(report[.bowel].isEmpty ? "当天情况未记录" : report[.bowel], systemImage: "leaf")
                .font(BubuTheme.Font.caption.weight(.semibold)).foregroundStyle(env.theme.theme.textAccent)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: typeSize.isAccessibilitySize ? 1 : 3), spacing: 8) {
                ForEach(Array([SchoolReportField.bowelFirst, .bowelSecond, .bowelThird].enumerated()), id: \.offset) { index, field in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 6) {
                            Text("\(index + 1)").font(.caption.weight(.bold)).frame(width: 24, height: 24)
                                .background(env.theme.theme.primary.opacity(0.16), in: Circle())
                            Text("第\(index + 1)次").font(.caption)
                        }
                        Text(report[field].isEmpty ? "未记录" : "已记录")
                            .font(BubuTheme.Font.caption).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .topLeading).padding(9)
                        .background(env.theme.theme.surfaceTint.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            ForEach([SchoolReportField.bowelFirst, .bowelSecond, .bowelThird], id: \.rawValue) { field in
                if !report[field].isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "clock").foregroundStyle(env.theme.theme.textAccent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(field.rawValue).font(.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                            Text(report[field]).font(BubuTheme.Font.caption).fixedSize(horizontal: false, vertical: true)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct SchoolTeacherPanel: View {
    let report: SchoolDailyReport
    @Environment(AppEnvironment.self) private var env
    var body: some View {
        SchoolPanel(title: "老师叮嘱", symbol: "backpack") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "backpack.fill").font(.system(size: 30)).foregroundStyle(SchoolPalette.coral).accessibilityHidden(true)
                    SchoolObservationText(title: "准备物品", value: report[.supplies], symbol: "bag")
                }
                Rectangle().fill(env.theme.theme.primary.opacity(0.16)).frame(height: 1)
                SchoolObservationText(title: "特别叮嘱", value: report[.notice], symbol: "text.bubble")
            }.padding(12).background(env.theme.theme.surfaceTint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct SchoolObservationText: View {
    let title: String
    let value: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(BubuTheme.Color.secondaryText)
            Text(value.isEmpty ? "未记录" : value).font(BubuTheme.Font.caption.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
