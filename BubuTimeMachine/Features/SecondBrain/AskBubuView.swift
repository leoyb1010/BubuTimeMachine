import SwiftUI
import Observation

// MARK: - 布布问答（POST ask）

nonisolated struct AskExchange: Identifiable, Sendable, Hashable {
    let id = UUID()
    let question: String
    var response: AskResponseDTO?
    var errorText: String?
}

/// Last ~10 questions for this app session; never written to disk.
@Observable @MainActor
final class AskBubuSession {
    static let shared = AskBubuSession()
    var scope: String?
    var exchanges: [AskExchange] = []

    func reset(for scope: String) {
        guard self.scope != scope else { return }
        self.scope = scope
        exchanges = []
    }

    func append(_ exchange: AskExchange) {
        exchanges.append(exchange)
        if exchanges.count > 10 { exchanges.removeFirst(exchanges.count - 10) }
    }

    func update(_ id: UUID, response: AskResponseDTO?, error: String?) {
        guard let index = exchanges.firstIndex(where: { $0.id == id }) else { return }
        exchanges[index].response = response
        exchanges[index].errorText = error
    }
}

struct AskBubuView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var session = AskBubuSession.shared
    @State private var draft = ""
    @State private var asking = false
    @State private var route: TimelinePagerRoute?
    @FocusState private var focused: Bool
    /// Siri 带来的问题：出现时自动问一次。
    var initialQuestion: String? = nil
    @State private var askedInitial = false

    static let examples = ["她第一次去海边是什么时候？", "最近一次去动物园", "她最喜欢玩什么", "她和姥姥一起做过什么"]

    var body: some View {
        let client = BubuLearningClient(env: env)
        ZStack {
            BubuThemedBackground().ignoresSafeArea()
            if let client {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: BubuTheme.Spacing.item) {
                            if session.exchanges.isEmpty { intro }
                            ForEach(session.exchanges) { exchange in
                                exchangeView(exchange, client: client).id(exchange.id)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(BubuTheme.Spacing.item)
                        .bubuContentColumn(820)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: session.exchanges) { _, _ in
                        withAnimation(reduceMotion ? nil : BubuMotion.gentle) { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .safeAreaInset(edge: .bottom) { inputBar(client: client) }
                .task(id: client.scope) {
                    session.reset(for: client.scope)
                    if let initialQuestion, !askedInitial {
                        askedInitial = true
                        await ask(initialQuestion, client: client)
                    }
                }
                .navigationDestination(item: $route) { route in
                    OnlineTimelineDetailPager(client: client, items: route.items, initial: route.initial, loadMore: {}, hasMore: false)
                }
            } else {
                SecondBrainNotConnected(title: "布布问答")
            }
        }
        .navigationTitle("布布问答")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("brain.ask")
    }

    // MARK: Pieces

    private var intro: some View {
        VStack(spacing: BubuTheme.Spacing.m) {
            BubuMascotBadge(size: 104, expression: .thinking)
            Text("问问布布的相册").font(BubuTheme.Font.title).foregroundStyle(BubuTheme.Color.warmBrown)
            Text("家里的第二大脑会先翻出相关的照片，再试着用一句话回答你。点答案里的小数字，就能看到那张照片。")
                .font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BubuTheme.Spacing.section)
    }

    private func inputBar(client: BubuLearningClient) -> some View {
        VStack(spacing: BubuTheme.Spacing.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BubuTheme.Spacing.s) {
                    ForEach(Self.examples, id: \.self) { example in
                        Button { Task { await ask(example, client: client) } } label: {
                            Text(example).font(BubuTheme.Font.caption)
                                .foregroundStyle(BubuTheme.Color.deepRose)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(BubuTheme.Color.pinkSurface, in: Capsule())
                        }
                        .buttonStyle(BubuPressableStyle())
                        .disabled(asking)
                        .accessibilityHint("用这个例子提问")
                    }
                }
                .padding(.horizontal, BubuTheme.Spacing.item)
            }
            HStack(spacing: BubuTheme.Spacing.s) {
                TextField("问一个关于布布的问题…", text: $draft, axis: .vertical)
                    .lineLimit(1...3)
                    .font(BubuTheme.Font.body)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { Task { await ask(draft, client: client) } }
                    .onChange(of: draft) { _, value in if value.count > 200 { draft = String(value.prefix(200)) } }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
                    .accessibilityIdentifier("ask.input")
                Button { Task { await ask(draft, client: client) } } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 36, design: .rounded))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, canSend ? BubuTheme.Color.primary : BubuTheme.Color.softFill)
                }
                .buttonStyle(BubuPressableStyle(scale: 0.9))
                .disabled(!canSend)
                .accessibilityLabel("发送问题")
                .accessibilityIdentifier("ask.send")
            }
            .padding(.horizontal, BubuTheme.Spacing.item)
        }
        .padding(.vertical, BubuTheme.Spacing.s)
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool { !asking && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    @ViewBuilder
    private func exchangeView(_ exchange: AskExchange, client: BubuLearningClient) -> some View {
        VStack(alignment: .leading, spacing: BubuTheme.Spacing.s) {
            HStack {
                Spacer(minLength: 48)
                Text(exchange.question).font(BubuTheme.Font.body.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(BubuTheme.Gradient.primaryButton,
                                in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20,
                                                           bottomTrailingRadius: 6, topTrailingRadius: 20, style: .continuous))
                    .accessibilityLabel("你问：\(exchange.question)")
            }
            HStack(alignment: .top, spacing: BubuTheme.Spacing.s) {
                BubuMascotBadge(size: 36, expression: exchange.response == nil && exchange.errorText == nil ? .thinking : .happy,
                                isAlive: false)
                VStack(alignment: .leading, spacing: BubuTheme.Spacing.m) {
                    if let response = exchange.response {
                        answer(response, client: client)
                    } else if let error = exchange.errorText {
                        Text(error).font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.danger)
                        Button("再问一次") { Task { await ask(exchange.question, client: client, replacing: exchange.id) } }
                            .font(BubuTheme.Font.caption.weight(.semibold)).tint(BubuTheme.Color.deepRose)
                    } else {
                        AskThinkingDots()
                    }
                }
                .padding(BubuTheme.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BubuTheme.Color.card.opacity(0.95),
                            in: UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 20,
                                                       bottomTrailingRadius: 20, topTrailingRadius: 20, style: .continuous))
            }
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
    }

    @ViewBuilder
    private func answer(_ response: AskResponseDTO, client: BubuLearningClient) -> some View {
        let itemIDs = Set(response.items.map(\.id))
        if response.modelUsed, let text = response.answer?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            let parts = AskCitationParser.parse(text, citations: response.citations, itemIDs: itemIDs)
            Text(Self.attributed(parts))
                .font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.warmBrown)
                .tint(BubuTheme.Color.deepRose)
                .environment(\.openURL, OpenURLAction { url in
                    guard url.scheme == "bubu-cite", let id = url.host() else { return .discarded }
                    open(id, in: response.items)
                    return .handled
                })
            if !AskCitationParser.hasCitations(parts), !response.citations.isEmpty {
                citationChips(response)
            }
        } else if response.items.isEmpty {
            Text("没有找到相关的照片，换个说法试试？").font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.warmBrown)
        } else {
            Text("现在只找到了这些相关的照片").font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.warmBrown)
        }
        if !response.items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(Array(response.items.enumerated()), id: \.element.id) { index, item in
                        Button { open(item.id, in: response.items) } label: {
                            SecondBrainThumb(item: item, client: client, width: 96, height: 120)
                                .overlay(alignment: .topLeading) {
                                    if let number = citationNumber(item.id, response) {
                                        Text("\(number)").font(BubuTheme.Font.caption.weight(.heavy)).foregroundStyle(.white)
                                            .frame(width: 22, height: 22).background(BubuTheme.Color.deepRose, in: Circle())
                                            .padding(5).accessibilityHidden(true)
                                    }
                                }
                        }
                        .buttonStyle(BubuPressableStyle())
                        .entranceEffect(index: index)
                    }
                }
            }
            .frame(height: 120)
        }
    }

    private func citationChips(_ response: AskResponseDTO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(response.citations.enumerated()), id: \.offset) { index, citation in
                Button { open(citation.id, in: response.items) } label: {
                    Label("\(index + 1). " + (citation.note?.isEmpty == false ? citation.note! : "看看这张"), systemImage: "photo")
                        .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.deepRose)
                }
                .buttonStyle(BubuPressableStyle())
            }
        }
    }

    private func citationNumber(_ id: String, _ response: AskResponseDTO) -> Int? {
        response.citations.firstIndex { $0.id == id }.map { $0 + 1 }
    }

    static func attributed(_ parts: [AskAnswerPart]) -> AttributedString {
        var result = AttributedString()
        for part in parts {
            switch part {
            case .text(let text):
                result += AttributedString(text)
            case .cite(let number, let id):
                var marker = AttributedString("[\(number)]")
                marker.link = URL(string: "bubu-cite://\(id)")
                marker.swiftUI.foregroundColor = BubuTheme.Color.deepRose
                marker.swiftUI.font = BubuTheme.Font.caption.weight(.heavy)
                marker.swiftUI.baselineOffset = 4
                result += marker
            }
        }
        return result
    }

    private func open(_ id: String, in items: [OnlineTimelineItem]) {
        guard let item = items.first(where: { $0.id.lowercased() == id.lowercased() }) else { return }
        BubuHaptics.selection()
        route = TimelinePagerRoute(items: items, initial: item)
    }

    // MARK: Asking

    private func ask(_ raw: String, client: BubuLearningClient, replacing: UUID? = nil) async {
        let question = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !question.isEmpty, !asking else { return }
        asking = true
        defer { asking = false }
        focused = false
        if replacing == nil { draft = "" }
        let id: UUID
        if let replacing {
            id = replacing
            session.update(replacing, response: nil, error: nil)
        } else {
            let exchange = AskExchange(question: question)
            id = exchange.id
            withAnimation(reduceMotion ? nil : BubuMotion.gentle) { session.append(exchange) }
        }
        BubuHaptics.tapLight()
        do {
            let response = try await client.send("POST", "api/ask", body: AskRequestBody(question: question), as: AskResponseDTO.self)
            withAnimation(reduceMotion ? nil : BubuMotion.gentle) { session.update(id, response: response, error: nil) }
            BubuHaptics.success()
        } catch {
            session.update(id, response: nil, error: learningErrorText(error, fallback: "暂时问不到，请稍后再试。"))
        }
    }
}

/// Three soft dots while the family service thinks; static (with text) under Reduce Motion.
struct AskThinkingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            if reduceMotion {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(BubuTheme.Color.primary.opacity(0.6)).frame(width: 8, height: 8) }
            } else {
                TimelineView(.animation) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { index in
                            let phase = sin(time * 4 - Double(index) * 0.7)
                            Circle().fill(BubuTheme.Color.primary.opacity(0.45 + 0.35 * (phase + 1) / 2))
                                .frame(width: 8, height: 8)
                                .offset(y: -3 * max(0, phase))
                        }
                    }
                }
            }
            Text("正在翻相册…").font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在翻相册")
    }
}
