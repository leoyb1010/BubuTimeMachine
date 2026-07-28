import SwiftUI
import SwiftData
import PhotosUI

// MARK: - 布布档案编辑
/// 编辑布布的名字、生日、头像、首页背景照片。生日驱动全 App 年龄计算。
struct ChildProfileView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    /// 按创建时间排序：无序时 `first` 在多档案场景会漂移，输入目标可能在按键间跳到另一条。
    @Query(sort: \ChildProfile.createdAt) private var profiles: [ChildProfile]

    @State private var avatarPick: PhotosPickerItem?
    @State private var heroPick: PhotosPickerItem?

    private var profile: ChildProfile? { profiles.first }
    private var theme: BubuThemeDefinition { env.theme.theme }

    var body: some View {
        Form {
            if let profile {
                statSection(profile)     // 先看「此刻的布布」，再往下编辑
                avatarSection(profile)
                infoSection(profile)
                heroSection(profile)
            } else {
                Text("还没有布布的档案").foregroundStyle(BubuTheme.Color.secondaryText)
            }
        }
        // 脱掉系统灰表格：不加这两行，进档案页会从马卡龙卡片风直接掉进 iOS 默认分组表
        .bubuContentColumn(760)   // Form 宽屏收口：760 比正文列宽些，容得下右侧输入框
        .scrollContentBackground(.hidden)
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .navigationTitle("布布的档案")
        .safeAreaInset(edge: .bottom) {
            if profiles.count > 1 {
                // 历史上出现过「同一家庭两份档案」，此时编辑的是最早那份，另一份会造成年龄/身份卡不一致。
                Label("检测到 \(profiles.count) 份布布档案，当前编辑的是最早创建的那份。多余的档案可以联系管理员在服务器上清理。",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.warning)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(BubuTheme.Color.warning.opacity(0.12))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
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
                                Text("👶").font(BubuTheme.Font.scaled(50))
                            }
                        }
                        .frame(width: 110, height: 110)
                        .clipShape(Circle())
                        .overlay { Circle().stroke(tint.opacity(0.3), lineWidth: 3) }

                        Image(systemName: "camera.circle.fill")
                            .font(BubuTheme.Font.scaled(28))
                            .foregroundStyle(tint)
                            .background(Circle().fill(BubuTheme.Color.card))
                    }
                }
                Spacer()
            }
            .listRowBackground(Color.clear)
            if profile.avatarMediaFileName != nil {
                Button(role: .destructive) {
                    profile.avatarMediaFileName = nil
                    profile.avatarRemoteURL = nil
                    profile.syncState = .local
                    commitProfile()
                } label: {
                    Label("移除头像", systemImage: "person.crop.circle.badge.minus")
                }
            }
        }
    }

    private func infoSection(_ profile: ChildProfile) -> some View {
        Section("基本信息") {
            // 文本字段一律走缓冲提交：输入期间不落库，失焦/回车才写一次。
            // 直接绑 @Model 并逐键 save 会重建视图树、清空中文输入法的拼音（出生地曾因此完全不能输入）。
            BubuBufferedField(title: "名字", placeholder: "布布", value: profile.name) { newName in
                guard !newName.isEmpty else { return }
                profile.name = newName
                profile.syncState = .local
                env.config.childName = newName
                commitProfile()
            }
            DatePicker("生日", selection: Binding(
                get: { profile.birthday },
                set: {
                    // 保存前归一化到当天 0 点，保持与全 App 年龄口径一致（C-P1-5）。
                    profile.birthday = Calendar.current.startOfDay(for: $0)
                    profile.syncState = .local
                    commitProfile()
                }),
                in: ...Date.now, displayedComponents: .date)
            BubuBufferedField(title: "出生地", placeholder: "选填", value: profile.birthPlace ?? "") { place in
                profile.birthPlace = place.isEmpty ? nil : place
                profile.syncState = .local
                commitProfile()
            }
            BubuBufferedField(title: "小名", placeholder: "选填", value: profile.nickname ?? "") { nick in
                profile.nickname = nick.isEmpty ? nil : nick
                profile.syncState = .local
                commitProfile()
            }
            // 性别 / 血型：身份卡背面会展示这两项，此前缺少输入入口，导致永远「未填写」。
            Picker("性别", selection: optionalStringBinding(\.gender, on: profile)) {
                Text("未填写").tag(Self.unset)
                ForEach(Self.genderOptions, id: \.self) { Text($0).tag($0) }
            }
            Picker("血型", selection: optionalStringBinding(\.bloodType, on: profile)) {
                Text("未填写").tag(Self.unset)
                ForEach(Self.bloodTypeOptions, id: \.self) { Text($0).tag($0) }
            }
        }
    }

    // MARK: 可选字符串字段的输入选项

    /// Picker 的「未填写」占位标签：映射回 model 的 nil。
    private static let unset = ""
    private static let genderOptions = ["男", "女", "其他"]
    private static let bloodTypeOptions = ["A", "B", "O", "AB"]

    /// 档案改动落库 + 刷新小组件快照。
    /// 输入类字段已在 BubuBufferedField 内缓冲，到这里必定是「用户完成了一次编辑」，
    /// 因此可以直接同步保存，不需要旧的 700ms 去抖（去抖窗口内被杀还会丢改动）。
    private func commitProfile() {
        try? context.save()
        env.refreshWidgetSnapshot(context: context)
        WidgetRefresher.reload()
        env.syncEngine.syncNow()
    }

    /// 把 `String?` 字段桥接成 Picker 可用的非可选 `String` 绑定（空串 = nil = 未填写）。
    private func optionalStringBinding(
        _ keyPath: ReferenceWritableKeyPath<ChildProfile, String?>,
        on profile: ChildProfile
    ) -> Binding<String> {
        Binding(
            get: { profile[keyPath: keyPath] ?? Self.unset },
            set: {
                profile[keyPath: keyPath] = $0.isEmpty ? nil : $0
                profile.syncState = .local
                commitProfile()
            }
        )
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
                    commitProfile()
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
        // 头像降采样到 600px 再存：原图动辄十几 MB 超过小组件 2MB 上限，
        // 桌面小组件的头像会永远是"布"字兜底（R4 待核-头像）
        let avatarData: Data
        if let image = UIImage(data: data),
           let small = await image.byPreparingThumbnail(ofSize: Self.avatarSize(for: image.size)),
           let jpeg = small.jpegData(compressionQuality: 0.9) {
            avatarData = jpeg
        } else {
            avatarData = data
        }
        if let name = try? env.mediaStore.savePhoto(avatarData) {
            profile.avatarMediaFileName = name
            profile.avatarRemoteURL = nil   // 置空触发下一轮同步补传新头像
            profile.syncState = .local
            try? context.save()
            env.refreshWidgetSnapshot(context: context)
            WidgetRefresher.reload()        // 头像变了，刷新桌面小组件
        }
    }

    private static func avatarSize(for size: CGSize) -> CGSize {
        let maxSide = max(size.width, size.height)
        guard maxSide > 600, maxSide > 0 else { return size }
        let k = 600 / maxSide
        return CGSize(width: size.width * k, height: size.height * k)
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
