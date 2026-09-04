import SwiftUI
import SwiftData
import UIKit

// MARK: - 入园查验预防接种证
/// 入园查验接种证在国内是强制环节，而这份清单要的数据 App 里**已经全有了**：
/// `VaccineDose.schedule` 覆盖 0–72 月龄共 22 剂（含 36 月龄流脑 AC 与 72 月龄白破加强），
/// `VaccineRecord` 结构完整。缺的只是「按今天该种到哪一剂」算一遍，
/// 并且拿出一页能直接给保健医看的东西。
///
/// 隐私边界：这页会离开手机（截图/分享给老师或保健医），所以**只印查验需要的字段**——
/// 姓名、出生年月、每剂疫苗名与接种日期。不印住址、不印血型、不印证件号
/// （档案里本来也没有证件号字段），也不印任何记录正文。
struct SchoolVaccineCheckView: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var profiles: [ChildProfile]
    @Query(sort: \VaccineRecord.injectedAt) private var records: [VaccineRecord]

    @State private var shareURL: URL?
    @State private var rendering = false

    private var profile: ChildProfile? { profiles.first }
    private var theme: Color { env.theme.theme.primary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let summary {
                    headline(summary)
                    if !summary.missing.isEmpty { missingCard(summary) }
                    doneCard(summary)
                    shareRow(summary)
                } else {
                    ContentUnavailableView {
                        Label("还没有布布的档案", systemImage: "figure.child")
                    } description: {
                        Text("先在设置里填好布布的生日，才能算出该种哪几剂。")
                    }
                }
                disclaimer
            }
            .padding()
            .bubuContentColumn()
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .navigationTitle("入园查验")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareURL) { url in ShareSheet(items: [url]) }
    }

    // MARK: 计算

    struct Summary {
        let name: String
        let birthday: Date
        let ageMonths: Int
        /// 按今天的月龄，本该已经种完的剂次。
        let due: [VaccineDose]
        let done: [(dose: VaccineDose, record: VaccineRecord)]
        let missing: [VaccineDose]
        /// 还没到月龄、暂时不用管的剂次数量。
        let notYetCount: Int
    }

    private var summary: Summary? {
        guard let profile else { return nil }
        let months = Calendar.current.dateComponents([.month], from: profile.birthday, to: .now).month ?? 0
        let byDose = Dictionary(records.compactMap { r in r.doseId.map { ($0, r) } },
                                uniquingKeysWith: { first, _ in first })
        let due = VaccineDose.schedule.filter { $0.monthDue <= months }
            .sorted { $0.monthDue < $1.monthDue }
        var done: [(VaccineDose, VaccineRecord)] = []
        var missing: [VaccineDose] = []
        for dose in due {
            if let record = byDose[dose.id] { done.append((dose, record)) } else { missing.append(dose) }
        }
        return Summary(name: profile.name,
                       birthday: profile.birthday,
                       ageMonths: months,
                       due: due,
                       done: done,
                       missing: missing,
                       notYetCount: VaccineDose.schedule.count - due.count)
    }

    // MARK: 视图

    private func headline(_ s: Summary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                BubuMascotBadge(size: 46, expression: s.missing.isEmpty ? .cheer : .thinking)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.missing.isEmpty ? "查验清单齐了" : "还差 \(s.missing.count) 剂")
                        .font(BubuTheme.Font.title)
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Text("按 \(s.ageMonths) 月龄，应种 \(s.due.count) 剂，已记录 \(s.done.count) 剂")
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
            }
            if s.notYetCount > 0 {
                Text("另有 \(s.notYetCount) 剂还没到月龄，入园查验不看这几剂。")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BubuTheme.Color.card,
                    in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
    }

    private func missingCard(_ s: Summary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("这几剂在 App 里没有记录")
                .font(BubuTheme.Font.headline)
                .foregroundStyle(BubuTheme.Color.deepRose)
            Text("可能是真的没种，也可能是种了没记。先翻一下接种证纸本，补记之后这张单子就齐了。")
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(s.missing) { dose in
                HStack(spacing: 8) {
                    Image(systemName: "circle")
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.deepRose)
                    Text("\(dose.vaccine) · \(dose.doseLabel)")
                        .font(BubuTheme.Font.body)
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Spacer(minLength: 4)
                    Text("\(dose.monthDue) 月龄")
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
                .frame(minHeight: 32)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BubuTheme.Color.peachSurface.opacity(0.55),
                    in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
    }

    private func doneCard(_ s: Summary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("已记录 \(s.done.count) 剂")
                .font(BubuTheme.Font.headline)
                .foregroundStyle(BubuTheme.Color.warmBrown)
            ForEach(s.done, id: \.dose.id) { item in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.success)
                    Text("\(item.dose.vaccine) · \(item.dose.doseLabel)")
                        .font(BubuTheme.Font.body)
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Spacer(minLength: 4)
                    Text(BubuDateFormat.yearMonthDay(item.record.injectedAt))
                        .font(BubuTheme.Font.caption.monospacedDigit())
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
                .frame(minHeight: 32)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BubuTheme.Color.card,
                    in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
    }

    private func shareRow(_ s: Summary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { await share(s) }
            } label: {
                HStack(spacing: 8) {
                    if rendering { ProgressView().tint(.white) }
                    Image(systemName: "square.and.arrow.up")
                    Text(rendering ? "正在生成…" : "生成一页给保健医")
                        .font(BubuTheme.Font.headline.weight(.bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(theme, in: Capsule())
            }
            .buttonStyle(BubuPressableStyle())
            .disabled(rendering)

            Text("生成的是重新绘制的图片，只含姓名、出生年月和每剂的疫苗名与日期，不带位置信息，也不含任何记录正文。")
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var disclaimer: some View {
        Text("清单按国家免疫规划一类苗排期计算，仅供家庭对照，最终以接种点与园方查验结果为准。自费苗不计入。")
            .font(BubuTheme.Font.caption)
            .foregroundStyle(BubuTheme.Color.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    // MARK: 分享

    /// 用 ImageRenderer 重新绘制成 PNG。
    /// 走重绘而不是截图：截图会带上首页背景照片、状态栏和任何当时在屏幕上的内容，
    /// 而重绘的这张图里有什么是这段代码说了算的。同 ShareCard 的做法。
    @MainActor
    private func share(_ s: Summary) async {
        rendering = true
        defer { rendering = false }
        let sheet = VaccineCheckSheetView(summary: s)
            .frame(width: 360)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 3
        renderer.isOpaque = true
        guard let cg = renderer.cgImage,
              let data = UIImage(cgImage: cg, scale: 1, orientation: .up).pngData() else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(s.name)_入园查验接种证.png")
        try? data.write(to: url, options: .atomic)
        BubuHaptics.success()
        shareURL = url
    }
}

// MARK: - 给保健医看的那一页（固定纸面，与设备深浅色无关）
private struct VaccineCheckSheetView: View {
    let summary: SchoolVaccineCheckView.Summary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("入园查验 · 预防接种情况")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Text("\(summary.name) · \(BubuDateFormat.yearMonthDay(summary.birthday)) 出生 · \(summary.ageMonths) 月龄")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("已完成 \(summary.done.count) / 应种 \(summary.due.count)")
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                ForEach(summary.done, id: \.dose.id) { item in
                    HStack(alignment: .firstTextBaseline) {
                        Text("✓").font(.system(size: 12, weight: .bold))
                        Text("\(item.dose.vaccine) \(item.dose.doseLabel)")
                            .font(.system(size: 13))
                        Spacer(minLength: 6)
                        Text(BubuDateFormat.yearMonthDay(item.record.injectedAt))
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !summary.missing.isEmpty {
                Divider()
                Text("未记录 \(summary.missing.count) 剂")
                    .font(.system(size: 14, weight: .semibold))
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(summary.missing) { dose in
                        HStack(alignment: .firstTextBaseline) {
                            Text("—").font(.system(size: 12, weight: .bold))
                            Text("\(dose.vaccine) \(dose.doseLabel)")
                                .font(.system(size: 13))
                            Spacer(minLength: 6)
                            Text("应于 \(dose.monthDue) 月龄")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Divider()
            Text("家庭自记清单，按国家免疫规划一类苗排期整理，以接种证原件为准。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.99, green: 0.98, blue: 0.96))
        .foregroundStyle(Color(red: 0.22, green: 0.18, blue: 0.16))
    }
}
