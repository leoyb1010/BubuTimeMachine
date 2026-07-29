import Testing
import Foundation
import UIKit
@testable import BubuTimeMachine

// MARK: - 桌面壁纸裁剪回归测试
/// 伪透明小组件成立的前提，是「用户在预览里拖的那个框」和「小组件真正拿到的那块壁纸」
/// 严格对应。这段换算错一点，桌面上的小组件底就会和身后的壁纸错位——
/// 那比不透明还难看，而且肉眼很难判断错了多少。所以把坐标换算钉在这里。
///
/// 覆盖三件事：归一化坐标 → 像素矩形的映射、输出尺寸的收敛、越界时不炸。
@MainActor
struct WidgetWallpaperCropTests {

    /// 造一张四象限纯色图：左上红、右上绿、左下蓝、右下黄。
    /// 裁哪个象限就该得到哪种颜色——这是判断"裁对位置"最直接的证据。
    private func quadrantImage(size: CGFloat = 400) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { ctx in
            let half = size / 2
            let cells: [(CGRect, UIColor)] = [
                (CGRect(x: 0, y: 0, width: half, height: half), .red),
                (CGRect(x: half, y: 0, width: half, height: half), .green),
                (CGRect(x: 0, y: half, width: half, height: half), .blue),
                (CGRect(x: half, y: half, width: half, height: half), .yellow),
            ]
            for (rect, color) in cells {
                color.setFill()
                ctx.fill(rect)
            }
        }
    }

    /// 取图正中心那一像素的颜色。
    private func centerColor(_ image: UIImage) -> (r: Int, g: Int, b: Int)? {
        guard let cg = image.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: -CGFloat(cg.width) / 2 + 0.5, y: -CGFloat(cg.height) / 2 + 0.5,
                                width: CGFloat(cg.width), height: CGFloat(cg.height)))
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }

    @Test("裁左上角得到红色象限")
    func cropsTopLeftQuadrant() throws {
        let src = quadrantImage()
        let data = try #require(WidgetWallpaperView.crop(
            src, normalized: CGRect(x: 0.05, y: 0.05, width: 0.4, height: 0.4), slot: .small))
        let out = try #require(UIImage(data: data))
        let c = try #require(centerColor(out))
        #expect(c.r > 200 && c.g < 60 && c.b < 60)
    }

    @Test("裁右下角得到黄色象限——证明 x/y 没有对调")
    func cropsBottomRightQuadrant() throws {
        let src = quadrantImage()
        let data = try #require(WidgetWallpaperView.crop(
            src, normalized: CGRect(x: 0.55, y: 0.55, width: 0.4, height: 0.4), slot: .small))
        let out = try #require(UIImage(data: data))
        let c = try #require(centerColor(out))
        #expect(c.r > 200 && c.g > 200 && c.b < 80)
    }

    @Test("裁右上角得到绿色——x/y 对调的话这里会变成蓝色")
    func cropsTopRightQuadrant() throws {
        let src = quadrantImage()
        let data = try #require(WidgetWallpaperView.crop(
            src, normalized: CGRect(x: 0.55, y: 0.05, width: 0.4, height: 0.4), slot: .small))
        let out = try #require(UIImage(data: data))
        let c = try #require(centerColor(out))
        #expect(c.g > 130 && c.b < 90)
    }

    @Test("输出宽度收敛到该尺寸的目标像素，且保持裁框的宽高比")
    func clampsOutputSize() throws {
        let src = quadrantImage(size: 3000)
        let rect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.4)
        let data = try #require(WidgetWallpaperView.crop(src, normalized: rect, slot: .medium))
        let out = try #require(UIImage(data: data))
        #expect(out.size.width == WidgetWallpaper.Slot.medium.outputPixelWidth)
        // 高宽比跟随裁框（0.4/0.8 = 0.5），允许 1px 的取整误差。
        #expect(abs(out.size.height / out.size.width - 0.5) < 0.01)
    }

    @Test("裁框超出图片边界时只取交集，不返回 nil、不崩")
    func clipsOutOfBoundsRect() throws {
        let src = quadrantImage()
        let data = try #require(WidgetWallpaperView.crop(
            src, normalized: CGRect(x: 0.8, y: 0.8, width: 0.5, height: 0.5), slot: .small))
        let out = try #require(UIImage(data: data))
        #expect(out.size.width > 0 && out.size.height > 0)
    }

    @Test("完全在图片外的裁框返回 nil，而不是给出一张空图")
    func rejectsFullyOutsideRect() {
        let src = quadrantImage()
        let data = WidgetWallpaperView.crop(
            src, normalized: CGRect(x: 1.5, y: 1.5, width: 0.2, height: 0.2), slot: .small)
        #expect(data == nil)
    }

    // MARK: 桌面网格

    /// iPhone 17 Pro Max：440×956pt。用户真机截图上量出来的位置——
    /// 大卡 (38.7, 99.8) 365×383、中卡第三行 top≈521pt。网格必须落在这些数上。
    private let proMaxAspect: CGFloat = 956.0 / 440.0

    @Test("候选位数量：中/小卡 3 行、大卡 2 个落位、小卡还分左右两列")
    func slotCounts() {
        #expect(WidgetWallpaper.HomeGrid.slots(for: .large, aspect: proMaxAspect).count == 2)
        #expect(WidgetWallpaper.HomeGrid.slots(for: .medium, aspect: proMaxAspect).count == 3)
        #expect(WidgetWallpaper.HomeGrid.slots(for: .small, aspect: proMaxAspect).count == 6)
    }

    @Test("大卡首个落位对上真机量出来的坐标")
    func largeFirstSlotMatchesDevice() throws {
        let s = try #require(WidgetWallpaper.HomeGrid.slots(for: .large, aspect: proMaxAspect).first)
        // 归一化：x=38.7/440、y=99.8/956、w=364/440、h=382/956
        #expect(abs(s.minX - 38.7 / 440) < 0.005)
        #expect(abs(s.minY - 99.8 / 956) < 0.005)
        #expect(abs(s.width - 364.0 / 440) < 0.005)
        #expect(abs(s.height - 382.0 / 956) < 0.005)
    }

    @Test("中卡第三行对上真机量出来的 521pt")
    func mediumThirdRowMatchesDevice() throws {
        let rows = WidgetWallpaper.HomeGrid.slots(for: .medium, aspect: proMaxAspect)
        #expect(abs(rows[2].minY - 521.0 / 956) < 0.008)
        #expect(abs(rows[0].minY - 99.8 / 956) < 0.005)
    }

    @Test("小卡左右两列关于屏幕中线对称")
    func smallColumnsAreSymmetric() {
        let s = WidgetWallpaper.HomeGrid.slots(for: .small, aspect: proMaxAspect)
        let left = s[0], right = s[1]
        #expect(abs(left.minY - right.minY) < 0.0001)      // 同一行
        #expect(abs(left.minX - (1 - right.maxX)) < 0.0001) // 左右边距相等
        #expect(right.minX > left.maxX)                     // 不重叠
    }

    @Test("所有候选位都完整落在图内")
    func slotsStayInsideImage() {
        for slot in WidgetWallpaper.Slot.allCases {
            for r in WidgetWallpaper.HomeGrid.slots(for: slot, aspect: proMaxAspect) {
                #expect(r.minX >= 0 && r.minY >= 0 && r.maxX <= 1.0001 && r.maxY <= 1.0001,
                        "\(slot) 的候选位越界：\(r)")
            }
        }
    }

    @Test("aspect 非法时返回空，不产生除零的鬼坐标")
    func rejectsInvalidAspect() {
        #expect(WidgetWallpaper.HomeGrid.slots(for: .large, aspect: 0).isEmpty)
    }

    @Test("三种尺寸的宽高比与真机小组件一致")
    func slotAspectRatios() {
        #expect(WidgetWallpaper.Slot.small.heightOverWidth == 1.0)
        #expect(abs(WidgetWallpaper.Slot.medium.heightOverWidth - 170.0 / 364.0) < 0.0001)
        #expect(abs(WidgetWallpaper.Slot.large.heightOverWidth - 382.0 / 364.0) < 0.0001)
        // 大卡和中卡同宽，只有小卡窄。
        #expect(WidgetWallpaper.Slot.large.widthRatio == WidgetWallpaper.Slot.medium.widthRatio)
        #expect(WidgetWallpaper.Slot.small.widthRatio < WidgetWallpaper.Slot.medium.widthRatio)
    }
}
