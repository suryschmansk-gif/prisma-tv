import Foundation
import Security
import SwiftUI

// MARK: - Keychain (a senha nunca fica em texto puro)

enum Keychain {
    private static let service = "app.prismatv.account"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "main"]
    }

    static func save(_ account: Account) {
        guard let data = try? JSONEncoder().encode(account) else { return }
        delete()
        var q = baseQuery
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    static func load() -> Account? {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Account.self, from: data)
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

// MARK: - Progresso ("Continuar assistindo")

struct WatchEntry: Codable, Identifiable, Hashable, Sendable {
    let key: String              // "movie-123" ou "episode-456"
    var kind: MediaItem.Kind     // .movie ou .series
    var streamId: String         // id do filme ou do episódio
    var ext: String
    var title: String
    var subtitle: String?
    var image: URL?
    var seriesId: Int?
    var position: Double
    var duration: Double
    var updatedAt: Date
    var season: Int? = nil
    var episode: Int? = nil
    var episodeTitle: String? = nil

    var id: String { key }
    var fraction: Double { duration > 0 ? min(1, max(0, position / duration)) : 0 }
    var isFinished: Bool { duration > 0 && (position / duration > 0.93 || duration - position < 90) }
    var remaining: Double { max(0, duration - position) }
}

@MainActor
final class ProgressStore: ObservableObject {
    @Published private(set) var entries: [String: WatchEntry] = [:]

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("progress.json")
    }()

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: WatchEntry].self, from: data) {
            entries = decoded
        }
    }

    func entry(_ key: String) -> WatchEntry? { entries[key] }

    func update(_ e: WatchEntry) {
        entries[e.key] = e
        save()
    }

    func remove(_ key: String) {
        entries[key] = nil
        save()
    }

    func removeSeries(_ seriesId: Int) {
        entries = entries.filter { $0.value.seriesId != seriesId }
        save()
    }

    /// Último episódio mexido de uma série.
    func lastEpisode(seriesId: Int) -> WatchEntry? {
        entries.values.filter { $0.seriesId == seriesId }.max { $0.updatedAt < $1.updatedAt }
    }

    /// Um card por filme / por série, do mais recente para o mais antigo.
    var continueWatching: [WatchEntry] {
        var latest: [String: WatchEntry] = [:]
        for e in entries.values {
            let group = e.seriesId.map { "series-\($0)" } ?? e.key
            if let cur = latest[group], cur.updatedAt >= e.updatedAt { continue }
            latest[group] = e
        }
        return latest.values
            .filter { !$0.isFinished && $0.position > 20 }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - Favoritos

@MainActor
final class FavoritesStore: ObservableObject {
    @Published private(set) var keys: Set<String>

    init() {
        keys = Set(UserDefaults.standard.stringArray(forKey: "favorites") ?? [])
    }

    func contains(_ key: String) -> Bool { keys.contains(key) }

    func toggle(_ key: String) {
        if keys.contains(key) { keys.remove(key) } else { keys.insert(key) }
        UserDefaults.standard.set(Array(keys), forKey: "favorites")
    }
}

// MARK: - Guia de programação (EPG)

@MainActor
final class EPGStore: ObservableObject {
    @Published private(set) var listings: [Int: [EPGEntry]] = [:]
    var api: XtreamAPI?
    private var inFlight: Set<Int> = []
    private var fetchedAt: [Int: Date] = [:]
    private var fetchedLimit: [Int: Int] = [:]

    func load(_ channel: LiveChannel, limit: Int = 8) async {
        guard channel.epgId != nil, let api, !inFlight.contains(channel.id) else { return }
        let id = channel.id
        if let t = fetchedAt[id], Date().timeIntervalSince(t) < 900, (fetchedLimit[id] ?? 0) >= limit,
           listings[id]?.contains(where: { $0.end > Date() }) == true { return }
        inFlight.insert(id)
        let items = (try? await api.shortEPG(streamId: id, limit: limit)) ?? []
        inFlight.remove(id)
        listings[id] = items.sorted { $0.start < $1.start }
        fetchedAt[id] = Date()
        fetchedLimit[id] = limit
    }

    func now(_ id: Int) -> EPGEntry? {
        let d = Date()
        return listings[id]?.first { $0.start <= d && $0.end > d }
    }

    func next(_ id: Int) -> EPGEntry? {
        let d = Date()
        return listings[id]?.first { $0.start > d }
    }

    func upcoming(_ id: Int) -> [EPGEntry] {
        let d = Date()
        return listings[id]?.filter { $0.end > d } ?? []
    }

    func reset() {
        listings = [:]; fetchedAt = [:]; fetchedLimit = [:]; inFlight = []
    }
}

// MARK: - Pedido de reprodução

struct EpisodeContext {
    let series: MediaItem
    let info: SeriesInfo
    let episode: Episode

    /// Número da temporada (pela chave do servidor, que é a fonte mais confiável).
    var season: Int {
        info.episodesBySeason.first { $0.value.contains(episode) }?.key ?? episode.season
    }
    var seasonEpisodes: [Episode] { info.episodesBySeason[season] ?? [] }
    var next: Episode? {
        let all = info.allEpisodes
        guard let i = all.firstIndex(of: episode), i + 1 < all.count else { return nil }
        return all[i + 1]
    }
}

struct PlayerRequest: Identifiable {
    let id = UUID()
    var url: URL
    var title: String
    var subtitle: String?
    var isLive: Bool
    var startAt: Double
    var progress: WatchEntry?
    var channels: [LiveChannel] = []
    var channelIndex: Int = 0
    var episode: EpisodeContext? = nil
    var favKey: String? = nil
}

// MARK: - Orientação (o player gira sozinho para a horizontal)

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .all

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientationLock
    }
}

@MainActor
enum Orientation {
    static func landscape() { apply(.landscape, rotateTo: .landscapeRight) }

    static func restore() {
        let phone = UIDevice.current.userInterfaceIdiom == .phone
        apply(.all, rotateTo: phone ? .portrait : nil)
    }

    private static func apply(_ mask: UIInterfaceOrientationMask, rotateTo: UIInterfaceOrientationMask?) {
        AppDelegate.orientationLock = mask
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        for window in scene.windows { window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
        if let rotateTo {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: rotateTo)) { _ in }
        }
    }
}

// MARK: - Biblioteca (estado central do app)

@MainActor
final class Library: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, failed(String) }

    @Published private(set) var account: Account?
    @Published private(set) var userInfo: UserInfo?
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var catalog = Catalog()
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false
    @Published var player: PlayerRequest?

    let progress: ProgressStore
    let favorites: FavoritesStore
    let epg: EPGStore

    init() {
        progress = ProgressStore()
        favorites = FavoritesStore()
        epg = EPGStore()
        account = Keychain.load()
        if account != nil {
            Task { await self.start() }
        }
    }

    var api: XtreamAPI? { account.map { XtreamAPI(account: $0) } }

    var isEmpty: Bool { catalog.channels.isEmpty && catalog.movies.isEmpty && catalog.series.isEmpty }

    var failureMessage: String? {
        if case .failed(let msg) = state { return msg }
        return nil
    }

    // MARK: Login / logout

    func login(_ newAccount: Account) async throws {
        var acc = newAccount
        acc.server = Account.normalize(acc.server)
        if acc.name.trimmingCharacters(in: .whitespaces).isEmpty {
            acc.name = URL(string: acc.server)?.host ?? "Minha lista"
        }
        let user = try await XtreamAPI(account: acc).authenticate()
        Keychain.save(acc)
        userInfo = user
        account = acc
        catalog = Catalog()
        epg.reset()
        epg.api = XtreamAPI(account: acc)
        await refresh()
    }

    func logout() {
        if let account { CatalogCache.clear(for: account) }
        Keychain.delete()
        account = nil
        userInfo = nil
        catalog = Catalog()
        lastUpdated = nil
        state = .idle
        epg.reset()
        epg.api = nil
    }

    // MARK: Carregamento

    func start() async {
        guard let account else { return }
        epg.api = XtreamAPI(account: account)
        if isEmpty {
            let acc = account
            let cached = await Task.detached(priority: .userInitiated) { () -> Catalog? in
                guard let raw = CatalogCache.load(for: acc) else { return nil }
                return Catalog.build(from: raw)
            }.value
            if let cached {
                catalog = cached
                lastUpdated = CatalogCache.updatedAt(for: acc)
                state = .loaded
            }
        }
        let stale = lastUpdated.map { Date().timeIntervalSince($0) > 12 * 3600 } ?? true
        if stale || isEmpty {
            await refresh()
        } else {
            userInfo = try? await api?.authenticate()
        }
    }

    func refresh() async {
        guard let account, !isRefreshing else { return }
        let api = XtreamAPI(account: account)
        isRefreshing = true
        defer { isRefreshing = false }
        if isEmpty { state = .loading }
        do {
            userInfo = try await api.authenticate()
            let raw = try await withThrowingTaskGroup(of: (String, Data).self, returning: [String: Data].self) { group in
                for action in Catalog.actions {
                    group.addTask {
                        let payload = try await api.data(action: action)
                        return (action, payload)
                    }
                }
                var out: [String: Data] = [:]
                for try await (action, data) in group { out[action] = data }
                return out
            }
            let built = await Task.detached(priority: .userInitiated) { () -> Catalog in
                CatalogCache.save(raw, for: account)
                return Catalog.build(from: raw)
            }.value
            catalog = built
            lastUpdated = Date()
            state = .loaded
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            state = isEmpty ? .failed(msg) : .loaded
        }
    }

    // MARK: Reprodução

    func liveURL(_ channel: LiveChannel) -> URL? {
        let preferred = UserDefaults.standard.string(forKey: "liveFormat") ?? "ts"
        var format = preferred
        if let allowed = userInfo?.allowedFormats, !allowed.isEmpty, !allowed.contains(preferred) {
            format = allowed.contains("m3u8") ? "m3u8" : (allowed.first ?? preferred)
        }
        return api?.liveURL(channel.id, format: format)
    }

    func playChannel(_ channel: LiveChannel, in list: [LiveChannel]) {
        guard let url = liveURL(channel) else { return }
        let index = list.firstIndex(of: channel) ?? 0
        player = PlayerRequest(url: url, title: channel.name, subtitle: nil, isLive: true, startAt: 0,
                               progress: nil, channels: list.isEmpty ? [channel] : list, channelIndex: index)
    }

    func playMovie(_ item: MediaItem, ext: String? = nil, resume: Bool) {
        let finalExt = ext ?? item.ext
        guard let url = api?.movieURL(String(item.streamId), ext: finalExt) else { return }
        let existing = progress.entry(item.progressKey)
        let entry = WatchEntry(key: item.progressKey, kind: .movie, streamId: String(item.streamId), ext: finalExt,
                               title: item.title, subtitle: item.year.map { String($0) },
                               image: item.backdrop ?? item.poster, seriesId: nil,
                               position: existing?.position ?? 0, duration: existing?.duration ?? 0, updatedAt: Date())
        let start = resume ? (existing.map { $0.isFinished ? 0 : $0.position } ?? 0) : 0
        player = PlayerRequest(url: url, title: item.title, subtitle: entry.subtitle, isLive: false,
                               startAt: start, progress: entry, favKey: item.favKey)
    }

    func episodeRequest(_ ep: Episode, series: MediaItem, info: SeriesInfo?, resume: Bool) -> PlayerRequest? {
        guard let url = api?.episodeURL(ep.id, ext: ep.ext) else { return nil }
        let existing = progress.entry(ep.progressKey)
        let context = info.map { EpisodeContext(series: series, info: $0, episode: ep) }
        let season = context?.season ?? ep.season
        let subtitle = "T\(season) · E\(ep.number) · \(ep.title)"
        var entry = WatchEntry(key: ep.progressKey, kind: .series, streamId: ep.id, ext: ep.ext,
                               title: series.title, subtitle: subtitle,
                               image: ep.image ?? info?.backdrop ?? series.backdrop ?? series.poster,
                               seriesId: series.streamId,
                               position: existing?.position ?? 0,
                               duration: existing?.duration ?? Double(ep.durationSecs ?? 0), updatedAt: Date())
        entry.season = season
        entry.episode = ep.number
        entry.episodeTitle = ep.title
        let start = resume ? (existing.map { $0.isFinished ? 0 : $0.position } ?? 0) : 0
        return PlayerRequest(url: url, title: series.title, subtitle: subtitle, isLive: false,
                             startAt: start, progress: entry, episode: context, favKey: series.favKey)
    }

    func playEpisode(_ ep: Episode, series: MediaItem, info: SeriesInfo?, resume: Bool) {
        player = episodeRequest(ep, series: series, info: info, resume: resume)
    }

    func resume(_ entry: WatchEntry) {
        guard let api else { return }
        let url = entry.kind == .movie
            ? api.movieURL(entry.streamId, ext: entry.ext)
            : api.episodeURL(entry.streamId, ext: entry.ext)
        guard let url else { return }
        let fav = entry.seriesId.map { "series-\($0)" } ?? "movie-\(entry.streamId)"
        player = PlayerRequest(url: url, title: entry.title, subtitle: entry.subtitle, isLive: false,
                               startAt: entry.isFinished ? 0 : entry.position, progress: entry, favKey: fav)
    }
}
