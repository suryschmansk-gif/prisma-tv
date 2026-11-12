import Foundation

// MARK: - Decodificação tolerante
// Servidores Xtream Codes são inconsistentes: o mesmo campo pode vir como
// número, texto, null ou até array vazio. Estes helpers nunca quebram.

extension KeyedDecodingContainer {
    func flexString(_ key: Key) -> String? {
        if let v = try? decodeIfPresent(String.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return String(v) }
        if let v = try? decodeIfPresent(Double.self, forKey: key) { return String(v) }
        return nil
    }

    func flexInt(_ key: Key) -> Int? {
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Double.self, forKey: key) { return Int(v) }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            let t = s.trimmingCharacters(in: .whitespaces)
            if let i = Int(t) { return i }
            if let d = Double(t) { return Int(d) }
        }
        return nil
    }

    func flexDouble(_ key: Key) -> Double? {
        if let v = try? decodeIfPresent(Double.self, forKey: key) { return v }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            return Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }

    func flexStringArray(_ key: Key) -> [String] {
        if let v = try? decodeIfPresent([String].self, forKey: key) { return v }
        if let s = flexString(key), !s.isEmpty { return [s] }
        return []
    }

    func flexURL(_ key: Key) -> URL? { TextUtil.url(flexString(key)) }
}

/// Decodifica um item e devolve nil se ele estiver quebrado, sem derrubar a lista inteira.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

// MARK: - Helpers de texto

enum TextUtil {
    static func url(_ raw: String?) -> URL? {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if let u = URL(string: s), u.scheme != nil { return u }
        if let enc = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), let u = URL(string: enc), u.scheme != nil { return u }
        return nil
    }

    static func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    static func searchKey(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
    }

    private static let yearRegex = try? NSRegularExpression(pattern: "(?:\\(|\\[|-\\s*|\\s)((?:19|20)\\d{2})(?:\\)|\\]|\\s*$)")
    private static let prefixRegex = try? NSRegularExpression(pattern: "^\\s*[A-Z]{2,4}\\s*[|:]\\s*")

    /// Tenta achar o ano dentro do nome, ex.: "Duna (2021)" ou "Duna - 2021".
    static func year(in name: String) -> Int? {
        guard let rx = yearRegex else { return nil }
        let range = NSRange(name.startIndex..., in: name)
        guard let m = rx.matches(in: name, range: range).last,
              let r = Range(m.range(at: 1), in: name) else { return nil }
        return Int(name[r])
    }

    /// Remove prefixos de país do tipo "PT | " ou "BR: " que poluem os títulos.
    static func cleanTitle(_ name: String) -> String {
        var s = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let rx = prefixRegex {
            s = rx.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        return s.isEmpty ? name : s
    }

    private static let episodePrefixRegex = try? NSRegularExpression(pattern: "^.*?S\\d+\\s*E\\d+\\s*[-–:|]?\\s*", options: [.caseInsensitive])

    /// "Série X - S01E02 - O Retorno" → "O Retorno"
    static func episodeTitle(_ raw: String, number: Int) -> String {
        var s = raw
        if let rx = episodePrefixRegex {
            s = rx.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "Episódio \(number)" : s
    }

    static func base64Decoded(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        if let d = Data(base64Encoded: s), let t = String(data: d, encoding: .utf8) { return t }
        return s
    }

    static func genres(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        return raw.components(separatedBy: CharacterSet(charactersIn: ",/&|"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count < 30 }
    }
}

// MARK: - Conta

struct Account: Codable, Equatable, Sendable {
    var name: String
    var server: String
    var username: String
    var password: String

    /// Aceita "dominio.com:8080", "http://dominio.com:8080/", ou até o link inteiro do player_api.
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = s.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") { s = "http://" + s }
        for marker in ["/player_api.php", "/get.php", "/xmltv.php", "?"] {
            if let r = s.range(of: marker) { s = String(s[..<r.lowerBound]) }
        }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// Lê um link M3U do tipo http://host:porta/get.php?username=X&password=Y&type=m3u_plus
    static func fromM3U(_ link: String) -> Account? {
        guard let comps = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = comps.host,
              let user = comps.queryItems?.first(where: { $0.name == "username" })?.value,
              let pass = comps.queryItems?.first(where: { $0.name == "password" })?.value
        else { return nil }
        let scheme = comps.scheme ?? "http"
        let port = comps.port.map { ":\($0)" } ?? ""
        return Account(name: host, server: "\(scheme)://\(host)\(port)", username: user, password: pass)
    }
}

// MARK: - Respostas da API

struct XCategory: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String

    private enum K: String, CodingKey { case category_id, category_name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        guard let id = c.flexString(.category_id) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "sem category_id"))
        }
        self.id = id
        self.name = TextUtil.nonEmpty(c.flexString(.category_name)) ?? "Sem nome"
    }
}

struct LiveChannel: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let icon: URL?
    let categoryId: String
    let epgId: String?
    let number: Int?
    let searchKey: String

    private enum K: String, CodingKey { case stream_id, name, stream_icon, category_id, epg_channel_id, num }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        guard let id = c.flexInt(.stream_id) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "sem stream_id"))
        }
        self.id = id
        let n = TextUtil.nonEmpty(c.flexString(.name)) ?? "Canal \(id)"
        self.name = n
        self.icon = c.flexURL(.stream_icon)
        self.categoryId = c.flexString(.category_id) ?? ""
        self.epgId = TextUtil.nonEmpty(c.flexString(.epg_channel_id))
        self.number = c.flexInt(.num)
        self.searchKey = TextUtil.searchKey(n)
    }

    static func == (a: LiveChannel, b: LiveChannel) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    var favKey: String { "live-\(id)" }
}

/// Filme ou série, já no formato que as telas usam.
struct MediaItem: Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case movie, series }

    let kind: Kind
    let streamId: Int
    let title: String
    let poster: URL?
    let backdrop: URL?
    let rating: Double?
    let year: Int?
    let genres: [String]
    let categoryId: String
    let added: Int
    let ext: String
    let plot: String?
    let searchKey: String

    var id: String { "\(kind.rawValue)-\(streamId)" }
    var favKey: String { id }
    var progressKey: String { "movie-\(streamId)" }

    static func == (a: MediaItem, b: MediaItem) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

private func normalizedRating(_ ten: Double?, _ five: Double?) -> Double? {
    if let r = ten, r > 0 { return min(r, 10) }
    if let r = five, r > 0 { return min(r * 2, 10) }
    return nil
}

struct MovieDTO: Decodable {
    let item: MediaItem

    private enum K: String, CodingKey {
        case stream_id, name, title, stream_icon, rating, rating_5based, category_id, added, container_extension, year, plot, genre
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        guard let id = c.flexInt(.stream_id) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "sem stream_id"))
        }
        let raw = TextUtil.nonEmpty(c.flexString(.name)) ?? TextUtil.nonEmpty(c.flexString(.title)) ?? "Filme \(id)"
        let title = TextUtil.cleanTitle(raw)
        var year = c.flexInt(.year)
        if let y = year, y < 1900 || y > 2100 { year = nil }
        item = MediaItem(
            kind: .movie,
            streamId: id,
            title: title,
            poster: c.flexURL(.stream_icon),
            backdrop: nil,
            rating: normalizedRating(c.flexDouble(.rating), c.flexDouble(.rating_5based)),
            year: year ?? TextUtil.year(in: raw),
            genres: TextUtil.genres(c.flexString(.genre)),
            categoryId: c.flexString(.category_id) ?? "",
            added: c.flexInt(.added) ?? 0,
            ext: TextUtil.nonEmpty(c.flexString(.container_extension)) ?? "mp4",
            plot: TextUtil.nonEmpty(c.flexString(.plot)),
            searchKey: TextUtil.searchKey(title)
        )
    }
}

struct SeriesDTO: Decodable {
    let item: MediaItem

    private enum K: String, CodingKey {
        case series_id, name, cover, rating, rating_5based, category_id, last_modified, genre, plot, releaseDate, release_date, year, backdrop_path
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        guard let id = c.flexInt(.series_id) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "sem series_id"))
        }
        let raw = TextUtil.nonEmpty(c.flexString(.name)) ?? "Série \(id)"
        let title = TextUtil.cleanTitle(raw)
        let release = c.flexString(.releaseDate) ?? c.flexString(.release_date)
        var year = c.flexInt(.year)
        if year == nil, let r = release, r.count >= 4 { year = Int(r.prefix(4)) }
        if let y = year, y < 1900 || y > 2100 { year = nil }
        item = MediaItem(
            kind: .series,
            streamId: id,
            title: title,
            poster: c.flexURL(.cover),
            backdrop: TextUtil.url(c.flexStringArray(.backdrop_path).first),
            rating: normalizedRating(c.flexDouble(.rating), c.flexDouble(.rating_5based)),
            year: year ?? TextUtil.year(in: raw),
            genres: TextUtil.genres(c.flexString(.genre)),
            categoryId: c.flexString(.category_id) ?? "",
            added: c.flexInt(.last_modified) ?? 0,
            ext: "",
            plot: TextUtil.nonEmpty(c.flexString(.plot)),
            searchKey: TextUtil.searchKey(title)
        )
    }
}

struct UserInfo: Decodable, Sendable {
    let username: String?
    let auth: Int
    let status: String?
    let expiration: Date?
    let maxConnections: Int?
    let activeConnections: Int?
    let allowedFormats: [String]

    private enum K: String, CodingKey {
        case username, auth, status, exp_date, max_connections, active_cons, allowed_output_formats
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        username = c.flexString(.username)
        auth = c.flexInt(.auth) ?? 0
        status = c.flexString(.status)
        expiration = c.flexInt(.exp_date).flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil }
        maxConnections = c.flexInt(.max_connections)
        activeConnections = c.flexInt(.active_cons)
        allowedFormats = c.flexStringArray(.allowed_output_formats)
    }
}

struct AuthResponse: Decodable, Sendable {
    let user: UserInfo?
    private enum K: String, CodingKey { case user_info }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        user = try? c.decodeIfPresent(UserInfo.self, forKey: .user_info)
    }
}

// MARK: - Detalhes

struct MovieInfo: Decodable, Sendable {
    var plot: String?
    var cast: String?
    var director: String?
    var genre: String?
    var releaseDate: String?
    var duration: String?
    var durationSecs: Int?
    var backdrop: URL?
    var poster: URL?
    var rating: Double?
    var ext: String?

    private enum K: String, CodingKey { case info, movie_data }
    private enum IK: String, CodingKey {
        case plot, description, cast, actors, director, genre, releasedate, release_date
        case duration, duration_secs, backdrop_path, movie_image, cover_big, rating
    }
    private enum MK: String, CodingKey { case container_extension }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        if let i = try? c.nestedContainer(keyedBy: IK.self, forKey: .info) {
            plot = TextUtil.nonEmpty(i.flexString(.plot)) ?? TextUtil.nonEmpty(i.flexString(.description))
            cast = TextUtil.nonEmpty(i.flexString(.cast)) ?? TextUtil.nonEmpty(i.flexString(.actors))
            director = TextUtil.nonEmpty(i.flexString(.director))
            genre = TextUtil.nonEmpty(i.flexString(.genre))
            releaseDate = TextUtil.nonEmpty(i.flexString(.releasedate)) ?? TextUtil.nonEmpty(i.flexString(.release_date))
            duration = TextUtil.nonEmpty(i.flexString(.duration))
            durationSecs = i.flexInt(.duration_secs)
            backdrop = TextUtil.url(i.flexStringArray(.backdrop_path).first)
            poster = i.flexURL(.movie_image) ?? i.flexURL(.cover_big)
            rating = normalizedRating(i.flexDouble(.rating), nil)
        }
        if let m = try? c.nestedContainer(keyedBy: MK.self, forKey: .movie_data) {
            ext = TextUtil.nonEmpty(m.flexString(.container_extension))
        }
    }
}

struct Episode: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let number: Int
    let season: Int
    let rawTitle: String
    let ext: String
    let image: URL?
    let plot: String?
    let durationSecs: Int?

    var title: String { TextUtil.episodeTitle(rawTitle, number: number) }
    var progressKey: String { "episode-\(id)" }

    private enum K: String, CodingKey { case id, episode_num, season, title, container_extension, info }
    private enum IK: String, CodingKey { case movie_image, cover_big, plot, duration_secs }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        guard let id = c.flexString(.id) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "sem id"))
        }
        self.id = id
        number = c.flexInt(.episode_num) ?? 0
        season = c.flexInt(.season) ?? 1
        rawTitle = c.flexString(.title) ?? ""
        ext = TextUtil.nonEmpty(c.flexString(.container_extension)) ?? "mp4"
        if let i = try? c.nestedContainer(keyedBy: IK.self, forKey: .info) {
            image = i.flexURL(.movie_image) ?? i.flexURL(.cover_big)
            plot = TextUtil.nonEmpty(i.flexString(.plot))
            durationSecs = i.flexInt(.duration_secs)
        } else {
            image = nil; plot = nil; durationSecs = nil
        }
    }

    static func == (a: Episode, b: Episode) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct SeriesInfo: Decodable, Sendable {
    var plot: String?
    var cast: String?
    var director: String?
    var genre: String?
    var backdrop: URL?
    var cover: URL?
    var episodesBySeason: [Int: [Episode]] = [:]

    var seasons: [Int] { episodesBySeason.keys.sorted() }
    var allEpisodes: [Episode] { seasons.flatMap { episodesBySeason[$0] ?? [] } }

    private enum K: String, CodingKey { case info, episodes }
    private enum IK: String, CodingKey { case plot, cast, director, genre, backdrop_path, cover }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        if let i = try? c.nestedContainer(keyedBy: IK.self, forKey: .info) {
            plot = TextUtil.nonEmpty(i.flexString(.plot))
            cast = TextUtil.nonEmpty(i.flexString(.cast))
            director = TextUtil.nonEmpty(i.flexString(.director))
            genre = TextUtil.nonEmpty(i.flexString(.genre))
            backdrop = TextUtil.url(i.flexStringArray(.backdrop_path).first)
            cover = i.flexURL(.cover)
        }
        var map: [Int: [Episode]] = [:]
        if let dict = try? c.decode([String: [Lossy<Episode>]].self, forKey: .episodes) {
            for (key, list) in dict {
                for ep in list.compactMap(\.value) {
                    map[Int(key) ?? ep.season, default: []].append(ep)
                }
            }
        } else if let arr = try? c.decode([[Lossy<Episode>]].self, forKey: .episodes) {
            for list in arr {
                for ep in list.compactMap(\.value) { map[ep.season, default: []].append(ep) }
            }
        }
        for key in map.keys { map[key]?.sort { $0.number < $1.number } }
        episodesBySeason = map
    }
}

struct EPGEntry: Decodable, Identifiable, Hashable, Sendable {
    let title: String
    let summary: String?
    let start: Date
    let end: Date

    var id: String { "\(start.timeIntervalSince1970)-\(title)" }

    func progress(at now: Date = Date()) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(start) / total))
    }

    private enum K: String, CodingKey { case title, description, start_timestamp, stop_timestamp, start, end }

    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        title = TextUtil.base64Decoded(c.flexString(.title)) ?? "Sem título"
        summary = TextUtil.nonEmpty(TextUtil.base64Decoded(c.flexString(.description)))
        if let s = c.flexInt(.start_timestamp), let e = c.flexInt(.stop_timestamp) {
            start = Date(timeIntervalSince1970: TimeInterval(s))
            end = Date(timeIntervalSince1970: TimeInterval(e))
        } else if let s = c.flexString(.start).flatMap(Self.parser.date(from:)),
                  let e = c.flexString(.end).flatMap(Self.parser.date(from:)) {
            start = s; end = e
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "sem horário"))
        }
    }
}

struct EPGResponse: Decodable {
    let listings: [EPGEntry]
    private enum K: String, CodingKey { case epg_listings }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        listings = ((try? c.decode([Lossy<EPGEntry>].self, forKey: .epg_listings)) ?? []).compactMap(\.value)
    }
}
