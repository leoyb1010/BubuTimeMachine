import SwiftUI
import SwiftData
import PhotosUI

// MARK: - 布布档案编辑
/// 编辑布布的名字、生日、头像、首页背景照片。生日驱动全 App 年龄计算。
struct ChildProfileView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Query private var profiles: [ChildProfile]

    @State private var avatarPick: PhotosPickerItem?
    @State private var heroPick: PhotosPickerItem?

    private var profile: ChildProfile? { profiles.first }
    private var theme: BubuThemeDefinition { env.theme.theme }

    var body: some View {
        Form {
            if let profile {
                avatarSection(profile)
                infoSection(profile)
                heroSection(profile)
                statSection(profile)
            } else {
                Text("还没有布布的档案").foregroundStyle(BubuTheme.Color.secondaryText)
            }
        }
        .navigationTitle("布布的档案")
        .onChange(of: avatarPick) { _, item in Task { await loadAvatar(item) } }
        .onChange(of: heroPick) { _, item in Task { await loadHero(item) } }
    }

    private func avatarSection(_ profile: ChildProfile) -> some View {
        let avatarData = profile.avatarMediaFileName.flatMap { env.mediaStore.data(forMedia: $0) }
        let avatarUI = avatarData.flatMap { UIImage(data: $0) }
        let tint = theme.primary
        return Section {
            HStack {
                Spacer()
                PhotosPicker(selection: $avatarPick, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        ZStack {
                            if let avatarUI {
                                Image(uiImage: avatarUI).resizable().scaledToFill()
                            } else {
                                tint.opacity(0.15)
                                Text("👶").font(.system(size: 50))
                            }
                        }
                        .frame(width: 110, height: 110)
                        .clipShape(Circle())
                        .overlay { Circle().stroke(tint.opacity(0.3), lineWidth: 3) }

                        Image(systemName: "camera.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(tint)
                            .background(Circle().fill(BubuTheme.Color.card))
                    }
                }
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
    }

    private func infoSection(_ profile: ChildProfile) -> some View {
        Section("基本信息") {
            HStack {
                Text("名字")
                Spacer()
                TextField("布布", text: Binding(
                    get: { profile.name },
                    set: { profile.name = $0; profile.syncState = .local; env.config.childName = $0; try? context.save() }))
                    .multilineTextAlignment(.trailing)
            }
            DatePicker("生日", selection: Binding(
                get: { profile.birthday },
                set: { profile.birthday = $0; profile.syncState = .local; try? context.save() }),
                in: ...Date.now, displayedComponents: .date)
            HStack {
                Text("出生地")
                Spacer()
                TextField("选填", text: Binding(
                    get: { profile.birthPlace ?? "" },
                    set: { profile.birthPlace = $0.isEmpty ? nil : $0; profile.syncState = .local; try? context.save() }))
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private func heroSection(_ profile: ChildProfile) -> some View {
        let tint = theme.primary
        return Section {
            PhotosPicker(selection: $heroPick, matching: .images) {
                Label("选一张布布的照片做首页背景", systemImage: "photo.on.rectangle.angled")
                    .foregroundStyle(tint)
            }
            if profile.heroBackgroundFileName != nil {
                Button(role: .destructive) {
                    profile.heroBackgroundFileName = nil
                    profile.syncState = .local
                    try? context.save()
                } label: { Label("恢复主题背景", systemImage: "arrow.uturn.backward") }
            }
        } header: {
            Text("首页背景")
        } footer: {
            Text("设置后，首页会以布布的照片为背景，更有专属感。")
        }
    }

    private func statSection(_ profile: ChildProfile) -> some View {
        Section("此刻的布布") {
            LabeledContent("年龄", value: AgeCalculator.ageDescription(birthday: profile.birthday, at: .now))
            LabeledContent("来到世界", value: "第 \(AgeCalculator.daysSinceBirth(birthday: profile.birthday)) 天")
            LabeledContent("距下个生日", value: "\(AgeCalculator.daysUntilNextBirthday(birthday: profile.birthday)) 天")
        }
    }

    private func loadAvatar(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let profile else { return }
        if let name = try? env.mediaStore.savePhoto(data) {
            profile.avatarMediaFileName = name
            profile.syncState = .local
            try? context.save()
        }
    }

    private func loadHero(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let profile else { return }
        if let name = try? env.mediaStore.savePhoto(data) {
            profile.heroBackgroundFileName = name
            profile.syncState = .local
            env.theme.heroMode = .photo
            try? context.save()
        }
    }
}
