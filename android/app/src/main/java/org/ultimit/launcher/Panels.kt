package org.ultimit.launcher

import android.content.Context
import android.content.Intent
import android.os.Environment
import android.os.StatFs
import android.provider.Settings as AndroidSettings
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.offset
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.sin

/** Everything a panel needs to read state or act. */
class Ui(
    val repo: AppRepository,
    val settings: Settings,
    val media: MediaFeed,
    val openWindow: (String) -> Unit,
    val playBoot: () -> Unit,
)

const val ALL = "all"

fun windowTitle(id: String) = Cat.of(id)?.title ?: "Apps"

@Composable
fun windowSub(id: String, ui: Ui): String {
    val apps by ui.repo.apps.collectAsState()
    val notifs by Feeds.notifs.collectAsState()
    val n = apps.count { it.cat.id == id }
    return when (Cat.of(id)) {
        Cat.GAMES -> "Library · $n titles"
        Cat.MAILER -> "Inbox · ${notifs.count { isMail(it, apps) }} new"
        Cat.NEWS -> "Feed · ${notifs.size} items"
        Cat.AUDIO -> "BGM player"
        Cat.DATA -> "/storage · $n apps"
        Cat.ACCESSORY -> "Look & system"
        null -> "${apps.size} installed"
    }
}

private fun isMail(n: Notif, apps: List<AppEntry>) =
    n.category == android.app.Notification.CATEGORY_EMAIL ||
        n.category == android.app.Notification.CATEGORY_MESSAGE ||
        apps.any { it.pkg == n.pkg && it.cat == Cat.MAILER }

@Composable
fun PanelContent(id: String, ui: Ui) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val w = maxWidth
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            when (Cat.of(id)) {
                Cat.GAMES -> GamesPanel(ui, w)
                Cat.MAILER -> MailerPanel(ui, w)
                Cat.NEWS -> NewsPanel(ui, w)
                Cat.AUDIO -> AudioPanel(ui, w)
                Cat.DATA -> DataPanel(ui, w)
                Cat.ACCESSORY -> AccessoryPanel(ui, w)
                null -> AllPanel(ui, w)
            }
        }
    }
}

@Composable
private fun appsIn(ui: Ui, cat: Cat): List<AppEntry> {
    val apps by ui.repo.apps.collectAsState()
    return apps.filter { it.cat == cat }
}

@Composable
private fun AppGrid(ui: Ui, apps: List<AppEntry>, w: androidx.compose.ui.unit.Dp, empty: String) {
    val s = LocalSkin.current
    if (apps.isEmpty()) BasicText(empty, style = Type.ui(12).copy(color = s.dim))
    else TileGrid(apps, minCell = 76.dp, maxWidth = w - 32.dp) { app, m -> AppTile(app, ui.repo, modifier = m) }
}

// ---------- GAMES ----------

private fun hours(ms: Long) = if (ms < 3_600_000) "${ms / 60_000} min" else "${ms / 3_600_000} h"
private fun ago(t: Long): String {
    if (t <= 0) return "Never"
    val d = (System.currentTimeMillis() - t) / 86_400_000
    return when { d < 1 -> "Today"; d < 2 -> "Yesterday"; else -> SimpleDateFormat("MMM dd", Locale.US).format(Date(t)) }
}

@Composable
private fun GamesPanel(ui: Ui, w: androidx.compose.ui.unit.Dp) {
    val s = LocalSkin.current
    val games = appsIn(ui, Cat.GAMES)
    val usage by ui.repo.usage.collectAsState()
    val total = games.sumOf { usage[it.pkg]?.totalMs ?: 0L }
    val sorted = games.sortedByDescending { usage[it.pkg]?.lastUsed ?: 0L }
    Lbl("Library", "${games.size} titles" + if (usage.isNotEmpty()) " · ${hours(total)}" else "")
    if (games.isEmpty()) {
        BasicText("No games found. Long-press any app and choose Move to rail → Games.", style = Type.ui(12).copy(color = s.dim))
        return
    }
    var sel by remember { mutableStateOf(sorted.first().key) }
    val g = sorted.firstOrNull { it.key == sel } ?: sorted.first()
    val wide = w >= 560.dp
    if (wide) {
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            Box(Modifier.weight(1f)) {
                TileGrid(sorted, minCell = 96.dp, maxWidth = (w - 48.dp) * 0.44f) { app, m -> GameTile(app, app.key == sel, m) { sel = app.key } }
            }
            Box(Modifier.weight(1.3f)) { GameDetail(ui, g, usage[g.pkg]) }
        }
    } else {
        GameDetail(ui, g, usage[g.pkg])
        TileGrid(sorted, minCell = 92.dp, maxWidth = w - 32.dp) { app, m -> GameTile(app, app.key == sel, m) { sel = app.key } }
    }
    if (!ui.repo.hasUsageAccess()) UsageAccessRow(ui)
}

@Composable
private fun GameTile(app: AppEntry, selected: Boolean, m: Modifier, onClick: () -> Unit) {
    val s = LocalSkin.current
    Box(
        m.aspectRatio(3f / 4f)
            .then(if (selected) Modifier.border(2.dp, s.accent) else Modifier.border(1.dp, s.line))
            .background(s.panel2)
            .clickable(onClick = onClick),
    ) {
        // Blown-up, blurred icon as cover art, then the crisp icon on top.
        Image(app.icon, null, Modifier.fillMaxSize().blur(24.dp), contentScale = ContentScale.Crop, alpha = .7f)
        Image(app.icon, app.label, Modifier.size(44.dp).align(Alignment.Center))
        Box(
            Modifier.align(Alignment.BottomStart).fillMaxWidth()
                .background(Brush.verticalGradient(listOf(Color.Transparent, Color(0, 0, 0, 200))))
                .padding(start = 8.dp, end = 8.dp, top = 18.dp, bottom = 8.dp)
        ) {
            BasicText(app.label, maxLines = 2, overflow = TextOverflow.Ellipsis, style = Type.ui(12, FontWeight.SemiBold).copy(color = Color.White, lineHeight = Type.tight))
        }
    }
}

@Composable
private fun GameDetail(ui: Ui, g: AppEntry, u: Usage?) {
    val s = LocalSkin.current
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.fillMaxWidth().height(110.dp).border(1.dp, s.line)) {
            Image(g.icon, null, Modifier.fillMaxSize().blur(40.dp), contentScale = ContentScale.Crop, alpha = .8f)
            Image(g.icon, null, Modifier.padding(start = 16.dp).size(64.dp).align(Alignment.CenterStart))
        }
        BasicText(g.label, style = Type.display(16, .03).copy(color = s.fg))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Chip("Android", s.ok)
            if (g.isWork) Chip("Work", s.warn)
            if (g.cat != g.autoCat) Chip("Pinned", s.dim)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Column { BasicText("PLAYED", style = Type.mono(10, .14).copy(color = s.dim)); BasicText(u?.let { hours(it.totalMs) } ?: "—", style = Type.ui(12).copy(color = s.fg)) }
            Column { BasicText("LAST", style = Type.mono(10, .14).copy(color = s.dim)); BasicText(u?.let { ago(it.lastUsed) } ?: "—", style = Type.ui(12).copy(color = s.fg)) }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            UBtn("Launch", primary = true) { ui.repo.launch(g) }
            UBtn("App info") { ui.repo.openInfo(g) }
        }
    }
}

@Composable
private fun UsageAccessRow(ui: Ui) {
    val s = LocalSkin.current
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        BasicText("Play time needs usage access.", style = Type.ui(12).copy(color = s.dim))
        UBtn("Grant usage access") {
            scope.launch {
                if (Root.available() && Root.grantUsage(ctx).ok) { ui.repo.refresh(); Toasts.show("Games", "Usage access granted.") }
                else ctx.startActivity(Intent(AndroidSettings.ACTION_USAGE_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
        }
    }
}

// ---------- MAILER / NEWS (notification-backed) ----------

@Composable
private fun ListenerGate(ui: Ui, what: String) {
    val s = LocalSkin.current
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val connected by Feeds.connected.collectAsState()
    if (connected) return
    Column(Modifier.fillMaxWidth().border(1.dp, s.line).padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        BasicText("$what needs notification access.", style = Type.ui(13).copy(color = s.fg))
        UBtn("Enable") {
            scope.launch {
                if (Root.available() && Root.grantListener(ctx).ok) { Toasts.show("Feeds", "Notification access granted."); ui.media.start() }
                else ctx.startActivity(Intent(AndroidSettings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
        }
    }
}

private val hm = SimpleDateFormat("HH:mm", Locale.US)
private fun stamp(t: Long): String {
    val d = (System.currentTimeMillis() - t) / 86_400_000
    return if (d < 1) hm.format(Date(t)) else if (d < 2) "Yday" else SimpleDateFormat("MMM dd", Locale.US).format(Date(t))
}

@Composable
private fun NotifRow(n: Notif, mail: Boolean) {
    val s = LocalSkin.current
    Column(Modifier.fillMaxWidth()) {
        Row(
            Modifier.fillMaxWidth().clickable { Feeds.open(n) }.padding(horizontal = 6.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            if (mail) Box(Modifier.padding(top = 6.dp).size(6.dp).background(s.accent))
            else BasicText(stamp(n.time), style = Type.mono(11, .04).copy(color = s.dim), modifier = Modifier.width(44.dp))
            Column(Modifier.weight(1f)) {
                BasicText(if (mail) n.title.ifBlank { n.app } else n.title.ifBlank { n.app }, maxLines = 1, overflow = TextOverflow.Ellipsis, style = Type.ui(13, FontWeight.SemiBold).copy(color = s.fg))
                BasicText(
                    if (mail) "${n.app} · ${n.text}" else n.text, maxLines = 2, overflow = TextOverflow.Ellipsis,
                    style = Type.ui(12).copy(color = s.dim),
                )
            }
            Column(horizontalAlignment = Alignment.End) {
                if (mail) BasicText(stamp(n.time), style = Type.mono(11, .04).copy(color = s.dim))
                BasicText("[×]", style = Type.mono(12, 0.0).copy(color = s.dim), modifier = Modifier.clickable { Feeds.dismiss(n) }.padding(4.dp))
            }
        }
        Rule()
    }
}

@Composable
private fun MailerPanel(ui: Ui, w: androidx.compose.ui.unit.Dp) {
    val s = LocalSkin.current
    val apps by ui.repo.apps.collectAsState()
    val notifs by Feeds.notifs.collectAsState()
    val mail = notifs.filter { isMail(it, apps) }
    ListenerGate(ui, "The inbox")
    Lbl("Inbox", "${mail.size} new")
    Column { Rule(); if (mail.isEmpty()) BasicText("Nothing new.", style = Type.ui(12).copy(color = s.dim), modifier = Modifier.padding(vertical = 10.dp)); mail.forEach { NotifRow(it, mail = true) } }
    Lbl("Clients")
    AppGrid(ui, appsIn(ui, Cat.MAILER), w, "No mail or messaging apps found.")
}

@Composable
private fun NewsPanel(ui: Ui, w: androidx.compose.ui.unit.Dp) {
    val s = LocalSkin.current
    val apps by ui.repo.apps.collectAsState()
    val notifs by Feeds.notifs.collectAsState()
    val feed = notifs.filterNot { isMail(it, apps) }
    ListenerGate(ui, "The feed")
    val top = feed.firstOrNull()
    // Featured card: the newest item, over a slice of the wallpaper.
    Box(Modifier.fillMaxWidth().height(150.dp).border(1.dp, s.line).background(Brush.linearGradient(listOf(s.bg1, s.bg2))).clickable(enabled = top != null) { top?.let(Feeds::open) }) {
        Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().background(Brush.verticalGradient(listOf(Color.Transparent, Color(0, 0, 0, 153)))).padding(16.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                BasicText((top?.let { "${it.app} · ${stamp(it.time)}" } ?: "Ultimit · now").uppercase(), style = Type.mono(10, .2).copy(color = Color.White.copy(alpha = .8f)))
                BasicText(top?.let { it.title.ifBlank { it.text } } ?: "Ultimit 0.1 “Mine” is running on this phone", maxLines = 2, overflow = TextOverflow.Ellipsis, style = Type.display(15, .02).copy(color = Color.White))
            }
        }
    }
    Lbl("Latest", "${feed.size}")
    Column { Rule(); feed.drop(1).take(40).forEach { NotifRow(it, mail = false) } }
    Lbl("Readers")
    AppGrid(ui, appsIn(ui, Cat.NEWS), w, "No news or browser apps found.")
}

// ---------- AUDIO ----------

@Composable
private fun AudioPanel(ui: Ui, w: androidx.compose.ui.unit.Dp) {
    val s = LocalSkin.current
    val now by ui.media.now.collectAsState()
    ListenerGate(ui, "Now playing")
    LaunchedEffect(Unit) { ui.media.start() }
    Viz(playing = now?.playing == true)
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        val art = now?.art
        Box(Modifier.size(56.dp).border(1.dp, s.line).background(s.panel2)) {
            if (art != null) Image(art.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            else Icon("audio", 28.dp, s.dim, modifier = Modifier.align(Alignment.Center))
        }
        Column(Modifier.weight(1f)) {
            BasicText(now?.title ?: "Nothing playing", maxLines = 1, overflow = TextOverflow.Ellipsis, style = Type.ui(14, FontWeight.SemiBold).copy(color = s.fg))
            BasicText(listOfNotNull(now?.artist?.ifBlank { null }, now?.app).joinToString(" · ").ifBlank { "Start music in any player" }, maxLines = 1, overflow = TextOverflow.Ellipsis, style = Type.mono(11, .06).copy(color = s.dim))
        }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        UBtn("Prev") { ui.media.prev() }
        UBtn(if (now?.playing == true) "Pause" else "Play", primary = true) { ui.media.toggle() }
        UBtn("Next") { ui.media.next() }
    }
    Lbl("Players")
    AppGrid(ui, appsIn(ui, Cat.AUDIO), w, "No music or video apps found.")
}

/** Decorative spectrum bars, like the mockup's visualizer. Real audio capture would need mic permission. */
@Composable
private fun Viz(playing: Boolean) {
    val s = LocalSkin.current
    var t by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(playing) {
        val start = withFrameMillis { it }
        while (true) withFrameMillis { t = (it - start).toFloat() }
    }
    Canvas(Modifier.fillMaxWidth().height(110.dp).border(1.dp, s.line)) {
        val n = 48; val bw = size.width / n
        for (i in 0 until n) {
            val v = if (playing) {
                val a = sin(i * .55f + t / 180f) * .5f + .5f
                val b = sin(i * 1.7f - t / 260f) * .5f + .5f
                ((a * b) * (1f - i / (n * 1.4f)) + .05f).coerceIn(0f, 1f)
            } else .04f + .03f * sin(i * .7f + t / 900f)
            val bh = maxOf(2f, v * (size.height - 12f))
            drawRect(s.accent.copy(alpha = .35f + v * .65f), androidx.compose.ui.geometry.Offset(i * bw + 1f, size.height - bh - 6f), androidx.compose.ui.geometry.Size(bw - 3f, bh))
        }
    }
}

// ---------- DATA ----------

@Composable
private fun DataPanel(ui: Ui, w: androidx.compose.ui.unit.Dp) {
    val s = LocalSkin.current
    val stat = remember { runCatching { StatFs(Environment.getDataDirectory().path) }.getOrNull() }
    BasicText("/ storage / emulated / 0", style = Type.mono(12, .06).copy(color = s.fg))
    Lbl("Apps")
    AppGrid(ui, appsIn(ui, Cat.DATA), w, "No file or productivity apps found.")
    if (stat != null) {
        val total = stat.totalBytes; val used = total - stat.availableBytes
        val gb = { b: Long -> "%.0f GB".format(b / 1e9) }
        BasicText("DISK · ${gb(used)} OF ${gb(total)} USED", style = Type.mono(10, .18).copy(color = s.dim))
        Box(Modifier.fillMaxWidth().height(6.dp).background(s.panel2).border(1.dp, s.line)) {
            Box(Modifier.fillMaxWidth((used.toFloat() / total).coerceIn(0f, 1f)).height(6.dp).background(s.accent))
        }
    }
}

// ---------- ACCESSORY ----------

@Composable
private fun AccessoryPanel(ui: Ui, w: androidx.compose.ui.unit.Dp) {
    val s = LocalSkin.current
    val st = ui.settings
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var root by remember { mutableStateOf<Boolean?>(null) }
    LaunchedEffect(Unit) { root = Root.available() }

    Lbl("Skin")
    TileGrid(Skins, minCell = 110.dp, maxWidth = w - 32.dp, spacing = 10.dp) { sk, m ->
        Column(
            m.then(if (sk.id == st.skin) Modifier.border(2.dp, s.accent) else Modifier.border(1.dp, s.line))
                .clickable { applySkinChoice(ctx, ui, sk.id, scope) },
        ) {
            Box(Modifier.fillMaxWidth().height(56.dp).background(Brush.linearGradient(listOf(sk.bg1, sk.bg2)))) {
                Box(Modifier.width(10.dp).height(56.dp).background(sk.accent))
            }
            BasicText(sk.name.uppercase(), style = Type.ui(11, FontWeight.SemiBold, .16).copy(color = s.fg), modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp))
        }
    }

    Lbl("Wallpaper")
    Tog("Animate shards", st.motion) { st.updateMotion(it) }
    Column {
        BasicText("SHARD COUNT · ${st.density}", style = Type.mono(10, .18).copy(color = s.dim))
        SquareSlider(st.density.toFloat(), 16f..60f) { st.updateDensity(it.toInt()) }
    }

    Lbl("Shell")
    Tog("News ticker", st.ticker) { st.updateTicker(it) }
    Tog("Boot sequence on start", st.bootOnStart) { st.updateBootOnStart(it) }

    Lbl("System", if (root == true) "root ok" else if (root == false) "no root" else "")
    Tog(
        "Match Android colors to skin", st.rootSync,
        sub = "Quick settings, notifications and Material You apps follow the skin (root)",
    ) { on ->
        st.updateRootSync(on)
        scope.launch {
            val r = if (on) Root.applySkin(skinById(st.skin), st.syncNight) else Root.resetPalette()
            Toasts.show("Accessory", if (r.ok) (if (on) "System colors set to ${skinById(st.skin).name}." else "System colors reset.") else "Root refused: ${r.out.take(80)}")
        }
    }
    if (st.rootSync) Tog("Match dark / light mode", st.syncNight, sub = "Silver switches Android to light, the rest to dark") { on ->
        st.updateSyncNight(on); scope.launch { Root.applySkin(skinById(st.skin), on) }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        UBtn("Play boot") { ui.playBoot() }
        UBtn("Set up (root)") {
            scope.launch {
                val r = Root.setUp(ctx)
                if (r.ok) { Toasts.show("Accessory", "Default home, notification and usage access set."); ui.repo.refresh(); ui.media.start() }
                else { Toasts.show("Accessory", "No root. Opening home settings."); ctx.startActivity(Intent(AndroidSettings.ACTION_HOME_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
            }
        }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        UBtn("Android settings") { ctx.startActivity(Intent(AndroidSettings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
        UBtn("All apps") { ui.openWindow(ALL) }
    }

    Lbl("Tools")
    AppGrid(ui, appsIn(ui, Cat.ACCESSORY), w, "Nothing here yet.")
    BasicText(
        "Ultimit for Android. The look is a tribute to Altimit OS from the .hack games by CyberConnect2. " +
            "The name is a fan homage; the emblem and art are original. Long-press any app to move it between rails.",
        style = Type.ui(12).copy(color = s.dim, lineHeight = 1.6.em),
    )
}

fun applySkinChoice(ctx: Context, ui: Ui, id: String, scope: kotlinx.coroutines.CoroutineScope) {
    ui.settings.updateSkin(id)
    if (ui.settings.rootSync) scope.launch {
        val r = Root.applySkin(skinById(id), ui.settings.syncNight)
        if (!r.ok) Toasts.show("Accessory", "Couldn't set system colors: ${r.out.take(80)}")
    }
}

/** Minimal square slider in skin colors. Tap or drag anywhere on the track. */
@Composable
fun SquareSlider(value: Float, range: ClosedFloatingPointRange<Float>, onChange: (Float) -> Unit) {
    val s = LocalSkin.current
    var widthPx by remember { mutableFloatStateOf(1f) }
    val frac = ((value - range.start) / (range.endInclusive - range.start)).coerceIn(0f, 1f)
    val set = { x: Float -> onChange(range.start + (x / widthPx).coerceIn(0f, 1f) * (range.endInclusive - range.start)) }
    val thumb = 12.dp
    Box(
        Modifier.fillMaxWidth().height(28.dp)
            .onSizeChanged { widthPx = it.width.toFloat().coerceAtLeast(1f) }
            .pointerInput(Unit) { detectTapGestures { set(it.x) } }
            .pointerInput(Unit) { detectHorizontalDragGestures { change, _ -> change.consume(); set(change.position.x) } },
        contentAlignment = Alignment.CenterStart,
    ) {
        Box(Modifier.fillMaxWidth().height(2.dp).background(s.line))
        Box(Modifier.fillMaxWidth(frac).height(2.dp).background(s.accent))
        Box(
            Modifier
                .offset { IntOffset(((widthPx - thumb.toPx()) * frac).toInt(), 0) }
                .size(thumb).background(s.accent)
        )
    }
}

// ---------- ALL APPS ----------

@Composable
private fun AllPanel(ui: Ui, w: androidx.compose.ui.unit.Dp) {
    val s = LocalSkin.current
    val apps by ui.repo.apps.collectAsState()
    var q by remember { mutableStateOf("") }
    Row(Modifier.fillMaxWidth().border(1.dp, s.line).background(s.panel2).padding(horizontal = 10.dp, vertical = 9.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon("search", 16.dp, s.dim)
        Spacer(Modifier.width(8.dp))
        Box(Modifier.weight(1f)) {
            if (q.isEmpty()) BasicText("SEARCH", style = Type.mono(12, .18).copy(color = s.dim))
            BasicTextField(
                q, { q = it }, singleLine = true,
                textStyle = Type.ui(14).copy(color = s.fg), cursorBrush = SolidColor(s.accent),
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
    val list = if (q.isBlank()) apps else apps.filter { it.label.contains(q, true) || it.pkg.contains(q, true) }
    Lbl("Installed", "${list.size}")
    TileGrid(list, minCell = 76.dp, maxWidth = w - 32.dp) { app, m -> AppTile(app, ui.repo, modifier = m) }
}
