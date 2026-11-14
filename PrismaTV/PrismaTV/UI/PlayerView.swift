import SwiftUI
import UIKit

// MARK: - Controles reutilizáveis

private struct GlassCircleButton: View {
    let icon: String
    var size: CGFloat = 44
    var iconSize: CGFloat? = nil
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize ?? size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .glass(Circle())
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel(label)
    }
}

private struct PillLabel: View {
    let text: String?
    let icon: String?
    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: 13, weight: .semibold)) }
            if let text { Text(text).font(.system(size: 13, weight: .semibold)) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, text == nil ? 0 : 12)
        .frame(minWidth: 36, minHeight: 36)
        .background(Color.white.opacity(0.13), in: Capsule())
    }
}

private struct VerticalGlassSlider: View {
    @Binding var value: Double
    let icon: String
    let label: String
    var onChange: (Double) -> Void

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    Color.clear
                    Rectangle()
                        .fill(Color.white.opacity(0.92))
                        .frame(height: geo.size.height * CGFloat(value))
                }
                .clipShape(Capsule())
                .contentShape(Capsule())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { g in
                        let v = 1 - Double(g.location.y / max(1, geo.size.height))
                        value = min(1, max(0, v))
                        onChange(value)
                    }
                )
            }
            .frame(width: 34, height: 140)
            .glass(Capsule())
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value * 100)) por cento")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: value = min(1, value + 0.1)
            case .decrement: value = max(0, value - 0.1)
            @unknown default: break
            }
            onChange(value)
        }
    }
}

// MARK: - Tela do player

struct PlayerView: View {
    let request: PlayerRequest

    @EnvironmentObject private var lib: Library
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var epg: EPGStore

    @StateObject private var c = PlaybackController()
    @State private var active: PlayerRequest
    @State private var channelIndex: Int
    @State private var showControls = true
    @State private var hideTask: Task<Void, Never>?
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var lastSaved = Date.distantPast
    @State private var showEpisodes = false
    @State private var drawerSeason: Int?
    @State private var volume: Double = 1
    @State private var brightness: Double = 0.5
    @State private var originalBrightness: CGFloat = 0.5
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?
    @State private var nextCancelled = false
    @State private var locked = false
    @State private var showUnlockHint = false
    @State private var unlockProgress: CGFloat = 0
    @State private var hintTask: Task<Void, Never>?

    init(request: PlayerRequest) {
        self.request = request
        _active = State(initialValue: request)
        _channelIndex = State(initialValue: request.channelIndex)
    }

    private var currentChannel: LiveChannel? {
        active.channels.indices.contains(channelIndex) ? active.channels[channelIndex] : nil
    }

    private var ctx: EpisodeContext? { active.episode }

    // MARK: Textos

    private var kicker: String {
        if active.isLive {
            return "TV AO VIVO · CANAL \(channelIndex + 1) DE \(max(1, active.channels.count))"
        }
        if let ctx { return "\(ctx.series.title.uppercased()) · TEMPORADA \(ctx.season)" }
        if let e = active.progress, let s = e.season { return "\(e.title.uppercased()) · TEMPORADA \(s)" }
        return "FILME"
    }

    private var headline: String {
        if active.isLive { return currentChannel?.name ?? active.title }
        if let ctx { return "Episódio \(ctx.episode.number) — \(ctx.episode.title)" }
        if let e = active.progress, let n = e.episode {
            return "Episódio \(n)" + (e.episodeTitle.map { " — \($0)" } ?? "")
        }
        return active.title
    }

    private var endsAt: String {
        let remain = max(0, c.duration - c.current) / Double(max(0.25, c.rate))
        return Fmt.hour.string(from: Date().addingTimeInterval(remain))
    }

    private var statusLine: String {
        if active.isLive { return "Use ▲ ▼ para trocar de canal" }
        guard c.duration > 0 else { return "Carregando…" }
        if let ctx {
            return "T\(ctx.season) · E\(ctx.episode.number) de \(ctx.seasonEpisodes.count) · termina às \(endsAt)"
        }
        return "Termina às \(endsAt)"
    }

    private var showSkipIntro: Bool {
        !active.isLive && (ctx != nil || active.progress?.episode != nil) && c.current > 5 && c.current < 85 && !c.isBuffering
    }

    // MARK: Corpo

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlayerSurface(controller: c)
                .ignoresSafeArea()

            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture { toggleControls() }

            if c.isBuffering && !c.failed && !c.ended {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
                    .frame(width: 84, height: 84)
                    .glass(Circle())
                    .transition(.opacity)
            }

            if showControls && !locked && !c.failed && !showEpisodes && countdown == nil {
                controls.transition(.opacity)
            }

            if showSkipIntro && countdown == nil && !locked {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            c.seek(to: 90)
                            scheduleHide()
                        } label: {
                            HStack(spacing: 8) {
                                Text("Pular abertura").font(.system(size: 14, weight: .bold))
                                Image(systemName: "forward.end.fill").font(.system(size: 12, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18).padding(.vertical, 12)
                            .glass(Capsule())
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, showControls ? 132 : 28)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            if c.failed {
                failureCard
            }

            if showEpisodes, let ctx {
                episodesDrawer(ctx)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if locked && showUnlockHint {
                unlockHint
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }

            if let countdown, let next = ctx?.next, !locked {
                nextCard(next: next, seconds: countdown)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showControls)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showUnlockHint)
        .animation(.easeInOut(duration: 0.25), value: locked)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showEpisodes)
        .animation(.easeInOut(duration: 0.25), value: countdown)
        .animation(.easeInOut(duration: 0.25), value: showSkipIntro)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            originalBrightness = UIScreen.main.brightness
            brightness = Double(originalBrightness)
            Orientation.landscape()
            c.load(active.url, startAt: active.startAt)
            scheduleHide()
        }
        .onDisappear {
            saveProgress(force: true)
            countdownTask?.cancel()
            c.stop()
            UIScreen.main.brightness = originalBrightness
            UIApplication.shared.isIdleTimerDisabled = false
            Orientation.restore()
        }
        .task { await loadContextIfNeeded() }
        .onReceive(c.$current) { _ in saveProgress(force: false) }
        .onReceive(c.$ended) { ended in
            guard ended else { return }
            if active.isLive {
                c.load(active.url, startAt: 0)   // transmissão caiu: reconecta sozinho
                return
            }
            saveProgress(force: true)
            if ctx?.next != nil && !nextCancelled {
                startCountdown()
            } else if ctx == nil {
                close()
            }
        }
    }

    // MARK: Camada de controles

    private var controls: some View {
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom).frame(height: 150)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom).frame(height: 190)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            HStack {
                VerticalGlassSlider(value: $volume, icon: "speaker.wave.2.fill", label: "Volume") { v in
                    c.setVolume(v); scheduleHide()
                }
                Spacer()
                VerticalGlassSlider(value: $brightness, icon: "sun.max.fill", label: "Brilho") { v in
                    UIScreen.main.brightness = CGFloat(v); scheduleHide()
                }
            }
            .padding(.horizontal, 6)

            VStack(spacing: 0) {
                topBar
                Spacer()
                centerButtons
                Spacer()
                bottomPanel
            }
            .padding(.horizontal, 52)
            .padding(.vertical, 10)
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            GlassCircleButton(icon: "chevron.down", label: "Fechar player") { close() }
            VStack(alignment: .leading, spacing: 3) {
                Text(kicker)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                Text(headline)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer()
            if active.isLive {
                HStack(spacing: 6) {
                    Circle().fill(.white).frame(width: 7, height: 7)
                    Text("AO VIVO").font(.system(size: 12, weight: .heavy)).tracking(0.6)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.red.opacity(0.9), in: Capsule())
            }
            GlassCircleButton(icon: "lock.fill", label: "Travar a tela contra toques") { lock() }
            if c.pipPossible {
                GlassCircleButton(icon: "pip.enter", label: "Abrir telinha flutuante") {
                    c.startPiP()
                }
            }
            if let key = active.favKey {
                let fav = favorites.contains(key)
                GlassCircleButton(icon: fav ? "heart.fill" : "heart",
                                  label: fav ? "Remover da minha lista" : "Adicionar à minha lista") {
                    favorites.toggle(key); scheduleHide()
                }
            }
        }
    }

    private var centerButtons: some View {
        HStack(spacing: 46) {
            if active.isLive {
                GlassCircleButton(icon: "chevron.up", size: 60, label: "Canal anterior") { zap(-1) }
                    .disabled(active.channels.count < 2)
            } else {
                GlassCircleButton(icon: "gobackward.10", size: 60, iconSize: 24, label: "Voltar 10 segundos") {
                    c.jump(-10); scheduleHide()
                }
            }
            GlassCircleButton(icon: c.isPlaying ? "pause.fill" : "play.fill", size: 84, iconSize: 32,
                              label: c.isPlaying ? "Pausar" : "Reproduzir") {
                c.togglePlay(); scheduleHide()
            }
            if active.isLive {
                GlassCircleButton(icon: "chevron.down", size: 60, label: "Próximo canal") { zap(1) }
                    .disabled(active.channels.count < 2)
            } else {
                GlassCircleButton(icon: "goforward.10", size: 60, iconSize: 24, label: "Avançar 10 segundos") {
                    c.jump(10); scheduleHide()
                }
            }
        }
    }

    private var bottomPanel: some View {
        VStack(spacing: 6) {
            if active.isLive {
                liveInfo
            } else {
                HStack(spacing: 12) {
                    Text(Fmt.time(scrubbing ? scrubValue : c.current))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .frame(minWidth: 46, alignment: .leading)
                    Slider(value: Binding(get: { scrubbing ? scrubValue : c.current },
                                          set: { scrubValue = $0 }),
                           in: 0...max(c.duration, 1),
                           onEditingChanged: { editing in
                               if editing {
                                   scrubValue = c.current
                                   scrubbing = true
                                   hideTask?.cancel()
                               } else {
                                   c.seek(to: scrubValue)
                                   scrubbing = false
                                   scheduleHide()
                               }
                           })
                        .tint(Theme.accent)
                    Text("-" + Fmt.time(max(0, c.duration - (scrubbing ? scrubValue : c.current))))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(minWidth: 52, alignment: .trailing)
                }
                .foregroundStyle(.white)
            }

            HStack(spacing: 6) {
                Text(statusLine)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                Spacer(minLength: 8)

                if let ctx {
                    Button {
                        drawerSeason = ctx.season
                        showEpisodes = true
                        hideTask?.cancel()
                    } label: { PillLabel(text: "Episódios", icon: "rectangle.stack") }
                        .buttonStyle(.pressable)
                    if ctx.next != nil {
                        Button { playNext() } label: { PillLabel(text: "Próximo", icon: "forward.end.fill") }
                            .buttonStyle(.pressable)
                    }
                }

                if !active.isLive {
                    Menu {
                        ForEach([Float(0.5), 0.75, 1, 1.25, 1.5, 2], id: \.self) { r in
                            Button { c.setRate(r); scheduleHide() } label: {
                                if r == c.rate { Label(rateLabel(r), systemImage: "checkmark") } else { Text(rateLabel(r)) }
                            }
                        }
                    } label: { PillLabel(text: c.rate == 1 ? "1x" : rateLabel(c.rate), icon: nil) }
                        .accessibilityLabel("Velocidade")
                }

                if !c.audioTracks.isEmpty {
                    Menu {
                        ForEach(c.audioTracks) { t in
                            Button { c.selectAudio(t.id); scheduleHide() } label: {
                                if t.id == c.currentAudio { Label(t.name, systemImage: "checkmark") } else { Text(t.name) }
                            }
                        }
                    } label: { PillLabel(text: nil, icon: "waveform") }
                        .accessibilityLabel("Áudio")
                }

                if !c.subtitleTracks.isEmpty {
                    Menu {
                        ForEach(c.subtitleTracks) { t in
                            Button { c.selectSubtitle(t.id); scheduleHide() } label: {
                                if t.id == c.currentSubtitle { Label(t.name, systemImage: "checkmark") } else { Text(t.name) }
                            }
                        }
                    } label: { PillLabel(text: nil, icon: "captions.bubble") }
                        .accessibilityLabel("Legendas")
                }

                Menu {
                    ForEach(c.aspectOptions) { opt in
                        Button { c.setAspect(opt); scheduleHide() } label: {
                            if opt.name == c.aspect { Label(opt.name, systemImage: "checkmark") } else { Text(opt.name) }
                        }
                    }
                } label: { PillLabel(text: nil, icon: "arrow.up.left.and.arrow.down.right") }
                    .accessibilityLabel("Proporção da tela")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glass(RoundedRectangle(cornerRadius: 22, style: .continuous), dark: true)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }

    private var liveInfo: some View {
        HStack(spacing: 12) {
            Text("AGORA").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accent)
            if let ch = currentChannel, let now = epg.now(ch.id) {
                Text(now.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                ProgressLine(value: now.progress(), height: 4).frame(maxWidth: 180)
                if let next = epg.next(ch.id) {
                    Text("A seguir \(Fmt.hour.string(from: next.start)) \(next.title)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            } else {
                Text(currentChannel?.name ?? active.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .task(id: channelIndex) {
            if let ch = currentChannel { await epg.load(ch) }
        }
    }

    private func rateLabel(_ r: Float) -> String {
        r == 1 ? "Normal" : String(format: "%gx", r).replacingOccurrences(of: ".", with: ",")
    }

    // MARK: Gaveta de episódios

    private func episodesDrawer(_ ctx: EpisodeContext) -> some View {
        let season = drawerSeason ?? ctx.season
        let list = ctx.info.episodesBySeason[season] ?? []
        return ZStack(alignment: .trailing) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { showEpisodes = false; scheduleHide() }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ctx.series.title.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                        Text("Temporada \(season)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    GlassCircleButton(icon: "xmark", size: 36, label: "Fechar lista de episódios") {
                        showEpisodes = false; scheduleHide()
                    }
                }

                if ctx.info.seasons.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(ctx.info.seasons, id: \.self) { s in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) { drawerSeason = s }
                                } label: { Chip(title: "T\(s)", selected: s == season) }
                                    .buttonStyle(PressableStyle(scale: 0.94))
                            }
                        }
                    }
                }

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 8) {
                            ForEach(list) { ep in
                                drawerRow(ep, ctx: ctx).id(ep.id)
                            }
                        }
                    }
                    .onAppear { proxy.scrollTo(ctx.episode.id, anchor: .center) }
                }
            }
            .padding(14)
            .frame(width: 350)
            .frame(maxHeight: .infinity)
            .glass(RoundedRectangle(cornerRadius: 26, style: .continuous), dark: true)
            .padding(10)
        }
    }

    private func drawerRow(_ ep: Episode, ctx: EpisodeContext) -> some View {
        let isCurrent = ep.id == ctx.episode.id
        let entry = progress.entry(ep.progressKey)
        let tag: String
        if isCurrent {
            tag = "Assistindo agora · \(Fmt.time(c.current)) de \(Fmt.time(c.duration))"
        } else if entry?.isFinished == true {
            tag = "Assistido"
        } else if let e = entry, e.position > 20 {
            tag = "Parou em \(Fmt.time(e.position))"
        } else if let d = ep.durationSecs, d > 0 {
            tag = "\(max(1, d / 60)) min"
        } else {
            tag = ""
        }
        let fraction = isCurrent ? (c.duration > 0 ? c.current / c.duration : 0) : (entry?.isFinished == true ? 1 : entry?.fraction ?? 0)

        return Button {
            switchEpisode(ep, ctx: ctx)
        } label: {
            HStack(spacing: 10) {
                FramedImage(url: ep.image ?? ctx.info.backdrop ?? ctx.series.backdrop ?? ctx.series.poster,
                            ratio: 16.0 / 9.0, placeholder: "E\(ep.number)", corner: 9, maxWidth: 220)
                    .frame(width: 96)
                    .overlay(alignment: .bottom) {
                        if fraction > 0 {
                            ProgressLine(value: fraction, height: 3).padding(.horizontal, 5).padding(.bottom, 4)
                        }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(ep.number). \(ep.title)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !tag.isEmpty {
                        Text(tag)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isCurrent ? Theme.accent : .white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(7)
            .background(isCurrent ? Theme.accent.opacity(0.12) : Color.white.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isCurrent ? Theme.accent.opacity(0.55) : .clear, lineWidth: 1))
        }
        .buttonStyle(PressableStyle(scale: 0.97))
    }

    // MARK: Cartões

    private func nextCard(next: Episode, seconds: Int) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 12) {
                    ZStack {
                        FramedImage(url: next.image ?? ctx?.info.backdrop, ratio: 16.0 / 9.0, placeholder: "", corner: 10, maxWidth: 240)
                            .frame(width: 112)
                        Text("\(seconds)")
                            .font(.system(size: 24, weight: .heavy).monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .glass(Circle())
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PRÓXIMO EPISÓDIO")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(Theme.accent)
                        Text("E\(next.number) · \(next.title)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            Button { playNext() } label: {
                                Text("Assistir agora")
                                    .font(.system(size: 12, weight: .heavy))
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(Theme.primary, in: Capsule())
                                    .foregroundStyle(Theme.onPrimary)
                            }
                            .buttonStyle(.pressable)
                            Button {
                                countdownTask?.cancel()
                                countdown = nil
                                nextCancelled = true
                                showControls = true
                            } label: { PillLabel(text: "Cancelar", icon: nil) }
                                .buttonStyle(.pressable)
                        }
                    }
                }
                .padding(14)
                .frame(width: 360)
                .glass(RoundedRectangle(cornerRadius: 22, style: .continuous), dark: true)
            }
        }
        .padding(24)
    }

    private var failureCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Theme.accent)
            Text("Não foi possível reproduzir").font(.headline).foregroundStyle(.white)
            Text(active.isLive
                 ? "O canal pode estar fora do ar. Tente outro canal ou troque o formato em Configurações."
                 : "O conteúdo pode estar indisponível no servidor no momento.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button { c.load(active.url, startAt: c.current) } label: {
                    Text("Tentar de novo")
                        .font(.system(size: 14, weight: .bold))
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .background(Theme.primary, in: Capsule())
                        .foregroundStyle(Theme.onPrimary)
                }
                .buttonStyle(.pressable)
                Button { close() } label: { PillLabel(text: "Fechar", icon: nil) }
                    .buttonStyle(.pressable)
            }
        }
        .padding(24)
        .frame(maxWidth: 400)
        .glass(RoundedRectangle(cornerRadius: 24, style: .continuous), dark: true)
        .padding()
    }

    // MARK: Ações

    private func toggleControls() {
        if locked { flashUnlockHint(); return }
        showControls.toggle()
        if showControls { scheduleHide() }
    }

    // MARK: Trava de tela

    private var unlockHint: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.25), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: unlockProgress)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: unlockProgress >= 1 ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tela travada").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    Text("Segure aqui para desbloquear").font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .glass(Capsule(), dark: true)
            .scaleEffect(unlockProgress > 0 ? 1.05 : 1)
            .onLongPressGesture(minimumDuration: 1.0, maximumDistance: 40, pressing: { pressing in
                hintTask?.cancel()
                withAnimation(pressing ? .linear(duration: 1.0) : .easeOut(duration: 0.2)) {
                    unlockProgress = pressing ? 1 : 0
                }
                if !pressing { flashUnlockHint() }
            }, perform: { unlock() })
            .accessibilityLabel("Tela travada. Toque duas vezes e segure para desbloquear.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { unlock() }
            .padding(.bottom, 40)
        }
    }

    private func lock() {
        hideTask?.cancel()
        locked = true
        showControls = false
        showEpisodes = false
        flashUnlockHint()
    }

    private func unlock() {
        hintTask?.cancel()
        Feedback.tap()
        locked = false
        unlockProgress = 0
        showUnlockHint = false
        scheduleHide()
    }

    private func flashUnlockHint() {
        showUnlockHint = true
        hintTask?.cancel()
        hintTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, unlockProgress == 0 else { return }
            showUnlockHint = false
        }
    }

    private func scheduleHide() {
        if locked { return }
        hideTask?.cancel()
        showControls = true
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard !Task.isCancelled, c.isPlaying, !scrubbing, !showEpisodes else { return }
            showControls = false
        }
    }

    private func zap(_ delta: Int) {
        let n = active.channels.count
        guard n > 1 else { return }
        channelIndex = (channelIndex + delta + n) % n
        if let ch = currentChannel, let url = lib.liveURL(ch) {
            active.url = url
            active.title = ch.name
            c.load(url, startAt: 0)
        }
        scheduleHide()
    }

    private func startCountdown() {
        countdownTask?.cancel()
        countdown = 6
        countdownTask = Task { @MainActor in
            while let left = countdown, left > 1 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                countdown = left - 1
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return }
            playNext()
        }
    }

    private func playNext() {
        guard let ctx, let next = ctx.next else { return }
        switchEpisode(next, ctx: ctx)
    }

    private func switchEpisode(_ ep: Episode, ctx: EpisodeContext) {
        guard ep.id != ctx.episode.id || c.ended else { showEpisodes = false; return }
        let unfinished = progress.entry(ep.progressKey).map { !$0.isFinished } ?? false
        guard let req = lib.episodeRequest(ep, series: ctx.series, info: ctx.info, resume: unfinished) else { return }
        saveProgress(force: true)
        countdownTask?.cancel()
        countdown = nil
        nextCancelled = false
        showEpisodes = false
        active = req
        lastSaved = .distantPast
        c.load(req.url, startAt: req.startAt)
        scheduleHide()
    }

    private func loadContextIfNeeded() async {
        guard active.episode == nil, let entry = active.progress, let sid = entry.seriesId,
              let api = lib.api, let series = lib.catalog.itemsByKey["series-\(sid)"] else { return }
        guard let info = try? await api.seriesInfo(id: sid),
              let ep = info.allEpisodes.first(where: { $0.id == entry.streamId }) else { return }
        active.episode = EpisodeContext(series: series, info: info, episode: ep)
    }

    private func saveProgress(force: Bool) {
        guard var entry = active.progress, c.duration > 0 else { return }
        if !force && Date().timeIntervalSince(lastSaved) < 10 { return }
        let position = c.ended ? c.duration : c.current
        guard position > 1 else { return }
        lastSaved = Date()
        entry.position = position
        entry.duration = c.duration
        entry.updatedAt = Date()
        progress.update(entry)
    }

    private func close() {
        saveProgress(force: true)
        lib.player = nil
    }
}
