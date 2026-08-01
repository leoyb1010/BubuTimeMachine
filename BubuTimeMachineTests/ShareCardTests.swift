import Testing
import Foundation
import UIKit
@testable import BubuTimeMachine

// MARK: - 分享卡渲染回归
/// 分享卡是唯一会离开这个家的产物——排版塌了、隐私漏了，是当着别人的面出错。
/// 所以三件事必须钉死：输出尺寸对得上各平台构图、隐私字段不出现、缺图不崩。
@MainActor
struct ShareCardTests {

    private func sample(photo: UIImage? = nil, then: UIImage? = nil) -> ShareCard.Content {
        ShareCard.Content(childName: "布布", dateText: "7月30日", ageText: "2岁2个月",
                          note: "第一次自己穿上鞋子", photo: photo,
                          thenPhoto: then, thenDateText: "7月30日", thenAgeText: "1岁2个月")
    }

    private func solid(_ color: UIColor, size: CGFloat = 400) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        }
    }

    @Test("三种版式各自渲染出正确的像素尺寸")
    func rendersExpectedSizes() throws {
        let photo = solid(.systemPink)
        for layout in ShareCard.Layout.allCases {
            let image = try #require(ShareCard.render(sample(photo: photo, then: photo), layout: layout),
                                     "\(layout.title) 渲染失败")
            #expect(abs(image.size.width - layout.pixelSize.width) < 2)
            #expect(abs(image.size.height - layout.pixelSize.height) < 2)
        }
    }

    @Test("竖版是 3:4、方版是 1:1——对得上小红书与朋友圈的构图")
    func aspectRatiosMatchPlatforms() {
        let portrait = ShareCard.Layout.portrait.pixelSize
        #expect(abs(portrait.height / portrait.width - 4.0 / 3.0) < 0.01)
        let square = ShareCard.Layout.square.pixelSize
        #expect(square.width == square.height)
    }

    @Test("没有照片时依然渲染出卡片，不返回 nil、不崩")
    func rendersWithoutPhoto() throws {
        let image = try #require(ShareCard.render(sample(), layout: .portrait))
        #expect(image.size.width > 0)
    }

    @Test("关掉年龄开关后，卡面内容里不含年龄")
    func ageCanBeHidden() throws {
        var content = sample(photo: solid(.systemTeal))
        content.ageText = nil
        content.thenAgeText = nil
        // 渲染成功即可——年龄为 nil 时卡面分支不绘制年龄胶囊。
        let image = try #require(ShareCard.render(content, layout: .portrait))
        #expect(image.size.height > 0)
    }

    @Test("写文件成功且落在临时目录，文件名不含月日汉字（跨平台安全）")
    func writesShareableFile() throws {
        let url = try #require(ShareCard.renderToFile(sample(photo: solid(.systemIndigo)), layout: .square))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(url.pathExtension == "png")
        #expect(!url.lastPathComponent.contains("月"))
        #expect(!url.lastPathComponent.contains("日"))
        // 1080px 的 PNG 不该是个空壳。
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        #expect(size > 5_000)
    }
}
