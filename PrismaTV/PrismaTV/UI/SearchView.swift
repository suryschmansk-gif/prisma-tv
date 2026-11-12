import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var lib: Library
    @EnvironmentObject private var favorites: FavoritesStore

    @State private var query = ""
    @State private var channels: [LiveChannel] = []
    @State private var series: [MediaItem] = []
    @State private var movies: [MediaItem] = []
    @State private var searching = false

    private struct Found: Sendable {
        var channels: [LiveChannel] = []
        var series: [MediaItem] = []
        var movies: [MediaItem] = []
    }

    private var active: Bool { query.trimmingCharacters(in: .whitespaces).count >= 2 }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Buscar")
                            .font(.system(size: 30, weight: .heavy))
                            .tracking(-0.6)
                        SearchField(prompt: "Séries, filmes e canais", text: $query)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    if !active {
                        VStack(spacing: 10) {
                            Image(systemName: "sparkle.magnifyingglass")
                                .font(.system(size: 42))
                                .foregroundStyle(Theme.accent)
                            Text("Busque em tudo ao mesmo tempo")
                                .font(.system(size: 17, weight: .bold))
                            Text("Acentos e maiúsculas não importam.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 70)
                        .reveal()
                    } else if !searching && channels.isEmpty && series.isEmpty && movies.isEmpty {
                        Text("Nada encontrado para “\(query)”.")
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 70)
                    } else {
                        PosterRow(title: "Séries", items: series).reveal()
                        PosterRow(title: "Filmes", items: movies).reveal(0.05)
                        if !channels.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "Canais")
                                ForEach(Array(channels.enumerated()), id: \.element.id) { index, ch in
                                    ChannelCard(channel: ch, number: index + 1,
                                                isFavorite: favorites.contains(ch.favKey),
                                                onPlay: { lib.playChannel(ch, in: channels) },
                                                onInfo: {})
                                        .padding(.horizontal)
                                }
                            }
                            .reveal(0.1)
                        }
                    }
                }
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.immediately)
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MediaItem.self) { DetailRouter(item: $0) }
            .task(id: query) { await search() }
        }
    }

    private func search() async {
        let raw = query.trimmingCharacters(in: .whitespaces)
        guard raw.count >= 2 else {
            channels = []; series = []; movies = []
            return
        }
        searching = true
        try? await Task.sleep(nanoseconds: 300_000_000)
        if Task.isCancelled { return }
        let q = TextUtil.searchKey(raw)
        let catalog = lib.catalog
        let found = await Task.detached(priority: .userInitiated) { () -> Found in
            func rank(_ items: [MediaItem]) -> [MediaItem] {
                let hits = items.filter { $0.searchKey.contains(q) }
                let starts = hits.filter { $0.searchKey.hasPrefix(q) }
                let rest = hits.filter { !$0.searchKey.hasPrefix(q) }
                return Array((starts + rest).prefix(40))
            }
            var f = Found()
            f.series = rank(catalog.series)
            f.movies = rank(catalog.movies)
            f.channels = Array(catalog.channels.filter { $0.searchKey.contains(q) }.prefix(30))
            return f
        }.value
        if Task.isCancelled { return }
        withAnimation(.easeOut(duration: 0.25)) {
            channels = found.channels
            series = found.series
            movies = found.movies
            searching = false
        }
    }
}
