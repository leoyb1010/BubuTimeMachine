import SwiftUI
import SwiftData
import PhotosUI

// MARK: - 快速记录面板
/// 拍/选媒体 + 一句话 + 心情 + 语音。全程可选填，任一有内容即可存。
/// 保存时端侧自动分析照片（时间/地点/标签）。
struct QuickCaptureSheet: View {
    @Bindable var model: CaptureModel
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    private var theme: Color { env.theme.theme.primary }

    var body: some View {
        NavigationStack {
            ZStack {
                BubuTheme.Color.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: BubuTheme.Spacing.section) {
                        primaryActions
                        photoPicker

                        if !model.pickedItems.isEmpty {
                            selectedPreviewGrid
                        }

                        MoodPicker(selection: $model.mood, tint: theme)

                        noteField

                        voiceSection

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

                if let hint = model.analyzingHint {
                    analyzingOverlay(hint)
                }
            }
            .alert("保存失败", isPresented: Binding(get: { model.saveError != nil }, set: { if !$0 { model.saveError = nil } })) {
                Button("好") { model.saveError = nil }
            } message: {
                Text(model.saveError ?? "")
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

    private var primaryActions: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            actionCard("拍/选", icon: "camera.fill", subtitle: "照片视频")
            actionCard("说给布布", icon: "mic.fill", subtitle: "点一下录音")
            actionCard("写一句", icon: "pencil", subtitle: "文字记录")
        }
    }

    private func actionCard(_ title: String, icon: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 22, weight: .semibold)).foregroundStyle(theme)
            Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(BubuTheme.Color.warmBrown)
            Text(subtitle).font(.system(size: 11)).foregroundStyle(BubuTheme.Color.secondaryText).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 92)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
    }

    private var photoPicker: some View {
        let tint = theme
        return PhotosPicker(
            selection: $model.pickedItems,
            maxSelectionCount: 9,
            matching: .any(of: [.images, .videos])
        ) {
            VStack(spacing: 14) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(tint)
                Text("从相册补充照片或视频")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text("会自动认出拍摄时间、地点和画面内容")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
            .bubuCardShadow()
        }
    }

    private var selectedPreviewGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("已选 \(model.pickedItems.count) 个")
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
                            if preview.isVideo {
                                Label("视频", systemImage: "play.circle.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7).padding(.vertical, 4)
                                    .background(.black.opacity(0.45), in: Capsule())
                                    .padding(6)
                            }
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
    }

    private var selectedCount: some View {
        Text("已选 \(model.pickedItems.count) 张")
            .font(BubuTheme.Font.caption)
            .foregroundStyle(BubuTheme.Color.secondaryText)
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("想说点什么吗？（可不填）")
                .font(BubuTheme.Font.body)
                .foregroundStyle(BubuTheme.Color.secondaryText)
            TextField("此刻的布布……", text: $model.note, axis: .vertical)
                .font(BubuTheme.Font.body)
                .lineLimit(3...6)
                .padding()
                .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
        }
    }

    @ViewBuilder
    private var voiceSection: some View {
        if let v = model.pendingVoice {
            VStack(alignment: .leading, spacing: 10) {
                Text("已录语音")
                    .font(BubuTheme.Font.body)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
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
            }
        } else {
            VoiceRecorderBar(mediaStore: env.mediaStore) { fileName, duration, waveform in
                model.pendingVoice = (fileName, duration, waveform)
            }
        }
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
