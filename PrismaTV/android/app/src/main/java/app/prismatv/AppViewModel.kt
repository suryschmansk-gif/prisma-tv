package app.prismatv

import android.app.Application
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File

// ---------- Preferências ----------

object Prefs {
    private fun sp(c: Context) = c.getSharedPreferences("prisma", Context.MODE_PRIVATE)
    fun account(c: Context): Account? = Account.fromJson(sp(c).getString("account", null))
    fun saveAccount(c: Context, a: Account?) = sp(c).edit().putString("account", a?.toJson()).apply()
    fun favorites(c: Context): Set<String> = sp(c).getStringSet("favorites", emptySet())?.toSet() ?: emptySet()
    fun saveFavorites(c: Context, s: Set<String>) = sp(c).edit().putStringSet("favorites", s).apply()
    fun tapSounds(c: Context) = sp(c).getBoolean("tapSounds", true)
    fun setTapSounds(c: Context, v: Boolean) = sp(c).edit().putBoolean("tapSounds", v).apply()
    fun liveFormat(c: Context) = sp(c).getString("liveFormat", "ts") ?: "ts"
    fun setLiveFormat(c: Context, v: String) = sp(c).edit().putString("liveFormat", v).apply()
}

private object CatalogCache {
    private fun dir(c: Context, a: Account): File {
        val safe = "${a.server}|${a.username}".map { if (it.isLetterOrDigit()) it else '_' }.joinToString("")
        return File(c.cacheDir, "catalog-$safe")
    }

    fun save(c: Context, a: Account, raw: Map<String, String>) {
        val d = dir(c, a); d.mkdirs()
        raw.forEach { (k, v) -> File(d, "$k.json").writeText(v) }
        File(d, "updated.txt").writeText(System.currentTimeMillis().toString())
    }

    fun load(c: Context, a: Account): Map<String, String>? {
        val d = dir(c, a)
        val out = Catalog.actions.mapNotNull { k -> File(d, "$k.json").takeIf { it.exists() }?.let { k to it.readText() } }.toMap()
        return out.ifEmpty { null }
    }

    fun updatedAt(c: Context, a: Account): Long? = File(dir(c, a), "updated.txt").takeIf { it.exists() }?.readText()?.toLongOrNull()
    fun clear(c: Context, a: Account) { dir(c, a).deleteRecursively() }
}

// ---------- Reprodução ----------

data class EpisodeContext(val series: MediaItem, val info: SeriesInfo, val episode: Episode) {
    val season: Int get() = info.seasonOf(episode)
    val seasonEpisodes: List<Episode> get() = info.bySeason[season].orEmpty()
    val next: Episode?
        get() {
            val all = info.all
            val i = all.indexOfFirst { it.id == episode.id }
            return if (i >= 0 && i + 1 < all.size) all[i + 1] else null
        }
}

data class PlayerRequest(
    val url: String,
    val title: String,
    val subtitle: String?,
    val isLive: Boolean,
    val startAt: Long,
    val progress: WatchEntry?,
    val channels: List<Channel> = emptyList(),
    val channelIndex: Int = 0,
    val episode: EpisodeContext? = null,
    val favKey: String? = null,
    val id: Long = System.nanoTime(),
)

sealed class LoadState {
    data object Idle : LoadState()
    data object Loading : LoadState()
    data object Loaded : LoadState()
    data class Failed(val message: String) : LoadState()
}

// ---------- Estado central ----------

class AppViewModel(app: Application) : AndroidViewModel(app) {
    private val ctx: Context get() = getApplication()

    var account by mutableStateOf<Account?>(Prefs.account(app))
        private set
    var userInfo by mutableStateOf<UserInfo?>(null)
        private set
    var state by mutableStateOf<LoadState>(LoadState.Idle)
        private set
    var catalog by mutableStateOf(Catalog())
        private set
    var lastUpdated by mutableStateOf<Long?>(null)
        private set
    var refreshing by mutableStateOf(false)
        private set
    var player by mutableStateOf<PlayerRequest?>(null)
    var favorites by mutableStateOf(Prefs.favorites(app))
        private set
    var tapSounds by mutableStateOf(Prefs.tapSounds(app))
        private set
    var liveFormat by mutableStateOf(Prefs.liveFormat(app))
        private set

    val progress = mutableStateMapOf<String, WatchEntry>()
    val epg = mutableStateMapOf<Int, List<EpgEntry>>()
    private val epgFetched = HashMap<Int, Pair<Long, Int>>()
    private val epgInFlight = HashSet<Int>()

    private val progressFile get() = File(ctx.filesDir, "progress.json")

    val api: XtreamApi? get() = account?.let { XtreamApi(it) }

    init {
        loadProgress()
        if (account != null) viewModelScope.launch { start() }
    }

    // ----- conta -----

    suspend fun login(input: Account) {
        val server = Account.normalize(input.server)
        val acc = input.copy(
            server = server,
            name = input.name.ifBlank { android.net.Uri.parse(server).host ?: "Minha lista" },
        )
        val user = XtreamApi(acc).authenticate()
        Prefs.saveAccount(ctx, acc)
        userInfo = user
        account = acc
        catalog = Catalog()
        epg.clear(); epgFetched.clear()
        refresh()
    }

    fun logout() {
        account?.let { CatalogCache.clear(ctx, it) }
        Prefs.saveAccount(ctx, null)
        account = null
        userInfo = null
        catalog = Catalog()
        lastUpdated = null
        state = LoadState.Idle
        epg.clear(); epgFetched.clear()
    }

    fun setTapSoundsEnabled(v: Boolean) { tapSounds = v; Prefs.setTapSounds(ctx, v) }
    fun setLiveFormatValue(v: String) { liveFormat = v; Prefs.setLiveFormat(ctx, v) }

    // ----- carregamento -----

    private suspend fun start() {
        val acc = account ?: return
        if (catalog.isEmpty) {
            val cached = withContext(Dispatchers.Default) { CatalogCache.load(ctx, acc)?.let { Catalog.build(it) } }
            if (cached != null) {
                catalog = cached
                lastUpdated = CatalogCache.updatedAt(ctx, acc)
                state = LoadState.Loaded
            }
        }
        val stale = lastUpdated?.let { System.currentTimeMillis() - it > 12 * 3600_000L } ?: true
        if (stale || catalog.isEmpty) refresh()
        else userInfo = runCatching { XtreamApi(acc).authenticate() }.getOrNull()
    }

    fun refreshAsync() { viewModelScope.launch { refresh() } }

    suspend fun refresh() {
        val acc = account ?: return
        if (refreshing) return
        refreshing = true
        if (catalog.isEmpty) state = LoadState.Loading
        try {
            val api = XtreamApi(acc)
            userInfo = api.authenticate()
            val raw = withContext(Dispatchers.IO) {
                Catalog.actions.map { a -> async { a to api.raw(a) } }.awaitAll().toMap()
            }
            val built = withContext(Dispatchers.Default) {
                CatalogCache.save(ctx, acc, raw)
                Catalog.build(raw)
            }
            catalog = built
            lastUpdated = System.currentTimeMillis()
            state = LoadState.Loaded
        } catch (e: Exception) {
            state = if (catalog.isEmpty) LoadState.Failed(e.message ?: "Erro desconhecido") else LoadState.Loaded
        } finally {
            refreshing = false
        }
    }

    // ----- favoritos -----

    fun isFavorite(key: String) = key in favorites
    fun toggleFavorite(key: String) {
        favorites = if (key in favorites) favorites - key else favorites + key
        Prefs.saveFavorites(ctx, favorites)
    }

    // ----- progresso -----

    private fun loadProgress() {
        runCatching {
            val o = JSONObject(progressFile.readText())
            o.keys().forEach { k -> o.optJSONObject(k)?.let(WatchEntry::fromJson)?.let { progress[k] = it } }
        }
    }

    private fun saveProgress() {
        val o = JSONObject()
        progress.values.forEach { o.put(it.key, it.toJson()) }
        runCatching { progressFile.writeText(o.toString()) }
    }

    fun updateProgress(e: WatchEntry) { progress[e.key] = e; saveProgress() }
    fun removeProgress(key: String) { progress.remove(key); saveProgress() }
    fun removeSeriesProgress(seriesId: Int) {
        progress.values.filter { it.seriesId == seriesId }.forEach { progress.remove(it.key) }
        saveProgress()
    }

    fun lastEpisode(seriesId: Int): WatchEntry? = progress.values.filter { it.seriesId == seriesId }.maxByOrNull { it.updatedAt }

    fun continueWatching(kind: Kind): List<WatchEntry> {
        val latest = HashMap<String, WatchEntry>()
        for (e in progress.values) {
            if (e.kind != kind) continue
            val group = e.seriesId?.let { "series-$it" } ?: e.key
            val cur = latest[group]
            if (cur == null || e.updatedAt > cur.updatedAt) latest[group] = e
        }
        return latest.values.filter { !it.isFinished && it.position > 20_000 }.sortedByDescending { it.updatedAt }
    }

    // ----- guia de programação -----

    fun loadEpg(ch: Channel, limit: Int = 8) {
        if (ch.epgId == null || ch.id in epgInFlight) return
        val api = api ?: return
        val now = System.currentTimeMillis()
        val prev = epgFetched[ch.id]
        if (prev != null && now - prev.first < 15 * 60_000 && prev.second >= limit && epg[ch.id]?.any { it.end > now } == true) return
        epgInFlight.add(ch.id)
        viewModelScope.launch {
            val list = api.shortEpg(ch.id, limit)
            epg[ch.id] = list
            epgFetched[ch.id] = System.currentTimeMillis() to limit
            epgInFlight.remove(ch.id)
        }
    }

    fun epgNow(id: Int): EpgEntry? { val n = System.currentTimeMillis(); return epg[id]?.firstOrNull { it.start <= n && it.end > n } }
    fun epgNext(id: Int): EpgEntry? { val n = System.currentTimeMillis(); return epg[id]?.firstOrNull { it.start > n } }
    fun epgUpcoming(id: Int): List<EpgEntry> { val n = System.currentTimeMillis(); return epg[id]?.filter { it.end > n }.orEmpty() }

    // ----- reprodução -----

    fun liveUrl(ch: Channel): String? {
        var format = liveFormat
        val allowed = userInfo?.allowedFormats.orEmpty()
        if (allowed.isNotEmpty() && format !in allowed) format = if ("m3u8" in allowed) "m3u8" else allowed.first()
        return api?.liveUrl(ch.id, format)
    }

    fun playChannel(ch: Channel, list: List<Channel>) {
        val url = liveUrl(ch) ?: return
        val idx = list.indexOfFirst { it.id == ch.id }.coerceAtLeast(0)
        player = PlayerRequest(url, ch.name, null, true, 0, null, list.ifEmpty { listOf(ch) }, idx)
    }

    fun playMovie(item: MediaItem, ext: String? = null, resume: Boolean) {
        val e = ext ?: item.ext
        val url = api?.movieUrl(item.streamId.toString(), e) ?: return
        val existing = progress[item.progressKey]
        val entry = WatchEntry(item.progressKey, Kind.MOVIE, item.streamId.toString(), e, item.title, item.year?.toString(),
            item.backdrop ?: item.poster, null, existing?.position ?: 0, existing?.duration ?: 0, System.currentTimeMillis())
        val start = if (resume) existing?.let { if (it.isFinished) 0 else it.position } ?: 0 else 0
        player = PlayerRequest(url, item.title, entry.subtitle, false, start, entry, favKey = item.key)
    }

    fun episodeRequest(ep: Episode, series: MediaItem, info: SeriesInfo?, resume: Boolean): PlayerRequest? {
        val url = api?.episodeUrl(ep.id, ep.ext) ?: return null
        val existing = progress[ep.progressKey]
        val context = info?.let { EpisodeContext(series, it, ep) }
        val season = context?.season ?: ep.season
        val subtitle = "T$season · E${ep.number} · ${ep.title}"
        val entry = WatchEntry(
            ep.progressKey, Kind.SERIES, ep.id, ep.ext, series.title, subtitle,
            ep.image ?: info?.backdrop ?: series.backdrop ?: series.poster, series.streamId,
            existing?.position ?: 0, existing?.duration ?: ((ep.durationSecs ?: 0) * 1000L), System.currentTimeMillis(),
            season, ep.number, ep.title,
        )
        val start = if (resume) existing?.let { if (it.isFinished) 0 else it.position } ?: 0 else 0
        return PlayerRequest(url, series.title, subtitle, false, start, entry, episode = context, favKey = series.key)
    }

    fun playEpisode(ep: Episode, series: MediaItem, info: SeriesInfo?, resume: Boolean) {
        player = episodeRequest(ep, series, info, resume)
    }

    fun resume(e: WatchEntry, fromStart: Boolean = false) {
        val api = api ?: return
        val url = if (e.kind == Kind.MOVIE) api.movieUrl(e.streamId, e.ext) else api.episodeUrl(e.streamId, e.ext)
        val fav = e.seriesId?.let { "series-$it" } ?: "movie-${e.streamId}"
        val start = if (fromStart || e.isFinished) 0 else e.position
        player = PlayerRequest(url, e.title, e.subtitle, false, start, e, favKey = fav)
    }
}
