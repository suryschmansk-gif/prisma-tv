package app.prismatv.ui

import android.content.pm.PackageManager
import android.view.SoundEffectConstants
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.prismatv.MediaItem
import app.prismatv.TextUtil
import app.prismatv.WatchEntry
import coil.compose.AsyncImage

// ---------- Tema (grafite + azul-gelo) ----------

object P {
    val Bg = Color(0xFF0A0A0D)
    val Surface = Color(0xFF15151A)
    val Surface2 = Color(0xFF1F1F26)
    val Accent = Color(0xFF9CC0FF)
    val Accent2 = Color(0xFFC3B5FF)
    val Primary = Color(0xFFF5F5F7)
    val OnPrimary = Color(0xFF0A0A0D)
    val Muted = Color(0x9EFFFFFF)
    val Hairline = Color(0x14FFFFFF)
    val Glass = Color(0x29FFFFFF)
    val GlassDark = Color(0xB315151A)
    val GlassBorder = Color(0x29FFFFFF)
    val ProgressBrush = Brush.horizontalGradient(listOf(Accent, Accent2))
    const val CREDIT = "Desenvolvido por Caio S L Torres"
}

@Composable
fun PrismaTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = P.Accent, onPrimary = P.OnPrimary, background = P.Bg, surface = P.Surface,
            onBackground = Color.White, onSurface = Color.White, surfaceVariant = P.Surface2,
        ),
        content = content,
    )
}

@Composable
fun rememberIsTv(): Boolean {
    val ctx = LocalContext.current
    return remember {
        ctx.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            !ctx.packageManager.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN)
    }
}

// ---------- Som e vibração ao tocar ----------

object FeedbackSettings { var soundsOn = true }

@Composable
fun rememberFeedback(): () -> Unit {
    val view = LocalView.current
    val haptic = LocalHapticFeedback.current
    return remember(view) {
        {
            haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
            if (FeedbackSettings.soundsOn) view.playSoundEffect(SoundEffectConstants.CLICK)
        }
    }
}

/**
 * Área clicável premium: encolhe ao tocar, cresce com borda azul quando focada pelo controle
 * da TV, e toca som + vibração.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun Pressable(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    shape: Shape = RoundedCornerShape(14.dp),
    focusScale: Float = 1.06f,
    onLongClick: (() -> Unit)? = null,
    content: @Composable BoxScope.() -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val focused by interaction.collectIsFocusedAsState()
    val scale by animateFloatAsState(
        targetValue = when { pressed -> 0.95f; focused -> focusScale; else -> 1f },
        animationSpec = tween(180), label = "press",
    )
    val feedback = rememberFeedback()
    Box(
        modifier = modifier
            .graphicsLayer { scaleX = scale; scaleY = scale }
            .clip(shape)
            .then(if (focused) Modifier.border(2.dp, P.Accent, shape) else Modifier)
            .combinedClickable(
                interactionSource = interaction,
                indication = null,
                onLongClick = onLongClick?.let { l -> { feedback(); l() } },
                onClick = { feedback(); onClick() },
            ),
        content = content,
    )
}

/** Fade + leve subida quando o conteúdo aparece na tela. */
fun Modifier.reveal(delayMs: Int = 0): Modifier = composed {
    var shown by rememberSaveable { mutableStateOf(false) }
    val a by animateFloatAsState(
        targetValue = if (shown) 1f else 0f,
        animationSpec = tween(550, delayMs, FastOutSlowInEasing), label = "reveal",
    )
    LaunchedEffect(Unit) { shown = true }
    graphicsLayer { alpha = a; translationY = (1f - a) * 40f }
}

fun Modifier.glass(shape: Shape, dark: Boolean = false): Modifier =
    this.clip(shape).background(if (dark) P.GlassDark else P.Glass).border(1.dp, P.GlassBorder, shape)

// ---------- Peças visuais ----------

@Composable
fun Artwork(url: String?, placeholder: String, modifier: Modifier = Modifier, contentScale: ContentScale = ContentScale.Crop) {
    Box(modifier.background(Brush.linearGradient(listOf(P.Surface2, P.Surface))), contentAlignment = Alignment.Center) {
        if (placeholder.isNotEmpty()) {
            Text(
                placeholder, color = Color.White.copy(alpha = 0.5f), fontSize = 13.sp, fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center, maxLines = 4, modifier = Modifier.padding(8.dp),
            )
        }
        if (!url.isNullOrBlank()) {
            AsyncImage(model = url, contentDescription = null, contentScale = contentScale, modifier = Modifier.fillMaxSize())
        }
    }
}

@Composable
fun ProgressBar(fraction: Float, modifier: Modifier = Modifier, height: Dp = 4.dp, rounded: Boolean = true) {
    val shape = if (rounded) RoundedCornerShape(height / 2) else RoundedCornerShape(0.dp)
    Box(modifier.height(height).clip(shape).background(Color.White.copy(alpha = 0.14f))) {
        Box(Modifier.fillMaxWidth(fraction.coerceIn(0f, 1f)).height(height).background(P.ProgressBrush))
    }
}

@Composable
fun PosterCard(item: MediaItem, isFavorite: Boolean, width: Dp?, onClick: () -> Unit) {
    val mod = if (width != null) Modifier.width(width) else Modifier.fillMaxWidth()
    Column(mod, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Pressable(onClick = onClick, shape = RoundedCornerShape(14.dp), modifier = Modifier.fillMaxWidth()) {
            Artwork(item.poster, item.title, Modifier.fillMaxWidth().aspectRatio(2f / 3f))
            TextUtil.rating(item.rating)?.let {
                Text(
                    "★ $it", color = P.Accent, fontSize = 10.sp, fontWeight = FontWeight.Bold,
                    modifier = Modifier.align(Alignment.TopStart).padding(7.dp)
                        .background(Color.Black.copy(alpha = 0.6f), CircleShape).padding(horizontal = 7.dp, vertical = 3.dp),
                )
            }
            if (isFavorite) {
                Icon(
                    Icons.Filled.Favorite, null, tint = P.Accent,
                    modifier = Modifier.align(Alignment.TopEnd).padding(7.dp)
                        .background(Color.Black.copy(alpha = 0.6f), CircleShape).padding(5.dp).size(11.dp),
                )
            }
            Box(Modifier.matchParentSize().border(1.dp, P.Hairline, RoundedCornerShape(14.dp)))
        }
        Text(
            item.title, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
            maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.heightIn(min = 34.dp),
        )
        Text(item.meta, color = P.Muted, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
fun ContinueCard(entry: WatchEntry, width: Dp, onClick: () -> Unit, onLongClick: () -> Unit) {
    val badge = if (entry.season != null && entry.episode != null) "T${entry.season} · E${entry.episode}"
    else if (entry.seriesId == null) "FILME" else "SÉRIE"
    val line = entry.episode?.let { n -> "Episódio $n" + (entry.episodeTitle?.let { " — $it" } ?: "") } ?: (entry.subtitle ?: "")
    Pressable(onClick = onClick, onLongClick = onLongClick, shape = RoundedCornerShape(18.dp), focusScale = 1.04f,
        modifier = Modifier.width(width)) {
        Column(Modifier.background(P.Surface)) {
            Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f)) {
                Artwork(entry.image, entry.title, Modifier.fillMaxSize())
                Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.55f)))))
                Box(Modifier.align(Alignment.Center).size(50.dp).glass(CircleShape), contentAlignment = Alignment.Center) {
                    Icon(Icons.Filled.PlayArrow, null, tint = Color.White, modifier = Modifier.size(24.dp))
                }
                Text(
                    badge, color = P.Accent, fontSize = 11.sp, fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(10.dp).background(Color.Black.copy(alpha = 0.55f), CircleShape)
                        .padding(horizontal = 9.dp, vertical = 4.dp),
                )
            }
            ProgressBar(entry.fraction, Modifier.fillMaxWidth(), rounded = false)
            Column(Modifier.padding(horizontal = 13.dp, vertical = 11.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(entry.title, color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (line.isNotEmpty()) Text(line, color = Color.White.copy(alpha = 0.85f), fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(entry.progressLine, color = P.Muted, fontSize = 12.sp, maxLines = 1)
            }
        }
    }
}

@Composable
fun Chip(text: String, selected: Boolean, onClick: () -> Unit) {
    Pressable(onClick = onClick, shape = CircleShape, focusScale = 1.08f) {
        Text(
            text, maxLines = 1, fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
            color = if (selected) P.OnPrimary else Color.White,
            modifier = Modifier
                .background(if (selected) P.Primary else P.Surface, CircleShape)
                .border(1.dp, if (selected) Color.Transparent else P.Hairline, CircleShape)
                .padding(horizontal = 15.dp, vertical = 9.dp),
        )
    }
}

@Composable
fun PrimaryButton(text: String, icon: ImageVector? = Icons.Filled.PlayArrow, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Pressable(onClick = onClick, shape = RoundedCornerShape(14.dp), focusScale = 1.04f, modifier = modifier) {
        Row(
            Modifier.fillMaxWidth().background(P.Primary).padding(vertical = 15.dp, horizontal = 16.dp),
            horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
        ) {
            if (icon != null) { Icon(icon, null, tint = P.OnPrimary, modifier = Modifier.size(20.dp)); Spacer(Modifier.width(8.dp)) }
            Text(text, color = P.OnPrimary, fontSize = 15.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
fun GlassButton(text: String, icon: ImageVector? = null, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Pressable(onClick = onClick, shape = RoundedCornerShape(14.dp), focusScale = 1.04f, modifier = modifier) {
        Row(
            Modifier.glass(RoundedCornerShape(14.dp)).padding(vertical = 15.dp, horizontal = 18.dp),
            horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
        ) {
            if (icon != null) { Icon(icon, null, tint = Color.White, modifier = Modifier.size(19.dp)); Spacer(Modifier.width(8.dp)) }
            Text(text, color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Bold, maxLines = 1)
        }
    }
}

@Composable
fun CircleGlassButton(icon: ImageVector, description: String, size: Dp = 44.dp, iconSize: Dp? = null, tint: Color = Color.White,
                      modifier: Modifier = Modifier, onClick: () -> Unit) {
    Pressable(onClick = onClick, shape = CircleShape, focusScale = 1.12f, modifier = modifier) {
        Box(Modifier.size(size).glass(CircleShape), contentAlignment = Alignment.Center) {
            Icon(icon, description, tint = tint, modifier = Modifier.size(iconSize ?: (size * 0.45f)))
        }
    }
}

@Composable
fun SearchBox(value: String, onChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier, trailing: String? = null) {
    Row(
        modifier
            .clip(RoundedCornerShape(13.dp))
            .background(P.Surface)
            .border(1.dp, P.Hairline, RoundedCornerShape(13.dp))
            .padding(horizontal = 13.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Filled.Search, null, tint = Color.White.copy(alpha = 0.55f), modifier = Modifier.size(19.dp))
        Spacer(Modifier.width(8.dp))
        Box(Modifier.weight(1f)) {
            if (value.isEmpty()) Text(placeholder, color = Color.White.copy(alpha = 0.5f), fontSize = 15.sp)
            BasicTextField(
                value = value, onValueChange = onChange, singleLine = true,
                textStyle = TextStyle(color = Color.White, fontSize = 15.sp),
                cursorBrush = SolidColor(P.Accent), modifier = Modifier.fillMaxWidth(),
            )
        }
        if (value.isNotEmpty()) {
            Icon(Icons.Filled.Close, "Limpar", tint = Color.White.copy(alpha = 0.5f),
                modifier = Modifier.size(19.dp).clip(CircleShape).combinedClickableSimple { onChange("") })
        } else if (trailing != null) {
            Text(trailing, color = Color.White.copy(alpha = 0.5f), fontSize = 12.sp)
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
private fun Modifier.combinedClickableSimple(onClick: () -> Unit): Modifier = this.combinedClickable(onClick = onClick)

@Composable
fun SectionTitle(text: String, modifier: Modifier = Modifier) {
    Text(text, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = modifier.padding(horizontal = 16.dp))
}

@Composable
fun AppLogo(size: Dp = 64.dp) {
    Box(
        Modifier.size(size).clip(RoundedCornerShape(size * 0.28f))
            .background(Brush.linearGradient(listOf(Color(0xFF1C2030), Color(0xFF0B0C12))))
            .border(1.dp, P.Accent.copy(alpha = 0.4f), RoundedCornerShape(size * 0.28f)),
        contentAlignment = Alignment.Center,
    ) {
        Icon(Icons.Filled.PlayArrow, null, tint = P.Accent, modifier = Modifier.size(size * 0.55f))
    }
}

@Composable
fun CreditFooter(modifier: Modifier = Modifier) {
    Text(
        P.CREDIT, color = Color.White.copy(alpha = 0.4f), fontSize = 12.sp, textAlign = TextAlign.Center,
        modifier = modifier.fillMaxWidth().padding(vertical = 18.dp),
    )
}
