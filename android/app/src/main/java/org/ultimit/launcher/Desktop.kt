package org.ultimit.launcher

import android.content.Context
import android.media.AudioManager
import android.net.ConnectivityManager
import android.os.BatteryManager
import android.os.Build
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.EaseIn
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.basicMarquee
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableFloatState
import androidx.compose.runtime.Stable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.BlurredEdgeTreatment
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

/** The physical hinge of a dual-screen device, in window pixels. */
data class Hinge(val bounds: Rect, val vertical: Boolean)

private val OpenEase = CubicBezierEasing(.2f, .8f, .2f, 1f)

/** One floating window. [pane] is which screen it lives on when spanned. */
@Stable
class Win(val id: String, pane: Int) {
    var pane by mutableIntStateOf(pane)
    var minimized by mutableStateOf(false)
    var closing by mutableStateOf(false)
    val anim = Animatable(0f)
}

/** Window manager: open, focus, minimize, close and move between screens. */
class DesktopState(private val scope: CoroutineScope) {
    val wins = mutableStateListOf<Win>()
    var paneCount by mutableIntStateOf(1)

    fun topOf(pane: Int): Win? = wins.lastOrNull { it.pane.coerceAtMost(paneCount - 1) == pane && !it.minimized }
    fun isOnTop(w: Win) = topOf(w.pane.coerceAtMost(paneCount - 1)) === w
    fun anyOpen() = wins.any { !it.minimized && !it.closing }

    fun open(id: String) {
        val w = wins.firstOrNull { it.id == id && !it.closing }
        if (w != null) {
            wins.remove(w); wins.add(w)
            if (w.minimized) { w.minimized = false; scope.launch { w.anim.snapTo(0f); w.anim.animateTo(1f, tween(420, easing = OpenEase)) } }
            return
        }
        val pane = if (paneCount < 2) 0 else when {
            topOf(paneCount - 1) == null -> paneCount - 1
            topOf(0) == null -> 0
            else -> paneCount - 1
        }
        val nw = Win(id, pane)
        wins.add(nw)
        scope.launch { nw.anim.animateTo(1f, tween(420, easing = OpenEase)) }
    }

    fun toggle(id: String) {
        val w = wins.firstOrNull { it.id == id && !it.closing }
        if (w != null && !w.minimized && isOnTop(w)) minimize(w) else open(id)
    }

    fun minimize(w: Win) = scope.launch {
        w.anim.animateTo(0f, tween(300, easing = EaseIn)); w.minimized = true
    }

    fun close(w: Win) {
        if (w.closing) return
        w.closing = true
        scope.launch { w.anim.animateTo(0f, tween(300, easing = EaseIn)); wins.remove(w) }
    }

    fun swapPane(w: Win) {
        if (paneCount < 2) return
        w.pane = if (w.pane == 0) 1 else 0
        wins.remove(w); wins.add(w)
    }

    /** Back: close the most recently focused visible window. Returns false if nothing was open. */
    fun back(): Boolean {
        val w = wins.lastOrNull { !it.minimized && !it.closing } ?: return false
        close(w); return true
    }

    fun closeAll() = wins.filter { !it.closing }.forEach { close(it) }
}

@Composable
fun Desktop(
    settings: Settings,
    repo: AppRepository,
    media: MediaFeed,
    hinge: Hinge?,
    resumed: Boolean,
    state: DesktopState,
    bootTick: Int,
    onBootPlayed: () -> Unit,
) {
    val skin = skinById(settings.skin)
    val ctx = LocalContext.current
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()
    var bootRun by remember { mutableIntStateOf(0) }
    LaunchedEffect(bootTick) { if (bootTick > 0) bootRun++ }
    val ui = remember(repo, settings, media) { Ui(repo, settings, media, { state.open(it) }, { bootRun++ }) }

    // Shared wallpaper clock. Only the draw phase reads it, so ticking it redraws without recomposing.
    val clock = remember { mutableFloatStateOf(0f) }
    LaunchedEffect(settings.motion, resumed) {
        if (!settings.motion || !resumed) return@LaunchedEffect
        val start = withFrameMillis { it } - clock.floatValue.toLong()
        var last = 0L
        while (true) withFrameMillis { if (it - last > 33) { clock.floatValue = (it - start).toFloat(); last = it } }
    }

    CompositionLocalProvider(LocalSkin provides skin) {
        BoxWithConstraints(Modifier.fillMaxSize().background(skin.bg1)) {
            val W = constraints.maxWidth.toFloat(); val H = constraints.maxHeight.toFloat()
            val dp = density.density
            val insets = WindowInsets.systemBars.union(WindowInsets.displayCutout)
            val topIn = insets.getTop(density).toFloat(); val botIn = insets.getBottom(density).toFloat()

            // ---- panes: one per physical screen ----
            val panes: List<Rect> = when {
                hinge == null -> listOf(Rect(0f, 0f, W, H))
                hinge.vertical -> listOf(Rect(0f, 0f, hinge.bounds.left, H), Rect(hinge.bounds.right, 0f, W, H))
                else -> listOf(Rect(0f, 0f, W, hinge.bounds.top), Rect(0f, hinge.bounds.bottom, W, H))
            }
            SideEffect { state.paneCount = panes.size }
            val verticalRail = (panes.size == 2 && hinge?.vertical == true) || (panes.size == 1 && W > H * 1.15f)
            val railW = 84f * dp; val barH = 66f * dp; val tickH = 26f * dp
            val showTicker = verticalRail && settings.ticker

            val scene = remember(W, H, settings.density, verticalRail) { WallScene(W, H, settings.density, if (verticalRail) railW else 0f, dp) }

            fun area(i: Int): Rect {
                val p = panes[i]
                var l = p.left; var t = p.top; var r = p.right; var b = p.bottom
                if (verticalRail && i == 0) l += railW
                if (t < 1f) t += topIn + (if (verticalRail) 10f else 64f) * dp
                val last = i == panes.size - 1
                if (verticalRail) { if (b > H - 1f) b -= (if (showTicker) tickH else 0f) + botIn }
                else if (last) b -= barH + botIn
                val m = 8f * dp
                return Rect(l + m, t, r - m, b - m)
            }

            // ---- wallpaper + gestures on empty space ----
            Canvas(
                Modifier.fillMaxSize()
                    .pointerInput(verticalRail) {
                        var dy = 0f
                        detectVerticalDragGestures(
                            onDragStart = { dy = 0f },
                            onVerticalDrag = { c, d -> c.consume(); dy += d },
                            onDragEnd = {
                                if (dy < -80 * dp) state.open(ALL)
                                else if (dy > 80 * dp) scope.launch { expandNotifications(ctx) }
                            },
                        )
                    }
                    .pointerInput(Unit) {
                        detectTapGestures(onDoubleTap = { scope.launch { Root.runAsync("input keyevent 223") } })
                    }
            ) { scene.draw(this, skin, clock.floatValue, settings.motion) }

            // ---- orbit shortcuts around the shard origin (desktop-style layouts only) ----
            if (verticalRail) {
                val g = scene.geo; val ro = g.r * .62f
                val p0 = panes[0]
                Cat.entries.forEachIndexed { i, c ->
                    val a = -2.5f + i / 5f * 1.35f
                    val x = (g.px + cos(a) * ro).coerceIn(max(120f * dp, p0.left + railW + 30f * dp), p0.right - 140f * dp)
                    val y = max(150f * dp, g.py + sin(a) * ro).coerceAtMost(H - 120f * dp)
                    Orb(c, x, y) { state.open(c.id) }
                }
            }

            // ---- status block and wordmark ----
            val sys = rememberSys(ctx)
            Status(
                sys,
                modifier = if (verticalRail) Modifier.align(Alignment.TopEnd).padding(top = with(density) { topIn.toDp() } + 12.dp, end = 24.dp)
                else Modifier.align(Alignment.TopStart).padding(top = with(density) { topIn.toDp() } + 8.dp, start = 16.dp),
                big = verticalRail,
            )
            Wordmark(
                settings.skin,
                Modifier.align(Alignment.BottomEnd).padding(
                    end = if (verticalRail) 30.dp else 16.dp,
                    bottom = with(density) { botIn.toDp() } + if (verticalRail) (if (showTicker) 26.dp else 0.dp) + 24.dp else 82.dp,
                ),
            )

            // ---- windows: the top window of each pane ----
            for (i in panes.indices) {
                val w = state.topOf(i) ?: continue
                key(w) {
                    WindowFrame(w, area(i), state, ui, scene, clock, settings.motion, two = panes.size == 2)
                }
            }

            // ---- rail ----
            Rail(state, verticalRail, botIn, onEmblem = { state.toggle(ALL) }, onEmblemLong = { bootRun++ })

            // ---- ticker ----
            if (showTicker) Ticker(Modifier.align(Alignment.BottomStart).padding(start = 84.dp).padding(bottom = with(density) { botIn.toDp() }), sys)

            // ---- toasts ----
            Column(
                Modifier.align(Alignment.TopEnd).padding(top = with(density) { topIn.toDp() } + if (verticalRail) 96.dp else 64.dp, end = 16.dp).widthIn(max = 340.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) { Toasts.items.forEach { key(it.id) { ToastView(it) } } }

            // ---- boot ----
            if (bootRun > 0) key(bootRun) { Boot(skin, hinge != null) { bootRun = 0; onBootPlayed() } }
        }
    }
}

// ---------- window frame ----------

@Composable
private fun WindowFrame(w: Win, r: Rect, state: DesktopState, ui: Ui, scene: WallScene, clock: MutableFloatState, motion: Boolean, two: Boolean) {
    val s = LocalSkin.current
    val density = LocalDensity.current
    val focused = state.wins.lastOrNull { !it.minimized && !it.closing } === w
    val wDp = with(density) { r.width.toDp() }; val hDp = with(density) { r.height.toDp() }
    Box(
        Modifier
            .offset { IntOffset(r.left.roundToInt(), r.top.roundToInt()) }
            .size(wDp, hDp)
            .drawWithContent {
                // Opens like a console line drawing itself: a 2px line grows from the centre,
                // then the window drops down from it. Same keyframes as the mockup's winIn.
                val p = w.anim.value
                val wf = if (p < .45f) p / .45f else 1f
                val hf = if (p < .45f) 0f else (p - .45f) / .55f
                val left = size.width * (1f - wf) / 2f
                val bottom = max(2f * density.density, size.height * hf)
                clipRect(left, 0f, size.width - left, bottom) { this@drawWithContent.drawContent() }
            }
            .graphicsLayer { alpha = (.3f + w.anim.value * 1.6f).coerceAtMost(1f) }
            .pointerInput(w) { detectTapGestures(onPress = { if (state.wins.lastOrNull() !== w) { state.wins.remove(w); state.wins.add(w) } }) },
    ) {
        // Frosted glass: the wallpaper slice behind this window, blurred, under the panel tint.
        Box(
            Modifier.fillMaxSize()
                .clipToBounds()
                .blur(18.dp, BlurredEdgeTreatment.Rectangle)
                .drawBehind { translate(-r.left, -r.top) { scene.draw(this, s, clock.floatValue, motion) } }
        )
        Box(Modifier.fillMaxSize().background(s.panel).border(1.dp, if (focused) s.lineStrong else s.line).brackets(s.accent))
        Column(Modifier.fillMaxSize()) {
            var drag by remember { mutableFloatStateOf(0f) }
            Row(
                Modifier.fillMaxWidth()
                    .pointerInput(two) {
                        if (!two) return@pointerInput
                        detectHorizontalDragGestures(
                            onDragStart = { drag = 0f },
                            onHorizontalDrag = { c, d -> c.consume(); drag += d },
                            onDragEnd = { if ((w.pane == 0 && drag > 100 * density.density) || (w.pane == 1 && drag < -100 * density.density)) state.swapPane(w) },
                        )
                    }
                    .padding(start = 16.dp, end = 6.dp, top = 12.dp, bottom = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                BasicText(windowTitle(w.id), style = Type.display(17).copy(color = s.fg), maxLines = 1)
                BasicText(windowSub(w.id, ui).uppercase(), style = Type.mono(10, .16).copy(color = s.dim), maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                Box(Modifier.weight(1f).height(1.dp).background(Brush.horizontalGradient(listOf(s.lineStrong, Color.Transparent))))
                if (two) WinBtn(if (w.pane == 0) "[ → ]" else "[ ← ]") { state.swapPane(w) }
                WinBtn("[ _ ]") { state.minimize(w) }
                WinBtn("[ × ]") { state.close(w) }
            }
            Box(Modifier.weight(1f).fillMaxWidth()) { PanelContent(w.id, ui) }
        }
    }
}

@Composable
private fun WinBtn(t: String, onClick: () -> Unit) {
    val s = LocalSkin.current
    BasicText(t, style = Type.mono(12, 0.0).copy(color = s.dim), modifier = Modifier.clickable(onClick = onClick).padding(horizontal = 6.dp, vertical = 6.dp))
}

// ---------- rail ----------

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun androidx.compose.foundation.layout.BoxScope.Rail(state: DesktopState, vertical: Boolean, botIn: Float, onEmblem: () -> Unit, onEmblemLong: () -> Unit) {
    val s = LocalSkin.current
    val density = LocalDensity.current
    val bot = with(density) { botIn.toDp() }
    fun on(c: Cat): Boolean { val w = state.wins.firstOrNull { it.id == c.id && !it.closing }; return w != null && !w.minimized }
    if (vertical) {
        Column(
            Modifier.align(Alignment.TopStart).fillMaxHeight().width(84.dp).background(s.rail)
                .drawBehind { drawLine(s.line, Offset(size.width, 0f), Offset(size.width, size.height), 1f) }
                .padding(top = 30.dp, bottom = bot + 14.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Emblem(40.dp, s.fg, modifier = Modifier.combinedClickable(onClick = onEmblem, onLongClick = onEmblemLong))
            Spacer(Modifier.height(14.dp))
            Cat.entries.forEach { c -> RailBtn(c, on(c), vertical = true) { state.toggle(c.id) } }
            Spacer(Modifier.weight(1f))
            Box(Modifier.size(14.dp, 140.dp), contentAlignment = Alignment.Center) {
                BasicText("ULTIMIT 0.1 · ${s.id.uppercase()}", style = Type.mono(9, .1).copy(color = s.dim), softWrap = false, modifier = Modifier.rotate(-90f).width(160.dp))
            }
        }
    } else {
        Row(
            Modifier.align(Alignment.BottomStart).fillMaxWidth().background(s.rail)
                .drawBehind { drawLine(s.line, Offset(0f, 0f), Offset(size.width, 0f), 1f) }
                .padding(start = 6.dp, end = 6.dp, bottom = bot).height(66.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.width(44.dp).fillMaxHeight().combinedClickable(onClick = onEmblem, onLongClick = onEmblemLong), contentAlignment = Alignment.Center) { Emblem(28.dp, s.fg) }
            Cat.entries.forEach { c -> RailBtn(c, on(c), vertical = false, modifier = Modifier.weight(1f)) { state.toggle(c.id) } }
        }
    }
}

@Composable
private fun RailBtn(c: Cat, on: Boolean, vertical: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val s = LocalSkin.current
    Column(
        modifier
            .then(if (vertical) Modifier.width(72.dp) else Modifier.fillMaxHeight())
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onClick)
            .drawBehind {
                if (on) {
                    val b = 3.dp.toPx()
                    if (vertical) drawRect(s.accent, Offset(-6.dp.toPx(), 12.dp.toPx()), androidx.compose.ui.geometry.Size(b, size.height - 24.dp.toPx()))
                    else drawRect(s.accent, Offset(size.width * .2f, 0f), androidx.compose.ui.geometry.Size(size.width * .6f, b))
                }
            }
            .padding(top = if (vertical) 10.dp else 8.dp, bottom = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterVertically),
    ) {
        Icon(c.id, 26.dp, s.fg)
        BasicText(c.label, style = Type.ui(if (vertical) 9 else 8, FontWeight.SemiBold, .18).copy(color = s.fg), maxLines = 1, softWrap = false)
    }
}

@Composable
private fun Orb(c: Cat, x: Float, y: Float, onClick: () -> Unit) {
    val s = LocalSkin.current
    val half = 23.dp
    Row(
        Modifier.offset { IntOffset((x - half.toPx()).roundToInt(), (y - half.toPx()).roundToInt()) },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.size(46.dp).clip(CircleShape).background(s.panel).border(1.dp, s.lineStrong, CircleShape).clickable(onClick = onClick),
            contentAlignment = Alignment.Center,
        ) { Icon(c.id, 20.dp, s.fg) }
        Spacer(Modifier.width(8.dp))
        BasicText(c.label, style = Type.ui(10, FontWeight.SemiBold, .2).copy(color = s.fg.copy(alpha = .75f)))
    }
}

// ---------- status, wordmark, ticker ----------

data class Sys(val time: String, val date: String, val battery: Int, val charging: Boolean, val net: Boolean, val vol: Int, val model: String)

private val days = arrayOf("SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT")

@Composable
private fun rememberSys(ctx: Context): Sys {
    val v by produceState(Sys("00:00:00", "----.--.-- ---", 0, false, false, 0, Build.MODEL ?: "phone")) {
        val bm = ctx.getSystemService(BatteryManager::class.java)
        val cm = ctx.getSystemService(ConnectivityManager::class.java)
        val am = ctx.getSystemService(AudioManager::class.java)
        val tf = SimpleDateFormat("HH:mm:ss", Locale.US); val df = SimpleDateFormat("yyyy.MM.dd", Locale.US)
        while (true) {
            val now = Date()
            val cal = java.util.Calendar.getInstance()
            // Every system read is guarded: a status readout must never take the home screen down.
            val max = runCatching { am.getStreamMaxVolume(AudioManager.STREAM_MUSIC) }.getOrDefault(1).coerceAtLeast(1)
            value = Sys(
                tf.format(now), "${df.format(now)} ${days[cal.get(java.util.Calendar.DAY_OF_WEEK) - 1]}",
                runCatching { bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) }.getOrDefault(0),
                runCatching { bm.isCharging }.getOrDefault(false),
                runCatching { cm.activeNetwork != null }.getOrDefault(false),
                runCatching { am.getStreamVolume(AudioManager.STREAM_MUSIC) }.getOrDefault(0) * 100 / max,
                Build.MODEL ?: "phone",
            )
            delay(1000L - System.currentTimeMillis() % 1000L)
        }
    }
    return v
}

@Composable
private fun Status(sys: Sys, modifier: Modifier, big: Boolean) {
    val s = LocalSkin.current
    Column(modifier, horizontalAlignment = if (big) Alignment.End else Alignment.Start) {
        BasicText(sys.time, style = Type.mono(if (big) 26 else 20, .06).copy(color = s.fg, fontFeatureSettings = "tnum"))
        BasicText(sys.date, style = Type.mono(11, .22).copy(color = s.dim))
        Spacer(Modifier.height(6.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Dot("NET", sys.net, s)
            BasicText("BAT ${sys.battery}${if (sys.charging) "+" else ""}", style = Type.mono(10, .14).copy(color = if (sys.battery <= 15 && !sys.charging) s.bad else s.dim))
            BasicText("VOL ${sys.vol}", style = Type.mono(10, .14).copy(color = s.dim))
        }
    }
}

@Composable
private fun Dot(label: String, ok: Boolean, s: Skin) {
    Row {
        BasicText("$label ", style = Type.mono(10, .14).copy(color = s.dim))
        BasicText("●", style = Type.mono(10, .14).copy(color = if (ok) s.ok else s.bad))
    }
}

@Composable
private fun Wordmark(skinId: String, modifier: Modifier) {
    val s = LocalSkin.current
    Column(modifier, horizontalAlignment = Alignment.End) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            BasicText("[", style = Type.ui(34).copy(color = s.dim))
            BasicText(" ULTIMIT ", style = Type.display(34, .14).copy(color = s.fg), softWrap = false)
            BasicText("]", style = Type.ui(34).copy(color = s.dim))
        }
        BasicText("OPERATING SYSTEM · ${skinId.uppercase()}", style = Type.mono(10, .5).copy(color = s.dim))
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun Ticker(modifier: Modifier, sys: Sys) {
    val s = LocalSkin.current
    val notifs by Feeds.notifs.collectAsState()
    val hm = remember { SimpleDateFormat("HH:mm", Locale.US) }
    val items = if (notifs.isNotEmpty()) notifs.take(12).map { hm.format(Date(it.time)) to "${it.app} — ${it.title.ifBlank { it.text }}" }
    else listOf(
        sys.time.take(5) to "Ultimit 0.1 “Mine” running on ${sys.model}",
        "BAT" to "${sys.battery}% battery${if (sys.charging) ", charging" else ""}",
        "NET" to if (sys.net) "Connected" else "Offline",
    )
    Row(modifier.fillMaxWidth().height(26.dp).background(s.rail).drawBehind { drawLine(s.line, Offset(0f, 0f), Offset(size.width, 0f), 1f) }, verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.fillMaxHeight().background(s.accent).padding(start = 16.dp, end = 12.dp), contentAlignment = Alignment.Center) {
            BasicText("NEWS", style = Type.mono(11, .2).copy(color = s.onAccent))
        }
        val text = androidx.compose.ui.text.buildAnnotatedString {
            items.forEachIndexed { i, (t, h) ->
                if (i > 0) append("     ◆     ")
                pushStyle(androidx.compose.ui.text.SpanStyle(color = s.fg)); append(t); pop()
                append("  "); append(h)
            }
        }
        BasicText(
            text, maxLines = 1, softWrap = false,
            style = Type.mono(11, .08).copy(color = s.dim),
            modifier = Modifier.weight(1f).padding(start = 16.dp).basicMarquee(iterations = Int.MAX_VALUE, velocity = 40.dp),
        )
    }
}

// ---------- boot ----------

@Composable
private fun Boot(skin: Skin, dual: Boolean, onDone: () -> Unit) {
    val emb = remember { Animatable(0f) }
    val word = remember { Animatable(0f) }
    val fade = remember { Animatable(1f) }
    val lines = remember { mutableStateListOf<String>() }
    val scope = rememberCoroutineScope()
    var done by remember { mutableStateOf(false) }
    fun end() { if (done) return; done = true; scope.launch { fade.animateTo(0f, tween(600)); onDone() } }
    val all = remember {
        fun row(k: String, v: String) = (k + " " + v).let { it + " " + ".".repeat(max(3, 38 - it.length)) + " ok" }
        listOf(
            row("kernel", System.getProperty("os.version")?.substringBefore('-') ?: "linux"),
            row("android", "${Build.VERSION.RELEASE} (sdk ${Build.VERSION.SDK_INT})"),
            row("device", "${Build.MANUFACTURER} ${Build.MODEL}".trim()),
            row("soc", if (Build.VERSION.SDK_INT >= 31) Build.SOC_MODEL else Build.HARDWARE),
            row("posture", if (dual) "dual screen, hinge" else "single screen"),
            row("shell", "compose ui"),
            row("skin", skin.id),
        )
    }
    LaunchedEffect(Unit) {
        launch { emb.animateTo(1f, tween(1400)) }
        launch { delay(1100); word.animateTo(1f, tween(600)) }
        delay(500)
        for (l in all) { lines.add(l); delay(260) }
        delay(800)
        end()
    }
    Box(
        Modifier.fillMaxSize().graphicsLayer { alpha = fade.value }.background(Color.Black)
            .pointerInput(Unit) { detectTapGestures { end() } },
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp), modifier = Modifier.padding(16.dp)) {
            Emblem(84.dp, Color(0xFFE9EDF2), stroke = 1.2f, progress = emb.value)
            BasicText("[ ULTIMIT ]", style = Type.display(30, .2).copy(color = Color(0xFFE9EDF2).copy(alpha = word.value)))
            BasicText(
                lines.joinToString("\n"),
                style = Type.mono(11, 0.0).copy(color = Color(0xFF8D949E), lineHeight = 1.7.em),
                modifier = Modifier.widthIn(max = 420.dp).fillMaxWidth().height(150.dp),
            )
        }
    }
}

// ---------- helpers ----------

/** Pulls down the notification shade. Tries the platform call, then root. */
suspend fun expandNotifications(ctx: Context) {
    val ok = runCatching {
        @Suppress("WrongConstant")
        val sb = ctx.getSystemService("statusbar")
        Class.forName("android.app.StatusBarManager").getMethod("expandNotificationsPanel").invoke(sb)
    }.isSuccess
    if (!ok) Root.expandNotifications()
}
