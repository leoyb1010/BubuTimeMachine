import SwiftUI
import SwiftData
import UIKit

// MARK: - 一页纸给老师
/// 入园时老师真正需要的只有五样：怎么称呼她、对什么过敏、有没有在吃药、
/// 出事找谁、谁能来接。这些信息 App 里都有，只是散在档案、成员和健康记录里，
/// 从来没有一个「拿得出手的一页」。
///
/// 隐私边界（这页一定会离开手机，发到老师微信里）：
/// - 只印上面那五样，**不印**生日全量、出生地、血型、任何记录正文与照片。
/// - 出图走 `ImageRenderer` 重新绘制，不是截图——截图会带上首页背景照片和当时屏幕上的一切。
/// - 家人的手机号只存在本机（`FamilyMember.contactPhone` 不进 DTO），不上服务器。
struct SchoolTeacherSheetView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Query private var profiles: [ChildProfile]
    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]

    @State private var shareURL: URL?
    @State private var rendering = false
    /// 出图时是否连出生年月一起印。默认开——园方通常需要核对年龄；不想给就关掉。
    @State private var includeBirthday = true

    private var profile: ChildProfile? { profiles.first }
    private var theme: Color { env.theme.theme.primary }
    private var pickupMembers: [FamilyMember] { members.filter(\.canPickUpFromSchool) }

    var body: some View {
        Form {
            if let profile {
                Section {
                    LabeledContent("称呼") {
                        Text(profile.nickname?.isEmpty == false ? profile.nickname! : profile.name)
                    }
                    BubuBufferedField(title: "过敏源", placeholder: "没有就留空",
                                      value: profile.allergies ?? "") { text in
                        profile.allergies = text.isEmpty ? nil : text
                        profile.syncState = .local
                        save()
                    }
                    BubuBufferedField(title: "用药或健康备注", placeholder: "选填",
                                      value: profile.medicalNotes ?? "") { text in
                        profile.medicalNotes = text.isEmpty ? nil : text
                        profile.syncState = .local
                        save()
                    }
                } header: {
                    Text("老师最需要知道的")
                } footer: {
                    Text("过敏这一条最好如实写清楚，包括反应是什么。老师不会翻你的记录，只会看这一页。")
                }

                Section {
                    ForEach(members) { member in
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: Binding(
                                get: { member.canPickUpFromSchool },
                                set: { member.canPickUpFromSchool = $0; save() })) {
                                Text("\(member.avatarEmoji) \(member.name)（\(member.relation)）")
                            }
                            if member.canPickUpFromSchool {
                                BubuBufferedField(title: "电话", placeholder: "选填",
                                                  value: member.contactPhone ?? "") { text in
                                    member.contactPhone = text.isEmpty ? nil : text
                                    save()
                                }
                            }
                        }
                    }
                } header: {
                    Text("可以来接的人")
                } footer: {
                    Text("电话只存在这台手机里，不会同步到服务器，也不会随其它记录外发。")
                }

                Section {
                    Toggle("这一页也印出生年月", isOn: $includeBirthday)
                    Button {
                        Task { await share(profile) }
                    } label: {
                        HStack(spacing: 8) {
                            if rendering { ProgressView() }
                            Text(rendering ? "正在生成…" : "生成一页发给老师")
                        }
                    }
                    .disabled(rendering)
                } footer: {
                    Text("生成的是重新绘制的图片，只含上面这几项，不带位置信息，也不含任何照片或记录正文。")
                }
            } else {
                ContentUnavailableView {
                    Label("还没有布布的档案", systemImage: "figure.child")
                } description: {
                    Text("先在设置里建好档案，再来生成给老师的这一页。")
                }
            }
        }
        .navigationTitle("给老师的一页")
        .navigationBarTitleDisplayMode(.inline)
        .bubuContentColumn(760)
        .scrollContentBackground(.hidden)
        .background(BubuTheme.Color.background)
        .sheet(item: $shareURL) { url in ShareSheet(items: [url]) }
    }

    private func save() {
        try? context.save()
    }

    @MainActor
    private func share(_ profile: ChildProfile) async {
        rendering = true
        defer { rendering = false }
        let content = TeacherSheetContent(
            displayName: profile.nickname?.isEmpty == false ? profile.nickname! : profile.name,
            fullName: profile.name,
            birthday: includeBirthday ? profile.birthday : nil,
            allergies: profile.allergies,
            medicalNotes: profile.medicalNotes,
            contacts: pickupMembers.map {
                .init(name: $0.name, relation: $0.relation, phone: $0.contactPhone)
            })
        let sheet = TeacherSheetPage(content: content)
            .frame(width: 360)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 3
        renderer.isOpaque = true
        guard let cg = renderer.cgImage,
              let data = UIImage(cgImage: cg, scale: 1, orientation: .up).pngData() else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(content.displayName)_入园信息.png")
        try? data.write(to: url, options: .atomic)
        BubuHaptics.success()
        shareURL = url
    }
}

// MARK: - 纸面内容（明确列出会离开设备的每一个字段）
struct TeacherSheetContent {
    struct Contact {
        let name: String
        let relation: String
        let phone: String?
    }
    let displayName: String
    let fullName: String
    let birthday: Date?
    let allergies: String?
    let medicalNotes: String?
    let contacts: [Contact]
}

private struct TeacherSheetPage: View {
    let content: TeacherSheetContent

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(content.fullName)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                HStack(spacing: 8) {
                    Text("小名 \(content.displayName)")
                    if let birthday = content.birthday {
                        Text("·")
                        Text("\(BubuDateFormat.yearMonthDay(birthday)) 出生")
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }

            Divider()

            block(title: "过敏",
                  value: content.allergies?.isEmpty == false ? content.allergies! : "无",
                  emphasized: content.allergies?.isEmpty == false)

            if let notes = content.medicalNotes, !notes.isEmpty {
                block(title: "用药 / 健康备注", value: notes, emphasized: false)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("可以来接的人")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                if content.contacts.isEmpty {
                    Text("未登记")
                        .font(.system(size: 14))
                } else {
                    ForEach(Array(content.contacts.enumerated()), id: \.offset) { _, contact in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(contact.name)（\(contact.relation)）")
                                .font(.system(size: 14, weight: .medium))
                            Spacer(minLength: 6)
                            Text(contact.phone?.isEmpty == false ? contact.phone! : "—")
                                .font(.system(size: 14).monospacedDigit())
                        }
                    }
                }
            }

            Divider()
            Text("家长自填，供老师存档。如信息有变会重新发一份。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.99, green: 0.98, blue: 0.96))
        .foregroundStyle(Color(red: 0.22, green: 0.18, blue: 0.16))
    }

    private func block(title: String, value: String, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: emphasized ? 17 : 15, weight: emphasized ? .bold : .regular))
                .foregroundStyle(emphasized ? Color(red: 0.70, green: 0.20, blue: 0.12)
                                            : Color(red: 0.22, green: 0.18, blue: 0.16))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
