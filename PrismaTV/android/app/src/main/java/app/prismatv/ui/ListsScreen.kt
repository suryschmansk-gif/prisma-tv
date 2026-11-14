package app.prismatv.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.prismatv.AppViewModel
import app.prismatv.Kind
import app.prismatv.MediaItem

private enum class MyList(val label: String, val icon: ImageVector, val empty: String) {
    WATCHING("Assistindo", Icons.Filled.PlayCircle, "O que você começar a assistir aparece aqui."),
    WATCHLIST("Quero ver", Icons.Filled.Bookmark, "Segure o dedo (ou o OK do controle) numa capa e toque em \"Quero ver\" para guardar para depois."),
    FAVORITES("Favoritos", Icons.Filled.Favorite, "Toque no coração de uma série ou filme para guardar aqui."),
    WATCHED("Já assisti", Icons.Filled.CheckCircle, "Marque o que você já assistiu para não se perder."),
}

private enum class TypeFilter(val label: String) { ALL("Tudo"), SERIES("Séries"), MOVIES("Filmes") }

@Composable
fun ListsScreen(vm: AppViewModel, isTv: Boolean, onOpen: (MediaItem) -> Unit) {
    var list by rememberSaveable { mutableStateOf(MyList.WATCHLIST) }
    var filter by rememberSaveable { mutableStateOf(TypeFilter.ALL) }

    fun passes(kind: Kind) = when (filter) {
        TypeFilter.ALL -> true
        TypeFilter.SERIES -> kind == Kind.SERIES
        TypeFilter.MOVIES -> kind == Kind.MOVIE
    }

    val watching = (vm.continueWatching(Kind.SERIES) + vm.continueWatching(Kind.MOVIE))
        .filter { passes(it.kind) }.sortedByDescending { it.updatedAt }
    fun keys(l: MyList): Set<String> = when (l) {
        MyList.WATCHLIST -> vm.watchlist
        MyList.FAVORITES -> vm.favorites
        MyList.WATCHED -> vm.watched
        MyList.WATCHING -> emptySet()
    }
    fun count(l: MyList) = if (l == MyList.WATCHING) watching.size else keys(l).count { vm.catalog.byKey.containsKey(it) }

    Column(Modifier.fillMaxSize().background(P.Bg)) {
        Column(Modifier.statusBarsPadding().padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text("Minhas listas", color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.ExtraBold, modifier = Modifier.padding(horizontal = 16.dp))
            LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                items(MyList.entries) { l ->
                    val active = l == list
                    val bg by animateFloatAsState(if (active) 1f else 0f, tween(250), label = "tabbg")
                    Pressable(onClick = { list = l }, shape = CircleShape, focusScale = 1.08f) {
                        Row(
                            Modifier.background(if (active) P.Primary.copy(alpha = bg) else P.Surface, CircleShape)
                                .padding(horizontal = 14.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            val tint = if (active) P.OnPrimary else Color.White
                            Icon(l.icon, null, tint = tint, modifier = Modifier.size(15.dp))
                            Spacer(Modifier.width(6.dp))
                            Text(l.label, color = tint, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                            Spacer(Modifier.width(6.dp))
                            Text(
                                "${count(l)}", color = tint, fontSize = 11.sp, fontWeight = FontWeight.Bold,
                                modifier = Modifier.background(tint.copy(alpha = 0.15f), CircleShape).padding(horizontal = 6.dp, vertical = 2.dp),
                            )
                        }
                    }
                }
            }
            Row(Modifier.padding(horizontal = 10.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                TypeFilter.entries.forEach { f ->
                    Pressable(onClick = { filter = f }, shape = CircleShape, focusScale = 1.08f) {
                        Column(Modifier.padding(horizontal = 12.dp, vertical = 6.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(f.label, color = if (f == filter) P.Accent else P.Muted, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                            Spacer(Modifier.height(3.dp))
                            Box(Modifier.width(24.dp).height(2.dp).background(if (f == filter) P.Accent else Color.Transparent, CircleShape))
                        }
                    }
                }
            }
        }

        AnimatedContent(
            targetState = list to filter,
            transitionSpec = { (fadeIn(tween(250)) + slideInVertically(tween(300)) { it / 12 }) togetherWith fadeOut(tween(150)) },
            label = "lists",
            modifier = Modifier.weight(1f),
        ) { (l, _) ->
            val items = keys(l).mapNotNull { vm.catalog.byKey[it] }.filter { passes(it.kind) }.sortedBy { it.searchKey }
            val empty = if (l == MyList.WATCHING) watching.isEmpty() else items.isEmpty()
            if (empty) {
                Column(
                    Modifier.fillMaxSize().padding(40.dp).reveal(),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
                ) {
                    Icon(l.icon, null, tint = P.Accent.copy(alpha = 0.8f), modifier = Modifier.size(44.dp))
                    Spacer(Modifier.height(12.dp))
                    Text(if (l == MyList.WATCHING) "Nada em andamento" else "Lista vazia", color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(6.dp))
                    Text(l.empty, color = P.Muted, fontSize = 14.sp, textAlign = TextAlign.Center)
                }
            } else if (l == MyList.WATCHING) {
                LazyVerticalGrid(
                    columns = GridCells.Adaptive(if (isTv) 300.dp else 260.dp),
                    contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 16.dp, bottom = if (isTv) 40.dp else 110.dp),
                    horizontalArrangement = Arrangement.spacedBy(14.dp), verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    items(watching, key = { it.key }) { e ->
                        Box(Modifier.reveal()) {
                            ContinueCard(e, if (isTv) 300.dp else 340.dp, onClick = { vm.resume(e) }, onLongClick = {
                                if (e.seriesId != null) vm.removeSeriesProgress(e.seriesId) else vm.removeProgress(e.key)
                            })
                        }
                    }
                }
            } else {
                LazyVerticalGrid(
                    columns = GridCells.Adaptive(if (isTv) 150.dp else 104.dp),
                    contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 16.dp, bottom = if (isTv) 40.dp else 110.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(18.dp),
                ) {
                    items(items, key = { it.key }) { item ->
                        Box(Modifier.reveal()) { PosterCard(item, vm, null) { onOpen(item) } }
                    }
                    item(span = { GridItemSpan(maxLineSpan) }) { CreditFooter() }
                }
            }
        }
    }
}
