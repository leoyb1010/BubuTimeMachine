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
                        photoPicker

                        if !model.pickedItems.isEmpty {
                            selectedCount
                        }

                        MoodPicker(selection: $model.mood, tint: theme)

                        noteField

                        voiceSection

                        Spacer(minLength: 12)
                    }
                    .padding()
                }

                if let hint = model.analyzingHint {
                    analyzingOverlay(hint)
                }
            }
            .navigationTitle("记录此刻")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("以后再说") { model.showQuickCapture = false }
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await model.savePickedItems(into: modelContext) }
                    } label: {
                        if model.isSaving { ProgressView() }
                        else { Text("保存").font(BubuTheme.Font.headline.weight(.bold)) }
                    }
                    .disabled(!model.canSave || model.isSaving)
                }
            }
        }
    }

    private var photoPicker: some View {
        let tint = theme
        return PhotosPicker(
            selection: $model.pickedItems,
            maxSelectionCount: 9,
            matching: .any(of: [.images, .videos])
        ) {
            VStack(spacing: 14) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(tint)
                Text("从相册选照片或视频")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text("会自动认出拍摄时间、地点和画面内容")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 190)
            .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
            .bubuCardShadow()
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
