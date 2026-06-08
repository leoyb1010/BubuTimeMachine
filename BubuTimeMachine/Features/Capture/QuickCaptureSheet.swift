import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation
import UIKit

// MARK: - 快速记录面板
/// 拍/选媒体 + 一句话 + 心情 + 语音。全程可选填，任一有内容即可存。
/// 保存时端侧自动分析照片（时间/地点/标签）。
struct QuickCaptureSheet: View {
    @Bindable var model: CaptureModel
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @FocusState private var noteFocused: Bool
    @State private var showCamera = false
    @State private var cameraAlert: CameraAlert?
    @State private var highlightedTarget: CaptureTarget?

    private var theme: Color { env.theme.theme.primary }

    var body: some View {
        NavigationStack {
            ZStack {
                BubuTheme.Color.background.ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: BubuTheme.Spacing.item) {
                            introCard
                            primaryActions(proxy: proxy)

                            if !model.selectedPreviews.isEmpty {
                                selectedPreviewGrid
                            }

                            noteField
                                .id(CaptureTarget.note)

                            voiceCard
                                .id(CaptureTarget.voice)

                            photoPicker

                            locationPrivacyCard

                            MoodPicker(selection: $model.mood, tint: theme)

                            if let summary = model.lastSavedSummary {
                                Label(summary, systemImage: "checkmark.circle.fill")
                                    .font(BubuTheme.Font.caption)
                                    .foregroundStyle(BubuTheme.Color.success)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Spacer(minLength: 12)
                        }
                        .padding()
                    }
                }

                if let hint = model.analyzingHint {
                    analyzingOverlay(hint)
                }
            }
            .alert("保存失败", isPresented: Binding(get: { model.saveError != nil }, set: { if !$0 { model.saveError = nil } })) {
                Button("好") { model.saveError = nil }
            } message: {
                Text(model.saveError ?? "")
            }
            .alert(item: $cameraAlert) { alert in
                switch alert {
                case .unavailable:
                    Alert(title: Text("这台设备没有可用相机"),
                          message: Text("可以先从相册选择照片或视频，真机上再用拍照记录。"),
                          dismissButton: .default(Text("好")))
                case .denied:
                    Alert(title: Text("需要相机权限"),
                          message: Text("请到系统设置里允许布布时光机使用相机，这样才能拍下此刻的布布。"),
                          primaryButton: .default(Text("去设置"), action: openSettings),
                          secondaryButton: .cancel(Text("先不用")))
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraCaptureView { image in
                    model.addCameraPhoto(image)
                } onCancel: {
                    showCamera = false
                }
                .ignoresSafeArea()
            }
            .navigationTitle("记录此刻")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: model.pickedItems) { _, _ in
                Task { await model.updatePreviews() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("以后再说") { model.showQuickCapture = false }
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            let ok = await model.savePickedItems(into: modelContext)
                            if ok { env.syncEngine.syncNow() }
                        }
                    } label: {
                        if model.isSaving { ProgressView() }
                        else { Text("保存").font(BubuTheme.Font.headline.weight(.bold)) }
                    }
                    .disabled(!model.canSave || model.isSaving)
                }
            }
        }
    }

    private var introCard: some View {
        HStack(spacing: 12) {
            BubuMascotBadge(size: 54, expression: .happy)
            VStack(alignment: .leading, spacing: 4) {
                Text("这一刻想怎么留下？")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text("可以拍一张、写一句，也可以把声音直接留给未来的布布。")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding()
        .background(BubuTheme.Color.card.opacity(0.86), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private func primaryActions(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 10) {
            Button { Task { await requestCamera() } } label: {
                actionCard("拍照", expression: .yeah, subtitle: "拍下此刻")
            }
            .buttonStyle(.plain)

            Button { jump(to: .voice, proxy: proxy) } label: {
                actionCard("说给布布", expression: .love, subtitle: "录一段声音")
            }
            .buttonStyle(.plain)

            Button { jump(to: .note, proxy: proxy) } label: {
                actionCard("写一句", expression: .drawing, subtitle: "留一句话")
            }
            .buttonStyle(.plain)
        }
    }

    private func actionCard(_ title: String, expression: BubuExpression, subtitle: String) -> some View {
        VStack(spacing: 7) {
            BubuMascotBadge(size: 38, expression: expression)
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(BubuTheme.Color.warmBrown)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Text(subtitle)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 112)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous)
                .stroke(theme.opacity(0.12), lineWidth: 1)
        }
    }

    private var photoPicker: some View {
        let tint = theme
        return PhotosPicker(
            selection: $model.pickedItems,
            maxSelectionCount: 9,
            matching: .any(of: [.images, .videos])
        ) {
            HStack(spacing: 14) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 48, height: 48)
                    .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("从相册补充照片或视频")
                        .font(BubuTheme.Font.headline)
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Text("会自动认出拍摄时间、地点和画面内容")
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
            .padding()
            .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
            .bubuCardShadow()
        }
    }

    private var locationPrivacyCard: some View {
        Toggle(isOn: $model.includeLocation) {
            VStack(alignment: .leading, spacing: 3) {
                Text("记录地点")
                    .font(BubuTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text("关闭时只保留照片和时间，不保存 GPS 或地点名。")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(theme)
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private var selectedPreviewGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("已选 \(model.selectedPreviews.count) 个")
                    .font(BubuTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                Spacer()
                if model.isLoadingPreviews { ProgressView().controlSize(.small) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(model.selectedPreviews) { preview in
                    ZStack(alignment: .topTrailing) {
                        ZStack(alignment: .bottomLeading) {
                            if let image = preview.image {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous)
                                    .fill(BubuTheme.Color.cream)
                                    .overlay {
                                        Image(systemName: preview.isVideo ? "video" : "photo")
                                            .font(.system(size: 26))
                                            .foregroundStyle(BubuTheme.Color.secondaryText)
                                    }
                            }
                            Label(preview.label, systemImage: preview.isVideo ? "play.circle.fill" : "camera.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 4)
                                .background(.black.opacity(0.45), in: Capsule())
                                .padding(6)
                        }
                        .frame(height: 104)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))

                        Button {
                            model.removePickedItem(at: preview.index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white, .black.opacity(0.45))
                                .padding(5)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        .background(BubuTheme.Color.card.opacity(0.72), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                BubuMascotBadge(size: 38, expression: .drawing)
                VStack(alignment: .leading, spacing: 2) {
                    Text("写一句")
                        .font(BubuTheme.Font.headline)
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Text("不必完整，未来的布布会懂。")
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
                Spacer()
            }
            TextField("此刻的布布……", text: $model.note, axis: .vertical)
                .font(BubuTheme.Font.body)
                .lineLimit(3...6)
                .focused($noteFocused)
                .padding()
                .background(BubuTheme.Color.cream.opacity(0.65), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
        }
        .padding()
        .background(cardBackground(for: .note), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .overlay(highlightStroke(for: .note))
        .bubuCardShadow()
    }

    private var voiceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                BubuMascotBadge(size: 38, expression: .love)
                VStack(alignment: .leading, spacing: 2) {
                    Text("说给布布")
                        .font(BubuTheme.Font.headline)
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Text("点一下开始录，再点一下收好，会跟这条记录一起保存。")
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                        .lineLimit(2)
                }
                Spacer()
            }
            voiceSection
        }
        .padding()
        .background(cardBackground(for: .voice), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .overlay(highlightStroke(for: .voice))
        .bubuCardShadow()
    }

    @ViewBuilder
    private var voiceSection: some View {
        if let v = model.pendingVoice {
            HStack {
                VoicePlayerBubble(fileName: v.fileName, duration: v.duration,
                                  waveform: v.waveform, mediaStore: env.mediaStore, tint: theme)
                Button {
                    model.pendingVoice = nil
                } label: {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
                .buttonStyle(.plain)
            }
        } else {
            VoiceRecorderBar(mediaStore: env.mediaStore) { fileName, duration, waveform in
                model.pendingVoice = (fileName, duration, waveform)
            }
        }
    }

    private func jump(to target: CaptureTarget, proxy: ScrollViewProxy) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            proxy.scrollTo(target, anchor: .center)
            highlightedTarget = target
        }
        if target == .note {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(260))
                noteFocused = true
            }
        } else {
            noteFocused = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            if highlightedTarget == target { highlightedTarget = nil }
        }
    }

    @MainActor
    private func requestCamera() async {
        noteFocused = false
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraAlert = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted { showCamera = true } else { cameraAlert = .denied }
        case .denied, .restricted:
            cameraAlert = .denied
        @unknown default:
            cameraAlert = .denied
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func cardBackground(for target: CaptureTarget) -> Color {
        highlightedTarget == target ? theme.opacity(0.13) : BubuTheme.Color.card
    }

    private func highlightStroke(for target: CaptureTarget) -> some View {
        RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous)
            .stroke(highlightedTarget == target ? theme.opacity(0.55) : .clear, lineWidth: 2)
    }

    private func analyzingOverlay(_ hint: String) -> some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large).tint(theme)
            Text(hint).font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.warmBrown)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }
}

private enum CaptureTarget: Hashable {
    case note
    case voice
}

private enum CameraAlert: Identifiable {
    case unavailable
    case denied

    var id: String {
        switch self {
        case .unavailable: return "unavailable"
        case .denied: return "denied"
        }
    }
}
