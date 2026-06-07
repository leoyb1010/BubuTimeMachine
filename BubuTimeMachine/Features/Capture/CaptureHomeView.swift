import SwiftUI
import SwiftData
import PhotosUI

// MARK: - 记录此刻 首页
/// 姥姥场景关键交付物：一个巨型主按钮 + 纯语音入口。首屏极简。
struct CaptureHomeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @State private var model: CaptureModel?

    var body: some View {
        ZStack {
            BubuTheme.Color.background.ignoresSafeArea()

            if let model {
                content(model: model)
            }
        }
        .navigationTitle("布布时光机")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if model == nil {
                model = CaptureModel(mediaStore: env.mediaStore,
                                     role: env.config.currentRole)
            }
        }
    }

    @ViewBuilder
    private func content(model: CaptureModel) -> some View {
        @Bindable var model = model
        VStack(spacing: BubuTheme.Spacing.section) {
            Spacer()

            Text("留住布布的每一个此刻")
                .font(BubuTheme.Font.headline)
                .foregroundStyle(BubuTheme.Color.secondaryText)

            BigButton(title: BubuTheme.Copy.recordNow,
                      systemImage: "heart.circle.fill") {
                model.startQuickCapture()
            }
            .accessibilityLabel("记录此刻，可以拍照、录视频或说话")
            .padding(.horizontal)

            Button {
                // 纯语音入口（成长之声 / 语音补充）将在对应模块深入
                model.startQuickCapture()
            } label: {
                Label(BubuTheme.Copy.speakToBubu, systemImage: "mic.fill")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.primary)
            }

            Spacer()
        }
        .padding()
        .overlay(alignment: .top) {
            if model.savedFlash {
                savedToast
            }
        }
        .sheet(isPresented: $model.showQuickCapture) {
            QuickCaptureSheet(model: model)
        }
    }

    private var savedToast: some View {
        Label("已经收好啦", systemImage: "checkmark.circle.fill")
            .font(BubuTheme.Font.body)
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(BubuTheme.Color.success, in: Capsule())
            .bubuCardShadow()
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}
