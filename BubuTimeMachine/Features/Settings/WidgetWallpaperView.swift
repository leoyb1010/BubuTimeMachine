import SwiftUI
import PhotosUI
import UIKit

// MARK: - 桌面壁纸（伪透明小组件）
/// 导入一张桌面截图 → 拖框圈出小组件实际所在的位置 → App 裁好存进 App Group →
/// 小组件把那块壁纸当底，桌面上看起来就是透明的。
///
/// 为什么要用户自己圈位置：小组件没有任何 API 能知道自己在桌面的哪一格。
/// 硬编码 iOS 的桌面网格坐标要为每种机型、每种尺寸各算一套，还会被
/// 「更大的图标」「减少动态效果」等设置改变——拖一下最准，也最省事。
struct WidgetWallpaperView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var pickerItem: PhotosPickerItem?
    @State private var source: UIImage?
    @State private var slot: WidgetWallpaper.Slot = .large
    /// 拖框左上角在预览里的归一化位置（0–1）。
    @State private var origin: CGPoint = .init(x: 0.086, y: 0.11)
    @State private var enabled = WidgetWallpaper.isEnabled
    @State private var savedSlots: Set<WidgetWallpaper.Slot> = []
    @State private var showRemoveConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                guideCard
                if let source {
                    positioner(source)
                    slotPicker
                    enableToggle
                    removeButton
                } else {
                    importButton
                }
            }
            .padding()
            .bubuContentColumn()
        }
        .navigationTitle("桌面壁纸")
        .navigationBarTitleDisplayMode(.inline)
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .task { loadExisting() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await importPicked(item) }
        }
        .confirmationDialog("移除桌面壁纸？", isPresented: $showRemoveConfirm, titleVisibility: .visible) {
            Button("移除", role: .destructive) { remove() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("小组件会恢复成原来的浅色卡片底。导入的截图会一起删掉。")
        }
    }

    // MARK: 说明

    private var guideCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("怎么用", systemImage: "sparkles")
                .font(BubuTheme.Font.headline)
                .foregroundStyle(BubuTheme.Color.warmBrown)
            step(1, "把桌面滑到一页**空白页**（没有图标和小组件的那一页），按电源+音量键截屏。")
            step(2, "回到这里导入那张截图。")
            step(3, "选尺寸，把方框拖到小组件在桌面上实际待的位置，松手就存好了。")
            Text("小组件的底会换成那块壁纸，桌面上看起来就是透明的。换了壁纸要重新截一次。")
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)")
                .font(BubuTheme.Font.scaled(11, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(env.theme.theme.primary, in: Circle())
            Text(.init(text))
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.warmBrown)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var importButton: some View {
        // 注意：PhotosPicker 的 label 是 Sendable 闭包，里面取不到 MainActor 隔离的 env，
        // 这里必须用静态主题色而不是 env.theme。
        PhotosPicker(selection: $pickerItem, matching: .images) {
            Label("导入桌面截图", systemImage: "photo.badge.plus")
                .font(BubuTheme.Font.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(BubuTheme.Color.primary,
                            in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        }
    }

    // MARK: 拖框定位

    private func positioner(_ image: UIImage) -> some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                let previewW = geo.size.width
                let previewH = previewW * image.size.height / max(image.size.width, 1)
                let boxW = previewW * slot.widthRatio
                let boxH = boxW * slot.heightOverWidth

                ZStack(alignment: .topLeading) {
                    Image(uiImage: image)
                        .resizable().scaledToFit()
                        .frame(width: previewW, height: previewH)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(env.theme.theme.primary.opacity(0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(env.theme.theme.primary, lineWidth: 2)
                        )
                        .overlay(
                            Text(slot.displayName)
                                .font(BubuTheme.Font.scaled(12, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(env.theme.theme.primary, in: Capsule())
                        )
                        .frame(width: boxW, height: boxH)
                        .offset(x: origin.x * previewW, y: origin.y * previewH)
                        .gesture(
                            DragGesture()
                                .onChanged { v in
                                    // 直接按位移换算成归一化坐标，并夹在预览范围内——
                                    // 不夹的话拖出界会裁到空白。
                                    let nx = origin.x + v.translation.width / previewW
                                    let ny = origin.y + v.translation.height / previewH
                                    origin = CGPoint(
                                        x: min(max(nx, 0), 1 - boxW / previewW),
                                        y: min(max(ny, 0), 1 - boxH / previewH))
                                }
                                .onEnded { _ in save(image: image, boxW: boxW / previewW, boxH: boxH / previewH) }
                        )
                }
                .frame(width: previewW, height: previewH)
            }
            .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)

            Text(savedSlots.contains(slot) ? "已保存 \(slot.displayName) 的位置" : "拖动方框到小组件的位置，松手保存")
                .font(BubuTheme.Font.caption)
                .foregroundStyle(savedSlots.contains(slot) ? BubuTheme.Color.success : BubuTheme.Color.secondaryText)
        }
    }

    private var slotPicker: some View {
        Picker("尺寸", selection: $slot) {
            ForEach(WidgetWallpaper.Slot.allCases, id: \.self) { s in
                Text(savedSlots.contains(s) ? "\(s.displayName) ✓" : s.displayName).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: slot) { _, new in
            origin = WidgetWallpaper.normalizedRect(for: new).map { CGPoint(x: $0.origin.x, y: $0.origin.y) }
                ?? CGPoint(x: 0.086, y: 0.11)
        }
    }

    private var enableToggle: some View {
        Toggle(isOn: $enabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text("用壁纸做小组件底").font(BubuTheme.Font.body)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text("关掉就恢复成浅色卡片底").font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
        }
        .tint(env.theme.theme.primary)
        .padding(14)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .onChange(of: enabled) { _, on in
            WidgetWallpaper.isEnabled = on
            WidgetRefresher.reload()
        }
    }

    private var removeButton: some View {
        Button(role: .destructive) { showRemoveConfirm = true } label: {
            Label("移除桌面壁纸", systemImage: "trash")
                .font(BubuTheme.Font.body)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .background(BubuTheme.Color.danger.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
    }

    // MARK: 动作

    private func loadExisting() {
        guard WidgetWallpaper.hasSource,
              let data = try? Data(contentsOf: WidgetWallpaper.sourceURL),
              let image = UIImage(data: data) else { return }
        source = image
        savedSlots = Set(WidgetWallpaper.Slot.allCases.filter { WidgetWallpaper.normalizedRect(for: $0) != nil })
        if let r = WidgetWallpaper.normalizedRect(for: slot) { origin = r.origin }
    }

    private func importPicked(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        try? WidgetWallpaper.saveSource(data)
        source = image
        savedSlots = []
        enabled = true
        WidgetWallpaper.isEnabled = true
    }

    /// 按当前拖框位置裁一张存盘。归一化坐标 → 原图像素矩形 → 缩到 2 倍点尺寸 → JPEG。
    private func save(image: UIImage, boxW: CGFloat, boxH: CGFloat) {
        let rect = CGRect(x: origin.x, y: origin.y, width: boxW, height: boxH)
        WidgetWallpaper.setNormalizedRect(rect, for: slot)
        guard let data = Self.crop(image, normalized: rect, slot: slot) else { return }
        try? WidgetWallpaper.saveCropped(data, for: slot)
        savedSlots.insert(slot)
        WidgetRefresher.reload()
    }

    private func remove() {
        WidgetWallpaper.clear()
        source = nil
        savedSlots = []
        enabled = false
        WidgetRefresher.reload()
    }

    /// UIImage 的 `size` 是点，CGImage 是像素，两者差一个 scale——
    /// 截图走 Data 进来时 scale 恒为 1，但仍按 cgImage 的真实像素算，避免机型差异裁偏。
    nonisolated static func crop(_ image: UIImage, normalized: CGRect, slot: WidgetWallpaper.Slot) -> Data? {
        guard let cg = image.cgImage else { return nil }
        let pw = CGFloat(cg.width), ph = CGFloat(cg.height)
        let pixelRect = CGRect(x: (normalized.origin.x * pw).rounded(),
                               y: (normalized.origin.y * ph).rounded(),
                               width: (normalized.width * pw).rounded(),
                               height: (normalized.height * ph).rounded())
            .intersection(CGRect(x: 0, y: 0, width: pw, height: ph))
        guard !pixelRect.isEmpty, let cropped = cg.cropping(to: pixelRect) else { return nil }

        let targetW = min(slot.outputPixelWidth, pixelRect.width)
        let targetH = targetW * pixelRect.height / pixelRect.width
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let out = UIGraphicsImageRenderer(size: CGSize(width: targetW, height: targetH), format: format)
            .image { _ in
                UIImage(cgImage: cropped).draw(in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
            }
        return out.jpegData(compressionQuality: 0.9)
    }
}
