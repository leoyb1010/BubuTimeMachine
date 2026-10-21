import SwiftUI

/// Read-only derived information. The original media and the family's own text remain authoritative.
struct EntryMediaAnalysisSection: View {
    let media: [Media]
    let onPlay: (UUID, Double) -> Void
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if !media.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("素材解析", systemImage: "text.viewfinder").font(BubuTheme.Font.headline)
                if let access = LearningServiceAccess(env) {
                    ForEach(Array(media.enumerated()), id: \.element.id) { index, item in
                        if item.type == .photo || item.type == .video {
                            MediaAnalysisRow(media: item, number: index + 1, access: access,
                                             initiallyExpanded: index == 0, onPlay: onPlay)
                        }
                    }
                } else {
                    Text("开启已连接的家庭 AI 服务后，这里会显示第二大脑整理的描述、文字和视频片段。")
                        .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card))
            .accessibilityIdentifier("entry.media-analysis")
        }
    }
}

private struct MediaAnalysisRow: View {
    let media: Media
    let number: Int
    let access: LearningServiceAccess
    let onPlay: (UUID, Double) -> Void
    @State private var expanded: Bool

    init(media: Media, number: Int, access: LearningServiceAccess, initiallyExpanded: Bool,
         onPlay: @escaping (UUID, Double) -> Void) {
        self.media = media; self.number = number; self.access = access; self.onPlay = onPlay
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if expanded {
                if let remoteID = media.remoteId, !remoteID.isEmpty {
                    let key = MediaAnalysisCache.Key(service: access.baseURL.absoluteString, account: access.account,
                                                     mediaID: remoteID, contentHash: media.contentHash)
                    MediaAnalysisContent(access: access, key: key, isVideo: media.type == .video,
                                         onPlay: { onPlay(media.id, $0) })
                        .id(ContentIdentity(access: access, key: key))
                } else {
                    Text("这份素材还在手机里，完成家庭同步后即可查看解析。")
                        .font(BubuTheme.Font.caption).padding(.vertical, 8)
                }
            }
        } label: {
            Label("\(media.type == .video ? "视频" : "照片") \(number)", systemImage: media.type == .video ? "video" : "photo")
                .font(BubuTheme.Font.body.weight(.medium))
        }
    }
    private struct ContentIdentity: Hashable { let access: LearningServiceAccess; let key: MediaAnalysisCache.Key }
}

private struct MediaAnalysisContent: View {
    let access: LearningServiceAccess
    let key: MediaAnalysisCache.Key
    let isVideo: Bool
    let onPlay: (Double) -> Void
    @Environment(AppEnvironment.self) private var env
    @State private var analysis: MediaAnalysisDTO?
    @State private var fetchedAt: Date?
    @State private var showingCache = false
    @State private var loading = false
    @State private var message: String?
    @State private var sourceChanged = false
    @State private var revisionChanged = false
    @State private var requestID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let message {
                Text(message).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.warmBrown)
            }
            if showingCache, let fetchedAt {
                Text("设备缓存 · 最近获取于 \(fetchedAt.formatted(.dateTime.month().day().hour().minute()))")
                    .font(.caption).foregroundStyle(BubuTheme.Color.secondaryText)
            }
            if let analysis {
                HStack(alignment: .top) {
                    Text(stateLabel(analysis.state)).font(.subheadline.weight(.semibold))
                    Spacer()
                    if let revision = analysis.revision { Text("版本 \(revision)").font(.caption) }
                }
                Text("来源：\(providerLabel(analysis.provider))")
                    .font(.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                if let updated = analysis.updatedAt, let date = Self.isoDate(updated) {
                    Text("更新于 \(date.formatted(.dateTime.month().day().hour().minute()))")
                        .font(.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                }
                if revisionChanged { Text("解析版本已更新，以下为最新结果。").font(.caption) }
                if analysis.state == "ready" {
                    readyContent(analysis)
                } else {
                    Text(stateDescription(analysis.state)).font(.callout)
                }
                ForEach(Array(analysis.warnings.enumerated()), id: \.offset) { _, warning in
                    Text(warning).font(.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                }
            } else if loading { ProgressView("正在获取素材解析…") }
            HStack {
                Button(analysis?.state == "failed" ? "重新解析" : "刷新解析") {
                    Task { await load(retry: analysis?.state == "failed") }
                }.disabled(loading)
                if loading, analysis != nil { ProgressView().controlSize(.small) }
            }.font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 10)
        .task { await load() }
        .onDisappear { requestID = UUID() }
    }

    @ViewBuilder
    private func readyContent(_ value: MediaAnalysisDTO) -> some View {
        if !value.descriptionText.isEmpty { Text(value.descriptionText).font(.callout).textSelection(.enabled) }
        if !value.tags.isEmpty {
            Text(value.tags.joined(separator: " · ")).font(.caption).foregroundStyle(BubuTheme.Color.secondaryText)
        }
        if !value.ocr.isEmpty {
            DisclosureGroup("识别出的文字") {
                Text(value.ocr).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        if sourceChanged {
            Text("原片版本已变化，请先同步家庭记录，再核对这些片段。时间码跳转暂时关闭。")
                .font(.caption).foregroundStyle(BubuTheme.Color.secondaryText)
        } else if key.contentHash == nil || value.contentHash == nil {
            Text("原片校验信息尚未齐全，时间码以当前文件为准。")
                .font(.caption).foregroundStyle(BubuTheme.Color.secondaryText)
        }
        ForEach(Array(value.segments.enumerated()), id: \.offset) { _, segment in
            if isVideo, !sourceChanged, let start = segment.start, start.isFinite, start >= 0,
               segment.end == nil || (segment.end!.isFinite && segment.end! >= start) {
                Button { onPlay(start) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Label(Self.timecode(start), systemImage: "play.circle")
                            .font(.caption.monospacedDigit()).fixedSize()
                        Text(segment.text).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 6).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("从 \(Self.timecode(start)) 播放：\(segment.text)")
            } else if !segment.text.isEmpty { Text(segment.text).font(.callout).textSelection(.enabled) }
        }
        if value.descriptionText.isEmpty, value.ocr.isEmpty, value.segments.isEmpty {
            Text("解析已完成，暂未返回可展示的文字。").font(.callout)
        }
        Text("机器识别结果，可对照原件核对；不会改写家人留下的话。")
            .font(.caption).foregroundStyle(BubuTheme.Color.secondaryText)
    }

    private func load(retry: Bool = false) async {
        let attempt = UUID()
        requestID = attempt; loading = true; message = nil
        defer { if requestID == attempt { loading = false } }
        guard LearningServiceAccess(env) == access else { analysis = nil; return }
        let cache = MediaAnalysisCache.shared
        if analysis == nil, let saved = await cache.load(for: key) {
            guard requestID == attempt, !Task.isCancelled, LearningServiceAccess(env) == access else { return }
            analysis = saved.analysis; fetchedAt = saved.fetchedAt; showingCache = true
        }
        let previous = analysis
        let api = env.apiClient
        let service = MediaAnalysisClient(baseURL: access.baseURL)
        do {
            let token = try await api.authenticate(role: "ai").token
            guard requestID == attempt, !Task.isCancelled, LearningServiceAccess(env) == access else { return }
            let result = try await (retry ? service.retry(mediaID: key.mediaID, token: token)
                                         : service.fetch(mediaID: key.mediaID, token: token))
            guard requestID == attempt, !Task.isCancelled, LearningServiceAccess(env) == access else { return }
            if let expected = key.contentHash, !expected.isEmpty,
               let actual = result.contentHash, !actual.isEmpty, actual != expected {
                analysis = nil; showingCache = false; sourceChanged = true
                message = "原片版本已变化，请先同步家庭记录，再查看对应解析。旧解析已移出缓存。"
                await cache.remove(for: key)
                let latestKey = MediaAnalysisCache.Key(service: key.service, account: key.account,
                                                       mediaID: key.mediaID, contentHash: actual)
                try? await cache.save(result, for: latestKey)
                return
            }
            sourceChanged = previous?.contentHash != nil && result.contentHash != nil
                && previous?.contentHash != result.contentHash
            revisionChanged = previous?.revision != nil && result.revision != nil && previous?.revision != result.revision
            analysis = result; fetchedAt = .now; showingCache = false
            try? await cache.save(result, for: key)
        } catch {
            guard requestID == attempt, !Task.isCancelled, LearningServiceAccess(env) == access else { return }
            let serviceError = error as? LearningServiceError
            var invalidates = serviceError?.invalidatesCache ?? false
            if let apiError = error as? APIError {
                switch apiError {
                case .unauthorized, .forbidden, .notConfigured: invalidates = true
                default: break
                }
            }
            if invalidates {
                analysis = nil; showingCache = false
                await cache.remove(for: key)
            } else { showingCache = analysis != nil }
            message = serviceError?.errorDescription ?? (invalidates
                ? "家庭身份需要重新连接，暂不显示这份解析。"
                : "暂时未能刷新解析，可稍后重试。")
        }
    }

    private func stateLabel(_ state: String) -> String {
        switch state {
        case "ready": "解析已完成"
        case "queued": "等待第二大脑"
        case "processing": "正在解析"
        case "failed": "解析未完成"
        default: "解析暂不可用"
        }
    }
    private func stateDescription(_ state: String) -> String {
        switch state {
        case "queued": "等待第二大脑同步素材与解析，稍后点刷新即可查看。"
        case "processing": "第二大脑正在整理这份素材，稍后点刷新查看结果。"
        case "failed": "这次解析没有完成，可以重新解析；原件仍保留。"
        default: "第二大脑暂未提供这份素材的解析。"
        }
    }
    private func providerLabel(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "服务端未提供来源" }
        return value == "second-brain" ? "第二大脑" : value
    }
    private static func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "—" }
        let value = Int(seconds)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
    private static func isoDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
