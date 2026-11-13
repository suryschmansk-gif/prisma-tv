package app.prismatv.ui

import android.content.ClipboardManager
import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import app.prismatv.Account
import app.prismatv.AppViewModel
import app.prismatv.Kind
import app.prismatv.LoadState
import app.prismatv.MediaItem
import app.prismatv.TextUtil
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
fun PrismaApp(vm: AppViewModel) {
    var splash by remember { mutableStateOf(true) }
    LaunchedEffect(Unit) { delay(1500); splash = false }
    FeedbackSettings.soundsOn = vm.tapSounds

    val screen = when {
        vm.account == null -> "login"
        vm.catalog.isEmpty && vm.state is LoadState.Failed -> "failed"
        vm.catalog.isEmpty -> "loading"
        else -> "main"
    }

    Box(Modifier.fillMaxSize().background(P.Bg)) {
        Crossfade(targetState = screen, animationSpec = tween(350), label = "root") { s ->
            when (s) {
                "login" -> LoginScreen(vm)
                "failed" -> FailureScreen(vm, (vm.state as? LoadState.Failed)?.message ?: "")
                "loading" -> LoadingScreen()
                else -> MainScreen(vm)
            }
        }
        AnimatedVisibility(visible = splash, enter = fadeIn(), exit = fadeOut(tween(600))) { SplashScreen() }
        vm.player?.let { req -> PlayerScreen(vm, req) }
    }
}

// ---------- Abertura ----------

@Composable
fun SplashScreen() {
    var step by remember { mutableStateOf(0) }
    LaunchedEffect(Unit) { step = 1; delay(350); step = 2 }
    val logo by animateFloatAsState(if (step > 0) 1f else 0f, spring(dampingRatio = 0.6f, stiffness = 200f), label = "logo")
    val text by animateFloatAsState(if (step > 1) 1f else 0f, tween(500), label = "text")
    Box(Modifier.fillMaxSize().background(P.Bg), contentAlignment = Alignment.Center) {
        Box(
            Modifier.size(340.dp).graphicsLayer { scaleX = 0.5f + logo * 0.65f; scaleY = 0.5f + logo * 0.65f; alpha = logo }
                .blur(90.dp).background(P.Accent.copy(alpha = 0.22f), CircleShape),
        )
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Box(Modifier.graphicsLayer { scaleX = 0.6f + logo * 0.4f; scaleY = 0.6f + logo * 0.4f; alpha = logo; rotationX = (1f - logo) * -25f }) {
                AppLogo(96.dp)
            }
            Text(
                "Prisma TV", color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.ExtraBold,
                modifier = Modifier.graphicsLayer { alpha = text; translationY = (1f - text) * 30f },
            )
        }
        Text(
            P.CREDIT, color = Color.White.copy(alpha = 0.4f), fontSize = 12.sp,
            modifier = Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(bottom = 28.dp)
                .graphicsLayer { alpha = text },
        )
    }
}

// ---------- Login ----------

@Composable
private fun LoginField(label: String, value: String, onChange: (String) -> Unit, password: Boolean = false, keyboard: KeyboardType = KeyboardType.Text) {
    Row(
        Modifier.fillMaxWidth().background(P.Surface, RoundedCornerShape(14.dp))
            .border(1.dp, P.Hairline, RoundedCornerShape(14.dp)).padding(15.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, color = P.Muted, fontSize = 13.sp, modifier = Modifier.width(78.dp))
        BasicTextField(
            value = value, onValueChange = onChange, singleLine = true,
            textStyle = TextStyle(color = Color.White, fontSize = 15.sp),
            cursorBrush = SolidColor(P.Accent),
            visualTransformation = if (password) PasswordVisualTransformation() else VisualTransformation.None,
            keyboardOptions = KeyboardOptions(keyboardType = if (password) KeyboardType.Password else keyboard),
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
fun LoginScreen(vm: AppViewModel) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var name by rememberSaveable { mutableStateOf("") }
    var server by rememberSaveable { mutableStateOf("") }
    var user by rememberSaveable { mutableStateOf("") }
    var pass by rememberSaveable { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val canSubmit = server.isNotBlank() && user.isNotBlank() && pass.isNotEmpty()

    Box(
        Modifier.fillMaxSize().background(Brush.radialGradient(listOf(P.Accent.copy(alpha = 0.16f), P.Bg), radius = 900f))
            .verticalScroll(rememberScrollState()).statusBarsPadding().navigationBarsPadding().imePadding(),
        contentAlignment = Alignment.TopCenter,
    ) {
        Column(
            Modifier.widthIn(max = 480.dp).padding(24.dp).reveal(),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Spacer(Modifier.height(30.dp))
            AppLogo(88.dp)
            Text("Prisma TV", color = Color.White, fontSize = 32.sp, fontWeight = FontWeight.ExtraBold)
            Text("Entre com os dados da sua linha Xtream Codes", color = P.Muted, fontSize = 14.sp, textAlign = TextAlign.Center)
            Spacer(Modifier.height(8.dp))
            GlassButton("Colar link M3U", Icons.Filled.ContentPaste, Modifier.fillMaxWidth()) {
                val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                val text = cm.primaryClip?.getItemAt(0)?.coerceToText(ctx)?.toString().orEmpty()
                val acc = Account.fromM3U(text)
                if (acc == null) error = "Não encontrei um link M3U válido copiado. Ele deve conter username= e password=."
                else { error = null; server = acc.server; user = acc.username; pass = acc.password; if (name.isBlank()) name = acc.name }
            }
            LoginField("Nome", name, { name = it })
            LoginField("Servidor", server, { server = it }, keyboard = KeyboardType.Uri)
            LoginField("Usuário", user, { user = it })
            LoginField("Senha", pass, { pass = it }, password = true)
            error?.let { Text(it, color = Color(0xFFFF8C99), fontSize = 13.sp, modifier = Modifier.fillMaxWidth()) }
            PrimaryButton(if (loading) "Conectando…" else "Entrar", icon = null, modifier = Modifier.fillMaxWidth()) {
                if (!canSubmit || loading) return@PrimaryButton
                loading = true; error = null
                scope.launch {
                    try { vm.login(Account(name, server, user.trim(), pass)) } catch (e: Exception) { error = e.message }
                    loading = false
                }
            }
            Text("Seus dados ficam guardados só neste aparelho.", color = P.Muted, fontSize = 12.sp, textAlign = TextAlign.Center)
            CreditFooter()
        }
    }
}

@Composable
fun LoadingScreen() {
    val pulse by rememberInfiniteTransition(label = "pulse").animateFloat(
        0.95f, 1.05f, infiniteRepeatable(tween(1100), RepeatMode.Reverse), label = "p",
    )
    Column(
        Modifier.fillMaxSize().background(P.Bg).padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
    ) {
        Box(Modifier.graphicsLayer { scaleX = pulse; scaleY = pulse }) { AppLogo(84.dp) }
        Spacer(Modifier.height(22.dp))
        Text("Carregando sua lista…", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(16.dp))
        CircularProgressIndicator(color = P.Accent)
        Spacer(Modifier.height(16.dp))
        Text("Na primeira vez pode levar até um minuto.\nDepois disso o app abre na hora.", color = P.Muted, fontSize = 13.sp, textAlign = TextAlign.Center)
    }
}

@Composable
fun FailureScreen(vm: AppViewModel, message: String) {
    Column(
        Modifier.fillMaxSize().background(P.Bg).padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
    ) {
        Text("Não consegui carregar a lista", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
        Text(message, color = P.Muted, fontSize = 14.sp, textAlign = TextAlign.Center)
        PrimaryButton("Tentar de novo", Icons.Filled.Refresh, Modifier.widthIn(max = 320.dp)) { vm.refreshAsync() }
        GlassButton("Trocar de conta", modifier = Modifier.widthIn(max = 320.dp)) { vm.logout() }
    }
}

// ---------- Estrutura principal (abas) ----------

enum class Tab(val label: String, val icon: ImageVector) {
    SERIES("Séries", Icons.Filled.VideoLibrary),
    MOVIES("Filmes", Icons.Filled.Movie),
    LIVE("TV", Icons.Filled.LiveTv),
    SEARCH("Buscar", Icons.Filled.Search),
}

@Composable
fun MainScreen(vm: AppViewModel) {
    val isTv = rememberIsTv()
    var tab by rememberSaveable { mutableStateOf(Tab.SERIES) }
    val stack = remember { mutableStateListOf<MediaItem>() }
    var showSettings by remember { mutableStateOf(false) }
    val holder = rememberSaveableStateHolder()
    val open: (MediaItem) -> Unit = { stack.add(it) }
    val select: (Tab) -> Unit = { tab = it; stack.clear() }

    BackHandler(enabled = stack.isNotEmpty()) { stack.removeAt(stack.lastIndex) }

    val content: @Composable () -> Unit = {
        Box(Modifier.fillMaxSize()) {
            Crossfade(targetState = tab, animationSpec = tween(250), label = "tab") { t ->
                holder.SaveableStateProvider(t.name) {
                    when (t) {
                        Tab.SERIES -> SectionScreen(vm, Kind.SERIES, isTv, open) { showSettings = true }
                        Tab.MOVIES -> SectionScreen(vm, Kind.MOVIE, isTv, open) { showSettings = true }
                        Tab.LIVE -> LiveScreen(vm, isTv)
                        Tab.SEARCH -> SearchScreen(vm, isTv, open)
                    }
                }
            }
            AnimatedVisibility(
                visible = stack.isNotEmpty(),
                enter = fadeIn(tween(250)) + slideInHorizontally(tween(300)) { it / 6 },
                exit = fadeOut(tween(200)) + slideOutHorizontally(tween(250)) { it / 6 },
            ) {
                stack.lastOrNull()?.let { item ->
                    DetailScreen(vm, item, isTv, onBack = { if (stack.isNotEmpty()) stack.removeAt(stack.lastIndex) })
                }
            }
        }
    }

    if (isTv) {
        Row(Modifier.fillMaxSize().background(P.Bg)) {
            TvRail(tab, select) { showSettings = true }
            Box(Modifier.weight(1f).fillMaxHeight()) { content() }
        }
    } else {
        Box(Modifier.fillMaxSize().background(P.Bg)) {
            content()
            GlassTabBar(tab, select, Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(horizontal = 16.dp, vertical = 8.dp))
        }
    }

    if (showSettings) SettingsDialog(vm) { showSettings = false }
}

@Composable
private fun GlassTabBar(selected: Tab, onSelect: (Tab) -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier.widthIn(max = 520.dp).fillMaxWidth().glass(CircleShape, dark = true).padding(6.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Tab.entries.forEach { t ->
            val active = t == selected
            val bg by animateFloatAsState(if (active) 1f else 0f, tween(250), label = "tabbg")
            Pressable(onClick = { onSelect(t) }, shape = CircleShape, focusScale = 1.04f, modifier = Modifier.weight(1f)) {
                Column(
                    Modifier.fillMaxWidth().height(52.dp).background(P.Accent.copy(alpha = 0.16f * bg), CircleShape),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
                ) {
                    val tint = if (active) P.Accent else Color.White.copy(alpha = 0.7f)
                    Icon(t.icon, null, tint = tint, modifier = Modifier.size(21.dp))
                    Text(t.label, color = tint, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

@Composable
private fun TvRail(selected: Tab, onSelect: (Tab) -> Unit, onSettings: () -> Unit) {
    Column(
        Modifier.fillMaxHeight().width(108.dp).background(P.Surface.copy(alpha = 0.6f)).padding(vertical = 24.dp, horizontal = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        AppLogo(48.dp)
        Spacer(Modifier.height(16.dp))
        Tab.entries.forEach { t ->
            val active = t == selected
            Pressable(onClick = { onSelect(t) }, shape = RoundedCornerShape(16.dp), focusScale = 1.08f, modifier = Modifier.fillMaxWidth()) {
                Column(
                    Modifier.fillMaxWidth().background(if (active) P.Accent.copy(alpha = 0.16f) else Color.Transparent)
                        .padding(vertical = 12.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    val tint = if (active) P.Accent else Color.White.copy(alpha = 0.75f)
                    Icon(t.icon, t.label, tint = tint, modifier = Modifier.size(26.dp))
                    Text(t.label, color = tint, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
        Spacer(Modifier.weight(1f))
        Pressable(onClick = onSettings, shape = RoundedCornerShape(16.dp), modifier = Modifier.fillMaxWidth()) {
            Text("Conta", color = Color.White.copy(alpha = 0.75f), fontSize = 12.sp, fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp))
        }
    }
}

// ---------- Configurações ----------

@Composable
fun SettingsDialog(vm: AppViewModel, onDismiss: () -> Unit) {
    var confirmLogout by remember { mutableStateOf(false) }
    Dialog(onDismissRequest = onDismiss) {
        Column(
            Modifier.widthIn(max = 460.dp).fillMaxWidth().background(P.Surface, RoundedCornerShape(24.dp))
                .border(1.dp, P.Hairline, RoundedCornerShape(24.dp)).padding(20.dp).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("Configurações", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            InfoRow("Lista", vm.account?.name ?: "-")
            InfoRow("Servidor", android.net.Uri.parse(vm.account?.server ?: "").host ?: "-")
            InfoRow("Usuário", vm.account?.username ?: "-")
            vm.userInfo?.let { u ->
                InfoRow("Expira em", u.expiration?.let { TextUtil.day(it) } ?: "Sem data")
                u.maxConnections?.let { InfoRow("Conexões", "${u.activeConnections ?: 0} de $it") }
            }
            InfoRow("Canais · Filmes · Séries", "${vm.catalog.channels.size} · ${vm.catalog.movies.size} · ${vm.catalog.series.size}")
            GlassButton(if (vm.refreshing) "Atualizando…" else "Atualizar listas agora", Icons.Filled.Refresh, Modifier.fillMaxWidth()) {
                vm.refreshAsync()
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Som ao tocar nos botões", color = Color.White, fontSize = 15.sp, modifier = Modifier.weight(1f))
                Switch(
                    checked = vm.tapSounds, onCheckedChange = { vm.setTapSoundsEnabled(it) },
                    colors = SwitchDefaults.colors(checkedTrackColor = P.Accent, checkedThumbColor = P.OnPrimary),
                )
            }
            Text("Formato da TV ao vivo", color = Color.White, fontSize = 15.sp)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Chip("MPEG-TS (recomendado)", vm.liveFormat == "ts") { vm.setLiveFormatValue("ts") }
                Chip("HLS (m3u8)", vm.liveFormat == "m3u8") { vm.setLiveFormatValue("m3u8") }
            }
            Text("Se algum canal travar, experimente trocar o formato.", color = P.Muted, fontSize = 12.sp)
            if (confirmLogout) {
                PrimaryButton("Confirmar: sair da conta", icon = null, modifier = Modifier.fillMaxWidth()) { onDismiss(); vm.logout() }
            } else {
                GlassButton("Sair da conta", modifier = Modifier.fillMaxWidth()) { confirmLogout = true }
            }
            GlassButton("Fechar", modifier = Modifier.fillMaxWidth()) { onDismiss() }
            CreditFooter()
        }
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth()) {
        Text(label, color = Color.White, fontSize = 14.sp, modifier = Modifier.weight(1f))
        Text(value, color = P.Muted, fontSize = 14.sp, maxLines = 1)
    }
}
