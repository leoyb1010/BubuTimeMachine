import SwiftUI

// MARK: - 家人互动（契约 2.27，存在布布侧，不写回第二大脑）
/// 小红心 + 简短留言。红心先乐观更新，失败回滚。服务端还没部署这一组接口时整块隐藏。
struct TimelineSocialSection: View {
    let client: BubuLearningClient
    let itemID: String
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var social: TimelineSocialDTO?
    @State private var hidden = false
    @State private var draft = ""
    @State private var sending = false
    @State private var errorText: String?
    @State private var heartBusy = false
    @State private var pendingDelete: TimelineCommentDTO?
    @FocusState private var focused: Bool

    static let maxLength = 300

    var body: some View {
        Group {
            if !hidden {
                VStack(alignment: .leading, spacing: BubuTheme.Spacing.m) {
                    header
                    if let social {
                        ForEach(social.comments) { comment in
                            commentRow(comment)
                                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                        }
                        composer
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    if let errorText {
                        Text(errorText).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.danger)
                    }
                }
                .padding(BubuTheme.Spacing.item)
                .background(BubuTheme.Color.card.opacity(0.92), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
            }
        }
        .task(id: active ? itemID : "") {
            guard active, social == nil, !hidden else { return }
            await load()
        }
        .confirmationDialog("删除这条留言？", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let comment = pendingDelete { Task { await delete(comment) } }
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        }
    }

    private var path: String { "api/online-timeline/\(itemID)" }

    private var header: some View {
        HStack(spacing: BubuTheme.Spacing.s) {
            Text("家人的悄悄话").font(BubuTheme.Font.caption.weight(.bold)).foregroundStyle(BubuTheme.Color.deepRose)
            Spacer()
            Button { Task { await toggleHeart() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: social?.hearted == true ? "heart.fill" : "heart")
                        .foregroundStyle(BubuTheme.Color.primary)
                        .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : (social?.hearted ?? false))
                    Text("\(social?.hearts ?? 0)").font(BubuTheme.Font.body.weight(.bold).monospacedDigit())
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(BubuTheme.Color.pinkSurface, in: Capsule())
            }
            .buttonStyle(BubuPressableStyle(scale: 0.92))
            .disabled(social == nil || heartBusy)
            .accessibilityLabel(social?.hearted == true ? "取消小红心" : "送一颗小红心")
            .accessibilityValue("\(social?.hearts ?? 0) 颗")
            .accessibilityIdentifier("timeline.heart")
        }
    }

    private func commentRow(_ comment: TimelineCommentDTO) -> some View {
        HStack(alignment: .top, spacing: BubuTheme.Spacing.s) {
            Text(String(comment.author.prefix(1))).font(BubuTheme.Font.caption.weight(.heavy)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(BubuTheme.Color.actionFill, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(comment.author).font(BubuTheme.Font.caption.weight(.bold)).foregroundStyle(BubuTheme.Color.warmBrown)
                    if let date = comment.createdAt.flatMap(BubuLearningDates.parseISO) {
                        Text(date.formatted(.relative(presentation: .named).locale(Locale(identifier: "zh_CN"))))
                            .font(BubuTheme.Font.scaled(11, weight: .medium)).foregroundStyle(BubuTheme.Color.secondaryText)
                    }
                }
                Text(comment.text).font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.warmBrown).textSelection(.enabled)
            }
            Spacer(minLength: 0)
            if comment.isMine {
                Button { pendingDelete = comment } label: {
                    Image(systemName: "trash").font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("删除我的留言")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: BubuTheme.Spacing.s) {
            VStack(alignment: .trailing, spacing: 2) {
                TextField("说一句悄悄话…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .font(BubuTheme.Font.body)
                    .focused($focused)
                    .onChange(of: draft) { _, value in
                        if value.count > Self.maxLength { draft = String(value.prefix(Self.maxLength)) }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(BubuTheme.Color.softFill.opacity(0.6), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.xs, style: .continuous))
                    .accessibilityIdentifier("timeline.comment.input")
                if draft.count > Self.maxLength - 60 {
                    Text("\(draft.count)/\(Self.maxLength)").font(BubuTheme.Font.scaled(11, weight: .medium).monospacedDigit())
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
            }
            Button { Task { await post() } } label: {
                if sending {
                    ProgressView().frame(width: 34, height: 34)
                } else {
                    Image(systemName: "paperplane.circle.fill").font(.system(size: 34, design: .rounded))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, trimmed.isEmpty ? BubuTheme.Color.softFill : BubuTheme.Color.actionFill)
                }
            }
            .buttonStyle(BubuPressableStyle(scale: 0.9))
            .disabled(trimmed.isEmpty || sending)
            .accessibilityLabel("发送留言")
            .accessibilityIdentifier("timeline.comment.send")
        }
    }

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: Network

    private func load() async {
        do {
            let value = try await client.get(path + "/social", as: TimelineSocialDTO.self)
            withAnimation(reduceMotion ? nil : BubuMotion.gentle) { social = value }
            errorText = nil
        } catch is CancellationError {
        } catch {
            if GrowthServiceAvailability.hides(error) { hidden = true } else { errorText = learningErrorText(error) }
        }
    }

    private func toggleHeart() async {
        guard var current = social, !heartBusy else { return }
        let previous = current
        current.hearted.toggle()
        current.hearts = max(0, current.hearts + (current.hearted ? 1 : -1))
        withAnimation(reduceMotion ? nil : BubuMotion.quick) { social = current }
        current.hearted ? BubuHaptics.success() : BubuHaptics.selection()
        heartBusy = true
        defer { heartBusy = false }
        do {
            let result = try await client.send("POST", path + "/heart", body: TimelineHeartBody(on: current.hearted), as: TimelineHeartDTO.self)
            social?.hearts = result.hearts
            social?.hearted = result.hearted
            errorText = nil
        } catch {
            withAnimation(reduceMotion ? nil : BubuMotion.quick) {
                social?.hearts = previous.hearts
                social?.hearted = previous.hearted
            }
            errorText = learningErrorText(error, fallback: "小红心没有送出去，请稍后再试。")
        }
    }

    private func post() async {
        let text = String(trimmed.prefix(Self.maxLength))
        guard !text.isEmpty, !sending else { return }
        sending = true
        defer { sending = false }
        do {
            let comment = try await client.send("POST", path + "/comments", body: TimelineCommentBody(text: text), as: TimelineCommentDTO.self)
            withAnimation(reduceMotion ? nil : BubuMotion.gentle) { social?.comments.append(comment) }
            draft = ""
            focused = false
            errorText = nil
            BubuHaptics.success()
        } catch {
            errorText = learningErrorText(error, fallback: "留言没有发出去，请稍后再试。")
        }
    }

    private func delete(_ comment: TimelineCommentDTO) async {
        pendingDelete = nil
        do {
            _ = try await client.send("DELETE", path + "/comments/\(comment.id)", as: LearningEmptyResponse.self)
        } catch {
            errorText = learningErrorText(error, fallback: "没有删掉，请稍后再试。")
            return
        }
        await load()
        if social?.comments.contains(where: { $0.id == comment.id }) == true {
            errorText = "没有删掉，请稍后再试。"
        } else {
            BubuHaptics.selection()
        }
    }
}
