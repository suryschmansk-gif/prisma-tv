import SwiftUI

/// Aba "Listas": Assistindo, Quero ver, Favoritos e Já assisti.
struct MyListsView: View {
    enum ListKind: String, CaseIterable, Identifiable {
        case watching = "Assistindo"
        case watchlist = "Quero ver"
        case favorites = "Favoritos"
        case watched = "Já assisti"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .watching: return "play.circle.fill"
            case .watchlist: return "bookmark.fill"
            case .favorites: return "heart.fill"
            case .watched: return "checkmark.circle.fill"
            }
        }

        var emptyText: String {
            switch self {
            case .watching: return "O que você começar a assistir aparece aqui."
            case .watchlist: return "Segure o dedo numa capa e toque em \"Quero ver\" para guardar séries e filmes para depois."
            case .favorites: return "Toque no coração de uma série ou filme para guardar aqui."
            case .watched: return "Marque o que você já assistiu para não se perder."
            }
        }
    }

    enum TypeFilter: String, CaseIterable, Identifiable {
        case all = "Tudo", series = "Séries", movies = "Filmes"
        var id: String { rawValue }
    }

    @EnvironmentObject private var lib: Library
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var favorites: FavoritesStore
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var list: ListKind = .watchlist
    @State private var filter: TypeFilter = .all
    @Namespace private var pill

    private func keys(for kind: ListKind) -> Set<String> {
        switch kind {
        case .watchlist: return favorites.watchlist
        case .favorites: return favorites.keys
        case .watched: return favorites.watched
        case .watching: return []
        }
    }

    private func passes(_ kind: MediaItem.Kind) -> Bool {
        switch filter {
        case .all: return true
        case .series: return kind == .series
        case .movies: return kind == .movie
        }
    }

    private var items: [MediaItem] {
        keys(for: list)
            .compactMap { lib.catalog.itemsByKey[$0] }
            .filter { passes($0.kind) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var watching: [WatchEntry] {
        progress.continueWatching.filter { passes($0.kind) }
    }

    private func count(_ kind: ListKind) -> Int {
        kind == .watching ? progress.continueWatching.count : keys(for: kind).count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Minhas listas")
                        .font(.system(size: 30, weight: .heavy))
                        .tracking(-0.6)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    // Abas animadas
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(ListKind.allCases) { kind in
                                let active = kind == list
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { list = kind }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: kind.icon).font(.system(size: 13, weight: .bold))
                                        Text(kind.rawValue).font(.system(size: 14, weight: .semibold))
                                        Text("\(count(kind))")
                                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background((active ? Theme.onPrimary : Color.white).opacity(0.15), in: Capsule())
                                    }
                                    .foregroundStyle(active ? Theme.onPrimary : .white)
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background {
                                        if active {
                                            Capsule().fill(Theme.primary).matchedGeometryEffect(id: "pill", in: pill)
                                        } else {
                                            Capsule().fill(Theme.surface)
                                        }
                                    }
                                }
                                .buttonStyle(PressableStyle(scale: 0.94))
                            }
                        }
                        .padding(.horizontal)
                    }

                    HStack(spacing: 8) {
                        ForEach(TypeFilter.allCases) { f in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { filter = f }
                            } label: {
                                Text(f.rawValue)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(filter == f ? Theme.accent : Theme.muted)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .overlay(alignment: .bottom) {
                                        if filter == f {
                                            Capsule().fill(Theme.accent).frame(height: 2).padding(.horizontal, 10)
                                        }
                                    }
                            }
                            .buttonStyle(PressableStyle(scale: 0.94))
                        }
                    }
                    .padding(.horizontal, 8)

                    content
                        .id("\(list.rawValue)-\(filter.rawValue)")
                        .transition(.opacity.combined(with: .move(edge: .bottom)))

                    CreditFooter()
                }
                .padding(.bottom, 24)
            }
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MediaItem.self) { DetailRouter(item: $0) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if list == .watching {
            if watching.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: sizeClass == .regular ? 300 : 260), spacing: 14, alignment: .top)],
                          spacing: 16) {
                    ForEach(watching) { entry in
                        Button { lib.resume(entry) } label: { ContinueCard(entry: entry, width: sizeClass == .regular ? 300 : 340) }
                            .buttonStyle(.pressable)
                            .reveal()
                    }
                }
                .padding(.horizontal)
            }
        } else if items.isEmpty {
            emptyState
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: sizeClass == .regular ? 150 : 104), spacing: 12, alignment: .top)],
                      spacing: 20) {
                ForEach(items) { item in
                    NavigationLink(value: item) { PosterCard(item: item) }
                        .buttonStyle(.pressable)
                        .listMenu(item)
                        .reveal()
                }
            }
            .padding(.horizontal)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: list.icon)
                .font(.system(size: 42))
                .foregroundStyle(Theme.accent.opacity(0.8))
            Text(list == .watching ? "Nada em andamento" : "Lista vazia")
                .font(.system(size: 17, weight: .bold))
            Text(list.emptyText)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .reveal()
    }
}
