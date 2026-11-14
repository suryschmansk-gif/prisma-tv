import SwiftUI
import UIKit
import AudioToolbox

// MARK: - Tema (grafite + azul-gelo)

enum Theme {
    static let bg = Color(red: 0.039, green: 0.039, blue: 0.051)        // #0a0a0d
    static let surface = Color(red: 0.082, green: 0.082, blue: 0.102)   // #15151a
    static let surface2 = Color(red: 0.122, green: 0.122, blue: 0.149)  // #1f1f26
    static let accent = Color(red: 0.612, green: 0.753, blue: 1.0)      // #9cc0ff
    static let accent2 = Color(red: 0.765, green: 0.710, blue: 1.0)     // #c3b5ff
    static let primary = Color(red: 0.961, green: 0.961, blue: 0.969)   // #f5f5f7
    static let onPrimary = Color(red: 0.039, green: 0.039, blue: 0.051)
    static let muted = Color.white.opacity(0.62)
    static let hairline = Color.white.opacity(0.08)
    static let progress = LinearGradient(colors: [accent, accent2], startPoint: .leading, endPoint: .trailing)
}

enum Fmt {
    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let s = Int(seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    static func minutesLeft(_ seconds: Double) -> String {
        let m = Int((seconds / 60).rounded())
        if m >= 60 { return "faltam \(m / 60)h\(String(format: "%02d", m % 60))" }
        return "faltam \(max(1, m)) min"
    }

    /// "21:36 de 45:00 · faltam 23 min"
    static func progressLine(_ e: WatchEntry) -> String {
        guard e.duration > 0 else { return Fmt.time(e.position) }
        return "\(time(e.position)) de \(time(e.duration)) · \(minutesLeft(e.remaining))"
    }

    static let hour: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    static let day: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "pt_BR"); f.dateFormat = "dd 'de' MMM 'de' yyyy"; return f
    }()

    static func rating(_ r: Double?) -> String? {
        guard let r, r > 0 else { return nil }
        return String(format: "%.1f", r).replacingOccurrences(of: ".", with: ",")
    }
}

// MARK: - Som e vibração ao tocar

@MainActor
enum Feedback {
    private static let impact = UIImpactFeedbackGenerator(style: .light)
    private static let selection = UISelectionFeedbackGenerator()

    static var soundsOn: Bool { UserDefaults.standard.object(forKey: "tapSounds") as? Bool ?? true }

    static func tap() {
        impact.impactOccurred(intensity: 0.6)
        if soundsOn { AudioServicesPlaySystemSound(1104) }   // "tock" suave do teclado do iOS
    }

    static func select() {
        selection.selectionChanged()
        if soundsOn { AudioServicesPlaySystemSound(1104) }
    }
}

/// Botão que encolhe de leve ao tocar, com som e vibração.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        PressableBody(configuration: configuration, scale: scale)
    }
}

private struct PressableBody: View {
    let configuration: ButtonStyleConfiguration
    let scale: CGFloat
    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { pressed in
                if pressed { Feedback.tap() }
            }
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

// MARK: - Animação sutil de entrada (fade + leve subida)

private struct Reveal: ViewModifier {
    let delay: Double
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 18)
            .onAppear {
                guard !shown else { return }
                withAnimation(.easeOut(duration: 0.55).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func reveal(_ delay: Double = 0) -> some View { modifier(Reveal(delay: delay)) }

    /// Vidro estilo iOS: desfoca o que está atrás.
    func glass<S: Shape>(_ shape: S, dark: Bool = false) -> some View {
        self
            .background(dark ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(.ultraThinMaterial), in: shape)
            .overlay(shape.stroke(Color.white.opacity(0.16), lineWidth: 1))
    }

    func screenBackground() -> some View {
        self.background(Theme.bg.ignoresSafeArea())
    }
}

// MARK: - Imagens com cache

final class ImageLoader: @unchecked Sendable {
    static let shared = ImageLoader()
    private let cache = NSCache<NSURL, UIImage>()
    private let session: URLSession

    private init() {
        cache.countLimit = 600
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 600 * 1024 * 1024)
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.timeoutIntervalForRequest = 20
        session = URLSession(configuration: cfg)
    }

    func cached(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    func load(_ url: URL, maxPixels: CGFloat) async -> UIImage? {
        if let img = cached(url) { return img }
        guard let result = try? await session.data(from: url), let img = UIImage(data: result.0) else { return nil }
        var out = img
        if img.size.width > maxPixels, img.size.width > 0 {
            let size = CGSize(width: maxPixels, height: img.size.height * maxPixels / img.size.width)
            out = await img.byPreparingThumbnail(ofSize: size) ?? img
        }
        cache.setObject(out, forKey: url as NSURL)
        return out
    }
}

struct CachedImage: View {
    let url: URL?
    var placeholder: String = ""
    var maxWidth: CGFloat = 400
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                PlaceholderArt(text: placeholder)
                    .shimmer(active: url != nil)
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            if let hit = ImageLoader.shared.cached(url) { image = hit; return }
            image = nil
            let loaded = await ImageLoader.shared.load(url, maxPixels: maxWidth * 3)
            if !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.3)) { image = loaded }
            }
        }
    }
}

struct PlaceholderArt: View {
    let text: String
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.surface2, Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
            if !text.isEmpty {
                Text(text)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(8)
            } else {
                Image(systemName: "photo").foregroundStyle(.white.opacity(0.2))
            }
        }
    }
}

/// Moldura de proporção fixa que recorta a imagem sem estourar o layout.
struct FramedImage: View {
    let url: URL?
    var ratio: CGFloat = 2.0 / 3.0
    var placeholder: String = ""
    var corner: CGFloat = 14
    var maxWidth: CGFloat = 400

    var body: some View {
        Color.clear
            .aspectRatio(ratio, contentMode: .fit)
            .overlay(CachedImage(url: url, placeholder: placeholder, maxWidth: maxWidth))
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }
}

// MARK: - Cards

struct PosterCard: View {
    let item: MediaItem
    @EnvironmentObject private var favorites: FavoritesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FramedImage(url: item.poster, placeholder: item.title)
                .overlay(alignment: .topLeading) {
                    if let r = Fmt.rating(item.rating) {
                        Text("★ \(r)")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(.black.opacity(0.6), in: Capsule())
                            .foregroundStyle(Theme.accent)
                            .padding(7)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    VStack(spacing: 4) {
                        if favorites.contains(item.favKey) { badge("heart.fill") }
                        if favorites.inWatchlist(item.favKey) { badge("bookmark.fill") }
                    }
                    .padding(7)
                }
                .overlay(alignment: .bottom) {
                    if favorites.isWatched(item.favKey) {
                        Label("Assistido", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.onPrimary)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Theme.accent, in: Capsule())
                            .padding(.bottom, 8)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .shadow(color: .black.opacity(0.45), radius: 8, y: 5)

            Text(item.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)

            Text(metaLine)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    private func badge(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Theme.accent)
            .padding(6)
            .background(.black.opacity(0.6), in: Circle())
            .transition(.scale.combined(with: .opacity))
    }

    private var metaLine: String {
        var parts: [String] = []
        if let y = item.year { parts.append(String(y)) }
        if let g = item.genres.first { parts.append(g) }
        if parts.isEmpty { parts.append(item.kind == .movie ? "Filme" : "Série") }
        return parts.joined(separator: " · ")
    }
}

struct ContinueCard: View {
    let entry: WatchEntry
    var width: CGFloat = 272

    private var badge: String {
        if let s = entry.season, let e = entry.episode { return "T\(s) · E\(e)" }
        return entry.kind == .movie ? "FILME" : "SÉRIE"
    }

    private var line: String {
        if let e = entry.episode {
            return "Episódio \(e)" + (entry.episodeTitle.map { " — \($0)" } ?? "")
        }
        return entry.subtitle ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Color.clear
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .overlay(CachedImage(url: entry.image, placeholder: entry.title, maxWidth: 520))
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                Image(systemName: "play.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .glass(Circle())
            }
            .overlay(alignment: .topLeading) {
                Text(badge)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(10)
            }

            ProgressLine(value: entry.fraction, height: 4, rounded: false)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title).font(.system(size: 15, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                if !line.isEmpty {
                    Text(line).font(.system(size: 13)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                }
                Text(Fmt.progressLine(entry))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 13).padding(.vertical, 11)
        }
        .frame(width: width)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

struct ProgressLine: View {
    let value: Double
    var height: CGFloat = 4
    var rounded = true
    @State private var shown = false
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(.white.opacity(0.14))
                Rectangle().fill(Theme.progress)
                    .frame(width: geo.size.width * CGFloat(shown ? min(1, max(0, value)) : 0))
            }
            .clipShape(RoundedRectangle(cornerRadius: rounded ? height / 2 : 0))
        }
        .frame(height: height)
        .onAppear { withAnimation(.easeOut(duration: 0.8).delay(0.15)) { shown = true } }
    }
}

// MARK: - Seções

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 20, weight: .bold))
            .tracking(-0.3)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
    }
}

struct PosterRow: View {
    let title: String
    let items: [MediaItem]
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: title)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                PosterCard(item: item).frame(width: sizeClass == .regular ? 150 : 118)
                            }
                            .buttonStyle(.pressable)
                            .listMenu(item)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

struct TopRow: View {
    let title: String
    let items: [MediaItem]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: title)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .bottom, spacing: 8) {
                        ForEach(Array(items.prefix(5).enumerated()), id: \.element.id) { index, item in
                            NavigationLink(value: item) {
                                HStack(alignment: .bottom, spacing: -14) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 104, weight: .heavy, design: .rounded))
                                        .foregroundStyle(
                                            LinearGradient(colors: [Theme.accent.opacity(0.55), Theme.accent.opacity(0.08)],
                                                           startPoint: .top, endPoint: .bottom)
                                        )
                                        .offset(y: 14)
                                    FramedImage(url: item.poster, placeholder: item.title)
                                        .frame(width: 116)
                                        .shadow(color: .black.opacity(0.5), radius: 8, y: 5)
                                }
                            }
                            .buttonStyle(.pressable)
                            .listMenu(item)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

struct Chip: View {
    let title: String
    var selected: Bool = false
    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 15).padding(.vertical, 9)
            .background(selected ? Theme.primary : Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(selected ? Color.clear : Theme.hairline, lineWidth: 1))
            .foregroundStyle(selected ? Theme.onPrimary : .white)
    }
}

struct PrimaryButton: View {
    let title: String
    var icon: String = "play.fill"
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Theme.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(Theme.onPrimary)
        }
        .buttonStyle(.pressable)
    }
}

struct SecondaryButton: View {
    let title: String
    let icon: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .glass(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
        }
        .buttonStyle(.pressable)
    }
}

struct SearchField: View {
    let prompt: String
    @Binding var text: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.55))
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundStyle(.white)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.45))
                }
                .accessibilityLabel("Limpar busca")
            } else if let trailing {
                Text(trailing).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }
}

struct AppLogo: View {
    var size: CGFloat = 64
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.11, green: 0.125, blue: 0.19), Color(red: 0.043, green: 0.047, blue: 0.07)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .stroke(Theme.accent.opacity(0.4), lineWidth: 1)
            Image(systemName: "play.tv.fill")
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [Theme.accent, Theme.accent2], startPoint: .top, endPoint: .bottom))
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.accent.opacity(0.3), radius: 18, y: 8)
    }
}

/// Destaque grande no topo das telas de detalhe.
struct DetailHero: View {
    let image: URL?
    let kicker: String
    let title: String
    let meta: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .frame(height: 420)
                .overlay(CachedImage(url: image, maxWidth: 1000))
                .clipped()
            LinearGradient(stops: [
                .init(color: Theme.bg.opacity(0.35), location: 0),
                .init(color: .clear, location: 0.3),
                .init(color: Theme.bg.opacity(0.75), location: 0.72),
                .init(color: Theme.bg, location: 1),
            ], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                Text(kicker)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(Theme.accent)
                Text(title)
                    .font(.system(size: 34, weight: .heavy))
                    .tracking(-0.8)
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                if !meta.isEmpty {
                    Text(meta).font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}

struct ExpandableText: View {
    let text: String
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(expanded ? nil : 4)
            if text.count > 220 {
                Button(expanded ? "Mostrar menos" : "Mostrar mais") { withAnimation(.easeInOut) { expanded.toggle() } }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}

struct DetailRouter: View {
    let item: MediaItem
    var body: some View {
        switch item.kind {
        case .movie: MovieDetailView(item: item)
        case .series: SeriesDetailView(item: item)
        }
    }
}

/// Crédito do desenvolvedor, mostrado no fim das telas.
struct CreditFooter: View {
    var body: some View {
        Text("Desenvolvido por Caio S L Torres")
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.4))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
    }
}


// MARK: - Brilho animado enquanto a imagem carrega

private struct Shimmer: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = -1
    func body(content: Content) -> some View {
        content.overlay {
            if active {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.10), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.8)
                        .offset(x: phase * geo.size.width * 1.6)
                        .blendMode(.plusLighter)
                }
                .clipped()
                .onAppear {
                    withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
                }
            }
        }
    }
}

extension View {
    func shimmer(active: Bool = true) -> some View { modifier(Shimmer(active: active)) }
}

// MARK: - Listas (Favoritos, Quero ver, Já assisti)

@MainActor
enum ListActions {
    static func favorite(_ key: String, _ f: FavoritesStore, _ lib: Library) {
        let on = f.toggle(key)
        lib.showToast(on ? "heart.fill" : "heart.slash", on ? "Adicionado a Favoritos" : "Removido de Favoritos")
    }

    static func watchlist(_ key: String, _ f: FavoritesStore, _ lib: Library) {
        let on = f.toggleWatchlist(key)
        lib.showToast(on ? "bookmark.fill" : "bookmark.slash", on ? "Adicionado a Quero ver" : "Removido de Quero ver")
    }

    static func watched(_ key: String, _ f: FavoritesStore, _ lib: Library) {
        let on = f.toggleWatched(key)
        lib.showToast(on ? "checkmark.circle.fill" : "arrow.uturn.backward.circle", on ? "Marcado como assistido" : "Desmarcado como assistido")
    }
}

/// Segurar o dedo numa capa abre este menu.
private struct ListContextMenu: ViewModifier {
    let item: MediaItem
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var lib: Library

    func body(content: Content) -> some View {
        content.contextMenu {
            Button { ListActions.favorite(item.favKey, favorites, lib) } label: {
                Label(favorites.contains(item.favKey) ? "Remover de Favoritos" : "Adicionar a Favoritos",
                      systemImage: favorites.contains(item.favKey) ? "heart.slash" : "heart")
            }
            Button { ListActions.watchlist(item.favKey, favorites, lib) } label: {
                Label(favorites.inWatchlist(item.favKey) ? "Remover de Quero ver" : "Quero ver",
                      systemImage: favorites.inWatchlist(item.favKey) ? "bookmark.slash" : "bookmark")
            }
            Button { ListActions.watched(item.favKey, favorites, lib) } label: {
                Label(favorites.isWatched(item.favKey) ? "Desmarcar como assistido" : "Marcar como assistido",
                      systemImage: favorites.isWatched(item.favKey) ? "arrow.uturn.backward.circle" : "checkmark.circle")
            }
        }
    }
}

extension View {
    func listMenu(_ item: MediaItem) -> some View { modifier(ListContextMenu(item: item)) }
}

/// Os três botões de lista da tela de detalhes, com animação de "pulo".
struct ListButtons: View {
    let key: String
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var lib: Library

    var body: some View {
        HStack(spacing: 10) {
            ListToggleButton(title: "Favorito", icon: "heart", activeIcon: "heart.fill", active: favorites.contains(key)) {
                ListActions.favorite(key, favorites, lib)
            }
            ListToggleButton(title: "Quero ver", icon: "bookmark", activeIcon: "bookmark.fill", active: favorites.inWatchlist(key)) {
                ListActions.watchlist(key, favorites, lib)
            }
            ListToggleButton(title: "Já assisti", icon: "checkmark.circle", activeIcon: "checkmark.circle.fill", active: favorites.isWatched(key)) {
                ListActions.watched(key, favorites, lib)
            }
        }
    }
}

private struct ListToggleButton: View {
    let title: String
    let icon: String
    let activeIcon: String
    let active: Bool
    var action: () -> Void
    @State private var pop = false

    var body: some View {
        Button {
            pop = true
            withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) { pop = false }
            withAnimation(.easeInOut(duration: 0.2)) { action() }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: active ? activeIcon : icon)
                    .font(.system(size: 19, weight: .semibold))
                    .scaleEffect(pop ? 1.35 : 1)
                    .rotationEffect(.degrees(pop ? -12 : 0))
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(active ? Theme.accent : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(active ? Theme.accent.opacity(0.14) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .glass(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

struct ToastView: View {
    let toast: Toast
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.accent)
            Text(toast.text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .glass(Capsule(), dark: true)
        .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
    }
}
