import SwiftUI

// MARK: - 第二大脑数据说明（首次使用时一次性确认）
/// 时光与每日学习会读取家里第二大脑整理的内容；画面描述、人物归类和课程解析用的是云端 Gemini。
/// 这与“默认离线”的本机记录不同，所以第一次连接时如实说明，家人确认后才继续。
struct SecondBrainConsentModifier: ViewModifier {
    let active: Bool
    /// v3（2.26）：加了布布问答和地点查询的说明，老用户会再确认一次。
    nonisolated static let storageKey = "bubu.privacy.secondBrain.v3"
    @AppStorage(SecondBrainConsentModifier.storageKey) private var accepted = false

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(get: { active && !accepted }, set: { _ in })) {
            SecondBrainConsentSheet(onAccept: { accepted = true })
                .interactiveDismissDisabled()
        }
    }
}

extension View {
    /// Shown once per install the first time a screen actually uses the family service.
    func secondBrainConsent(active: Bool) -> some View {
        modifier(SecondBrainConsentModifier(active: active))
    }
}

private struct SecondBrainConsentSheet: View {
    let onAccept: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BubuTheme.Spacing.item) {
                BubuMascotBadge(size: 96, expression: .happy).frame(maxWidth: .infinity)
                Text("布布的照片是怎么被整理的").font(BubuTheme.Font.title).foregroundStyle(BubuTheme.Color.warmBrown)
                point("photo.stack", "时光里的照片和视频，来自家里 Mac mini 上的第二大脑。原片只存在家里的硬盘上。")
                point("sparkles", "画面描述、识别文字、视频转写和“这是不是布布”的归类，由第二大脑调用云端 Gemini 模型完成，只上传压缩后的缩略图或短片段。")
                point("text.bubble", "为了让描述读起来像家里人说话，第二大脑会把描述文字（含布布的全名）交给 Gemini 改写称呼；每月成长小报会把当月的描述、地点和家人称谓交给 Gemini 写成一段话。")
                point("waveform", "「布布的声音」会把视频里几秒钟的短音频（可能包含大人的声音）交给 Gemini 复听，确认她说了什么。")
                point("questionmark.bubble", "「布布问答」会把你问的问题和找到的几条画面描述交给 Gemini，请它组织成一句回答。")
                point("map", "「去过的地方」只把地名（比如“上海市·世纪公园”）交给 Apple 地图查位置，不发照片。")
                point("graduationcap", "每日学习里上传的课程视频，保存在家庭服务器，并由 Gemini 解析出题；只有家人账号能看。")
                point("lock.shield", "这些内容都要用家庭账号登录才能打开，不会公开分享；家人记下的文字和语音仍然只存在手机里，除非开启同步。")
                point("gearshape", "随时可以在设置里断开家庭服务，断开后时光只显示家人记录。")
                Button(action: onAccept) {
                    Text("知道了，继续").font(BubuTheme.Font.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(BubuTheme.Gradient.primaryButton, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.button, style: .continuous))
                }
                .buttonStyle(BubuPressableStyle())
                .accessibilityIdentifier("consent.accept")
            }
            .padding(BubuTheme.Spacing.l)
        }
        .background(BubuTheme.Color.background)
        .bubuLayoutRoot()   // 弹窗布局根
        .presentationDetents([.large])
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: BubuTheme.Spacing.m) {
            Image(systemName: symbol).font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.deepRose).frame(width: 28)
            Text(text).font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.warmBrown)
        }
    }
}
