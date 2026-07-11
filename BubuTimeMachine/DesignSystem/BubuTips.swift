import TipKit

// MARK: - 渐进式功能引导（TipKit，R4 H-3）
/// 好功能不该藏着：在正确的位置、只出现一次的小气泡，把「收进绘本」「递给长辈」教给全家。
/// TipKit 自动管理展示频率与"看过即不再弹"，零持久化代码。

/// 时光详情右上角的小书图标：收进成长绘本。
struct StorybookTip: Tip {
    var title: Text { Text("收进绘本") }
    var message: Text? { Text("点这本小书，这条时光就会被编进布布的成长绘本。") }
    var image: Image? { Image(systemName: "book.fill") }
}

/// 设置里的长辈模式开关：递给长辈的一键交接。
struct SimpleModeTip: Tip {
    var title: Text { Text("递给长辈") }
    var message: Text? { Text("把手机递给爷爷奶奶前打开它：大字大按钮，只留拍照、录音、看布布。") }
    var image: Image? { Image(systemName: "hand.tap.fill") }
}

/// 首页今天拍的卡片：一键收进时光机。
struct TodayPhotosTip: Tip {
    var title: Text { Text("今天拍的照片") }
    var message: Text? { Text("拍完照打开 App，这里会主动帮你把今天的照片收进时光轴。") }
    var image: Image? { Image(systemName: "photo.badge.plus.fill") }
}
