package app.prismatv

import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.Locale

class ApiError(message: String) : Exception(message)

class XtreamApi(val account: Account) {

    private fun q(s: String) = URLEncoder.encode(s, "UTF-8")
    private fun p(s: String) = Uri.encode(s)

    fun apiUrl(action: String?, params: Map<String, String> = emptyMap()): String {
        val sb = StringBuilder("${account.server}/player_api.php?username=${q(account.username)}&password=${q(account.password)}")
        if (action != null) sb.append("&action=").append(action)
        params.forEach { (k, v) -> sb.append('&').append(k).append('=').append(q(v)) }
        return sb.toString()
    }

    fun liveUrl(id: Int, format: String) = "${account.server}/live/${p(account.username)}/${p(account.password)}/$id.$format"
    fun movieUrl(id: String, ext: String) = "${account.server}/movie/${p(account.username)}/${p(account.password)}/$id.$ext"
    fun episodeUrl(id: String, ext: String) = "${account.server}/series/${p(account.username)}/${p(account.password)}/$id.$ext"

    suspend fun get(url: String): String = withContext(Dispatchers.IO) {
        val conn = try {
            URL(url).openConnection() as HttpURLConnection
        } catch (e: Exception) {
            throw ApiError("Endereço do servidor inválido. Use o formato http://dominio.com:porta")
        }
        conn.connectTimeout = 20_000
        conn.readTimeout = 180_000
        conn.setRequestProperty("User-Agent", "VLC/3.0.20 LibVLC/3.0.20")
        try {
            val code = conn.responseCode
            if (code == 401 || code == 403 || code == 451) throw ApiError(
                "O servidor recusou a conexão (erro $code). Alguns provedores bloqueiam acessos de fora do Brasil, " +
                    "de VPN ou de servidores na nuvem. No seu aparelho, na internet de casa, deve funcionar."
            )
            if (code !in 200..299) throw ApiError("O servidor respondeu com erro $code.")
            conn.inputStream.bufferedReader().use { it.readText() }
        } catch (e: ApiError) {
            throw e
        } catch (e: Exception) {
            throw ApiError("Falha de conexão: ${e.message ?: "sem resposta"}")
        } finally {
            conn.disconnect()
        }
    }

    suspend fun authenticate(): UserInfo {
        val text = get(apiUrl(null))
        val obj = try { JSONObject(text) } catch (e: Exception) {
            throw ApiError("O servidor não respondeu como um painel Xtream Codes. Confira o endereço e a porta.")
        }
        val wrong = "Usuário ou senha incorretos. Confira se digitou igual ao outro app."
        val user = obj.optJSONObject("user_info")?.let { Parse.user(it) } ?: throw ApiError(wrong)
        if (user.auth != 1) throw ApiError(wrong)
        val status = user.status?.lowercase(Locale.ROOT)
        if (status != null && status != "active") throw ApiError("Sua assinatura parece estar expirada ou desativada.")
        return user
    }

    suspend fun raw(action: String): String = get(apiUrl(action))

    suspend fun seriesInfo(id: Int): SeriesInfo =
        Parse.seriesInfo(JSONObject(get(apiUrl("get_series_info", mapOf("series_id" to id.toString())))))

    suspend fun movieInfo(id: Int): MovieInfo =
        Parse.movieInfo(JSONObject(get(apiUrl("get_vod_info", mapOf("vod_id" to id.toString())))))

    suspend fun shortEpg(streamId: Int, limit: Int): List<EpgEntry> = try {
        Parse.epg(JSONObject(get(apiUrl("get_short_epg", mapOf("stream_id" to streamId.toString(), "limit" to limit.toString())))))
    } catch (e: Exception) { emptyList() }
}

/** Listas já processadas para as telas. */
data class Catalog(
    val liveCategories: List<Category> = emptyList(),
    val channels: List<Channel> = emptyList(),
    val movieCategories: List<Category> = emptyList(),
    val movies: List<MediaItem> = emptyList(),
    val seriesCategories: List<Category> = emptyList(),
    val series: List<MediaItem> = emptyList(),
    val liveCounts: Map<String, Int> = emptyMap(),
    val movieCounts: Map<String, Int> = emptyMap(),
    val seriesCounts: Map<String, Int> = emptyMap(),
    val recentMovies: List<MediaItem> = emptyList(),
    val recentSeries: List<MediaItem> = emptyList(),
    val topMovies: List<MediaItem> = emptyList(),
    val topSeries: List<MediaItem> = emptyList(),
    val byKey: Map<String, MediaItem> = emptyMap(),
) {
    val isEmpty get() = channels.isEmpty() && movies.isEmpty() && series.isEmpty()

    companion object {
        val actions = listOf(
            "get_live_categories", "get_live_streams",
            "get_vod_categories", "get_vod_streams",
            "get_series_categories", "get_series",
        )

        fun build(raw: Map<String, String>): Catalog {
            val channels = Parse.channels(raw["get_live_streams"])
            val movies = Parse.movies(raw["get_vod_streams"])
            val series = Parse.series(raw["get_series"])
            val thisYear = java.util.Calendar.getInstance().get(java.util.Calendar.YEAR)
            fun top(list: List<MediaItem>) = list
                .filter { (it.year ?: 0) >= thisYear - 3 && (it.rating ?: 0.0) >= 7 }
                .sortedByDescending { it.rating ?: 0.0 }
                .take(5)
            return Catalog(
                liveCategories = Parse.categories(raw["get_live_categories"]),
                channels = channels,
                movieCategories = Parse.categories(raw["get_vod_categories"]),
                movies = movies,
                seriesCategories = Parse.categories(raw["get_series_categories"]),
                series = series,
                liveCounts = channels.groupingBy { it.categoryId }.eachCount(),
                movieCounts = movies.groupingBy { it.categoryId }.eachCount(),
                seriesCounts = series.groupingBy { it.categoryId }.eachCount(),
                recentMovies = movies.sortedByDescending { it.added }.take(24),
                recentSeries = series.sortedByDescending { it.added }.take(24),
                topMovies = top(movies),
                topSeries = top(series),
                byKey = (movies + series).associateBy { it.key },
            )
        }
    }
}
