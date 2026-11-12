import SwiftUI

/// Tela principal de Séries ou de Filmes: destaque, continuar assistindo, listas e catálogo completo.
struct SectionView: View {
    let kind: MediaItem.Kind

    @EnvironmentObject private var lib: Library
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var favorites: FavoritesStore
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var categoryId: String?
    @State private var query = ""
    @State private var filters = CatalogFilters()
    @State private var results: [MediaItem] = []
    @State private var computing = true
    @State private var showFilters = false
    @State private var showSettings = false

    private struct Key: Equatable {
        let category: String?
        let query: String
        let filters: CatalogFilters
        let total: Int
        let favCount: Int
    }

    private var isSeries: Bool { kind == .series }
    private var items: [MediaItem] { isSeries ? lib.catalog.series : lib.catalog.movies }
    private var categories: [XCategory] { isSeries ? lib.catalog.seriesCategories : lib.catalog.movieCategories }
    private var counts: [String: Int] { isSeries ? lib.catalog.seriesCounts : lib.catalog.movieCounts }
    private var genres: [String] { isSeries ? lib.catalog.seriesGenres : lib.catalog.movieGenres }

    private var resume: [WatchEntry] { progress.continueWatching.filter { $0.kind == kind } }

    private var favoriteItems: [MediaItem] {
        items.filter { favorites.contains($0.favKey) }
    }

    private var topItems: [MediaItem] {
        lib.catalog.topRated.filter { $0.kind == kind }
    }

    private var recentItems: [MediaItem] {
        isSeries ? lib.catalog.recentSeries : lib.catalog.recentMovies
    }

    /// O destaque é o que você está assistindo; se não houver nada, o mais recente com imagem.
    private var hero: (item: MediaItem, entry: WatchEntry?)? {
        if let e = resume.first {
            let key = e.seriesId.map { "series-\($0)" } ?? "movie-\(e.streamId)"
            if let item = lib.catalog.itemsByKey[key] { return (item, e) }
        }
        if let item = recentItems.first(where: { $0.backdrop != nil }) ?? recentItems.first { return (item, nil) }
        return nil
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 30) {
                        if let hero {
                            HeroBanner(item: hero.item, entry: hero.entry, topInset: geo.safeAreaInsets.top,
                                       title: isSeries ? "Séries" : "Filmes") {
                                showSettings = true
                            }
                        } else {
                            Text(isSeries ? "Séries" : "Filmes")
                                .font(.system(size: 30, weight: .heavy))
                                .padding(.horizontal)
                                .padding(.top, geo.safeAreaInsets.top + 12)
                        }

                        if !resume.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "Continuar assistindo")
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(alignment: .top, spacing: 14) {
                                        ForEach(resume) { entry in
                                            Button { lib.resume(entry) } label: {
                                                ContinueCard(entry: entry, width: sizeClass == .regular ? 320 : 272)
                                            }
                                            .buttonStyle(.pressable)
                                            .contextMenu { continueMenu(entry) }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                            .reveal()
                        }

                        PosterRow(title: "Minha lista", items: favoriteItems).reveal()
                        TopRow(title: isSeries ? "Top 5 séries" : "Top 5 filmes", items: topItems).reveal()
                        PosterRow(title: isSeries ? "Séries atualizadas" : "Adicionados recentemente", items: recentItems).reveal()

                        catalogSection
                    }
                    .padding(.bottom, 24)
                }
                .ignoresSafeArea(edges: .top)
                .refreshable { await lib.refresh() }
            }
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MediaItem.self) { DetailRouter(item: $0) }
            .task(id: Key(category: categoryId, query: query, filters: filters,
                          total: items.count, favCount: favorites.keys.count)) {
                await recompute()
            }
            .sheet(isPresented: $showFilters) { FilterSheet(filters: $filters, genres: genres) }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    @ViewBuilder
    private func continueMenu(_ entry: WatchEntry) -> some View {
        Button {
            var e = entry; e.position = 0
            lib.resume(e)
        } label: { Label("Assistir do início", systemImage: "arrow.counterclockwise") }
        Button(role: .destructive) {
            if let sid = entry.seriesId { progress.removeSeries(sid) } else { progress.remove(entry.key) }
        } label: { Label("Remover de Continuar assistindo", systemImage: "xmark.circle") }
    }

    // MARK: Catálogo completo

    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isSeries ? "Todas as séries" : "Todos os filmes")
                    .font(.system(size: 20, weight: .bold))
                    .tracking(-0.3)
                Spacer()
                Button { showFilters = true } label: {
                    Label(filters.activeCount > 0 ? "Filtros · \(filters.activeCount)" : "Filtros",
                          systemImage: "line.3.horizontal.decrease")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .background(filters.activeCount > 0 ? Theme.primary : Theme.surface, in: Capsule())
                        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                        .foregroundStyle(filters.activeCount > 0 ? Theme.onPrimary : .white)
                }
                .buttonStyle(.pressable)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    chip(nil, "Todas")
                    chip(CatalogEngine.favoritesId, "Minha lista")
                    ForEach(categories.filter { (counts[$0.id] ?? 0) > 0 }) { cat in
                        chip(cat.id, cat.name)
                    }
                }
                .padding(.horizontal)
            }

            SearchField(prompt: isSeries ? "Buscar em séries" : "Buscar em filmes",
                        text: $query,
                        trailing: computing ? nil : "\(results.count)")
                .padding(.horizontal)

            if results.isEmpty && !computing {
                Text("Nada encontrado. Tente outra categoria ou limpe os filtros.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: sizeClass == .regular ? 150 : 104), spacing: 12, alignment: .top)],
                          spacing: 20) {
                    ForEach(results) { item in
                        NavigationLink(value: item) { PosterCard(item: item) }
                            .buttonStyle(.pressable)
                            .reveal()
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func chip(_ id: String?, _ name: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { categoryId = id }
        } label: {
            Chip(title: name, selected: categoryId == id)
        }
        .buttonStyle(PressableStyle(scale: 0.94))
    }

    private func recompute() async {
        computing = true
        if !query.isEmpty {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
        }
        let snapshot = items
        let cat = categoryId, q = query, f = filters, favs = favorites.keys
        let out = await Task.detached(priority: .userInitiated) {
            CatalogEngine.run(snapshot, category: cat, favorites: favs, query: q, filters: f)
        }.value
        if Task.isCancelled { return }
        withAnimation(.easeOut(duration: 0.25)) {
            results = out
            computing = false
        }
    }
}

/// Destaque grande do topo, com zoom lento na imagem (efeito "Ken Burns").
struct HeroBanner: View {
    let item: MediaItem
    let entry: WatchEntry?
    let topInset: CGFloat
    let title: String
    var onSettings: () -> Void

    @EnvironmentObject private var lib: Library
    @State private var zoom = false

    private var kicker: String {
        if entry != nil { return "CONTINUE DE ONDE PAROU" }
        return item.kind == .series ? "SÉRIE EM DESTAQUE" : "NOVO NO CATÁLOGO"
    }

    private var meta: String {
        var parts: [String] = []
        if let g = item.genres.first { parts.append(g) }
        if let y = item.year { parts.append(String(y)) }
        if let r = Fmt.rating(item.rating) { parts.append("★ \(r)") }
        return parts.joined(separator: " · ")
    }

    private var playLabel: String {
        guard let e = entry else { return item.kind == .series ? "Ver episódios" : "Assistir" }
        if let s = e.season, let n = e.episode { return "Continuar T\(s) E\(n)" }
        return "Continuar"
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .frame(height: 470 + topInset * 0.3)
                .overlay(
                    CachedImage(url: item.backdrop ?? item.poster, maxWidth: 1000)
                        .scaleEffect(zoom ? 1.12 : 1.0)
                        .animation(.easeInOut(duration: 18).repeatForever(autoreverses: true), value: zoom)
                )
                .clipped()

            LinearGradient(stops: [
                .init(color: Theme.bg.opacity(0.45), location: 0),
                .init(color: .clear, location: 0.28),
                .init(color: Theme.bg.opacity(0.7), location: 0.7),
                .init(color: Theme.bg, location: 1),
            ], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 10) {
                Text(kicker)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(Theme.accent)
                Text(item.title)
                    .font(.system(size: 36, weight: .heavy))
                    .tracking(-0.8)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if let e = entry, let s = e.season, let n = e.episode {
                    Text("Temporada \(s) · Episódio \(n)\(e.episodeTitle.map { " — \($0)" } ?? "")")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                } else if !meta.isEmpty {
                    Text(meta).font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
                }
                HStack(spacing: 10) {
                    if let e = entry {
                        PrimaryButton(title: playLabel) { lib.resume(e) }
                    } else if item.kind == .movie {
                        PrimaryButton(title: playLabel) { lib.playMovie(item, resume: false) }
                    } else {
                        NavigationLink(value: item) {
                            Label(playLabel, systemImage: "play.fill")
                                .font(.system(size: 15, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(Theme.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .foregroundStyle(Theme.onPrimary)
                        }
                        .buttonStyle(.pressable)
                    }
                    NavigationLink(value: item) {
                        Text("Detalhes")
                            .font(.system(size: 15, weight: .bold))
                            .padding(.horizontal, 20).padding(.vertical, 15)
                            .glass(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.pressable)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .reveal(0.1)
        }
        .overlay(alignment: .top) {
            HStack {
                Text(title)
                    .font(.system(size: 30, weight: .heavy))
                    .tracking(-0.6)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 8)
                Spacer()
                Button(action: onSettings) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .glass(Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Conta e configurações")
            }
            .padding(.horizontal)
            .padding(.top, topInset + 6)
        }
        .onAppear { zoom = true }
    }
}
