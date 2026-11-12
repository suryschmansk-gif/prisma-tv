import SwiftUI

struct LiveView: View {
    @EnvironmentObject private var lib: Library
    @EnvironmentObject private var favorites: FavoritesStore

    @State private var categoryId: String?
    @State private var query = ""
    @State private var scheduleFor: LiveChannel?

    private var filtered: [LiveChannel] {
        let q = TextUtil.searchKey(query.trimmingCharacters(in: .whitespaces))
        return lib.catalog.channels.filter { ch in
            if let categoryId {
                if categoryId == CatalogEngine.favoritesId {
                    if !favorites.contains(ch.favKey) { return false }
                } else if ch.categoryId != categoryId { return false }
            }
            return q.isEmpty || ch.searchKey.contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            let list = filtered
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("TV ao vivo")
                            .font(.system(size: 30, weight: .heavy))
                            .tracking(-0.6)
                        Spacer()
                        HStack(spacing: 6) {
                            Circle().fill(Color.red).frame(width: 7, height: 7)
                            Text("\(list.count) canais")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(Color.red.opacity(0.16), in: Capsule())
                        .foregroundStyle(Color(red: 0.99, green: 0.65, blue: 0.65))
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    SearchField(prompt: "Buscar canal", text: $query).padding(.horizontal)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 8) {
                            chip(nil, "Todos")
                            chip(CatalogEngine.favoritesId, "Favoritos")
                            ForEach(lib.catalog.liveCategories.filter { (lib.catalog.liveCounts[$0.id] ?? 0) > 0 }) { cat in
                                chip(cat.id, cat.name)
                            }
                        }
                        .padding(.horizontal)
                    }

                    if list.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "tv.slash").font(.system(size: 38))
                            Text(categoryId == CatalogEngine.favoritesId
                                 ? "Segure o dedo num canal para adicionar aos favoritos."
                                 : "Nenhum canal encontrado.")
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 50)
                    }

                    ForEach(Array(list.enumerated()), id: \.element.id) { index, channel in
                        ChannelCard(channel: channel, number: index + 1,
                                    isFavorite: favorites.contains(channel.favKey),
                                    onPlay: { lib.playChannel(channel, in: list) },
                                    onInfo: { scheduleFor = channel })
                            .contextMenu {
                                Button { lib.playChannel(channel, in: list) } label: { Label("Assistir", systemImage: "play.fill") }
                                Button { scheduleFor = channel } label: { Label("Ver programação", systemImage: "list.bullet.rectangle") }
                                Button { favorites.toggle(channel.favKey) } label: {
                                    Label(favorites.contains(channel.favKey) ? "Remover dos favoritos" : "Adicionar aos favoritos",
                                          systemImage: favorites.contains(channel.favKey) ? "star.slash" : "star")
                                }
                            }
                            .padding(.horizontal)
                            .reveal()
                    }
                }
                .padding(.bottom, 20)
            }
            .background(
                ZStack(alignment: .top) {
                    Theme.bg
                    Circle().fill(Theme.accent.opacity(0.10)).frame(width: 500).blur(radius: 120).offset(y: -300)
                }
                .ignoresSafeArea()
            )
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await lib.refresh() }
            .sheet(item: $scheduleFor) { channel in
                ScheduleSheet(channel: channel, list: list)
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
}

struct ChannelCard: View {
    let channel: LiveChannel
    let number: Int
    let isFavorite: Bool
    var onPlay: () -> Void
    var onInfo: () -> Void

    @EnvironmentObject private var epg: EPGStore

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                HStack(spacing: 12) {
                    Color.clear
                        .frame(width: 58, height: 58)
                        .overlay(
                            CachedImage(url: channel.icon, placeholder: String(channel.name.prefix(3)),
                                        maxWidth: 140, contentMode: .fit)
                                .padding(8)
                        )
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Text(String(format: "%02d", number) + " · " + channel.name)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                            if isFavorite {
                                Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Theme.accent)
                            }
                        }
                        if let now = epg.now(channel.id) {
                            Text(now.title)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            HStack(spacing: 8) {
                                ProgressLine(value: now.progress(), height: 3)
                                if let next = epg.next(channel.id) {
                                    Text("depois \(Fmt.hour.string(from: next.start))")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.55))
                                        .fixedSize()
                                }
                            }
                        } else {
                            Text(channel.name)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.98))

            if channel.epgId != nil {
                Button(action: onInfo) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 40, height: 40)
                        .background(Theme.surface2, in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Ver programação")
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
        .task(id: channel.id) { await epg.load(channel) }
    }
}

struct ScheduleSheet: View {
    let channel: LiveChannel
    let list: [LiveChannel]

    @EnvironmentObject private var lib: Library
    @EnvironmentObject private var epg: EPGStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    PrimaryButton(title: "Assistir agora") {
                        dismiss()
                        lib.playChannel(channel, in: list)
                    }
                    let items = epg.upcoming(channel.id)
                    if items.isEmpty {
                        Text("Este canal não tem programação disponível.")
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 10)
                    }
                    ForEach(items) { entry in
                        let live = entry.start <= Date()
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text("\(Fmt.hour.string(from: entry.start)) – \(Fmt.hour.string(from: entry.end))")
                                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                                    .foregroundStyle(Theme.accent)
                                if live {
                                    Text("AGORA")
                                        .font(.system(size: 10, weight: .heavy))
                                        .padding(.horizontal, 7).padding(.vertical, 2)
                                        .background(Color.red, in: Capsule())
                                }
                            }
                            Text(entry.title).font(.system(size: 15, weight: .semibold))
                            if let s = entry.summary {
                                Text(s).font(.caption).foregroundStyle(Theme.muted).lineLimit(3)
                            }
                            if live { ProgressLine(value: entry.progress(), height: 3) }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(live ? Theme.accent.opacity(0.08) : Color.white.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding()
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(channel.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
            }
            .task { await epg.load(channel, limit: 20) }
        }
        .presentationDetents([.medium, .large])
    }
}
