import SwiftUI
import SwiftData
import PhotosUI

// MARK: - 快速记录面板
/// 拍/选媒体 + 可选一句话备注。全程可不填，选了就能存。
struct QuickCaptureSheet: View {
    @Bindable var model: CaptureModel
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                BubuTheme.Color.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: BubuTheme.Spacing.section) {
                        photoPicker

                        if !model.pickedItems.isEmpty {
                            Text("已选 \(model.pickedItems.count) 张")
                                .font(BubuTheme.Font.caption)
                                .foregroundStyle(BubuTheme.Color.secondaryText)
                        }

                        noteField

                        Spacer(minLength: 12)
                    }
                    .padding()
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
                        if model.isSaving {
                            ProgressView()
                        } else {
                            Text("保存").font(BubuTheme.Font.headline.weight(.bold))
                        }
                    }
                    .disabled(model.pickedItems.isEmpty || model.isSaving)
                }
            }
        }
    }

    private var photoPicker: some View {
        PhotosPicker(
            selection: $model.pickedItems,
            maxSelectionCount: 9,
            matching: .any(of: [.images, .videos])
        ) {
            VStack(spacing: 14) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(BubuTheme.Color.primary)
                Text("从相册选照片或视频")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
            .bubuCardShadow()
        }
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
}
