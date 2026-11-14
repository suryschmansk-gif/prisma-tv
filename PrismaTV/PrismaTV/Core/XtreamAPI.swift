import Foundation

enum XtreamError: LocalizedError {
    case badURL
    case unauthorized
    case blocked(Int)
    case expired
    case http(Int)
    case notJSON
    case network(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Endereço do servidor inválido. Confira se está no formato http://dominio.com:porta"
        case .unauthorized: return "Usuário ou senha incorretos. Confira se digitou igual ao outro app."
        case .blocked(let code): return "O servidor recusou a conexão (erro \(code)). Alguns provedores bloqueiam acessos de fora do Brasil, de VPN ou de servidores na nuvem (como o Appetize). No seu celular, na internet de casa, deve funcionar."
        case .expired: return "Sua assinatura parece estar expirada ou desativada."
        case .http(let code): return "O servidor respondeu com erro \(code)."
        case .notJSON: return "O servidor não respondeu como um painel Xtream Codes. Confira o endereço e a porta."
        case .network(let msg): return "Falha de conexão: \(msg)"
        }
    }
}

struct XtreamAPI: Sendable {
    let account: Account

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 600
        cfg.httpAdditionalHeaders = ["User-Agent": "VLC/3.0.20 LibVLC/3.0.20"]
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    // MARK: URLs

    func apiURL(action: String?, params: [String: String] = [:]) throws -> URL {
        guard var comps = URLComponents(string: account.server + "/player_api.php") else { throw XtreamError.badURL }
        var items = [
            URLQueryItem(name: "username", value: account.username),
            URLQueryItem(name: "password", value: account.password),
        ]
        if let action { items.append(URLQueryItem(name: "action", value: action)) }
        for (k, v) in params { items.append(URLQueryItem(name: k, value: v)) }
        comps.queryItems = items
        // "+" não é codificado pelo URLComponents e o servidor leria como espaço.
        comps.percentEncodedQuery = comps.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = comps.url else { throw XtreamError.badURL }
        return url
    }

    private static let pathAllowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))

    private func streamURL(_ type: String, _ id: String, _ ext: String) -> URL? {
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: Self.pathAllowed) ?? s }
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        let path = type.isEmpty
            ? "/\(enc(account.username))/\(enc(account.password))/\(id)\(suffix)"
            : "/\(type)/\(enc(account.username))/\(enc(account.password))/\(id)\(suffix)"
        return URL(string: account.server + path)
    }

    func liveURL(_ streamId: Int, format: String) -> URL? { streamURL("live", String(streamId), format) }
    func movieURL(_ streamId: String, ext: String) -> URL? { streamURL("movie", streamId, ext) }
    func episodeURL(_ episodeId: String, ext: String) -> URL? { streamURL("series", episodeId, ext) }

    // MARK: Requisições

    func data(action: String?, params: [String: String] = [:]) async throws -> Data {
        let url = try apiURL(action: action, params: params)
        let result: (Data, URLResponse)
        do {
            result = try await Self.session.data(from: url)
        } catch {
            throw XtreamError.network(error.localizedDescription)
        }
        if let http = result.1 as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if http.statusCode == 401 || http.statusCode == 403 || http.statusCode == 451 { throw XtreamError.blocked(http.statusCode) }
            throw XtreamError.http(http.statusCode)
        }
        return result.0
    }

    func authenticate() async throws -> UserInfo {
        let payload = try await data(action: nil)
        guard let resp = try? JSONDecoder().decode(AuthResponse.self, from: payload) else { throw XtreamError.notJSON }
        guard let user = resp.user, user.auth == 1 else { throw XtreamError.unauthorized }
        if let status = user.status?.lowercased(), status != "active" { throw XtreamError.expired }
        return user
    }

    func movieInfo(id: Int) async throws -> MovieInfo {
        let payload = try await data(action: "get_vod_info", params: ["vod_id": String(id)])
        return try JSONDecoder().decode(MovieInfo.self, from: payload)
    }

    func seriesInfo(id: Int) async throws -> SeriesInfo {
        let payload = try await data(action: "get_series_info", params: ["series_id": String(id)])
        return try JSONDecoder().decode(SeriesInfo.self, from: payload)
    }

    func shortEPG(streamId: Int, limit: Int) async throws -> [EPGEntry] {
        let payload = try await data(action: "get_short_epg", params: ["stream_id": String(streamId), "limit": String(limit)])
        return (try? JSONDecoder().decode(EPGResponse.self, from: payload))?.listings ?? []
    }

    /// Decodifica listas ignorando itens quebrados. Respostas que não são array viram lista vazia.
    static func decodeList<T: Decodable>(_ type: T.Type, from data: Data?) -> [T] {
        guard let data, let list = try? JSONDecoder().decode([Lossy<T>].self, from: data) else { return [] }
        return list.compactMap(\.value)
    }
}

// MARK: - Catálogo pré-processado

struct Catalog: Sendable {
    var liveCategories: [XCategory] = []
    var channels: [LiveChannel] = []
    var movieCategories: [XCategory] = []
    var movies: [MediaItem] = []
    var seriesCategories: [XCategory] = []
    var series: [MediaItem] = []

    var liveCounts: [String: Int] = [:]
    var movieCounts: [String: Int] = [:]
    var seriesCounts: [String: Int] = [:]
    var recentMovies: [MediaItem] = []
    var recentSeries: [MediaItem] = []
    var topRated: [MediaItem] = []
    var movieGenres: [String] = []
    var seriesGenres: [String] = []
    var itemsByKey: [String: MediaItem] = [:]
    var channelsByKey: [String: LiveChannel] = [:]

    static let actions = [
        "get_live_categories", "get_live_streams",
        "get_vod_categories", "get_vod_streams",
        "get_series_categories", "get_series",
    ]

    static func build(from raw: [String: Data]) -> Catalog {
        var c = Catalog()
        c.liveCategories = XtreamAPI.decodeList(XCategory.self, from: raw["get_live_categories"])
        c.channels = XtreamAPI.decodeList(LiveChannel.self, from: raw["get_live_streams"])
        c.movieCategories = XtreamAPI.decodeList(XCategory.self, from: raw["get_vod_categories"])
        c.movies = XtreamAPI.decodeList(MovieDTO.self, from: raw["get_vod_streams"]).map(\.item)
        c.seriesCategories = XtreamAPI.decodeList(XCategory.self, from: raw["get_series_categories"])
        c.series = XtreamAPI.decodeList(SeriesDTO.self, from: raw["get_series"]).map(\.item)

        for ch in c.channels { c.liveCounts[ch.categoryId, default: 0] += 1 }
        for m in c.movies { c.movieCounts[m.categoryId, default: 0] += 1 }
        for s in c.series { c.seriesCounts[s.categoryId, default: 0] += 1 }

        c.recentMovies = Array(c.movies.sorted { $0.added > $1.added }.prefix(24))
        c.recentSeries = Array(c.series.sorted { $0.added > $1.added }.prefix(24))
        let recentPool = (c.movies + c.series).filter { ($0.year ?? 0) >= Calendar.current.component(.year, from: Date()) - 3 }
        c.topRated = Array(recentPool.filter { ($0.rating ?? 0) >= 7 }.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }.prefix(24))
        c.movieGenres = topGenres(c.movies)
        c.seriesGenres = topGenres(c.series)

        for m in c.movies { c.itemsByKey[m.id] = m }
        for s in c.series { c.itemsByKey[s.id] = s }
        for ch in c.channels { c.channelsByKey[ch.favKey] = ch }
        return c
    }

    private static func topGenres(_ items: [MediaItem]) -> [String] {
        var freq: [String: Int] = [:]
        for i in items { for g in i.genres { freq[g, default: 0] += 1 } }
        return freq.filter { $0.value >= 3 }
            .sorted { $0.value > $1.value }
            .prefix(40)
            .map { $0.key }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

/// Guarda as listas em disco para o app abrir instantaneamente.
enum CatalogCache {
    private static func dir(_ account: Account) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let safe = "\(account.server)|\(account.username)".unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }
            .joined()
        return base.appendingPathComponent("catalog-\(safe)", isDirectory: true)
    }

    static func save(_ raw: [String: Data], for account: Account) {
        let d = dir(account)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        for (k, v) in raw { try? v.write(to: d.appendingPathComponent("\(k).json"), options: .atomic) }
        try? Data(String(Date().timeIntervalSince1970).utf8).write(to: d.appendingPathComponent("updated.txt"))
    }

    static func load(for account: Account) -> [String: Data]? {
        let d = dir(account)
        var out: [String: Data] = [:]
        for k in Catalog.actions {
            if let data = try? Data(contentsOf: d.appendingPathComponent("\(k).json")) { out[k] = data }
        }
        return out.isEmpty ? nil : out
    }

    static func updatedAt(for account: Account) -> Date? {
        guard let data = try? Data(contentsOf: dir(account).appendingPathComponent("updated.txt")),
              let s = String(data: data, encoding: .utf8), let t = Double(s) else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    static func clear(for account: Account) {
        try? FileManager.default.removeItem(at: dir(account))
    }
}
