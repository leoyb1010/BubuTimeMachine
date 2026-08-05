import SwiftData
import SwiftUI
import UIKit

/// 端侧“认布布”控制台。默认关闭；样本只保存在当前设备 App Group 中，不随档案同步。
struct ChildIdentitySettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(sort: \ChildProfile.createdAt) private var profiles: [ChildProfile]

    @State private var enabled = false
    @State private var positiveCount = 0
    @State private var negativeCount = 0
    @State private var working = false
    @State private var message: String?
    @State private var showClearConfirmation = false

    private let recognizer = ChildIdentityRecognizer()
    private var profile: ChildProfile? { profiles.first }

    var body: some View {
        Form {
            Section {
                Toggle("在这台 iPhone 认出布布", isOn: Binding(
                    get: { enabled },
                    set: { newValue in Task { await setRecognitionEnabled(newValue) } }
                ))
                .disabled(working)

                if working {
                    HStack {
                        ProgressView()
                        Text("正在端侧学习头像…")
                    }
                } else if positiveCount > 0 {
                    LabeledContent("本机模型", value: "布布 \(positiveCount) 张脸 · 排除 \(negativeCount) 张脸")
                } else {
                    Text("还没有可用的人脸样本。先在“布布的档案”里选一张清楚的正脸头像。")
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }

                Button {
                    Task { await learnCurrentAvatar() }
                } label: {
                    Label("用当前头像学习一次", systemImage: "person.crop.circle.badge.checkmark")
                }
                .disabled(working || profile?.avatarMediaFileName == nil)
            } header: {
                Text("认布布与精选")
            } footer: {
                Text("只用来给待整理照片加“可能是布布”的建议。即使很确定，也不会自动发布、上传或删除照片。")
            }

            Section("隐私边界") {
                privacyRow("人脸特征只存在这台 iPhone", icon: "iphone.gen3")
                privacyRow("不进入 PocketBase、日志或导出包", icon: "lock.shield.fill")
                privacyRow("“这是/不是布布”反馈只调整本机判断", icon: "hand.tap.fill")
            }

            Section {
                Button("清除本机识别模型", role: .destructive) {
                    showClearConfirmation = true
                }
                .disabled(working || (positiveCount == 0 && negativeCount == 0))
            } footer: {
                Text("关闭开关会保留样本，方便以后再开；清除会删除全部本机人脸特征，但不会影响头像、照片或时光记录。")
            }

            if let message {
                Section {
                    Text(message)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
            }
        }
        .navigationTitle("认布布与精选")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .bubuContentColumn(760)
        .scrollContentBackground(.hidden)
        .background(BubuTheme.Color.background)
        // 主导航是自绘悬浮条，不属于系统 tabBar；给极大字体的 Form 留出真实滚动尾距。
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 84) }
        .task { refreshStatus() }
        .confirmationDialog("清除这台 iPhone 上的识别模型？", isPresented: $showClearConfirmation,
                            titleVisibility: .visible) {
            Button("清除模型", role: .destructive) { clearModel() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只删除本机人脸特征，不删除任何照片、头像或时光记录。")
        }
    }

    private func privacyRow(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .foregroundStyle(BubuTheme.Color.warmBrown)
    }

    @MainActor
    private func setRecognitionEnabled(_ newValue: Bool) async {
        message = nil
        if !newValue {
            recognizer.setEnabled(false)
            refreshStatus()
            return
        }
        if positiveCount == 0 {
            await learnCurrentAvatar()
        } else {
            recognizer.setEnabled(true)
            refreshStatus()
        }
    }

    @MainActor
    private func learnCurrentAvatar() async {
        guard let fileName = profile?.avatarMediaFileName,
              let data = env.mediaStore.data(forMedia: fileName) else {
            message = "请先给布布设置一张清楚的正脸头像。"
            recognizer.setEnabled(false)
            refreshStatus()
            return
        }
        working = true
        defer { working = false }
        do {
            let learned = try await recognizer.learn(imageData: data, isChild: true)
            guard learned > 0 else {
                message = "这张头像没有检测到清楚的人脸，请换一张正脸照片再试。"
                recognizer.setEnabled(false)
                refreshStatus()
                return
            }
            recognizer.setEnabled(true)
            message = "已经只在本机学会了 \(learned) 张脸。之后可在待整理照片里继续纠正。"
            refreshStatus()
        } catch {
            recognizer.setEnabled(false)
            message = "本机模型暂时没能保存，照片和头像都没有改动。"
            refreshStatus()
        }
    }

    private func clearModel() {
        do {
            try recognizer.clearModel()
            message = "本机识别模型已清除。"
        } catch {
            message = "模型暂时没能清除，请稍后重试。"
        }
        refreshStatus()
    }

    private func refreshStatus() {
        guard let status = try? recognizer.status() else {
            enabled = false
            positiveCount = 0
            negativeCount = 0
            return
        }
        enabled = status.enabled
        positiveCount = status.positiveSamples
        negativeCount = status.negativeSamples
    }
}
