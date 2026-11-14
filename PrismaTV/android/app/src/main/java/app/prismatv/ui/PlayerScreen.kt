package app.prismatv.ui

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import android.net.Uri
import android.view.KeyEvent as AndroidKeyEvent
import android.view.WindowManager
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AspectRatio
import androidx.compose.material.icons.filled.BrightnessHigh
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ClosedCaption
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Forward10
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PictureInPictureAlt
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay10
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.nativeKeyCode
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import app.prismatv.AppViewModel
import app.prismatv.Episode
import app.prismatv.EpisodeContext
import app.prismatv.Kind
import app.prismatv.PlayerRequest
import app.prismatv.TextUtil
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.videolan.libvlc.LibVLC
import org.videolan.libvlc.Media
import org.videolan.libvlc.MediaPlayer
import org.videolan.libvlc.util.VLCVideoLayout

// ---------- Controlador do VLC ----------

class VlcController(context: Context) {
    private val libVlc = LibVLC(context, arrayListOf("--network-caching=2000", "--http-reconnect"))
    val player = MediaPlayer(libVlc)

    var playing by mutableStateOf(false)
    var buffering by mutableStateOf(true)
    var time by mutableLongStateOf(0L)
    var length by mutableLongStateOf(0L)
    var ended by mutableStateOf(false)
    var failed by mutableStateOf(false)
    var rate by mutableFloatStateOf(1f)
    var aspect by mutableStateOf("Original")
    var audioTracks by mutableStateOf<List<Pair<Int, String>>>(emptyList())
    var subTracks by mutableStateOf<List<Pair<Int, String>>>(emptyList())
    var currentAudio by mutableIntStateOf(-1)
    var currentSub by mutableIntStateOf(-1)

    init {
        player.setEventListener { e ->
            when (e.type) {
                MediaPlayer.Event.Playing -> { playing = true; buffering = false; refreshTracks() }
                MediaPlayer.Event.Paused, MediaPlayer.Event.Stopped -> playing = false
                MediaPlayer.Event.Buffering -> buffering = e.buffering < 100f
                MediaPlayer.Event.TimeChanged -> { time = e.timeChanged; if (buffering) buffering = false }
                MediaPlayer.Event.LengthChanged -> length = e.lengthChanged
                MediaPlayer.Event.EndReached -> { ended = true; playing = false }
                MediaPlayer.Event.EncounteredError -> { failed = true; buffering = false }
                MediaPlayer.Event.ESAdded -> refreshTracks()
                else -> {}
            }
        }
    }

    fun attach(layout: VLCVideoLayout) = player.attachViews(layout, null, true, false)

    fun load(url: String, startMs: Long) {
        ended = false; failed = false; buffering = true; time = startMs; length = 0
        audioTracks = emptyList(); subTracks = emptyList()
        val media = Media(libVlc, Uri.parse(url))
        media.setHWDecoderEnabled(true, false)
        media.addOption(":network-caching=2000")
        if (startMs > 5000) media.addOption(":start-time=${startMs / 1000}")
        player.setMedia(media)
        media.release()
        player.play()
        player.setRate(rate)
    }

    fun toggle() { if (player.isPlaying) player.pause() else player.play() }
    fun seekTo(ms: Long) {
        val target = if (length > 0) ms.coerceIn(0, length) else ms.coerceAtLeast(0)
        player.setTime(target); time = target; ended = false
    }
    fun jump(deltaMs: Long) = seekTo(time + deltaMs)
    fun setSpeed(r: Float) { rate = r; player.setRate(r) }
    fun setVolume(v: Float) { player.setVolume((v * 100).toInt().coerceIn(0, 100)) }
    fun selectAudio(id: Int) { player.setAudioTrack(id); currentAudio = id }
    fun selectSub(id: Int) { player.setSpuTrack(id); currentSub = id }
    fun setScale(name: String, scale: MediaPlayer.ScaleType) { aspect = name; player.setVideoScale(scale) }

    private fun refreshTracks() {
        audioTracks = player.audioTracks?.map { it.id to it.name }.orEmpty()
        subTracks = player.spuTracks?.map { it.id to it.name }.orEmpty()
        currentAudio = player.audioTrack
        currentSub = player.spuTrack
    }

    fun release() {
        player.setEventListener(null)
        player.stop()
        player.detachViews()
        player.release()
        libVlc.release()
    }
}

private fun Context.findActivity(): Activity? {
    var c = this
    while (c is ContextWrapper) { if (c is Activity) return c; c = c.baseContext }
    return null
}

// ---------- Tela do player ----------

@Composable
fun PlayerScreen(vm: AppViewModel, request: PlayerRequest, onPip: () -> Unit = {}) {
    val context = LocalContext.current
    val view = LocalView.current
    val isTv = rememberIsTv()
    val c = remember(request.id) { VlcController(context) }
    val pipSupported = remember {
        android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O &&
            context.packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }
    val inPip = vm.inPip

    var active by remember(request.id) { mutableStateOf(request) }
    var channelIndex by remember(request.id) { mutableIntStateOf(request.channelIndex) }
    var showControls by remember { mutableStateOf(true) }
    var lastInteraction by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var scrubbing by remember { mutableStateOf<Float?>(null) }
    var showEpisodes by remember { mutableStateOf(false) }
    var drawerSeason by remember { mutableStateOf<Int?>(null) }
    var countdown by remember { mutableStateOf<Int?>(null) }
    var nextCancelled by remember { mutableStateOf(false) }
    var locked by remember { mutableStateOf(false) }
    var showUnlockHint by remember { mutableStateOf(false) }
    var hintTick by remember { mutableLongStateOf(0L) }
    var lastSaved by remember { mutableLongStateOf(0L) }
    var volume by remember { mutableFloatStateOf(1f) }
    var brightness by remember { mutableFloatStateOf(0.6f) }
    val rootFocus = remember { FocusRequester() }
    val playFocus = remember { FocusRequester() }

    val ctx: EpisodeContext? = active.episode
    val currentChannel = active.channels.getOrNull(channelIndex)

    fun flashHint() { showUnlockHint = true; hintTick = System.currentTimeMillis() }
    fun poke() {
        if (locked) { flashHint(); return }
        lastInteraction = System.currentTimeMillis(); showControls = true
    }

    fun save(force: Boolean) {
        val entry = active.progress ?: return
        if (c.length <= 0) return
        val now = System.currentTimeMillis()
        if (!force && now - lastSaved < 10_000) return
        val pos = if (c.ended) c.length else c.time
        if (pos <= 1000) return
        lastSaved = now
        vm.updateProgress(entry.copy(position = pos, duration = c.length, updatedAt = now))
    }

    fun close() { save(true); vm.player = null }

    fun switchEpisode(ep: Episode, context: EpisodeContext) {
        val unfinished = vm.progress[ep.progressKey]?.isFinished == false
        val req = vm.episodeRequest(ep, context.series, context.info, unfinished) ?: return
        save(true)
        countdown = null; nextCancelled = false; showEpisodes = false
        active = req
        lastSaved = 0
        c.load(req.url, req.startAt)
        poke()
    }

    fun playNext() { val cx = ctx ?: return; val n = cx.next ?: return; switchEpisode(n, cx) }

    fun zap(delta: Int) {
        val n = active.channels.size
        if (n < 2) return
        channelIndex = (channelIndex + delta + n) % n
        val ch = active.channels[channelIndex]
        vm.liveUrl(ch)?.let { url -> active = active.copy(url = url, title = ch.name); c.load(url, 0) }
        poke()
    }

    // Tela cheia, horizontal, sem apagar a tela
    DisposableEffect(request.id) {
        val activity = context.findActivity()
        val window = activity?.window
        val previousOrientation = activity?.requestedOrientation
        if (!isTv) activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val insets = window?.let { WindowCompat.getInsetsController(it, view) }
        insets?.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        insets?.hide(WindowInsetsCompat.Type.systemBars())
        brightness = window?.attributes?.screenBrightness?.takeIf { it >= 0 } ?: 0.6f
        c.load(active.url, active.startAt)
        onDispose {
            save(true)
            c.release()
            window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            window?.let { w -> w.attributes = w.attributes.apply { screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE } }
            insets?.show(WindowInsetsCompat.Type.systemBars())
            if (!isTv && previousOrientation != null) activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
    }

    // Esconde os controles depois de 4,5 s parado
    LaunchedEffect(showControls, lastInteraction, c.playing, showEpisodes, scrubbing) {
        if (showControls && c.playing && !showEpisodes && scrubbing == null) {
            delay(4500)
            showControls = false
        }
    }

    // Salva o progresso a cada 10 s
    LaunchedEffect(c.time) { save(false) }

    // Fim do vídeo
    LaunchedEffect(c.ended) {
        if (!c.ended) return@LaunchedEffect
        if (active.isLive) { c.load(active.url, 0); return@LaunchedEffect }
        save(true)
        if (ctx?.next != null && !nextCancelled) {
            countdown = 6
            while ((countdown ?: 0) > 1) { delay(1000); countdown = countdown?.minus(1) ?: return@LaunchedEffect }
            delay(1000)
            if (countdown != null) playNext()
        } else if (ctx == null) {
            close()
        }
    }

    LaunchedEffect(showControls, showEpisodes) {
        delay(60)
        runCatching { if (showControls && !showEpisodes) playFocus.requestFocus() else if (!showEpisodes) rootFocus.requestFocus() }
    }

    // Carrega a lista de episódios quando veio de "Continuar assistindo"
    LaunchedEffect(request.id) {
        val entry = active.progress ?: return@LaunchedEffect
        val sid = entry.seriesId ?: return@LaunchedEffect
        if (active.episode != null) return@LaunchedEffect
        val series = vm.catalog.byKey["series-$sid"] ?: return@LaunchedEffect
        val info = runCatching { vm.api?.seriesInfo(sid) }.getOrNull() ?: return@LaunchedEffect
        val ep = info.all.firstOrNull { it.id == entry.streamId } ?: return@LaunchedEffect
        active = active.copy(episode = EpisodeContext(series, info, ep))
    }

    // Esconde o aviso de "tela travada" depois de 3 s
    LaunchedEffect(hintTick) {
        if (showUnlockHint) { delay(3000); showUnlockHint = false }
    }

    BackHandler(enabled = locked) { flashHint() }

    BackHandler(enabled = !locked) {
        when {
            showEpisodes -> showEpisodes = false
            isTv && showControls -> showControls = false
            else -> close()
        }
    }

    // Textos
    val kicker = when {
        active.isLive -> "TV AO VIVO · CANAL ${channelIndex + 1} DE ${active.channels.size.coerceAtLeast(1)}"
        ctx != null -> "${ctx.series.title.uppercase()} · TEMPORADA ${ctx.season}"
        active.progress?.season != null -> "${active.progress?.title.orEmpty().uppercase()} · TEMPORADA ${active.progress?.season}"
        else -> "FILME"
    }
    val headline = when {
        active.isLive -> currentChannel?.name ?: active.title
        ctx != null -> "Episódio ${ctx.episode.number} — ${ctx.episode.title}"
        active.progress?.episode != null -> "Episódio ${active.progress?.episode}" + (active.progress?.episodeTitle?.let { " — $it" } ?: "")
        else -> active.title
    }
    val endsAt = TextUtil.hour(System.currentTimeMillis() + ((c.length - c.time).coerceAtLeast(0) / c.rate.coerceAtLeast(0.25f)).toLong())
    val status = when {
        active.isLive -> if (isTv) "Use ▲ ▼ no controle para trocar de canal" else "Use ▲ ▼ para trocar de canal"
        c.length <= 0 -> "Carregando…"
        ctx != null -> "T${ctx.season} · E${ctx.episode.number} de ${ctx.seasonEpisodes.size} · termina às $endsAt"
        else -> "Termina às $endsAt"
    }
    val isEpisode = !active.isLive && (ctx != null || active.progress?.episode != null)
    val showSkip = isEpisode && c.time in 5_000L..85_000L && !c.buffering

    Box(
        Modifier.fillMaxSize().background(Color.Black)
            .focusRequester(rootFocus)
            .focusable()
            .onPreviewKeyEvent { ev ->
                if (ev.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                if (locked) { flashHint(); return@onPreviewKeyEvent ev.key.nativeKeyCode != AndroidKeyEvent.KEYCODE_BACK }
                when (ev.key.nativeKeyCode) {
                    AndroidKeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, AndroidKeyEvent.KEYCODE_MEDIA_PLAY, AndroidKeyEvent.KEYCODE_MEDIA_PAUSE -> { c.toggle(); poke(); true }
                    AndroidKeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> { c.jump(30_000); poke(); true }
                    AndroidKeyEvent.KEYCODE_MEDIA_REWIND -> { c.jump(-30_000); poke(); true }
                    AndroidKeyEvent.KEYCODE_CHANNEL_UP -> { zap(-1); true }
                    AndroidKeyEvent.KEYCODE_CHANNEL_DOWN -> { zap(1); true }
                    AndroidKeyEvent.KEYCODE_DPAD_CENTER, AndroidKeyEvent.KEYCODE_ENTER ->
                        if (!showControls) { c.toggle(); poke(); true } else { poke(); false }
                    AndroidKeyEvent.KEYCODE_DPAD_LEFT ->
                        if (!showControls && !active.isLive) { c.jump(-10_000); poke(); true } else { poke(); false }
                    AndroidKeyEvent.KEYCODE_DPAD_RIGHT ->
                        if (!showControls && !active.isLive) { c.jump(10_000); poke(); true } else { poke(); false }
                    AndroidKeyEvent.KEYCODE_DPAD_UP ->
                        if (!showControls && active.isLive) { zap(-1); true } else if (!showControls) { poke(); true } else { poke(); false }
                    AndroidKeyEvent.KEYCODE_DPAD_DOWN ->
                        if (!showControls && active.isLive) { zap(1); true } else if (!showControls) { poke(); true } else { poke(); false }
                    else -> { poke(); false }
                }
            },
    ) {
        AndroidView(
            factory = { ctxView -> VLCVideoLayout(ctxView).also { c.attach(it) } },
            modifier = Modifier.fillMaxSize(),
        )

        Box(
            Modifier.fillMaxSize().clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                if (locked) flashHint() else if (showControls) showControls = false else poke()
            },
        )

        if (c.buffering && !c.failed && !c.ended && !inPip) {
            Box(Modifier.align(Alignment.Center).size(84.dp).glass(CircleShape), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = Color.White, strokeWidth = 3.dp)
            }
        }

        AnimatedVisibility(
            visible = showControls && !locked && !inPip && !c.failed && !showEpisodes && countdown == null,
            enter = fadeIn(), exit = fadeOut(), modifier = Modifier.fillMaxSize(),
        ) {
            Box(Modifier.fillMaxSize()) {
                Box(Modifier.fillMaxSize().background(
                    Brush.verticalGradient(0f to Color.Black.copy(alpha = 0.7f), 0.3f to Color.Transparent, 0.6f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.75f))))

                if (!isTv) {
                    VerticalGlassSlider(volume, Icons.Filled.VolumeUp, "Volume", Modifier.align(Alignment.CenterStart).padding(start = 10.dp)) {
                        volume = it; c.setVolume(it); poke()
                    }
                    VerticalGlassSlider(brightness, Icons.Filled.BrightnessHigh, "Brilho", Modifier.align(Alignment.CenterEnd).padding(end = 10.dp)) {
                        brightness = it
                        context.findActivity()?.window?.let { w -> w.attributes = w.attributes.apply { screenBrightness = it.coerceIn(0.05f, 1f) } }
                        poke()
                    }
                }

                // topo
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 56.dp, vertical = 18.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    CircleGlassButton(Icons.Filled.KeyboardArrowDown, "Fechar player") { close() }
                    Column(Modifier.weight(1f)) {
                        Text(kicker, color = P.Accent, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.5.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(headline, color = Color.White, fontSize = 19.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    if (active.isLive) {
                        Row(
                            Modifier.background(Color.Red.copy(alpha = 0.9f), CircleShape).padding(horizontal = 12.dp, vertical = 7.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Box(Modifier.size(7.dp).background(Color.White, CircleShape))
                            Spacer(Modifier.width(6.dp))
                            Text("AO VIVO", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Black)
                        }
                    }
                    if (!isTv) {
                        CircleGlassButton(Icons.Filled.Lock, "Travar a tela contra toques") {
                            locked = true; showControls = false; showEpisodes = false; flashHint()
                        }
                    }
                    if (pipSupported && !isTv) {
                        CircleGlassButton(Icons.Filled.PictureInPictureAlt, "Abrir telinha flutuante") { onPip() }
                    }
                    active.favKey?.let { key ->
                        val fav = vm.isFavorite(key)
                        CircleGlassButton(if (fav) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                            if (fav) "Remover da minha lista" else "Adicionar à minha lista", tint = if (fav) P.Accent else Color.White) {
                            vm.toggleFavorite(key); poke()
                        }
                    }
                }

                // centro
                Row(Modifier.align(Alignment.Center), horizontalArrangement = Arrangement.spacedBy(46.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (active.isLive) CircleGlassButton(Icons.Filled.KeyboardArrowUp, "Canal anterior", 60.dp) { zap(-1) }
                    else CircleGlassButton(Icons.Filled.Replay10, "Voltar 10 segundos", 60.dp, 28.dp) { c.jump(-10_000); poke() }
                    CircleGlassButton(if (c.playing) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                        if (c.playing) "Pausar" else "Reproduzir", 84.dp, 38.dp, modifier = Modifier.focusRequester(playFocus)) { c.toggle(); poke() }
                    if (active.isLive) CircleGlassButton(Icons.Filled.KeyboardArrowDown, "Próximo canal", 60.dp) { zap(1) }
                    else CircleGlassButton(Icons.Filled.Forward10, "Avançar 10 segundos", 60.dp, 28.dp) { c.jump(10_000); poke() }
                }

                // painel inferior
                Column(
                    Modifier.align(Alignment.BottomCenter).padding(horizontal = 52.dp, vertical = 14.dp).widthIn(max = 1100.dp)
                        .fillMaxWidth().glass(RoundedCornerShape(22.dp), dark = true).padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    if (active.isLive) {
                        LiveInfo(vm, currentChannel)
                    } else {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            val shown = scrubbing?.toLong() ?: c.time
                            Text(TextUtil.time(shown), color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.width(56.dp))
                            Slider(
                                value = (scrubbing ?: c.time.toFloat()).coerceIn(0f, c.length.toFloat().coerceAtLeast(1f)),
                                onValueChange = { scrubbing = it; poke() },
                                onValueChangeFinished = { scrubbing?.let { c.seekTo(it.toLong()) }; scrubbing = null; poke() },
                                valueRange = 0f..c.length.toFloat().coerceAtLeast(1f),
                                colors = SliderDefaults.colors(thumbColor = Color.White, activeTrackColor = P.Accent, inactiveTrackColor = Color.White.copy(alpha = 0.28f)),
                                modifier = Modifier.weight(1f),
                            )
                            Text("-" + TextUtil.time((c.length - shown).coerceAtLeast(0)), color = Color.White.copy(alpha = 0.75f),
                                fontSize = 13.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.width(62.dp).padding(start = 6.dp))
                        }
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(status, color = Color.White.copy(alpha = 0.72f), fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                        if (ctx != null) {
                            Pill("Episódios", Icons.Filled.VideoLibrary) { drawerSeason = ctx.season; showEpisodes = true }
                            if (ctx.next != null) Pill("Próximo", Icons.Filled.SkipNext) { playNext() }
                        }
                        if (!active.isLive) {
                            MenuPill(if (c.rate == 1f) "1x" else rateLabel(c.rate), null,
                                listOf(0.5f, 0.75f, 1f, 1.25f, 1.5f, 2f).map { r -> Triple(rateLabel(r), r == c.rate) { c.setSpeed(r); poke() } })
                        }
                        if (c.audioTracks.isNotEmpty()) {
                            MenuPill(null, Icons.Filled.GraphicEq, c.audioTracks.map { (id, name) -> Triple(name, id == c.currentAudio) { c.selectAudio(id); poke() } })
                        }
                        if (c.subTracks.isNotEmpty()) {
                            MenuPill(null, Icons.Filled.ClosedCaption, c.subTracks.map { (id, name) -> Triple(name, id == c.currentSub) { c.selectSub(id); poke() } })
                        }
                        MenuPill(null, Icons.Filled.AspectRatio, listOf(
                            "Original" to MediaPlayer.ScaleType.SURFACE_BEST_FIT,
                            "Preencher a tela" to MediaPlayer.ScaleType.SURFACE_FILL,
                            "16:9" to MediaPlayer.ScaleType.SURFACE_16_9,
                            "4:3" to MediaPlayer.ScaleType.SURFACE_4_3,
                        ).map { (name, scale) -> Triple(name, name == c.aspect) { c.setScale(name, scale); poke() } })
                    }
                }
            }
        }

        // Tela travada: segurar para desbloquear
        AnimatedVisibility(
            visible = locked && showUnlockHint && !inPip,
            enter = fadeIn() + androidx.compose.animation.scaleIn(initialScale = 0.85f), exit = fadeOut(),
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 40.dp),
        ) {
            UnlockHint(onUnlocked = {
                locked = false; showUnlockHint = false
                lastInteraction = System.currentTimeMillis(); showControls = true
            }, onPressChanged = { pressing -> if (pressing) hintTick = Long.MAX_VALUE else flashHint() })
        }

        // Pular abertura
        AnimatedVisibility(
            visible = showSkip && countdown == null && !inPip && !locked,
            enter = fadeIn() + slideInHorizontally { it / 2 }, exit = fadeOut(),
            modifier = Modifier.align(Alignment.BottomEnd).padding(end = 24.dp, bottom = if (showControls) 128.dp else 28.dp),
        ) {
            Pressable(onClick = { c.seekTo(90_000); poke() }, shape = CircleShape) {
                Row(Modifier.glass(CircleShape).padding(horizontal = 18.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("Pular abertura", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.width(8.dp))
                    Icon(Icons.Filled.SkipNext, null, tint = Color.White, modifier = Modifier.size(18.dp))
                }
            }
        }

        if (c.failed && !inPip) {
            Column(
                Modifier.align(Alignment.Center).widthIn(max = 420.dp).glass(RoundedCornerShape(24.dp), dark = true).padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text("Não foi possível reproduzir", color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                Text(
                    if (active.isLive) "O canal pode estar fora do ar. Tente outro canal ou troque o formato em Configurações."
                    else "O conteúdo pode estar indisponível no servidor no momento.",
                    color = Color.White.copy(alpha = 0.75f), fontSize = 14.sp,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    PrimaryButton("Tentar de novo", icon = null, modifier = Modifier.weight(1f)) { c.load(active.url, c.time) }
                    GlassButton("Fechar", modifier = Modifier.weight(1f)) { close() }
                }
            }
        }

        // Gaveta de episódios
        AnimatedVisibility(
            visible = showEpisodes && ctx != null,
            enter = fadeIn() + slideInHorizontally { it }, exit = fadeOut() + slideOutHorizontally { it },
            modifier = Modifier.fillMaxSize(),
        ) {
            if (ctx != null) EpisodesDrawer(vm, ctx, drawerSeason ?: ctx.season, c,
                onSeason = { drawerSeason = it }, onPick = { switchEpisode(it, ctx) }, onClose = { showEpisodes = false; poke() })
        }

        // Próximo episódio
        AnimatedVisibility(
            visible = countdown != null && ctx?.next != null && !inPip && !locked,
            enter = fadeIn() + slideInVertically { it / 2 }, exit = fadeOut() + slideOutVertically { it / 2 },
            modifier = Modifier.align(Alignment.BottomEnd).padding(24.dp),
        ) {
            val next = ctx?.next
            if (next != null) {
                Row(
                    Modifier.width(380.dp).glass(RoundedCornerShape(22.dp), dark = true).padding(14.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Box(Modifier.width(112.dp).aspectRatio(16f / 9f).background(P.Surface2, RoundedCornerShape(10.dp)), contentAlignment = Alignment.Center) {
                        Artwork(next.image ?: ctx.info.backdrop, "", Modifier.fillMaxSize())
                        Box(Modifier.size(44.dp).glass(CircleShape), contentAlignment = Alignment.Center) {
                            Text("${countdown ?: ""}", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Black)
                        }
                    }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("PRÓXIMO EPISÓDIO", color = P.Accent, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp)
                        Text("E${next.number} · ${next.title}", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Pill("Assistir agora", null, primary = true) { playNext() }
                            Pill("Cancelar", null) { countdown = null; nextCancelled = true; poke() }
                        }
                    }
                }
            }
        }
    }
}

private fun rateLabel(r: Float): String = if (r == 1f) "Normal" else (if (r % 1f == 0f) "${r.toInt()}x" else "${r}x").replace('.', ',')

@Composable
private fun LiveInfo(vm: AppViewModel, ch: app.prismatv.Channel?) {
    LaunchedEffect(ch?.id) { ch?.let { vm.loadEpg(it) } }
    val now = ch?.let { vm.epgNow(it.id) }
    val next = ch?.let { vm.epgNext(it.id) }
    Row(Modifier.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("AGORA", color = P.Accent, fontSize = 12.sp, fontWeight = FontWeight.Bold)
        Text(now?.title ?: ch?.name.orEmpty(), color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1,
            overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
        if (now != null) ProgressBar(now.progress(), Modifier.width(160.dp))
        if (next != null) Text("A seguir ${TextUtil.hour(next.start)} ${next.title}", color = Color.White.copy(alpha = 0.7f), fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun Pill(text: String?, icon: ImageVector?, primary: Boolean = false, onClick: () -> Unit) {
    Pressable(onClick = onClick, shape = CircleShape, focusScale = 1.1f) {
        Row(
            Modifier.height(36.dp).background(if (primary) P.Primary else Color.White.copy(alpha = 0.13f), CircleShape)
                .padding(horizontal = if (text == null) 9.dp else 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val tint = if (primary) P.OnPrimary else Color.White
            if (icon != null) Icon(icon, text, tint = tint, modifier = Modifier.size(17.dp))
            if (icon != null && text != null) Spacer(Modifier.width(6.dp))
            if (text != null) Text(text, color = tint, fontSize = 13.sp, fontWeight = if (primary) FontWeight.Black else FontWeight.SemiBold)
        }
    }
}

@Composable
private fun MenuPill(text: String?, icon: ImageVector?, options: List<Triple<String, Boolean, () -> Unit>>) {
    var open by remember { mutableStateOf(false) }
    Box {
        Pill(text, icon) { open = true }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, modifier = Modifier.background(P.Surface)) {
            options.forEach { (label, selected, action) ->
                DropdownMenuItem(
                    text = { Text((if (selected) "✓  " else "     ") + label, color = if (selected) P.Accent else Color.White) },
                    onClick = { open = false; action() },
                )
            }
        }
    }
}

@Composable
private fun VerticalGlassSlider(value: Float, icon: ImageVector, label: String, modifier: Modifier, onChange: (Float) -> Unit) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(
            Modifier.width(34.dp).height(140.dp).glass(CircleShape)
                .pointerInput(Unit) {
                    detectVerticalDragGestures { change, _ ->
                        onChange((1f - change.position.y / size.height).coerceIn(0f, 1f))
                    }
                },
            contentAlignment = Alignment.BottomCenter,
        ) {
            Box(Modifier.fillMaxWidth().fillMaxHeight(value.coerceIn(0f, 1f)).background(Color.White.copy(alpha = 0.92f)))
        }
        Icon(icon, label, tint = Color.White, modifier = Modifier.size(18.dp))
    }
}

@Composable
private fun EpisodesDrawer(vm: AppViewModel, ctx: EpisodeContext, season: Int, c: VlcController,
                           onSeason: (Int) -> Unit, onPick: (Episode) -> Unit, onClose: () -> Unit) {
    val list = ctx.info.bySeason[season].orEmpty()
    val state = rememberLazyListState()
    LaunchedEffect(season) {
        val i = list.indexOfFirst { it.id == ctx.episode.id }
        if (i > 0) state.scrollToItem(i)
    }
    Box(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f))
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { onClose() })
        Column(
            Modifier.align(Alignment.CenterEnd).padding(10.dp).width(360.dp).fillMaxHeight()
                .glass(RoundedCornerShape(26.dp), dark = true).padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(ctx.series.title.uppercase(), color = P.Accent, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.4.sp, maxLines = 1)
                    Text("Temporada $season", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                }
                CircleGlassButton(Icons.Filled.Close, "Fechar lista de episódios", 36.dp, onClick = onClose)
            }
            if (ctx.info.seasons.size > 1) {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    items(ctx.info.seasons) { s -> Chip("T$s", s == season) { onSeason(s) } }
                }
            }
            LazyColumn(state = state, verticalArrangement = Arrangement.spacedBy(8.dp), contentPadding = PaddingValues(bottom = 8.dp)) {
                items(list, key = { it.id }) { ep ->
                    val isCurrent = ep.id == ctx.episode.id
                    val entry = vm.progress[ep.progressKey]
                    val tag = when {
                        isCurrent -> "Assistindo agora · ${TextUtil.time(c.time)} de ${TextUtil.time(c.length)}"
                        entry?.isFinished == true -> "Assistido"
                        entry != null && entry.position > 20_000 -> "Parou em ${TextUtil.time(entry.position)}"
                        (ep.durationSecs ?: 0) > 0 -> "${(ep.durationSecs!! / 60).coerceAtLeast(1)} min"
                        else -> ""
                    }
                    val fraction = if (isCurrent) (if (c.length > 0) c.time.toFloat() / c.length else 0f)
                    else if (entry?.isFinished == true) 1f else entry?.fraction ?: 0f
                    Pressable(onClick = { onPick(ep) }, shape = RoundedCornerShape(14.dp), focusScale = 1.03f, modifier = Modifier.fillMaxWidth()) {
                        Row(
                            Modifier.fillMaxWidth().background(if (isCurrent) P.Accent.copy(alpha = 0.12f) else Color.White.copy(alpha = 0.04f))
                                .border(1.dp, if (isCurrent) P.Accent.copy(alpha = 0.55f) else Color.Transparent, RoundedCornerShape(14.dp)).padding(7.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Box(Modifier.width(96.dp).aspectRatio(16f / 9f).background(P.Surface2, RoundedCornerShape(9.dp))) {
                                Artwork(ep.image ?: ctx.info.backdrop ?: ctx.series.backdrop, "E${ep.number}", Modifier.fillMaxSize())
                                if (fraction > 0f) ProgressBar(fraction, Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(5.dp), height = 3.dp)
                            }
                            Spacer(Modifier.width(10.dp))
                            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                Text("${ep.number}. ${ep.title}", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                if (tag.isNotEmpty()) Text(tag, color = if (isCurrent) P.Accent else Color.White.copy(alpha = 0.6f), fontSize = 11.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                            }
                        }
                    }
                }
            }
        }
    }
}


@Composable
private fun UnlockHint(onUnlocked: () -> Unit, onPressChanged: (Boolean) -> Unit) {
    val progress = remember { androidx.compose.animation.core.Animatable(0f) }
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val feedback = rememberFeedback()
    Row(
        Modifier
            .glass(CircleShape, dark = true)
            .pointerInput(Unit) {
                androidx.compose.foundation.gestures.detectTapGestures(onPress = {
                    onPressChanged(true)
                    val job = scope.launch {
                        progress.animateTo(1f, androidx.compose.animation.core.tween(1000, easing = androidx.compose.animation.core.LinearEasing))
                        feedback()
                        onUnlocked()
                    }
                    val released = tryAwaitRelease()
                    if (progress.value < 1f) {
                        job.cancel()
                        scope.launch { progress.animateTo(0f, androidx.compose.animation.core.tween(200)) }
                        onPressChanged(false)
                    }
                    if (!released) onPressChanged(false)
                })
            }
            .padding(horizontal = 18.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) {
            androidx.compose.material3.CircularProgressIndicator(
                progress = { progress.value }, color = P.Accent, trackColor = Color.White.copy(alpha = 0.25f),
                strokeWidth = 3.dp, modifier = Modifier.fillMaxSize(),
            )
            Icon(if (progress.value >= 1f) Icons.Filled.LockOpen else Icons.Filled.Lock, null, tint = Color.White, modifier = Modifier.size(18.dp))
        }
        Spacer(Modifier.width(12.dp))
        Column {
            Text("Tela travada", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold)
            Text("Segure aqui para desbloquear", color = Color.White.copy(alpha = 0.75f), fontSize = 12.sp)
        }
    }
}
