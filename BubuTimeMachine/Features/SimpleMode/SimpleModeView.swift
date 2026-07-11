import SwiftUI
import SwiftData

// MARK: - 简单模式（老人模式）
/// 跟随身份的极简界面：切到长辈（爷爷/奶奶/姥姥/姥爷）自动进入，名字用当前称谓。
/// 只保留三件事——拍一张 / 说一段 / 看布布，全部大字大按钮、零层级、零选择过载。
/// 复用现有 CaptureModel / CameraCaptureView / VoiceRecorderBar / MediaGalleryViewer，不重造记录管线。
struct SimpleModeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Environment(BubuRouter.self) private var router
    @Query private var profiles: [ChildProfile]
    @Query private var members: [FamilyMember]

    @State private var model: CaptureModel?
    @State private var showCamera = false
    @State private var showVoice = false
    @State private var showTimeline = false
    @State private var confirmation: String?
    @State private var saving = false

    private var role: FamilyRole { env.config.currentRole }
    private var childName: String { profiles.first?.name ?? env.config.childName }
    /// 当前身份的成员卡（取其自定义头像），无则回退关系默认 emoji。
    private var currentMember: FamilyMember? {
        members.first { $0.relation == role.rawValue }
    }
    private var ageText: String {
        guard let birthday = profiles.first?.birthday else { return "" }
        return AgeCalculator.ageDescription(birthday: birthday, at: .now)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [BubuTheme.Color.cream, BubuTheme.Color.peach.opacity(0.35)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                header
                Spacer(minLength: 4)
                bigButton(title: "拍一张", subtitle: "给\(childName)拍照片", icon: "camera.fill",
                          tint: BubuTheme.Color.primary) { openCamera() }
                bigButton(title: "说一段", subtitle: "说句话给\(childName)", icon: "mic.fill",
                          tint: BubuTheme.Color.info) { showVoice = true }
                bigButton(title: "看\(childName)", subtitle: "翻翻最近的照片", icon: "photo.stack.fill",
                          tint: BubuTheme.Color.success) { showTimeline = true }
                Spacer(minLength: 4)
                exitButton
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)

            if let confirmation { confirmationOverlay(confirmation) }
            if saving { savingOverlay }
        }
        .onAppear {
            if model == nil {
                model = CaptureModel(mediaStore: env.mediaStore,
                                     analyzer: env.photoAnalyzer, role: role)
            }
            // 简单模式没有 Tab，清掉小组件深链遗留的 pendingTab，避免下次进完整版误跳 Tab。
            router.pendingTab = nil
            consumeRecordShortcut()
        }
        .onChange(of: router.pendingQuickCapture) { _, _ in consumeRecordShortcut() }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView(onImage: { image in
                showCamera = false
                Task { await savePhoto(image) }
            }, onCancel: { showCamera = false })
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showVoice) { voiceSheet }
        .fullScreenCover(isPresented: $showTimeline) { SimpleTimelineView() }
    }

    // MARK: 顶部问候
    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Text(role.simpleModeName)
                    .font(BubuTheme.Font.scaled(17, weight: .bold))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                Spacer()
            }
            HStack(spacing: 14) {
                Text(currentMember?.avatarEmoji ?? Relation(rawValue: role.rawValue)?.defaultEmoji ?? "🙂")
                    .font(.system(size: 40))
                    .frame(width: 66, height: 66)
                    .background(BubuTheme.Color.card, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("你好呀")
                        .font(BubuTheme.Font.scaled(18, weight: .bold))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                    Text(childName)
                        .font(BubuTheme.Font.scaled(34, weight: .black))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    if !ageText.isEmpty {
                        Text(ageText)
                            .font(BubuTheme.Font.scaled(18, weight: .bold))
                            .foregroundStyle(BubuTheme.Color.deepRose)
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: 大按钮
    private func bigButton(title: String, subtitle: String, icon: String,
                           tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            BubuHaptics.tapLight()
            action()
        } label: {
            HStack(spacing: 18) {
                Image(systemName: icon)
                    .font(BubuTheme.Font.scaled(42, weight: .black, design: .default))
                    .foregroundStyle(.white)
                    .frame(width: 74, height: 74)
                    .background(.white.opacity(0.22), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(BubuTheme.Font.scaled(32, weight: .black))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(BubuTheme.Font.scaled(17, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, minHeight: 118)
            .background(
                LinearGradient(colors: [tint, tint.opacity(0.82)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 30, style: .continuous)
            )
            .shadow(color: tint.opacity(0.3), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: 退出到完整版（把手机还给爸爸妈妈）
    private var exitButton: some View {
        Button {
            BubuHaptics.tapLight()
            withAnimation(.smooth) { exitToFullApp() }
        } label: {
            Text("切换到完整版")
                .font(BubuTheme.Font.scaled(16, weight: .bold))
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(BubuTheme.Color.card, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// 退出简单模式：切回进入长辈模式前的父母身份（避免家长拿回手机后记录被误署长辈名），
    /// 并同步成员卡；没有记录到父母身份时仅退出模式。
    private func exitToFullApp() {
        if let prevRaw = env.config.roleBeforeElderRaw,
           let prevRole = FamilyRole(rawValue: prevRaw), !prevRole.isElder {
            env.config.currentRole = prevRole            // didSet 会把 simpleModeEnabled 置 false
            if let member = members.first(where: { $0.relation == prevRaw }) {
                env.currentMemberId = member.id
            }
        } else {
            env.config.simpleModeEnabled = false
        }
    }

    // MARK: 录音 sheet
    private var voiceSheet: some View {
        VStack(spacing: 20) {
            Text("说给\(childName)")
                .font(BubuTheme.Font.scaled(28, weight: .black))
                .foregroundStyle(BubuTheme.Color.warmBrown)
                .padding(.top, 28)
            Text("点一下开始，说完再点一下")
                .font(BubuTheme.Font.scaled(17, weight: .bold))
                .foregroundStyle(BubuTheme.Color.secondaryText)
            VoiceRecorderBar(mediaStore: env.mediaStore) { fileName, duration, waveform in
                showVoice = false
                Task { await saveVoice(fileName: fileName, duration: duration, waveform: waveform) }
            }
            .padding(.horizontal, 20)
            Spacer()
            Button("取消") { showVoice = false }
                .font(BubuTheme.Font.scaled(18, weight: .bold))
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .presentationDetents([.medium])
    }

    // MARK: 保存确认 / 进行中浮层
    private func confirmationOverlay(_ text: String) -> some View {
        VStack(spacing: 14) {
            Text("❤️").font(.system(size: 64))
            Text(text)
                .font(BubuTheme.Font.scaled(26, weight: .black))
                .foregroundStyle(.white)
        }
        .padding(40)
        .background(BubuTheme.Color.deepRose.opacity(0.95), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(radius: 20)
        .transition(.scale.combined(with: .opacity))
    }

    /// 保存中：全屏半透明遮罩 + 拦截点击，防止长辈误触在保存窗口内二次触发（共享 model 会串号）。
    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().scaleEffect(1.6).tint(.white)
                Text("正在收好…")
                    .font(BubuTheme.Font.scaled(20, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(36)
            .background(BubuTheme.Color.warmBrown.opacity(0.92), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .transition(.opacity)
    }

    // MARK: 保存逻辑
    private func openCamera() { showCamera = true }

    private func savePhoto(_ image: UIImage) async {
        guard let model, !saving else { return }   // 重入保护：保存窗口内不接受第二次动作
        withAnimation(.smooth) { saving = true }
        model.role = role   // 署名跟随当前身份
        model.startQuickCapture()
        model.addCameraPhoto(image)
        let ok = await model.savePickedItems(into: context)
        withAnimation(.smooth) { saving = false }
        env.syncEngine.syncNow()
        flashConfirmation(ok ? "照片收好啦" : "再试一次好吗")
    }

    private func saveVoice(fileName: String, duration: Double, waveform: [Float]) async {
        guard let model, !saving else { return }
        withAnimation(.smooth) { saving = true }
        model.role = role   // 署名跟随当前身份
        model.startQuickCapture()
        model.pendingVoice = (fileName, duration, waveform)
        let ok = await model.savePickedItems(into: context)
        withAnimation(.smooth) { saving = false }
        env.syncEngine.syncNow()
        flashConfirmation(ok ? "话已经收好啦" : "再试一次好吗")
    }

    private func flashConfirmation(_ text: String) {
        BubuHaptics.success()
        withAnimation(.smooth) { confirmation = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.smooth) { if confirmation == text { confirmation = nil } }
        }
    }

    /// 消费小组件「＋记一笔」深链：在简单模式里直接打开拍照。
    private func consumeRecordShortcut() {
        guard router.pendingQuickCapture else { return }
        router.pendingQuickCapture = false
        router.pendingTab = nil
        openCamera()
    }
}
