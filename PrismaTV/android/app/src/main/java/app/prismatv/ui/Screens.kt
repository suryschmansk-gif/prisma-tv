package app.prismatv.ui

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridScope
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import app.prismatv.AppViewModel
import app.prismatv.Channel
import app.prismatv.Episode
import app.prismatv.Kind
import app.prismatv.MediaItem
import app.prismatv.MovieInfo
import app.prismatv.SeriesInfo
import app.prismatv.TextUtil
import app.prismatv.WatchEntry
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

private const val FAVORITES_ID = "__favorites"

enum class SortOrder(val label: String) { RECENT("Adicionados recentemente"), AZ("Nome (A–Z)"), RATING("Melhor avaliados"), YEAR("Lançamento mais novo") }

/** Faz o item ocupar a largura toda, ignorando o espaçamento lateral da grade. */
private fun Modifier.bleed(h: Dp): Modifier = layout { measurable, constraints ->
    val extra = h.roundToPx() * 2
    val placeable = measurable.measure(constraints.copy(minWidth = constraints.minWidth + extra, maxWidth = constraints.maxWidth + extra))
    layout(placeable.width - extra, placeable.height) { placeable.place(-h.roundToPx(), 0) }
}

private fun LazyGridScope.full(key: String, content: @Composable () -> Unit) {
    item(key = key, span = { GridItemSpan(maxLineSpan) }) { content() }
}

private fun filterItems(items: List<MediaItem>, category: String?, favs: Set<String>, query: String, sort: SortOrder, minRating: Int): List<MediaItem> {
    val q = TextUtil.searchKey(query.trim())
    val out = items.filter { item ->
        (category == null || (if (category == FAVORITES_ID) item.key in favs else item.categoryId == category)) &&
            (q.isEmpty() || item.searchKey.contains(q)) &&
            (minRating == 0 || (item.rating ?: 0.0) >= minRating)
    }
    return when (sort) {
        SortOrder.RECENT -> out.sortedByDescending { it.added }
        SortOrder.AZ -> out.sortedBy { it.searchKey }
        SortOrder.RATING -> out.sortedByDescending { it.rating ?: 0.0 }
        SortOrder.YEAR -> out.sortedByDescending { it.year ?: 0 }
    }
}

// =================== Séries / Filmes ===================

@Composable
fun SectionScreen(vm: AppViewModel, kind: Kind, isTv: Boolean, onOpen: (MediaItem) -> Unit, onSettings: () -> Unit) {
    val isSeries = kind == Kind.SERIES
    val catalog = vm.catalog
    val items = if (isSeries) catalog.series else catalog.movies
    val categories = if (isSeries) catalog.seriesCategories else catalog.movieCategories
    val counts = if (isSeries) catalog.seriesCounts else catalog.movieCounts
    val favs = vm.favorites

    var categoryId by rememberSaveable { mutableStateOf<String?>(null) }
    var query by rememberSaveable { mutableStateOf("") }
    var sort by rememberSaveable { mutableStateOf(SortOrder.RECENT) }
    var minRating by rememberSaveable { mutableIntStateOf(0) }
    var showFilters by remember { mutableStateOf(false) }

    val results by produceState(initialValue = emptyList<MediaItem>(), items, categoryId, query, sort, minRating, favs) {
        if (query.isNotEmpty()) delay(250)
        value = withContext(Dispatchers.Default) { filterItems(items, categoryId, favs, query, sort, minRating) }
    }

    val resume = vm.continueWatching(kind)
    val heroEntry = resume.firstOrNull()
    val heroItem = heroEntry?.let { e -> catalog.byKey[e.seriesId?.let { "series-$it" } ?: "movie-${e.streamId}"] }
        ?: (if (isSeries) catalog.recentSeries else catalog.recentMovies).let { list -> list.firstOrNull { it.backdrop != null } ?: list.firstOrNull() }
    val favItems = items.filter { it.key in favs }
    val top = if (isSeries) catalog.topSeries else catalog.topMovies
    val recent = if (isSeries) catalog.recentSeries else catalog.recentMovies
    val posterWidth = if (isTv) 150.dp else 118.dp
    val activeFilters = (if (sort != SortOrder.RECENT) 1 else 0) + (if (minRating > 0) 1 else 0)

    LazyVerticalGrid(
        columns = GridCells.Adaptive(if (isTv) 150.dp else 104.dp),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = if (isTv) 40.dp else 110.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
        modifier = Modifier.fillMaxSize().background(P.Bg),
    ) {
        full("hero") {
            Box(Modifier.bleed(16.dp)) {
                if (heroItem != null) {
                    HeroBanner(vm, heroItem, heroEntry, if (isSeries) "Séries" else "Filmes", isTv, onOpen, onSettings)
                } else {
                    Text(if (isSeries) "Séries" else "Filmes", color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.ExtraBold,
                        modifier = Modifier.statusBarsPadding().padding(16.dp))
                }
            }
        }
        if (resume.isNotEmpty()) full("continue") {
            Column(Modifier.bleed(16.dp).reveal(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                SectionTitle("Continuar assistindo")
                LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    items(resume, key = { it.key }) { e ->
                        ContinueCard(e, if (isTv) 300.dp else 272.dp, onClick = { vm.resume(e) }, onLongClick = {
                            if (e.seriesId != null) vm.removeSeriesProgress(e.seriesId) else vm.removeProgress(e.key)
                        })
                    }
                }
            }
        }
        if (favItems.isNotEmpty()) full("favs") { PosterRow("Minha lista", favItems, favs, posterWidth, onOpen) }
        if (top.isNotEmpty()) full("top") { TopRow(if (isSeries) "Top 5 séries" else "Top 5 filmes", top, onOpen) }
        if (recent.isNotEmpty()) full("recent") {
            PosterRow(if (isSeries) "Séries atualizadas" else "Adicionados recentemente", recent, favs, posterWidth, onOpen)
        }
        full("catalog-header") {
            Column(Modifier.bleed(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(Modifier.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(if (isSeries) "Todas as séries" else "Todos os filmes", color = Color.White, fontSize = 20.sp,
                        fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                    Pressable(onClick = { showFilters = true }, shape = CircleShape) {
                        Row(
                            Modifier.background(if (activeFilters > 0) P.Primary else P.Surface, CircleShape)
                                .border(1.dp, P.Hairline, CircleShape).padding(horizontal = 13.dp, vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            val tint = if (activeFilters > 0) P.OnPrimary else Color.White
                            Icon(Icons.Filled.FilterList, null, tint = tint, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(6.dp))
                            Text(if (activeFilters > 0) "Filtros · $activeFilters" else "Filtros", color = tint, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
                LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    item { Chip("Todas", categoryId == null) { categoryId = null } }
                    item { Chip("Minha lista", categoryId == FAVORITES_ID) { categoryId = FAVORITES_ID } }
                    items(categories.filter { (counts[it.id] ?: 0) > 0 }, key = { it.id }) { c ->
                        Chip(c.name, categoryId == c.id) { categoryId = c.id }
                    }
                }
                SearchBox(query, { query = it }, if (isSeries) "Buscar em séries" else "Buscar em filmes",
                    Modifier.fillMaxWidth().padding(horizontal = 16.dp), trailing = results.size.toString())
            }
        }
        items(results, key = { it.key }) { item ->
            Box(Modifier.reveal()) { PosterCard(item, item.key in favs, null) { onOpen(item) } }
        }
        if (results.isEmpty()) full("empty") {
            Text("Nada encontrado. Tente outra categoria ou limpe os filtros.", color = P.Muted, fontSize = 14.sp,
                modifier = Modifier.padding(vertical = 30.dp))
        }
        full("credit") { CreditFooter() }
    }

    if (showFilters) {
        FilterDialog(sort, minRating, onSort = { sort = it }, onRating = { minRating = it }, onDismiss = { showFilters = false })
    }
}

@Composable
private fun HeroBanner(vm: AppViewModel, item: MediaItem, entry: WatchEntry?, title: String, isTv: Boolean,
                       onOpen: (MediaItem) -> Unit, onSettings: () -> Unit) {
    val zoom by rememberInfiniteTransition(label = "kb").animateFloat(
        1f, 1.12f, infiniteRepeatable(tween(18_000), RepeatMode.Reverse), label = "zoom",
    )
    val kicker = when {
        entry != null -> "CONTINUE DE ONDE PAROU"
        item.kind == Kind.SERIES -> "SÉRIE EM DESTAQUE"
        else -> "NOVO NO CATÁLOGO"
    }
    val playLabel = when {
        entry?.season != null && entry.episode != null -> "Continuar T${entry.season} E${entry.episode}"
        entry != null -> "Continuar"
        item.kind == Kind.SERIES -> "Ver episódios"
        else -> "Assistir"
    }
    Box(Modifier.fillMaxWidth().height(if (isTv) 380.dp else 480.dp)) {
        Artwork(item.backdrop ?: item.poster, "", Modifier.fillMaxSize().graphicsLayer { scaleX = zoom; scaleY = zoom })
        Box(
            Modifier.fillMaxSize().background(
                Brush.verticalGradient(0f to P.Bg.copy(alpha = 0.45f), 0.28f to Color.Transparent, 0.7f to P.Bg.copy(alpha = 0.7f), 1f to P.Bg),
            ),
        )
        if (!isTv) {
            Row(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 16.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(title, color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.ExtraBold, modifier = Modifier.weight(1f))
                CircleGlassButton(Icons.Filled.Person, "Conta e configurações", 42.dp, onClick = onSettings)
            }
        }
        Column(
            Modifier.align(Alignment.BottomStart).padding(horizontal = 20.dp, vertical = 8.dp).widthIn(max = 620.dp).reveal(100),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(kicker, color = P.Accent, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.8.sp)
            Text(item.title, color = Color.White, fontSize = 34.sp, fontWeight = FontWeight.ExtraBold, maxLines = 2,
                overflow = TextOverflow.Ellipsis, lineHeight = 38.sp)
            val line = if (entry?.season != null && entry.episode != null)
                "Temporada ${entry.season} · Episódio ${entry.episode}" + (entry.episodeTitle?.let { " — $it" } ?: "")
            else listOfNotNull(item.genres.firstOrNull(), item.year?.toString(), TextUtil.rating(item.rating)?.let { "★ $it" }).joinToString(" · ")
            if (line.isNotEmpty()) Text(line, color = Color.White.copy(alpha = 0.82f), fontSize = 13.sp, maxLines = 1)
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                PrimaryButton(playLabel, modifier = Modifier.weight(1f)) {
                    when {
                        entry != null -> vm.resume(entry)
                        item.kind == Kind.MOVIE -> vm.playMovie(item, resume = false)
                        else -> onOpen(item)
                    }
                }
                GlassButton("Detalhes") { onOpen(item) }
            }
        }
    }
}

@Composable
private fun PosterRow(title: String, items: List<MediaItem>, favs: Set<String>, width: Dp, onOpen: (MediaItem) -> Unit) {
    Column(Modifier.bleed(16.dp).reveal(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionTitle(title)
        LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            items(items, key = { it.key }) { item -> PosterCard(item, item.key in favs, width) { onOpen(item) } }
        }
    }
}

@Composable
private fun TopRow(title: String, items: List<MediaItem>, onOpen: (MediaItem) -> Unit) {
    Column(Modifier.bleed(16.dp).reveal(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionTitle(title)
        LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            itemsIndexed(items, key = { _, it -> it.key }) { i, item ->
                Row(verticalAlignment = Alignment.Bottom) {
                    Text(
                        "${i + 1}", fontSize = 100.sp, fontWeight = FontWeight.Black,
                        color = P.Accent.copy(alpha = 0.35f),
                        modifier = Modifier.offset(x = 10.dp, y = 16.dp),
                    )
                    Pressable(onClick = { onOpen(item) }, shape = RoundedCornerShape(14.dp)) {
                        Artwork(item.poster, item.title, Modifier.width(116.dp).aspectRatio(2f / 3f))
                    }
                }
            }
        }
    }
}

@Composable
private fun FilterDialog(sort: SortOrder, minRating: Int, onSort: (SortOrder) -> Unit, onRating: (Int) -> Unit, onDismiss: () -> Unit) {
    Dialog(onDismissRequest = onDismiss) {
        Column(
            Modifier.widthIn(max = 440.dp).fillMaxWidth().background(P.Surface, RoundedCornerShape(24.dp))
                .border(1.dp, P.Hairline, RoundedCornerShape(24.dp)).padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text("Filtros", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            Text("ORDENAR POR", color = P.Muted, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp)
            SortOrder.entries.forEach { o ->
                Pressable(onClick = { onSort(o) }, shape = RoundedCornerShape(13.dp), focusScale = 1.03f, modifier = Modifier.fillMaxWidth()) {
                    Row(Modifier.fillMaxWidth().background(if (o == sort) P.Accent.copy(alpha = 0.14f) else Color.White.copy(alpha = 0.05f))
                        .padding(14.dp)) {
                        Text(o.label, color = Color.White, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                        if (o == sort) Text("✓", color = P.Accent, fontWeight = FontWeight.Bold)
                    }
                }
            }
            Text("NOTA MÍNIMA", color = P.Muted, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(0, 6, 7, 8).forEach { r -> Chip(if (r == 0) "Todas" else "$r+", minRating == r) { onRating(r) } }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                GlassButton("Limpar", modifier = Modifier.weight(1f)) { onSort(SortOrder.RECENT); onRating(0) }
                PrimaryButton("Aplicar", icon = null, modifier = Modifier.weight(1f)) { onDismiss() }
            }
        }
    }
}

// =================== TV ao vivo ===================

@Composable
fun LiveScreen(vm: AppViewModel, isTv: Boolean) {
    var categoryId by rememberSaveable { mutableStateOf<String?>(null) }
    var query by rememberSaveable { mutableStateOf("") }
    var schedule by remember { mutableStateOf<Channel?>(null) }
    val favs = vm.favorites
    val q = TextUtil.searchKey(query.trim())
    val list = vm.catalog.channels.filter { ch ->
        (categoryId == null || (if (categoryId == FAVORITES_ID) ch.favKey in favs else ch.categoryId == categoryId)) &&
            (q.isEmpty() || ch.searchKey.contains(q))
    }

    LazyColumn(
        Modifier.fillMaxSize().background(Brush.radialGradient(listOf(P.Accent.copy(alpha = 0.10f), P.Bg), radius = 1200f)),
        contentPadding = PaddingValues(bottom = if (isTv) 40.dp else 110.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Row(Modifier.statusBarsPadding().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("TV ao vivo", color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.ExtraBold, modifier = Modifier.weight(1f))
                Row(
                    Modifier.background(Color.Red.copy(alpha = 0.16f), CircleShape).padding(horizontal = 11.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.size(7.dp).background(Color.Red, CircleShape))
                    Spacer(Modifier.width(6.dp))
                    Text("${list.size} canais", color = Color(0xFFFCA5A5), fontSize = 12.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
        item { SearchBox(query, { query = it }, "Buscar canal", Modifier.fillMaxWidth().padding(horizontal = 16.dp)) }
        item {
            LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                item { Chip("Todos", categoryId == null) { categoryId = null } }
                item { Chip("Favoritos", categoryId == FAVORITES_ID) { categoryId = FAVORITES_ID } }
                items(vm.catalog.liveCategories.filter { (vm.catalog.liveCounts[it.id] ?: 0) > 0 }, key = { it.id }) { c ->
                    Chip(c.name, categoryId == c.id) { categoryId = c.id }
                }
            }
        }
        if (list.isEmpty()) item {
            Text(
                if (categoryId == FAVORITES_ID) "Segure o dedo (ou o OK do controle) num canal para favoritar." else "Nenhum canal encontrado.",
                color = P.Muted, modifier = Modifier.fillMaxWidth().padding(40.dp),
            )
        }
        itemsIndexed(list, key = { _, c -> c.id }) { i, ch ->
            ChannelCard(vm, ch, i + 1, ch.favKey in favs,
                onPlay = { vm.playChannel(ch, list) },
                onInfo = { schedule = ch },
                onFavorite = { vm.toggleFavorite(ch.favKey) },
                modifier = Modifier.padding(horizontal = 16.dp).reveal())
        }
        item { CreditFooter() }
    }

    schedule?.let { ch -> ScheduleDialog(vm, ch, onPlay = { schedule = null; vm.playChannel(ch, list) }, onDismiss = { schedule = null }) }
}

@Composable
fun ChannelCard(vm: AppViewModel, ch: Channel, number: Int, isFavorite: Boolean, onPlay: () -> Unit, onInfo: () -> Unit,
                onFavorite: () -> Unit, modifier: Modifier = Modifier) {
    LaunchedEffect(ch.id) { vm.loadEpg(ch) }
    val now = vm.epgNow(ch.id)
    val next = vm.epgNext(ch.id)
    Row(
        modifier.fillMaxWidth().background(P.Surface, RoundedCornerShape(18.dp)).border(1.dp, P.Hairline, RoundedCornerShape(18.dp)).padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Pressable(onClick = onPlay, onLongClick = onFavorite, shape = RoundedCornerShape(14.dp), focusScale = 1.03f, modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(58.dp).background(P.Surface2, RoundedCornerShape(14.dp)).padding(8.dp)) {
                    Artwork(ch.icon, ch.name.take(3), Modifier.fillMaxSize(), androidx.compose.ui.layout.ContentScale.Fit)
                }
                Spacer(Modifier.width(12.dp))
                Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(String.format("%02d", number) + " · " + ch.name, color = P.Muted, fontSize = 12.sp, maxLines = 1,
                            overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                        if (isFavorite) { Spacer(Modifier.width(4.dp)); Icon(Icons.Filled.Star, null, tint = P.Accent, modifier = Modifier.size(11.dp)) }
                    }
                    Text(now?.title ?: ch.name, color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (now != null) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            ProgressBar(now.progress(), Modifier.weight(1f), height = 3.dp)
                            if (next != null) {
                                Spacer(Modifier.width(8.dp))
                                Text("depois ${TextUtil.hour(next.start)}", color = Color.White.copy(alpha = 0.55f), fontSize = 11.sp)
                            }
                        }
                    }
                }
            }
        }
        if (ch.epgId != null) {
            Spacer(Modifier.width(10.dp))
            Pressable(onClick = onInfo, shape = CircleShape, focusScale = 1.12f) {
                Box(Modifier.size(40.dp).background(P.Surface2, CircleShape), contentAlignment = Alignment.Center) {
                    Icon(Icons.AutoMirrored.Filled.List, "Ver programação", tint = Color.White.copy(alpha = 0.75f), modifier = Modifier.size(18.dp))
                }
            }
        }
    }
}

@Composable
private fun ScheduleDialog(vm: AppViewModel, ch: Channel, onPlay: () -> Unit, onDismiss: () -> Unit) {
    LaunchedEffect(ch.id) { vm.loadEpg(ch, 20) }
    val items = vm.epgUpcoming(ch.id)
    Dialog(onDismissRequest = onDismiss) {
        Column(
            Modifier.widthIn(max = 460.dp).fillMaxWidth().background(P.Surface, RoundedCornerShape(24.dp))
                .border(1.dp, P.Hairline, RoundedCornerShape(24.dp)).padding(18.dp).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(ch.name, color = Color.White, fontSize = 19.sp, fontWeight = FontWeight.Bold)
            PrimaryButton("Assistir agora", modifier = Modifier.fillMaxWidth(), onClick = onPlay)
            if (items.isEmpty()) Text("Este canal não tem programação disponível.", color = P.Muted)
            val nowMs = System.currentTimeMillis()
            items.forEach { e ->
                val live = e.start <= nowMs
                Column(
                    Modifier.fillMaxWidth().background(if (live) P.Accent.copy(alpha = 0.08f) else Color.White.copy(alpha = 0.05f), RoundedCornerShape(14.dp))
                        .padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(5.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("${TextUtil.hour(e.start)} – ${TextUtil.hour(e.end)}", color = P.Accent, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                        if (live) {
                            Spacer(Modifier.width(8.dp))
                            Text("AGORA", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Black,
                                modifier = Modifier.background(Color.Red, CircleShape).padding(horizontal = 7.dp, vertical = 2.dp))
                        }
                    }
                    Text(e.title, color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                    e.summary?.let { Text(it, color = P.Muted, fontSize = 12.sp, maxLines = 3, overflow = TextOverflow.Ellipsis) }
                    if (live) ProgressBar(e.progress(), Modifier.fillMaxWidth(), height = 3.dp)
                }
            }
            GlassButton("Fechar", modifier = Modifier.fillMaxWidth(), onClick = onDismiss)
        }
    }
}

// =================== Busca ===================

private data class Found(val series: List<MediaItem> = emptyList(), val movies: List<MediaItem> = emptyList(), val channels: List<Channel> = emptyList())

@Composable
fun SearchScreen(vm: AppViewModel, isTv: Boolean, onOpen: (MediaItem) -> Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    val catalog = vm.catalog
    val found by produceState(initialValue = Found(), query, catalog) {
        val raw = query.trim()
        if (raw.length < 2) { value = Found(); return@produceState }
        delay(300)
        val q = TextUtil.searchKey(raw)
        value = withContext(Dispatchers.Default) {
            fun rank(list: List<MediaItem>): List<MediaItem> {
                val hits = list.filter { it.searchKey.contains(q) }
                return (hits.filter { it.searchKey.startsWith(q) } + hits.filterNot { it.searchKey.startsWith(q) }).take(40)
            }
            Found(rank(catalog.series), rank(catalog.movies), catalog.channels.filter { it.searchKey.contains(q) }.take(30))
        }
    }
    val active = query.trim().length >= 2
    val width = if (isTv) 150.dp else 118.dp

    LazyColumn(
        Modifier.fillMaxSize().background(P.Bg),
        contentPadding = PaddingValues(bottom = if (isTv) 40.dp else 110.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        item {
            Column(Modifier.statusBarsPadding().padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Text("Buscar", color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.ExtraBold)
                SearchBox(query, { query = it }, "Séries, filmes e canais", Modifier.fillMaxWidth())
            }
        }
        if (!active) item {
            Column(Modifier.fillMaxWidth().padding(top = 60.dp).reveal(), horizontalAlignment = Alignment.CenterHorizontally) {
                Text("Busque em tudo ao mesmo tempo", color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(6.dp))
                Text("Acentos e maiúsculas não importam.", color = P.Muted, fontSize = 14.sp)
            }
        } else {
            if (found.series.isNotEmpty()) item { PosterRowPlain("Séries", found.series, vm.favorites, width, onOpen) }
            if (found.movies.isNotEmpty()) item { PosterRowPlain("Filmes", found.movies, vm.favorites, width, onOpen) }
            if (found.channels.isNotEmpty()) {
                item { SectionTitle("Canais") }
                itemsIndexed(found.channels, key = { _, c -> "c${c.id}" }) { i, ch ->
                    ChannelCard(vm, ch, i + 1, ch.favKey in vm.favorites, onPlay = { vm.playChannel(ch, found.channels) },
                        onInfo = {}, onFavorite = { vm.toggleFavorite(ch.favKey) }, modifier = Modifier.padding(horizontal = 16.dp))
                }
            }
            if (found.series.isEmpty() && found.movies.isEmpty() && found.channels.isEmpty()) item {
                Text("Nada encontrado para “$query”.", color = P.Muted, modifier = Modifier.fillMaxWidth().padding(40.dp))
            }
        }
    }
}

@Composable
private fun PosterRowPlain(title: String, items: List<MediaItem>, favs: Set<String>, width: Dp, onOpen: (MediaItem) -> Unit) {
    Column(Modifier.reveal(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionTitle(title)
        LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            items(items, key = { it.key }) { item -> PosterCard(item, item.key in favs, width) { onOpen(item) } }
        }
    }
}

// =================== Detalhes ===================

@Composable
fun DetailScreen(vm: AppViewModel, item: MediaItem, isTv: Boolean, onBack: () -> Unit) {
    val isSeries = item.kind == Kind.SERIES
    var seriesInfo by remember(item.key) { mutableStateOf<SeriesInfo?>(null) }
    var movieInfo by remember(item.key) { mutableStateOf<MovieInfo?>(null) }
    var failed by remember(item.key) { mutableStateOf(false) }
    var season by remember(item.key) { mutableStateOf<Int?>(null) }

    LaunchedEffect(item.key) {
        val api = vm.api ?: return@LaunchedEffect
        try {
            if (isSeries) {
                val info = api.seriesInfo(item.streamId)
                seriesInfo = info
                val last = vm.lastEpisode(item.streamId)
                season = last?.let { e -> info.bySeason.entries.firstOrNull { en -> en.value.any { it.id == e.streamId } }?.key } ?: info.seasons.firstOrNull()
            } else {
                movieInfo = api.movieInfo(item.streamId)
            }
        } catch (e: Exception) { failed = true }
    }

    val genres = TextUtil.genres(seriesInfo?.genre ?: movieInfo?.genre).ifEmpty { item.genres }
    val plot = seriesInfo?.plot ?: movieInfo?.plot ?: item.plot
    val fav = vm.isFavorite(item.key)
    val meta = buildList {
        item.year?.let { add(it.toString()) }
        seriesInfo?.seasons?.size?.takeIf { it > 0 }?.let { add(if (it == 1) "1 temporada" else "$it temporadas") }
        movieInfo?.durationSecs?.takeIf { it > 0 }?.let { d -> add(if (d >= 3600) "${d / 3600}h ${(d % 3600) / 60}min" else "${d / 60}min") }
        TextUtil.rating(movieInfo?.rating ?: item.rating)?.let { add("★ $it") }
    }.joinToString(" · ")

    LazyColumn(
        Modifier.fillMaxSize().background(P.Bg),
        contentPadding = PaddingValues(bottom = if (isTv) 40.dp else 110.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item {
            Box(Modifier.fillMaxWidth().height(if (isTv) 360.dp else 430.dp)) {
                Artwork(seriesInfo?.backdrop ?: movieInfo?.backdrop ?: item.backdrop ?: item.poster, "", Modifier.fillMaxSize())
                Box(Modifier.fillMaxSize().background(
                    Brush.verticalGradient(0f to P.Bg.copy(alpha = 0.35f), 0.3f to Color.Transparent, 0.72f to P.Bg.copy(alpha = 0.75f), 1f to P.Bg)))
                Row(Modifier.fillMaxWidth().statusBarsPadding().padding(16.dp)) {
                    CircleGlassButton(Icons.AutoMirrored.Filled.ArrowBack, "Voltar", 42.dp, onClick = onBack)
                    Spacer(Modifier.weight(1f))
                    CircleGlassButton(if (fav) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                        if (fav) "Remover da minha lista" else "Adicionar à minha lista", 42.dp, tint = if (fav) P.Accent else Color.White) {
                        vm.toggleFavorite(item.key)
                    }
                }
                Column(Modifier.align(Alignment.BottomStart).padding(horizontal = 20.dp, vertical = 14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text((if (isSeries) "SÉRIE" else "FILME") + (item.genres.firstOrNull()?.let { " · ${it.uppercase()}" } ?: ""),
                        color = P.Accent, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.8.sp)
                    Text(item.title, color = Color.White, fontSize = 32.sp, fontWeight = FontWeight.ExtraBold, lineHeight = 36.sp, maxLines = 3)
                    if (meta.isNotEmpty()) Text(meta, color = Color.White.copy(alpha = 0.75f), fontSize = 13.sp)
                }
            }
        }

        item {
            Column(Modifier.padding(horizontal = 16.dp).widthIn(max = 760.dp).reveal(50), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                if (isSeries) {
                    val info = seriesInfo
                    if (info != null) SeriesActions(vm, item, info)
                } else {
                    MovieActions(vm, item, movieInfo)
                }
                if (genres.isNotEmpty()) {
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) { items(genres) { Chip(it, false) {} } }
                }
                plot?.let { Text(it, color = Color.White.copy(alpha = 0.82f), fontSize = 14.sp, lineHeight = 21.sp) }
                (seriesInfo?.cast ?: movieInfo?.cast)?.let { Text("Elenco: $it", color = P.Muted, fontSize = 12.sp, maxLines = 2) }
                movieInfo?.director?.let { Text("Direção: $it", color = P.Muted, fontSize = 12.sp) }
            }
        }

        val info = seriesInfo
        if (isSeries && info != null) {
            val current = season ?: info.seasons.firstOrNull() ?: 1
            if (info.seasons.size > 1) item {
                LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(info.seasons) { s -> Chip("Temporada $s", s == current) { season = s } }
                }
            } else item { SectionTitle("Episódios") }
            val last = vm.lastEpisode(item.streamId)
            items(info.bySeason[current].orEmpty(), key = { it.id }) { ep ->
                val entry = vm.progress[ep.progressKey]
                val watching = last?.streamId == ep.id && entry?.isFinished == false
                EpisodeRow(ep, info.backdrop ?: item.backdrop ?: item.poster, entry, watching,
                    modifier = Modifier.padding(horizontal = 16.dp).widthIn(max = 760.dp).reveal(),
                    onClick = { vm.playEpisode(ep, item, info, resume = entry?.isFinished == false) },
                    onLongClick = { vm.playEpisode(ep, item, info, resume = false) })
            }
        } else if (isSeries && failed) {
            item { Text("Não consegui carregar os episódios.", color = P.Muted, modifier = Modifier.padding(16.dp)) }
        } else if (isSeries) {
            item { Box(Modifier.fillMaxWidth().padding(20.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = P.Accent) } }
        }
        item { CreditFooter() }
    }
}

@Composable
private fun ResumeCard(title: String, entry: WatchEntry) {
    Column(
        Modifier.fillMaxWidth().background(P.Surface, RoundedCornerShape(16.dp))
            .border(1.dp, P.Accent.copy(alpha = 0.22f), RoundedCornerShape(16.dp)).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text("VOCÊ PAROU EM", color = P.Accent, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.4.sp)
        Text(title, color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.Bold, maxLines = 2)
        ProgressBar(entry.fraction, Modifier.fillMaxWidth())
        Text(entry.progressLine, color = P.Muted, fontSize = 12.sp)
    }
}

@Composable
private fun RestartButton(onClick: () -> Unit) {
    Pressable(onClick = onClick, shape = RoundedCornerShape(14.dp), focusScale = 1.08f) {
        Box(Modifier.size(52.dp).background(P.Surface2), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.Replay, "Assistir do início", tint = Color.White)
        }
    }
}

@Composable
private fun MovieActions(vm: AppViewModel, item: MediaItem, info: MovieInfo?) {
    val e = vm.progress[item.progressKey]
    if (e != null && !e.isFinished && e.position > 20_000) {
        ResumeCard(item.title, e)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            PrimaryButton("Continuar de ${TextUtil.time(e.position)}", modifier = Modifier.weight(1f)) { vm.playMovie(item, info?.ext, resume = true) }
            RestartButton { vm.playMovie(item, info?.ext, resume = false) }
        }
    } else {
        PrimaryButton("Assistir", modifier = Modifier.fillMaxWidth()) { vm.playMovie(item, info?.ext, resume = false) }
    }
}

@Composable
private fun SeriesActions(vm: AppViewModel, item: MediaItem, info: SeriesInfo) {
    val all = info.all
    val first = all.firstOrNull() ?: return
    val last = vm.lastEpisode(item.streamId)
    val idx = last?.let { l -> all.indexOfFirst { it.id == l.streamId } } ?: -1
    val target: Episode
    val label: String
    val resume: Boolean
    if (last == null || idx < 0) {
        target = first; resume = false; label = "Assistir T${info.seasonOf(first)} E${first.number}"
    } else if (last.isFinished) {
        if (idx + 1 < all.size) { target = all[idx + 1]; label = "Próximo: T${info.seasonOf(target)} E${target.number}" }
        else { target = first; label = "Rever desde o início" }
        resume = false
    } else {
        target = all[idx]; resume = true; label = "Continuar T${info.seasonOf(target)} E${target.number}"
    }
    if (resume && last != null) ResumeCard("Temporada ${info.seasonOf(target)} · Episódio ${target.number} — ${target.title}", last)
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        PrimaryButton(label, modifier = Modifier.weight(1f)) { vm.playEpisode(target, item, info, resume) }
        if (resume) RestartButton { vm.playEpisode(target, item, info, resume = false) }
    }
}

@Composable
private fun EpisodeRow(ep: Episode, fallback: String?, entry: WatchEntry?, watching: Boolean, modifier: Modifier,
                       onClick: () -> Unit, onLongClick: () -> Unit) {
    val tag = when {
        watching && entry != null -> "Assistindo · parou em ${TextUtil.time(entry.position)}"
        entry?.isFinished == true -> "Assistido"
        (ep.durationSecs ?: 0) > 0 -> "${(ep.durationSecs!! / 60).coerceAtLeast(1)} min"
        else -> ""
    }
    Pressable(onClick = onClick, onLongClick = onLongClick, shape = RoundedCornerShape(16.dp), focusScale = 1.02f, modifier = modifier.fillMaxWidth()) {
        Row(
            Modifier.fillMaxWidth().background(if (watching) P.Accent.copy(alpha = 0.08f) else P.Surface)
                .border(1.dp, if (watching) P.Accent.copy(alpha = 0.45f) else P.Hairline, RoundedCornerShape(16.dp)).padding(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.width(132.dp).aspectRatio(16f / 9f).background(P.Surface2, RoundedCornerShape(11.dp))) {
                Artwork(ep.image ?: fallback, "E${ep.number}", Modifier.fillMaxSize())
                Box(Modifier.align(Alignment.Center).size(32.dp).glass(CircleShape), contentAlignment = Alignment.Center) {
                    Icon(Icons.Filled.PlayArrow, null, tint = Color.White, modifier = Modifier.size(16.dp))
                }
                if (entry != null && entry.position > 0) {
                    ProgressBar(if (entry.isFinished) 1f else entry.fraction, Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(6.dp), height = 3.dp)
                }
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("${ep.number}. ${ep.title}", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold,
                        maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    if (entry?.isFinished == true) Icon(Icons.Filled.CheckCircle, "Assistido", tint = P.Accent, modifier = Modifier.size(18.dp))
                }
                if (tag.isNotEmpty()) Text(tag, color = if (watching) P.Accent else Color.White.copy(alpha = 0.6f), fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                ep.plot?.let { Text(it, color = Color.White.copy(alpha = 0.55f), fontSize = 12.sp, maxLines = 2, overflow = TextOverflow.Ellipsis) }
            }
        }
    }
}
