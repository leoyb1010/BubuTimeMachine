import SwiftUI
import PhotosUI
import UIKit

// MARK: - 桌面壁纸（伪透明小组件）
/// 导入一张桌面截图 → 点中小组件所在的格子 → App 按那格裁好存进 App Group →
/// 小组件把那块壁纸当底，桌面上看起来就是透明的。
///
/// 为什么是「点格子」而不是「自由拖」：桌面小组件只能落在固定的几个位置上
/// （中/小卡 3 行、大卡 2 个落位、小卡还分左右两列），自由拖必然对不准，
/// 差几个像素桌面上就会露出错位的边。所以把全部候选位画出来让用户点，
/// 再留一个拖动做微调——万一某个机型的网格常数有偏差，还有救。
struct WidgetWallpaperView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var pickerItem: PhotosPickerItem?
    @State private var source: UIImage?
    @State private var slot: WidgetWallpaper.Slot = .large
    /// 当前选中的裁剪区域，相对整张截图归一化。`.zero` 表示还没选。
    @State private var rect: CGRect = .zero
    /// 按下那一刻的 rect。不存这个基准、直接在 onChanged 里累加 translation 的话，
    /// 位移会被每帧重复叠加（translation 本身就是从按下算起的累计量），框会飞出去——
    /// 这正是第一版「拖动不跟手」的原因。
    @State private var dragBase: CGRect?
    @State private var enabled = WidgetWallpaper.isEnabled
    @State private var savedSlots: Set<WidgetWallpaper.Slot> = []
    @State private var showRemoveConfirm = false

    /// 截图的 高÷宽。网格模型按「屏宽」为单位给常数，竖直方向要除以它才能换成归一化坐标。
    private var aspect: CGFloat {
        guard let source, source.size.width > 0 else { return 0 }
        return source.size.height / source.size.width
    }

    private var candidates: [CGRect] {
        WidgetWallpaper.HomeGrid.slots(for: slot, aspect: aspect)
    }

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
            step(3, "选尺寸，**点一下**小组件在桌面上所在的那个虚线格子就存好了。差一点可以按住框拖着微调。")
            Text("小组件的底会换成那块壁纸，桌面上看起来就是透明的。换了壁纸、或把小组件挪了位置，重新来一次即可。")
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
        // PhotosPicker 的 label 是 Sendable 闭包，里面取不到 MainActor 隔离的 env，
        // 必须用静态主题色。用 .images 而不是 .screenshots：截图被编辑过、
        // 或从别处存进相册就不算 screenshot，那样选择器会是空的。
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

    // MARK: 选格子

    private func positioner(_ image: UIImage) -> some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                ZStack(alignment: .topLeading) {
                    Image(uiImage: image)
                        .resizable().scaledToFill()
                        .frame(width: w, height: h)
                        .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.sm, style: .continuous))

                    // 候选格子：全画出来，点哪个选哪个。
                    ForEach(Array(candidates.enumerated()), id: \.offset) { _, c in
                        if !isSelected(c) {
                            RoundedRectangle(cornerRadius: BubuTheme.Radius.xs, style: .continuous)
                                .fill(.black.opacity(0.20))
                                .overlay(
                                    RoundedRectangle(cornerRadius: BubuTheme.Radius.xs, style: .continuous)
                                        .strokeBorder(.white.opacity(0.9),
                                                      style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                                )
                                .frame(width: c.width * w, height: c.height * h)
                                .offset(x: c.minX * w, y: c.minY * h)
                                .onTapGesture { select(c, image: image) }
                        }
                    }

                    // 选中的框：拖动微调。
                    if rect != .zero {
                        RoundedRectangle(cornerRadius: BubuTheme.Radius.xs, style: .continuous)
                            .fill(env.theme.theme.primary.opacity(0.22))
                            .overlay(
                                RoundedRectangle(cornerRadius: BubuTheme.Radius.xs, style: .continuous)
                                    .strokeBorder(env.theme.theme.primary, lineWidth: 2.5)
                            )
                            .overlay(
                                Label("就是这里", systemImage: "checkmark.circle.fill")
                                    .font(BubuTheme.Font.scaled(12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 9).padding(.vertical, 4)
                                    .background(env.theme.theme.primary, in: Capsule())
                            )
                            .frame(width: rect.width * w, height: rect.height * h)
                            .offset(x: rect.minX * w, y: rect.minY * h)
                            .gesture(
                                DragGesture()
                                    .onChanged { v in
                                        let base = dragBase ?? rect
                                        if dragBase == nil { dragBase = rect }
                                        rect.origin = CGPoint(
                                            x: min(max(base.minX + v.translation.width / w, 0), 1 - rect.width),
                                            y: min(max(base.minY + v.translation.height / h, 0), 1 - rect.height))
                                    }
                                    .onEnded { _ in
                                        dragBase = nil
                                        save(image: image)
                                    }
                            )
                    }
                }
                .frame(width: w, height: h)
            }
            .aspectRatio(aspect > 0 ? 1 / aspect : 0.46, contentMode: .fit)

            Text(hint)
                .font(BubuTheme.Font.caption)
                .foregroundStyle(rect == .zero ? BubuTheme.Color.secondaryText : BubuTheme.Color.success)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var hint: String {
        rect == .zero
            ? "点一下「\(slot.displayName)」在桌面上所在的格子"
            : "已保存 \(slot.displayName) 的位置 · 按住框可拖着微调"
    }

    /// 某候选位是不是当前选中的。拖过之后会有微小偏移，用容差判定，避免虚线框和实心框重叠画两遍。
    private func isSelected(_ c: CGRect) -> Bool {
        abs(c.minX - rect.minX) < 0.01 && abs(c.minY - rect.minY) < 0.01 && abs(c.width - rect.width) < 0.01
    }

    private var slotPicker: some View {
        Picker("尺寸", selection: $slot) {
            ForEach(WidgetWallpaper.Slot.allCases, id: \.self) { s in
                Text(savedSlots.contains(s) ? "\(s.displayName) ✓" : s.displayName).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: slot) { _, new in
            rect = WidgetWallpaper.normalizedRect(for: new) ?? .zero
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
        rect = WidgetWallpaper.normalizedRect(for: slot) ?? .zero
    }

    private func importPicked(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        try? WidgetWallpaper.saveSource(data)
        source = image
        savedSlots = []
        rect = .zero
        enabled = true
        WidgetWallpaper.isEnabled = true
    }

    private func select(_ candidate: CGRect, image: UIImage) {
        rect = candidate
        save(image: image)
    }

    /// 按当前框裁一张存盘。归一化坐标 → 原图像素矩形 → 缩到 2 倍点尺寸 → JPEG。
    private func save(image: UIImage) {
        guard rect != .zero else { return }
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
        rect = .zero
        enabled = false
        WidgetRefresher.reload()
    }

    /// UIImage 的 `size` 是点、CGImage 是像素，两者差一个 scale——
    /// 一律按 cgImage 的真实像素算，避免机型差异裁偏。
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
