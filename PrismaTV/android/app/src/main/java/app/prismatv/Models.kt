package app.prismatv

import android.net.Uri
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.text.Normalizer
import java.text.SimpleDateFormat
import java.util.Locale

// ---------- Leitura tolerante de JSON ----------
// Painéis Xtream mandam o mesmo campo como número, texto, null ou até array vazio.

fun JSONObject.str(key: String): String? {
    if (!has(key) || isNull(key)) return null
    return when (val v = opt(key)) {
        is String -> v.trim().ifEmpty { null }
        is Number, is Boolean -> v.toString()
        else -> null
    }
}

fun JSONObject.int(key: String): Int? = str(key)?.let { it.toIntOrNull() ?: it.toDoubleOrNull()?.toInt() }
fun JSONObject.long(key: String): Long? = str(key)?.let { it.toLongOrNull() ?: it.toDoubleOrNull()?.toLong() }
fun JSONObject.dbl(key: String): Double? = str(key)?.replace(',', '.')?.toDoubleOrNull()

fun JSONObject.firstStr(key: String): String? = when (val v = opt(key)) {
    is JSONArray -> if (v.length() > 0) v.optString(0).trim().ifEmpty { null } else null
    else -> str(key)
}

fun JSONObject.strList(key: String): List<String> = when (val v = opt(key)) {
    is JSONArray -> (0 until v.length()).mapNotNull { v.optString(it).trim().ifEmpty { null } }
    else -> listOfNotNull(str(key))
}

object TextUtil {
    private val yearRx = Regex("(?:\\(|\\[|-\\s*|\\s)((?:19|20)\\d{2})(?:\\)|\\]|\\s*$)")
    private val prefixRx = Regex("^\\s*[A-Z]{2,4}\\s*[|:]\\s*")
    private val episodeRx = Regex("^.*?S\\d+\\s*E\\d+\\s*[-–:|]?\\s*", RegexOption.IGNORE_CASE)
    private val marks = Regex("\\p{Mn}+")

    fun searchKey(s: String): String = Normalizer.normalize(s, Normalizer.Form.NFD).replace(marks, "").lowercase(Locale.ROOT)
    fun year(name: String): Int? = yearRx.findAll(name).lastOrNull()?.groupValues?.getOrNull(1)?.toIntOrNull()
    fun clean(name: String): String = prefixRx.replace(name.trim(), "").ifEmpty { name }
    fun episodeTitle(raw: String, n: Int): String = episodeRx.replace(raw, "").trim().ifEmpty { "Episódio $n" }
    fun genres(raw: String?): List<String> =
        raw?.split(',', '/', '&', '|')?.map { it.trim() }?.filter { it.isNotEmpty() && it.length < 30 } ?: emptyList()

    fun b64(s: String?): String? {
        if (s.isNullOrBlank()) return null
        return try { String(Base64.decode(s, Base64.DEFAULT), Charsets.UTF_8) } catch (e: Exception) { s }
    }

    fun time(ms: Long): String {
        val s = (ms / 1000).coerceAtLeast(0)
        val h = s / 3600
        val m = (s % 3600) / 60
        val sec = s % 60
        return if (h > 0) String.format(Locale.ROOT, "%d:%02d:%02d", h, m, sec) else String.format(Locale.ROOT, "%d:%02d", m, sec)
    }

    fun minutesLeft(ms: Long): String {
        val m = Math.round(ms / 60000.0).toInt()
        return if (m >= 60) String.format(Locale.ROOT, "faltam %dh%02d", m / 60, m % 60) else "faltam ${m.coerceAtLeast(1)} min"
    }

    fun rating(r: Double?): String? = if (r == null || r <= 0) null else String.format(Locale.ROOT, "%.1f", r).replace('.', ',')

    private val hourFmt = SimpleDateFormat("HH:mm", Locale.getDefault())
    fun hour(ms: Long): String = hourFmt.format(java.util.Date(ms))

    private val dayFmt = SimpleDateFormat("dd 'de' MMM 'de' yyyy", Locale("pt", "BR"))
    fun day(ms: Long): String = dayFmt.format(java.util.Date(ms))
}

// ---------- Conta ----------

data class Account(val name: String, val server: String, val username: String, val password: String) {
    fun toJson(): String = JSONObject()
        .put("name", name).put("server", server).put("username", username).put("password", password).toString()

    companion object {
        fun fromJson(s: String?): Account? = try {
            val o = JSONObject(s ?: return null)
            Account(o.optString("name"), o.getString("server"), o.getString("username"), o.getString("password"))
        } catch (e: Exception) { null }

        fun normalize(raw: String): String {
            var s = raw.trim()
            val lower = s.lowercase(Locale.ROOT)
            if (!lower.startsWith("http://") && !lower.startsWith("https://")) s = "http://$s"
            for (marker in listOf("/player_api.php", "/get.php", "/xmltv.php", "?")) {
                val i = s.indexOf(marker)
                if (i >= 0) s = s.substring(0, i)
            }
            return s.trimEnd('/')
        }

        fun fromM3U(link: String): Account? {
            val uri = Uri.parse(link.trim())
            val host = uri.host ?: return null
            val user = uri.getQueryParameter("username") ?: return null
            val pass = uri.getQueryParameter("password") ?: return null
            val port = if (uri.port > 0) ":${uri.port}" else ""
            return Account(host, "${uri.scheme ?: "http"}://$host$port", user, pass)
        }
    }
}

// ---------- Modelos ----------

data class Category(val id: String, val name: String)

data class Channel(
    val id: Int,
    val name: String,
    val icon: String?,
    val categoryId: String,
    val epgId: String?,
    val searchKey: String,
) {
    val favKey get() = "live-$id"
}

enum class Kind { MOVIE, SERIES }

data class MediaItem(
    val kind: Kind,
    val streamId: Int,
    val title: String,
    val poster: String?,
    val backdrop: String?,
    val rating: Double?,
    val year: Int?,
    val genres: List<String>,
    val categoryId: String,
    val added: Long,
    val ext: String,
    val plot: String?,
    val searchKey: String,
) {
    val key get() = (if (kind == Kind.MOVIE) "movie-" else "series-") + streamId
    val progressKey get() = "movie-$streamId"
    val meta: String
        get() {
            val parts = listOfNotNull(year?.toString(), genres.firstOrNull())
            return if (parts.isEmpty()) (if (kind == Kind.MOVIE) "Filme" else "Série") else parts.joinToString(" · ")
        }
}

data class Episode(
    val id: String,
    val number: Int,
    val season: Int,
    val rawTitle: String,
    val ext: String,
    val image: String?,
    val plot: String?,
    val durationSecs: Int?,
) {
    val title get() = TextUtil.episodeTitle(rawTitle, number)
    val progressKey get() = "episode-$id"
}

data class SeriesInfo(
    val plot: String?,
    val cast: String?,
    val genre: String?,
    val backdrop: String?,
    val cover: String?,
    val bySeason: Map<Int, List<Episode>>,
) {
    val seasons: List<Int> get() = bySeason.keys.sorted()
    val all: List<Episode> get() = seasons.flatMap { bySeason[it].orEmpty() }
    fun seasonOf(e: Episode): Int = bySeason.entries.firstOrNull { en -> en.value.any { it.id == e.id } }?.key ?: e.season
}

data class MovieInfo(
    val plot: String?,
    val cast: String?,
    val director: String?,
    val genre: String?,
    val releaseDate: String?,
    val durationSecs: Int?,
    val backdrop: String?,
    val poster: String?,
    val rating: Double?,
    val ext: String?,
)

data class EpgEntry(val title: String, val summary: String?, val start: Long, val end: Long) {
    fun progress(now: Long = System.currentTimeMillis()): Float =
        ((now - start).toFloat() / (end - start).coerceAtLeast(1)).coerceIn(0f, 1f)
}

data class UserInfo(
    val auth: Int,
    val status: String?,
    val expiration: Long?,
    val maxConnections: Int?,
    val activeConnections: Int?,
    val allowedFormats: List<String>,
)

/** Progresso salvo ("Continuar assistindo"). Tempos em milissegundos. */
data class WatchEntry(
    val key: String,
    val kind: Kind,
    val streamId: String,
    val ext: String,
    val title: String,
    val subtitle: String?,
    val image: String?,
    val seriesId: Int?,
    val position: Long,
    val duration: Long,
    val updatedAt: Long,
    val season: Int? = null,
    val episode: Int? = null,
    val episodeTitle: String? = null,
) {
    val fraction: Float get() = if (duration > 0) (position.toFloat() / duration).coerceIn(0f, 1f) else 0f
    val isFinished: Boolean get() = duration > 0 && (position.toFloat() / duration > 0.93f || duration - position < 90_000)
    val remaining: Long get() = (duration - position).coerceAtLeast(0)
    val progressLine: String
        get() = if (duration <= 0) TextUtil.time(position)
        else "${TextUtil.time(position)} de ${TextUtil.time(duration)} · ${TextUtil.minutesLeft(remaining)}"

    fun toJson(): JSONObject = JSONObject().apply {
        put("key", key); put("kind", kind.name); put("streamId", streamId); put("ext", ext); put("title", title)
        put("subtitle", subtitle ?: JSONObject.NULL); put("image", image ?: JSONObject.NULL)
        put("seriesId", seriesId ?: JSONObject.NULL); put("position", position); put("duration", duration)
        put("updatedAt", updatedAt); put("season", season ?: JSONObject.NULL); put("episode", episode ?: JSONObject.NULL)
        put("episodeTitle", episodeTitle ?: JSONObject.NULL)
    }

    companion object {
        fun fromJson(o: JSONObject): WatchEntry? = try {
            WatchEntry(
                key = o.getString("key"),
                kind = Kind.valueOf(o.optString("kind", "MOVIE")),
                streamId = o.getString("streamId"),
                ext = o.optString("ext", "mp4"),
                title = o.optString("title"),
                subtitle = o.str("subtitle"),
                image = o.str("image"),
                seriesId = o.int("seriesId"),
                position = o.optLong("position"),
                duration = o.optLong("duration"),
                updatedAt = o.optLong("updatedAt"),
                season = o.int("season"),
                episode = o.int("episode"),
                episodeTitle = o.str("episodeTitle"),
            )
        } catch (e: Exception) { null }
    }
}

// ---------- Conversão das respostas da API ----------

object Parse {
    private fun rating(ten: Double?, five: Double?): Double? = when {
        ten != null && ten > 0 -> ten.coerceAtMost(10.0)
        five != null && five > 0 -> (five * 2).coerceAtMost(10.0)
        else -> null
    }

    private fun validYear(y: Int?): Int? = y?.takeIf { it in 1900..2100 }

    private inline fun <T> list(text: String?, map: (JSONObject) -> T?): List<T> {
        if (text.isNullOrBlank()) return emptyList()
        val arr = try { JSONArray(text) } catch (e: Exception) { return emptyList() }
        val out = ArrayList<T>(arr.length())
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            try { map(o)?.let { out.add(it) } } catch (e: Exception) { /* item quebrado: ignora */ }
        }
        return out
    }

    fun categories(text: String?): List<Category> = list(text) { o ->
        val id = o.str("category_id") ?: return@list null
        Category(id, o.str("category_name") ?: "Sem nome")
    }

    fun channels(text: String?): List<Channel> = list(text) { o ->
        val id = o.int("stream_id") ?: return@list null
        val name = o.str("name") ?: "Canal $id"
        Channel(id, name, o.str("stream_icon"), o.str("category_id") ?: "", o.str("epg_channel_id"), TextUtil.searchKey(name))
    }

    fun movies(text: String?): List<MediaItem> = list(text) { o ->
        val id = o.int("stream_id") ?: return@list null
        val raw = o.str("name") ?: o.str("title") ?: "Filme $id"
        val title = TextUtil.clean(raw)
        MediaItem(
            kind = Kind.MOVIE, streamId = id, title = title,
            poster = o.str("stream_icon"), backdrop = null,
            rating = rating(o.dbl("rating"), o.dbl("rating_5based")),
            year = validYear(o.int("year")) ?: TextUtil.year(raw),
            genres = TextUtil.genres(o.str("genre")),
            categoryId = o.str("category_id") ?: "",
            added = o.long("added") ?: 0L,
            ext = o.str("container_extension") ?: "mp4",
            plot = o.str("plot"),
            searchKey = TextUtil.searchKey(title),
        )
    }

    fun series(text: String?): List<MediaItem> = list(text) { o ->
        val id = o.int("series_id") ?: return@list null
        val raw = o.str("name") ?: "Série $id"
        val title = TextUtil.clean(raw)
        val release = o.str("releaseDate") ?: o.str("release_date")
        val year = validYear(o.int("year")) ?: validYear(release?.take(4)?.toIntOrNull()) ?: TextUtil.year(raw)
        MediaItem(
            kind = Kind.SERIES, streamId = id, title = title,
            poster = o.str("cover"), backdrop = o.firstStr("backdrop_path"),
            rating = rating(o.dbl("rating"), o.dbl("rating_5based")),
            year = year,
            genres = TextUtil.genres(o.str("genre")),
            categoryId = o.str("category_id") ?: "",
            added = o.long("last_modified") ?: 0L,
            ext = "",
            plot = o.str("plot"),
            searchKey = TextUtil.searchKey(title),
        )
    }

    fun user(o: JSONObject): UserInfo = UserInfo(
        auth = o.int("auth") ?: 0,
        status = o.str("status"),
        expiration = o.long("exp_date")?.takeIf { it > 0 }?.times(1000),
        maxConnections = o.int("max_connections"),
        activeConnections = o.int("active_cons"),
        allowedFormats = o.strList("allowed_output_formats"),
    )

    private fun episode(o: JSONObject, seasonKey: Int?): Episode? {
        val id = o.str("id") ?: return null
        val info = o.optJSONObject("info")
        return Episode(
            id = id,
            number = o.int("episode_num") ?: 0,
            season = o.int("season") ?: seasonKey ?: 1,
            rawTitle = o.str("title") ?: "",
            ext = o.str("container_extension") ?: "mp4",
            image = info?.str("movie_image") ?: info?.str("cover_big"),
            plot = info?.str("plot"),
            durationSecs = info?.int("duration_secs"),
        )
    }

    fun seriesInfo(o: JSONObject): SeriesInfo {
        val info = o.optJSONObject("info")
        val map = HashMap<Int, MutableList<Episode>>()
        when (val eps = o.opt("episodes")) {
            is JSONObject -> {
                val keys = eps.keys()
                while (keys.hasNext()) {
                    val k = keys.next()
                    val arr = eps.optJSONArray(k) ?: continue
                    for (i in 0 until arr.length()) {
                        val e = arr.optJSONObject(i)?.let { episode(it, k.toIntOrNull()) } ?: continue
                        map.getOrPut(k.toIntOrNull() ?: e.season) { mutableListOf() }.add(e)
                    }
                }
            }
            is JSONArray -> {
                for (i in 0 until eps.length()) {
                    val arr = eps.optJSONArray(i) ?: continue
                    for (j in 0 until arr.length()) {
                        val e = arr.optJSONObject(j)?.let { episode(it, null) } ?: continue
                        map.getOrPut(e.season) { mutableListOf() }.add(e)
                    }
                }
            }
        }
        return SeriesInfo(
            plot = info?.str("plot"),
            cast = info?.str("cast"),
            genre = info?.str("genre"),
            backdrop = info?.firstStr("backdrop_path"),
            cover = info?.str("cover"),
            bySeason = map.mapValues { (_, v) -> v.sortedBy { it.number } },
        )
    }

    fun movieInfo(o: JSONObject): MovieInfo {
        val i = o.optJSONObject("info")
        val m = o.optJSONObject("movie_data")
        return MovieInfo(
            plot = i?.str("plot") ?: i?.str("description"),
            cast = i?.str("cast") ?: i?.str("actors"),
            director = i?.str("director"),
            genre = i?.str("genre"),
            releaseDate = i?.str("releasedate") ?: i?.str("release_date"),
            durationSecs = i?.int("duration_secs"),
            backdrop = i?.firstStr("backdrop_path"),
            poster = i?.str("movie_image") ?: i?.str("cover_big"),
            rating = i?.dbl("rating")?.takeIf { it > 0 },
            ext = m?.str("container_extension"),
        )
    }

    private val epgDate = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.ROOT)

    fun epg(o: JSONObject): List<EpgEntry> {
        val arr = o.optJSONArray("epg_listings") ?: return emptyList()
        val out = ArrayList<EpgEntry>()
        for (idx in 0 until arr.length()) {
            val e = arr.optJSONObject(idx) ?: continue
            val start = e.long("start_timestamp")?.times(1000) ?: e.str("start")?.let { runCatching { epgDate.parse(it)?.time }.getOrNull() }
            val end = e.long("stop_timestamp")?.times(1000) ?: e.str("end")?.let { runCatching { epgDate.parse(it)?.time }.getOrNull() }
            if (start == null || end == null) continue
            out.add(EpgEntry(TextUtil.b64(e.str("title")) ?: "Sem título", TextUtil.b64(e.str("description"))?.ifBlank { null }, start, end))
        }
        return out.sortedBy { it.start }
    }
}
