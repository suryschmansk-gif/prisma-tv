import SwiftUI

private struct FavoriteToolbarButton: View {
    let key: String
    @EnvironmentObject private var favorites: FavoritesStore
    var body: some View {
        let fav = favorites.contains(key)
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { favorites.toggle(key) }
        } label: {
            Image(systemName: fav ? "heart.fill" : "heart")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(fav ? Theme.accent : .white)
                .frame(width: 36, height: 36)
                .glass(Circle())
                .scaleEffect(fav ? 1.08 : 1)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(fav ? "Remover da minha lista" : "Adicionar à minha lista")
    }
}

private struct ResumeCard: View {
    let title: String
    let entry: WatchEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VOCÊ PAROU EM")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
            ProgressLine(value: entry.fraction)
            Text(Fmt.progressLine(entry))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Theme.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.accent.opacity(0.22), lineWidth: 1))
    }
}

private struct RestartButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Assistir do início")
    }
}

private struct GenreChips: View {
    let genres: [String]
    var body: some View {
        if !genres.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(genres, id: \.self) { Chip(title: $0) } }
            }
        }
    }
}

private extension View {
    func detailChrome(favKey: String) -> some View {
        self
            .ignoresSafeArea(edges: .top)
            .screenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { FavoriteToolbarButton(key: favKey) }
            }
    }
}

// MARK: - Filme

struct MovieDetailView: View {
    let item: MediaItem

    @EnvironmentObject private var lib: Library
    @EnvironmentObject private var progress: ProgressStore
    @State private var info: MovieInfo?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DetailHero(image: info?.backdrop ?? item.backdrop ?? info?.poster ?? item.poster,
                           kicker: "FILME" + (item.genres.first.map { " · \($0.uppercased())" } ?? ""),
                           title: item.title,
                           meta: meta)

                VStack(alignment: .leading, spacing: 14) {
                    if let e = progress.entry(item.progressKey), !e.isFinished, e.position > 20 {
                        ResumeCard(title: item.title, entry: e)
                        HStack(spacing: 10) {
                            PrimaryButton(title: "Continuar de \(Fmt.time(e.position))") {
                                lib.playMovie(item, ext: info?.ext, resume: true)
                            }
                            RestartButton { lib.playMovie(item, ext: info?.ext, resume: false) }
                        }
                    } else {
                        PrimaryButton(title: "Assistir") { lib.playMovie(item, ext: info?.ext, resume: false) }
                    }

                    let genres = TextUtil.genres(info?.genre).isEmpty ? item.genres : TextUtil.genres(info?.genre)
                    GenreChips(genres: genres)

                    if let plot = info?.plot ?? item.plot {
                        ExpandableText(text: plot)
                    } else if info == nil {
                        ProgressView().tint(Theme.accent).frame(maxWidth: .infinity)
                    }
                    credit("Elenco", info?.cast)
                    credit("Direção", info?.director)
                    credit("Lançamento", info?.releaseDate)
                }
                .padding(.horizontal)
                .reveal(0.05)
            }
            .padding(.bottom, 30)
        }
        .detailChrome(favKey: item.favKey)
        .task { if info == nil { info = try? await lib.api?.movieInfo(id: item.streamId) } }
    }

    private var meta: String {
        var m: [String] = []
        if let y = item.year { m.append(String(y)) }
        if let d = info?.durationSecs, d > 0 { m.append(d >= 3600 ? "\(d / 3600)h \((d % 3600) / 60)min" : "\(d / 60)min") }
        else if let d = info?.duration { m.append(d) }
        if let r = Fmt.rating(info?.rating ?? item.rating) { m.append("★ \(r)") }
        return m.joined(separator: " · ")
    }

    @ViewBuilder
    private func credit(_ label: String, _ value: String?) -> some View {
        if let value {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
                Text(value).font(.system(size: 14)).foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}

// MARK: - Série

struct SeriesDetailView: View {
    let item: MediaItem

    @EnvironmentObject private var lib: Library
    @EnvironmentObject private var progress: ProgressStore
    @State private var info: SeriesInfo?
    @State private var season: Int?
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DetailHero(image: info?.backdrop ?? item.backdrop ?? info?.cover ?? item.poster,
                           kicker: "SÉRIE" + (item.genres.first.map { " · \($0.uppercased())" } ?? ""),
                           title: item.title,
                           meta: meta)

                VStack(alignment: .leading, spacing: 14) {
                    if let info, let target = continueTarget(info) {
                        if let e = target.entry, target.resume {
                            ResumeCard(title: "Temporada \(target.season) · Episódio \(target.episode.number) — \(target.episode.title)", entry: e)
                        }
                        HStack(spacing: 10) {
                            PrimaryButton(title: target.label) {
                                lib.playEpisode(target.episode, series: item, info: info, resume: target.resume)
                            }
                            if target.resume {
                                RestartButton { lib.playEpisode(target.episode, series: item, info: info, resume: false) }
                            }
                        }
                    }

                    let genres = TextUtil.genres(info?.genre).isEmpty ? item.genres : TextUtil.genres(info?.genre)
                    GenreChips(genres: genres)
                    if let plot = info?.plot ?? item.plot { ExpandableText(text: plot) }
                    if let cast = info?.cast {
                        Text("Elenco: \(cast)").font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
                    }
                }
                .padding(.horizontal)
                .reveal(0.05)

                if let info {
                    episodesSection(info).reveal(0.1)
                } else if failed {
                    Text("Não consegui carregar os episódios. Puxe para baixo para tentar de novo.")
                        .font(.subheadline).foregroundStyle(Theme.muted).padding(.horizontal)
                } else {
                    ProgressView("Carregando episódios…").tint(Theme.accent).frame(maxWidth: .infinity).padding(.top, 20)
                }
            }
            .padding(.bottom, 30)
        }
        .refreshable { await load() }
        .detailChrome(favKey: item.favKey)
        .task { if info == nil { await load() } }
    }

    private func load() async {
        failed = false
        do {
            let loaded = try await lib.api?.seriesInfo(id: item.streamId)
            withAnimation(.easeOut(duration: 0.25)) { info = loaded }
            if season == nil, let loaded {
                let last = progress.lastEpisode(seriesId: item.streamId)
                let lastSeason = last.flatMap { e in
                    loaded.episodesBySeason.first { $0.value.contains { $0.id == e.streamId } }?.key
                }
                season = lastSeason ?? loaded.seasons.first
            }
        } catch {
            failed = true
        }
    }

    private var meta: String {
        var m: [String] = []
        if let y = item.year { m.append(String(y)) }
        if let info, !info.seasons.isEmpty {
            m.append(info.seasons.count == 1 ? "1 temporada" : "\(info.seasons.count) temporadas")
        }
        if let r = Fmt.rating(item.rating) { m.append("★ \(r)") }
        return m.joined(separator: " · ")
    }

    private struct Target {
        let episode: Episode
        let season: Int
        let label: String
        let resume: Bool
        let entry: WatchEntry?
    }

    private func seasonOf(_ ep: Episode, in info: SeriesInfo) -> Int {
        info.episodesBySeason.first { $0.value.contains(ep) }?.key ?? ep.season
    }

    private func continueTarget(_ info: SeriesInfo) -> Target? {
        let all = info.allEpisodes
        guard let first = all.first else { return nil }
        guard let last = progress.lastEpisode(seriesId: item.streamId),
              let idx = all.firstIndex(where: { $0.id == last.streamId }) else {
            let s = seasonOf(first, in: info)
            return Target(episode: first, season: s, label: "Assistir T\(s) E\(first.number)", resume: false, entry: nil)
        }
        let ep = all[idx]
        if last.isFinished {
            if idx + 1 < all.count {
                let next = all[idx + 1]
                let s = seasonOf(next, in: info)
                return Target(episode: next, season: s, label: "Próximo: T\(s) E\(next.number)", resume: false, entry: nil)
            }
            let s = seasonOf(first, in: info)
            return Target(episode: first, season: s, label: "Rever desde o início", resume: false, entry: nil)
        }
        let s = seasonOf(ep, in: info)
        return Target(episode: ep, season: s, label: "Continuar T\(s) E\(ep.number)", resume: true, entry: last)
    }

    @ViewBuilder
    private func episodesSection(_ info: SeriesInfo) -> some View {
        let current = season ?? info.seasons.first ?? 1
        let lastId = progress.lastEpisode(seriesId: item.streamId)?.streamId
        VStack(alignment: .leading, spacing: 14) {
            if info.seasons.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(info.seasons, id: \.self) { s in
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) { season = s }
                            } label: {
                                Chip(title: "Temporada \(s)", selected: s == current)
                            }
                            .buttonStyle(PressableStyle(scale: 0.94))
                        }
                    }
                    .padding(.horizontal)
                }
            } else {
                SectionHeader(title: "Episódios")
            }

            LazyVStack(spacing: 10) {
                ForEach(info.episodesBySeason[current] ?? []) { ep in
                    let entry = progress.entry(ep.progressKey)
                    let watching = ep.id == lastId && entry.map { !$0.isFinished } == true
                    Button {
                        lib.playEpisode(ep, series: item, info: info, resume: entry.map { !$0.isFinished } ?? false)
                    } label: {
                        EpisodeRow(episode: ep, fallbackImage: info.backdrop ?? item.backdrop ?? item.poster,
                                   entry: entry, watching: watching)
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                    .contextMenu {
                        Button {
                            lib.playEpisode(ep, series: item, info: info, resume: false)
                        } label: { Label("Assistir do início", systemImage: "arrow.counterclockwise") }
                        if entry != nil {
                            Button(role: .destructive) {
                                progress.remove(ep.progressKey)
                            } label: { Label("Marcar como não assistido", systemImage: "eye.slash") }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .id(current)
            .transition(.opacity)
        }
    }
}

struct EpisodeRow: View {
    let episode: Episode
    let fallbackImage: URL?
    let entry: WatchEntry?
    var watching: Bool = false

    private var tag: (text: String, color: Color) {
        if watching, let e = entry { return ("Assistindo · parou em \(Fmt.time(e.position))", Theme.accent) }
        if entry?.isFinished == true { return ("Assistido", .white.opacity(0.7)) }
        if let d = episode.durationSecs, d > 0 { return ("\(max(1, d / 60)) min", .white.opacity(0.55)) }
        return ("", .clear)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            FramedImage(url: episode.image ?? fallbackImage, ratio: 16.0 / 9.0, placeholder: "E\(episode.number)", corner: 11, maxWidth: 320)
                .frame(width: 132)
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .glass(Circle())
                }
                .overlay(alignment: .bottom) {
                    if let entry, entry.position > 0 {
                        ProgressLine(value: entry.isFinished ? 1 : entry.fraction, height: 3)
                            .padding(.horizontal, 6).padding(.bottom, 5)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(episode.number). \(episode.title)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    if entry?.isFinished == true {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                    }
                }
                if !tag.text.isEmpty {
                    Text(tag.text).font(.system(size: 12, weight: .semibold)).foregroundStyle(tag.color)
                }
                if let plot = episode.plot {
                    Text(plot)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .padding(8)
        .background(watching ? Theme.accent.opacity(0.08) : Theme.surface,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(watching ? Theme.accent.opacity(0.45) : Theme.hairline, lineWidth: 1))
        .contentShape(Rectangle())
    }
}
