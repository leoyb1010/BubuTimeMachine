import SwiftUI
import MapKit
import Observation

// MARK: - 去过的地方（GET places）
/// 服务端只给地名，没有经纬度。App 用 Apple 地图的地理编码按地名查位置（只发地名），
/// 一秒一个、结果缓存在 Application Support 的小 JSON 里；查不到的地方只出现在列表里。

@Observable @MainActor
final class PlaceGeocoder {
    private(set) var coordinates: [String: CLLocationCoordinate2D] = [:]
    private(set) var working = false
    private var cache = PlaceGeocodeCache.load(from: PlaceGeocodeCache.defaultURL)

    func resolve(_ names: [String]) async {
        for name in names {
            if let entry = cache.entries[name], let latitude = entry.latitude, let longitude = entry.longitude {
                coordinates[name] = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            }
        }
        let missing = names.filter { cache.entries[$0] == nil }
        guard !missing.isEmpty else { return }
        working = true
        defer { working = false }
        for (index, name) in missing.enumerated() {
            if Task.isCancelled { return }
            if index > 0 { try? await Task.sleep(for: .seconds(1)) }
            guard let request = MKGeocodingRequest(addressString: PlaceGeocodeCache.query(for: name)) else { continue }
            do {
                let items = try await request.mapItems
                if let location = items.first?.location {
                    cache.entries[name] = .init(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                    coordinates[name] = location.coordinate
                } else {
                    cache.entries[name] = .notFound
                }
                cache.save(to: PlaceGeocodeCache.defaultURL)
            } catch {
                // Network or throttling: skip for now, try again next visit. Not cached.
                if Task.isCancelled { return }
                if (error as? MKError)?.code == .placemarkNotFound {
                    cache.entries[name] = .notFound
                    cache.save(to: PlaceGeocodeCache.defaultURL)
                }
            }
        }
    }
}

struct PlacesMapView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var places: [PlaceDTO] = []
    @State private var loading = true
    @State private var errorText: String?
    @State private var geocoder = PlaceGeocoder()
    @State private var selected: String?
    @State private var position: MapCameraPosition = .automatic
    @State private var opened: PlaceDTO?

    private var maxCount: Int { places.map(\.count).max() ?? 1 }

    var body: some View {
        let client = BubuLearningClient(env: env)
        ZStack {
            BubuThemedBackground().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: BubuTheme.Spacing.item) {
                    if let client {
                        if loading && places.isEmpty {
                            ProgressView("正在找布布去过的地方…").frame(maxWidth: .infinity).padding(.vertical, 60)
                        } else if places.isEmpty {
                            VStack(spacing: BubuTheme.Spacing.m) {
                                BubuMascotBadge(size: 96, expression: .travel)
                                Text(errorText ?? "照片里还没有认出地点。").font(BubuTheme.Font.body)
                                    .foregroundStyle(BubuTheme.Color.secondaryText)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 50)
                        } else {
                            if !geocoder.coordinates.isEmpty {
                                map(client: client)
                            } else if geocoder.working {
                                Label("正在把地点放到地图上…", systemImage: "map")
                                    .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                            }
                            Text("去过 \(places.count) 个地方").font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
                            ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                                row(place, client: client).entranceEffect(index: index)
                            }
                        }
                    } else {
                        SecondBrainNotConnected(title: "去过的地方")
                    }
                }
                .padding(BubuTheme.Spacing.item)
                .bubuContentColumn(900)
            }
        }
        .navigationTitle("去过的地方")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: client?.scope) {
            guard let client else { loading = false; return }
            do {
                places = try await client.get("api/places", as: PlaceListDTO.self).items.sorted { $0.count > $1.count }
                errorText = nil
            } catch is CancellationError {
            } catch {
                errorText = learningErrorText(error)
            }
            loading = false
            await geocoder.resolve(places.map(\.name))
        }
        .navigationDestination(item: $opened) { place in
            if let client { PlaceItemsView(place: place, client: client) }
        }
        .accessibilityIdentifier("brain.places")
    }

    private func map(client: BubuLearningClient) -> some View {
        Map(position: $position, selection: $selected) {
            ForEach(places) { place in
                if let coordinate = geocoder.coordinates[place.name] {
                    Annotation(place.displayName, coordinate: coordinate, anchor: .bottom) {
                        pin(place, client: client)
                    }
                    .tag(place.name)
                    .annotationTitles(selected == place.name ? .visible : .hidden)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .onChange(of: selected) { _, value in if value != nil { BubuHaptics.selection() } }
        .accessibilityLabel("布布去过的地方地图")
    }

    private func pin(_ place: PlaceDTO, client: BubuLearningClient) -> some View {
        let isSelected = selected == place.name
        let ratio = sqrt(Double(place.count) / Double(max(maxCount, 1)))
        let size = 26 + 22 * ratio
        return VStack(spacing: 4) {
            if isSelected, let cover = place.coverUrl {
                Button { opened = place } label: {
                    VStack(spacing: 3) {
                        Color.clear.frame(width: 88, height: 88)
                            .overlay { LearningRemoteImage(path: cover, client: client, label: place.displayName, contentMode: .fill, diskCache: true) }
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Text("\(place.count) 张 · 看看").font(BubuTheme.Font.scaled(11, weight: .bold)).foregroundStyle(BubuTheme.Color.deepRose)
                    }
                    .padding(5)
                    .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: BubuTheme.Color.deepRose.opacity(0.25), radius: 8, y: 3)
                }
                .buttonStyle(BubuPressableStyle())
                .transition(reduceMotion ? .opacity : .scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                .accessibilityLabel("打开\(place.displayName)的 \(place.count) 张照片")
            }
            ZStack {
                Circle().fill(BubuTheme.Color.primary)
                Circle().stroke(.white, lineWidth: 3)
                Image(systemName: "heart.fill").font(.system(size: size * 0.42, weight: .bold, design: .rounded)).foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .scaleEffect(isSelected && !reduceMotion ? 1.15 : 1)
            .shadow(color: BubuTheme.Color.deepRose.opacity(0.3), radius: 4, y: 2)
        }
        .animation(reduceMotion ? nil : BubuMotion.quick, value: isSelected)
    }

    private func row(_ place: PlaceDTO, client: BubuLearningClient) -> some View {
        Button { opened = place } label: {
            HStack(spacing: BubuTheme.Spacing.m) {
                Group {
                    if let cover = place.coverUrl {
                        LearningRemoteImage(path: cover, client: client, label: place.displayName, contentMode: .fill, diskCache: true)
                    } else {
                        Image(systemName: "mappin.circle.fill").font(BubuTheme.Font.title).foregroundStyle(BubuTheme.Color.primary)
                    }
                }
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.xs, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(place.displayName).font(BubuTheme.Font.body.weight(.bold)).foregroundStyle(BubuTheme.Color.warmBrown)
                            .lineLimit(1)
                        if let city = place.city, !city.isEmpty, city != place.displayName {
                            Text(city).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText).lineLimit(1)
                        }
                    }
                    Text(Self.dayRange(place)).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                }
                Spacer(minLength: 0)
                Text("\(place.count)").font(BubuTheme.Font.headline.monospacedDigit()).foregroundStyle(BubuTheme.Color.deepRose)
                Image(systemName: "chevron.right").font(BubuTheme.Font.caption.weight(.bold)).foregroundStyle(BubuTheme.Color.secondaryText)
            }
            .padding(BubuTheme.Spacing.m)
            .background(BubuTheme.Color.card.opacity(0.95), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
        }
        .buttonStyle(BubuPressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(place.displayName)，\(place.city ?? "")，\(place.count) 张，\(Self.dayRange(place))")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("places.row")
    }

    static func dayRange(_ place: PlaceDTO) -> String {
        func format(_ day: String?) -> String? {
            guard let day, let date = BubuLearningDates.day(String(day.prefix(10))) else { return nil }
            return date.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN")))
        }
        switch (format(place.firstDay), format(place.lastDay)) {
        case let (first?, last?) where first != last: return "\(first) – \(last)"
        case let (first?, _): return first
        case let (_, last?): return last
        default: return "日期未知"
        }
    }
}

/// One place's photos (≤ 60, newest first) → the shared detail pager.
struct PlaceItemsView: View {
    let place: PlaceDTO
    let client: BubuLearningClient
    @State private var items: [OnlineTimelineItem] = []
    @State private var loading = true
    @State private var errorText: String?
    @State private var route: TimelinePagerRoute?

    var body: some View {
        ZStack {
            BubuThemedBackground().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: BubuTheme.Spacing.m) {
                    Text(PlacesMapView.dayRange(place)).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                    if loading && items.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 60)
                    } else if items.isEmpty {
                        Text(errorText ?? "这里的照片暂时打不开。").font(BubuTheme.Font.body)
                            .foregroundStyle(BubuTheme.Color.secondaryText).frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 4)], spacing: 4) {
                        ForEach(items) { item in
                            Button { route = TimelinePagerRoute(items: items, initial: item) } label: {
                                SecondBrainThumb(item: item, client: client, height: 120)
                            }
                            .buttonStyle(BubuPressableStyle())
                        }
                    }
                }
                .padding(BubuTheme.Spacing.item)
                .bubuContentColumn(900)
            }
        }
        .navigationTitle(place.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard items.isEmpty else { return }
            do { items = try await client.timelineItems(ids: place.itemIds); errorText = nil }
            catch { errorText = learningErrorText(error) }
            loading = false
        }
        .navigationDestination(item: $route) { route in
            OnlineTimelineDetailPager(client: client, items: route.items, initial: route.initial, loadMore: {}, hasMore: false)
        }
    }
}
