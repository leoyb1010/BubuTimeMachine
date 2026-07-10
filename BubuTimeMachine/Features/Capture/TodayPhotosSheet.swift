import SwiftUI
import SwiftData
import Photos

// MARK: - 今天拍的照片 · 一键收进时光机
/// 首页卡片点进来：网格展示今天新增的照片，多选后一键收录成时光轴记录（可加一句话）。
struct TodayPhotosSheet: View {
    let assets: [PHAsset]
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let onDone: ([PHAsset]) -> Void   // 处理过的资产（收录或全部忽略）回传给首页标记

    @State private var selected: Set<String> = []
    @State private var thumbs: [String: UIImage] = [:]
    @State private var note = ""
    @State private var saving = false

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 6)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(assets, id: \.localIdentifier) { asset in
                            cell(asset)
                        }
                    }
                    if !selected.isEmpty {
                        TextField("给这些照片配一句话（可选）", text: $note, axis: .vertical)
                            .font(BubuTheme.Font.body)
                            .padding(12)
                            .background(BubuTheme.Color.softFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding()
            }
            .background(BubuTheme.Color.background.ignoresSafeArea())
            .navigationTitle("今天拍的")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("全部忽略") { onDone(assets); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? "收好" : "收好 \(selected.count) 张") {
                        Task { await importSelected() }
                    }
                    .fontWeight(.bold)
                    .disabled(selected.isEmpty || saving)
                }
            }
            .overlay { if saving { savingOverlay } }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("📸").font(.system(size: 30))
            Text("挑出布布的照片，点「收好」就进时光轴啦")
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
            Spacer(minLength: 0)
        }
    }

    private func cell(_ asset: PHAsset) -> some View {
        let isOn = selected.contains(asset.localIdentifier)
        return ZStack(alignment: .topTrailing) {
            Group {
                if let img = thumbs[asset.localIdentifier] {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    BubuTheme.Color.softFill
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isOn ? BubuTheme.Color.primary : .clear, lineWidth: 3)
            }
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(isOn ? BubuTheme.Color.primary : .white.opacity(0.9))
                .shadow(radius: 2)
                .padding(4)
        }
        .onTapGesture {
            if isOn { selected.remove(asset.localIdentifier) } else { selected.insert(asset.localIdentifier) }
            BubuHaptics.selection()
        }
        .task {
            if thumbs[asset.localIdentifier] == nil {
                thumbs[asset.localIdentifier] = await PhotoLibraryScanner.loadImage(asset, targetPixel: 200)
            }
        }
    }

    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            ProgressView("正在收好…").tint(.white).foregroundStyle(.white)
                .padding(28).background(BubuTheme.Color.warmBrown.opacity(0.92), in: RoundedRectangle(cornerRadius: 22))
        }
    }

    private func importSelected() async {
        let model = CaptureModel(mediaStore: env.mediaStore, analyzer: env.photoAnalyzer,
                                 role: env.config.currentRole)
        saving = true
        model.startQuickCapture(prefillNote: note)
        let chosen = assets.filter { selected.contains($0.localIdentifier) }
        for asset in chosen {
            if let img = await PhotoLibraryScanner.loadImage(asset) {
                model.addCameraPhoto(img)
            }
        }
        _ = await model.savePickedItems(into: context)
        env.syncEngine.syncNow()
        env.refreshWidgetSnapshot(context: context)
        saving = false
        BubuHaptics.success()
        onDone(assets)   // 全部今日照片都标记处理过（选的收了，没选的这次也不再提示）
        dismiss()
    }
}
