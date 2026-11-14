import SwiftUI
import UIKit
import AVFoundation
import AVKit
import Combine
import MobileVLCKit

struct MediaTrack: Identifiable, Hashable {
    let id: Int32
    let name: String
}

enum PlaybackEngine { case native, vlc }

/// Player híbrido:
/// - Player da Apple (AVPlayer) para HLS/MP4: permite a telinha flutuante (Picture-in-Picture).
/// - VLC para o resto (MKV, AVI, TS…) e como plano B quando o player da Apple não consegue abrir.
final class PlaybackController: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    let vlc = VLCMediaPlayer()
    let av = AVPlayer()

    @Published var engine: PlaybackEngine = .vlc
    @Published var isPlaying = false
    @Published var isBuffering = true
    @Published var current: Double = 0
    @Published var duration: Double = 0
    @Published var ended = false
    @Published var failed = false
    @Published var audioTracks: [MediaTrack] = []
    @Published var subtitleTracks: [MediaTrack] = []
    @Published var currentAudio: Int32 = -1
    @Published var currentSubtitle: Int32 = -1
    @Published var aspect: String = "Original"
    @Published var rate: Float = 1
    @Published var pipPossible = false
    @Published var pipActive = false

    private weak var vlcView: UIView?
    private weak var avView: UIView?
    private weak var avLayer: AVPlayerLayer?
    private var pip: AVPictureInPictureController?

    private var url: URL?
    private var startAt: Double = 0
    private var timer: Timer?
    private var avObserver: Any?
    private var bag = Set<AnyCancellable>()
    private var audioGroup: AVMediaSelectionGroup?
    private var legibleGroup: AVMediaSelectionGroup?
    private var lastTime: Int32 = -1
    private var stalledTicks = 0
    private var wantsPlay = true
    private var tickCount = 0
    private var volume: Double = 1

    static func prefersNative(_ url: URL) -> Bool {
        ["m3u8", "mp4", "m4v", "mov"].contains(url.pathExtension.lowercased())
    }

    // MARK: Superfície de vídeo

    func attach(_ container: PlayerContainerView) {
        vlcView = container.vlcView
        avView = container.avView
        vlc.drawable = container.vlcView
        container.avView.playerLayer.player = av
        container.avView.playerLayer.videoGravity = .resizeAspect
        avLayer = container.avView.playerLayer
        if AVPictureInPictureController.isPictureInPictureSupported(),
           let controller = AVPictureInPictureController(playerLayer: container.avView.playerLayer) {
            controller.delegate = self
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            pip = controller
        }
        updateViews()
    }

    private func updateViews() {
        vlcView?.isHidden = engine != .vlc
        avView?.isHidden = engine != .native
        pipPossible = engine == .native && pip != nil
    }

    // MARK: Carregar

    func load(_ url: URL, startAt: Double) {
        self.url = url
        self.startAt = startAt
        ended = false
        failed = false
        isBuffering = true
        current = startAt
        duration = 0
        audioTracks = []
        subtitleTracks = []
        aspect = "Original"
        if Self.prefersNative(url) { loadNative(url, startAt: startAt) } else { loadVLC(url, startAt: startAt) }
    }

    private func loadVLC(_ url: URL, startAt: Double) {
        stopNative()
        engine = .vlc
        updateViews()
        lastTime = -1
        stalledTicks = 0
        let media = VLCMedia(url: url)
        media.addOption(":network-caching=2000")
        media.addOption(":http-reconnect")
        if startAt > 5 { media.addOption(":start-time=\(Int(startAt))") }
        vlc.media = media
        wantsPlay = true
        vlc.play()
        vlc.audio?.volume = Int32(volume * 100)
        startTimer()
    }

    private func loadNative(_ url: URL, startAt: Double) {
        stopVLC()
        engine = .native
        updateViews()
        bag.removeAll()
        audioGroup = nil
        legibleGroup = nil

        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 4

        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                if status == .failed { self.fallbackToVLC() }
                if status == .readyToPlay { self.loadNativeTracks(item) }
            }
            .store(in: &bag)

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.ended = true
                self?.isPlaying = false
            }
            .store(in: &bag)

        NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.fallbackToVLC() }
            .store(in: &bag)

        av.replaceCurrentItem(with: item)
        av.volume = Float(volume)
        if startAt > 5 { av.seek(to: CMTime(seconds: startAt, preferredTimescale: 600)) }
        av.defaultRate = rate
        wantsPlay = true
        av.playImmediately(atRate: rate)

        if avObserver == nil {
            avObserver = av.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] _ in
                self?.nativeTick()
            }
        }
    }

    /// Se o player da Apple não abrir o vídeo, tenta de novo com o VLC.
    private func fallbackToVLC() {
        guard engine == .native, let url else { return }
        let position = max(current, startAt)
        loadVLC(url, startAt: position)
    }

    // MARK: Controles

    func stop() {
        timer?.invalidate()
        timer = nil
        wantsPlay = false
        stopVLC()
        stopNative()
        if let avObserver { av.removeTimeObserver(avObserver) }
        avObserver = nil
    }

    private func stopVLC() {
        timer?.invalidate()
        timer = nil
        if vlc.media != nil { vlc.stop() }
    }

    private func stopNative() {
        bag.removeAll()
        av.pause()
        av.replaceCurrentItem(with: nil)
    }

    func togglePlay() {
        switch engine {
        case .vlc:
            if vlc.isPlaying { wantsPlay = false; vlc.pause() } else { wantsPlay = true; vlc.play() }
        case .native:
            if av.timeControlStatus == .paused { wantsPlay = true; av.playImmediately(atRate: rate) } else { wantsPlay = false; av.pause() }
        }
        isPlaying.toggle()
    }

    func seek(to seconds: Double) {
        guard duration > 0 else { return }
        let target = min(max(0, seconds), duration - 0.5)
        switch engine {
        case .vlc: vlc.position = Float(min(max(0, target / duration), 0.999))
        case .native: av.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        }
        current = target
        ended = false
    }

    func jump(_ seconds: Int32) {
        switch engine {
        case .vlc:
            if seconds > 0 { vlc.jumpForward(seconds) } else { vlc.jumpBackward(-seconds) }
            current = max(0, min(duration, current + Double(seconds)))
        case .native:
            seek(to: current + Double(seconds))
        }
    }

    func setRate(_ r: Float) {
        rate = r
        switch engine {
        case .vlc: vlc.rate = r
        case .native:
            av.defaultRate = r
            if av.timeControlStatus != .paused { av.rate = r }
        }
    }

    /// 0...1
    func setVolume(_ v: Double) {
        volume = max(0, min(1, v))
        vlc.audio?.volume = Int32(volume * 100)
        av.volume = Float(volume)
    }

    func selectAudio(_ id: Int32) {
        switch engine {
        case .vlc: vlc.currentAudioTrackIndex = id
        case .native:
            if let group = audioGroup, group.options.indices.contains(Int(id)) {
                av.currentItem?.select(group.options[Int(id)], in: group)
            }
        }
        currentAudio = id
    }

    func selectSubtitle(_ id: Int32) {
        switch engine {
        case .vlc: vlc.currentVideoSubTitleIndex = id
        case .native:
            if let group = legibleGroup {
                if id < 0 {
                    av.currentItem?.select(nil, in: group)
                } else if group.options.indices.contains(Int(id)) {
                    av.currentItem?.select(group.options[Int(id)], in: group)
                }
            }
        }
        currentSubtitle = id
    }

    struct AspectOption: Identifiable {
        let name: String
        let ratio: String?
        var id: String { name }
    }

    var aspectOptions: [AspectOption] {
        if engine == .native {
            return [AspectOption(name: "Original", ratio: nil), AspectOption(name: "Preencher a tela", ratio: "fill")]
        }
        let b = UIScreen.main.bounds
        let w = Int(max(b.width, b.height)), h = Int(min(b.width, b.height))
        return [AspectOption(name: "Original", ratio: nil),
                AspectOption(name: "Preencher a tela", ratio: "\(w):\(h)"),
                AspectOption(name: "16:9", ratio: "16:9"),
                AspectOption(name: "4:3", ratio: "4:3")]
    }

    func setAspect(_ option: AspectOption) {
        aspect = option.name
        switch engine {
        case .native:
            avLayer?.videoGravity = option.ratio == nil ? .resizeAspect : .resizeAspectFill
        case .vlc:
            if let ratio = option.ratio { vlc.videoAspectRatio = strdup(ratio) } else { vlc.videoAspectRatio = nil }
        }
    }

    // MARK: Telinha (Picture-in-Picture)

    func startPiP() {
        guard let pip, pip.isPictureInPicturePossible else { return }
        pip.startPictureInPicture()
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        pipActive = true
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        pipActive = false
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }

    // MARK: Atualização periódica

    private func nativeTick() {
        guard engine == .native else { return }
        let t = av.currentTime().seconds
        if t.isFinite && t > 0 { current = t }
        if let d = av.currentItem?.duration.seconds, d.isFinite, d > 0 { duration = d }
        isPlaying = av.timeControlStatus == .playing
        isBuffering = wantsPlay && (av.timeControlStatus == .waitingToPlayAtSpecifiedRate || av.currentItem?.status == .unknown)
        pipPossible = pip != nil
    }

    private func loadNativeTracks(_ item: AVPlayerItem) {
        let asset = item.asset
        Task { [weak self] in
            let audio = try? await asset.loadMediaSelectionGroup(for: .audible)
            let legible = try? await asset.loadMediaSelectionGroup(for: .legible)
            await MainActor.run {
                guard let self else { return }
                self.audioGroup = audio ?? nil
                self.legibleGroup = legible ?? nil
                if let g = self.audioGroup {
                    self.audioTracks = g.options.enumerated().map { MediaTrack(id: Int32($0.offset), name: $0.element.displayName) }
                    if let sel = item.currentMediaSelection.selectedMediaOption(in: g), let i = g.options.firstIndex(of: sel) {
                        self.currentAudio = Int32(i)
                    }
                }
                if let g = self.legibleGroup, !g.options.isEmpty {
                    self.subtitleTracks = [MediaTrack(id: -1, name: "Desligada")] +
                        g.options.enumerated().map { MediaTrack(id: Int32($0.offset), name: $0.element.displayName) }
                    if let sel = item.currentMediaSelection.selectedMediaOption(in: g), let i = g.options.firstIndex(of: sel) {
                        self.currentSubtitle = Int32(i)
                    } else {
                        self.currentSubtitle = -1
                    }
                }
            }
        }
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.vlcTick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func vlcTick() {
        guard engine == .vlc else { return }
        tickCount += 1
        let ms = vlc.time.intValue
        let len = vlc.media?.length.intValue ?? 0
        if ms > 0 { current = Double(ms) / 1000 }
        if len > 0 { duration = Double(len) / 1000 }
        isPlaying = vlc.isPlaying
        if vlc.isPlaying && abs(vlc.rate - rate) > 0.01 { vlc.rate = rate }

        switch vlc.state {
        case .error:
            failed = true
            isBuffering = false
        case .ended:
            ended = true
            isBuffering = false
        case .opening:
            isBuffering = true
        default:
            if ms == lastTime && wantsPlay && vlc.state != .paused { stalledTicks += 1 } else { stalledTicks = 0 }
            isBuffering = wantsPlay && (stalledTicks >= 2 || ms <= 0)
        }
        lastTime = ms

        if tickCount % 4 == 0 { refreshVLCTracks() }
    }

    private func refreshVLCTracks() {
        let aNames = (vlc.audioTrackNames as? [String]) ?? []
        let aIdx = (vlc.audioTrackIndexes as? [NSNumber]) ?? []
        let audio = zip(aIdx, aNames).map { MediaTrack(id: $0.int32Value, name: $1) }
        if audio != audioTracks { audioTracks = audio }

        let sNames = (vlc.videoSubTitlesNames as? [String]) ?? []
        let sIdx = (vlc.videoSubTitlesIndexes as? [NSNumber]) ?? []
        let subs = zip(sIdx, sNames).map { MediaTrack(id: $0.int32Value, name: $1) }
        if subs != subtitleTracks { subtitleTracks = subs }

        currentAudio = vlc.currentAudioTrackIndex
        currentSubtitle = vlc.currentVideoSubTitleIndex
    }

    deinit {
        timer?.invalidate()
        vlc.stop()
        if let avObserver { av.removeTimeObserver(avObserver) }
    }
}

// MARK: - Superfície (VLC + camada do player da Apple)

final class AVLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

final class PlayerContainerView: UIView {
    let vlcView = UIView()
    let avView = AVLayerView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        for v in [vlcView, avView] {
            v.frame = bounds
            v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            v.backgroundColor = .black
            addSubview(v)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) não usado") }
}

struct PlayerSurface: UIViewRepresentable {
    let controller: PlaybackController

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView(frame: .zero)
        controller.attach(view)
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {}
}
