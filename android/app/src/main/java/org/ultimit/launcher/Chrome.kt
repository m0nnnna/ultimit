package org.ultimit.launcher

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

// Shared building blocks: labels, chamfered buttons, chips, toggles, icons, emblem,
// toasts and the long-press menu. All read colors from LocalSkin.

/** Rail and panel icons, copied path-for-path from the mockup's `I` table (24x24 viewbox). */
object Icons {
    private val d = mapOf(
        "games" to "M3 9l3-3h12l3 3v6l-3 3h-3l-2-2h-2l-2 2H6l-3-3z M8 10v4M6 12h4M15.5 11h.01M17.5 13h.01",
        "mailer" to "M3 6h18v12H3z M3 6l9 7 9-7",
        "news" to "M4 4h16v16H4z M8 16V8l8 8V8",
        "audio" to "M3 12h2M7 8v8M11 4v16M15 9v6M19 11v2",
        "data" to "M12 3l8 4.5v9L12 21l-8-4.5v-9z M4 7.5l8 4.5 8-4.5M12 12v9",
        "accessory" to "M12 3l9 16H3z M12 9.5l3.5 6.5h-7z",
        "folder" to "M3 6h7l2 2h9v11H3z",
        "file" to "M6 3h9l4 4v14H6z M15 3v4h4",
        "play" to "M8 5l11 7-11 7z",
        "pause" to "M7 5h3v14H7z M14 5h3v14h-3z",
        "next" to "M6 5l9 7-9 7z M17 5v14",
        "prev" to "M18 5l-9 7 9 7z M7 5v14",
        "apps" to "M4 4h6v6H4z M14 4h6v6h-6z M4 14h6v6H4z M14 14h6v6h-6z",
        "search" to "M10.5 4a6.5 6.5 0 1 0 0 13a6.5 6.5 0 1 0 0-13z M15.5 15.5L20 20",
        "bell" to "M6 16V10a6 6 0 0 1 12 0v6l2 2H4z M10 20h4",
    )
    private val cache = HashMap<String, Path>()
    fun path(k: String): Path = cache.getOrPut(k) { PathParser().parsePathString(d[k] ?: d.getValue("file")).toPath() }
}

@Composable
fun Icon(name: String, size: Dp = 24.dp, color: Color = LocalSkin.current.fg, stroke: Float = 1.5f, modifier: Modifier = Modifier) {
    val p = Icons.path(name)
    Canvas(modifier.size(size)) {
        val s = this.size.minDimension / 24f
        scale(s, s, pivot = Offset.Zero) {
            drawPath(p, color, style = Stroke(width = stroke, join = StrokeJoin.Miter))
        }
    }
}

/** The six-spoke hexagon emblem from the mockup. [progress] < 1 draws it partially (boot). */
@Composable
fun Emblem(size: Dp, color: Color = LocalSkin.current.fg, stroke: Float = 1.6f, progress: Float = 1f, modifier: Modifier = Modifier) {
    Canvas(modifier.size(size)) {
        val k = this.size.minDimension / 48f
        val c = 24f; val outer = 20f; val inner = 8.5f
        fun p(rad: Float, i: Int, off: Float): Offset {
            val a = i * PI.toFloat() / 3 - PI.toFloat() / 2 + off
            return Offset((c + rad * cos(a)) * k, (c + rad * sin(a)) * k)
        }
        val o = (0 until 6).map { p(outer, it, 0f) }
        val n = (0 until 6).map { p(inner, it, .35f) }
        val path = Path().apply {
            moveTo(o[0].x, o[0].y); for (i in 1 until 6) lineTo(o[i].x, o[i].y); close()
            for (i in 0 until 6) { moveTo(o[i].x, o[i].y); lineTo(n[(i + 1) % 6].x, n[(i + 1) % 6].y) }
            moveTo(n[0].x, n[0].y); for (i in 1 until 6) lineTo(n[i].x, n[i].y); close()
        }
        val st = Stroke(width = stroke * k, join = StrokeJoin.Miter)
        if (progress >= 1f) drawPath(path, color, style = st)
        else {
            val pm = androidx.compose.ui.graphics.PathMeasure()
            // Draw each sub-path partially, like the mockup's stroke-dashoffset animation.
            // PathMeasure only measures one contour, so every stroke is its own path.
            val parts = listOf(
                Path().apply { moveTo(o[0].x, o[0].y); for (i in 1 until 6) lineTo(o[i].x, o[i].y); close() },
                Path().apply { moveTo(n[0].x, n[0].y); for (i in 1 until 6) lineTo(n[i].x, n[i].y); close() },
            ) + (0 until 6).map { i -> Path().apply { moveTo(o[i].x, o[i].y); lineTo(n[(i + 1) % 6].x, n[(i + 1) % 6].y) } }
            for (part in parts) {
                pm.setPath(part, false)
                val seg = Path()
                pm.getSegment(0f, pm.length * progress.coerceIn(0f, 1f), seg, true)
                drawPath(seg, color, style = st)
            }
        }
    }
}

/** Mono, tracked, uppercase section label with the accent square, like `.lbl`. */
@Composable
fun Lbl(text: String, trailing: String? = null, modifier: Modifier = Modifier) {
    val s = LocalSkin.current
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(6.dp).background(s.accent))
        Spacer(Modifier.width(8.dp))
        BasicText(text.uppercase(), style = Type.mono(10, .22).copy(color = s.dim))
        Spacer(Modifier.weight(1f))
        if (trailing != null) BasicText(trailing, style = Type.mono(10, .1).copy(color = s.dim))
    }
}

/** The chamfered corner cut used by `.btn`: top-left and bottom-right corners clipped. */
class Chamfer(private val cut: Dp) : androidx.compose.ui.graphics.Shape {
    override fun createOutline(
        size: androidx.compose.ui.geometry.Size,
        layoutDirection: androidx.compose.ui.unit.LayoutDirection,
        density: androidx.compose.ui.unit.Density,
    ): androidx.compose.ui.graphics.Outline {
        val c = with(density) { cut.toPx() }
        val p = Path().apply {
            moveTo(c, 0f); lineTo(size.width, 0f); lineTo(size.width, size.height - c)
            lineTo(size.width - c, size.height); lineTo(0f, size.height); lineTo(0f, c); close()
        }
        return androidx.compose.ui.graphics.Outline.Generic(p)
    }
}

fun chamfer(cut: Dp) = Chamfer(cut)

@Composable
fun UBtn(text: String, primary: Boolean = false, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val s = LocalSkin.current
    val shape = chamfer(8.dp)
    Box(
        modifier
            .clip(shape)
            .then(if (primary) Modifier.background(s.accent) else Modifier.border(1.dp, s.lineStrong, shape))
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        BasicText(text.uppercase(), style = Type.ui(11, FontWeight.SemiBold, .16).copy(color = if (primary) s.onAccent else s.fg))
    }
}

@Composable
fun Chip(text: String, color: Color) {
    Box(Modifier.border(1.dp, color).padding(horizontal = 7.dp, vertical = 2.dp)) {
        BasicText(text.uppercase(), style = Type.mono(10, .12).copy(color = color))
    }
}

/** Square toggle row, `.tog` in the mockup. */
@Composable
fun Tog(label: String, checked: Boolean, sub: String? = null, onChange: (Boolean) -> Unit) {
    val s = LocalSkin.current
    Column(Modifier.fillMaxWidth()) {
        Row(
            Modifier.fillMaxWidth().clickable { onChange(!checked) }.padding(vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                BasicText(label, style = Type.ui(14).copy(color = s.fg))
                if (sub != null) BasicText(sub, style = Type.ui(11).copy(color = s.dim))
            }
            Box(Modifier.size(34.dp, 16.dp).border(1.dp, s.lineStrong).padding(2.dp)) {
                Box(
                    Modifier.size(10.dp).align(if (checked) Alignment.CenterEnd else Alignment.CenterStart)
                        .background(if (checked) s.accent else s.dim)
                )
            }
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(s.line))
    }
}

/** Accent corner brackets top-left and bottom-right, `.win::before/::after`. */
fun Modifier.brackets(color: Color, len: Dp = 14.dp, width: Dp = 2.dp) = drawWithContent {
    drawContent()
    val l = len.toPx(); val w = width.toPx()
    drawRect(color, Offset(0f, 0f), androidx.compose.ui.geometry.Size(l, w))
    drawRect(color, Offset(0f, 0f), androidx.compose.ui.geometry.Size(w, l))
    drawRect(color, Offset(size.width - l, size.height - w), androidx.compose.ui.geometry.Size(l, w))
    drawRect(color, Offset(size.width - w, size.height - l), androidx.compose.ui.geometry.Size(w, l))
}

/** A one-pixel divider in the skin's line color. */
@Composable
fun Rule(strong: Boolean = false) {
    val s = LocalSkin.current
    Box(Modifier.fillMaxWidth().height(1.dp).background(if (strong) s.lineStrong else s.line))
}

// ---------- toasts ----------

data class ToastMsg(val id: Long, val title: String, val msg: String)

object Toasts {
    val items = mutableStateListOf<ToastMsg>()
    private var n = 0L
    fun show(title: String, msg: String) {
        val t = ToastMsg(++n, title, msg)
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            items.add(t)
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({ items.remove(t) }, 4200)
        }
    }
}

@Composable
fun ToastView(t: ToastMsg) {
    val s = LocalSkin.current
    Row(Modifier.widthIn(max = 340.dp).fillMaxWidth().background(s.panel).border(1.dp, s.lineStrong)) {
        Box(Modifier.width(3.dp).height(56.dp).background(s.accent))
        Column(Modifier.padding(horizontal = 14.dp, vertical = 10.dp)) {
            BasicText(t.title.uppercase(), style = Type.mono(10, .2).copy(color = s.dim))
            BasicText(t.msg, style = Type.ui(12).copy(color = s.fg))
        }
    }
}

// ---------- app tile + long-press menu ----------

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun AppTile(app: AppEntry, repo: AppRepository, iconSize: Dp = 48.dp, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null) {
    val s = LocalSkin.current
    var menu by remember { mutableStateOf(false) }
    Box(modifier) {
        Column(
            Modifier
                .fillMaxWidth()
                .combinedClickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onClick = { onClick?.invoke() ?: repo.launch(app) },
                    onLongClick = { menu = true },
                )
                .padding(vertical = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Image(app.icon, contentDescription = app.label, modifier = Modifier.size(iconSize))
            Spacer(Modifier.height(6.dp))
            BasicText(
                app.label, maxLines = 2, overflow = TextOverflow.Ellipsis,
                style = Type.ui(11, FontWeight.Medium).copy(color = s.fg, textAlign = androidx.compose.ui.text.style.TextAlign.Center),
                modifier = Modifier.padding(horizontal = 2.dp),
            )
        }
        if (menu) AppMenu(app, repo) { menu = false }
    }
}

@Composable
fun AppMenu(app: AppEntry, repo: AppRepository, onDismiss: () -> Unit) {
    val s = LocalSkin.current
    var moving by remember { mutableStateOf(false) }
    Popup(
        alignment = Alignment.TopCenter, offset = IntOffset(0, 40),
        onDismissRequest = onDismiss, properties = PopupProperties(focusable = true),
    ) {
        Column(Modifier.widthIn(min = 200.dp, max = 260.dp).background(s.panel).border(1.dp, s.lineStrong).brackets(s.accent, 10.dp).padding(6.dp)) {
            BasicText(app.label, style = Type.display(13).copy(color = s.fg), modifier = Modifier.padding(10.dp), maxLines = 1, overflow = TextOverflow.Ellipsis)
            Rule()
            @Composable fun item(t: String, f: () -> Unit) =
                BasicText(t, style = Type.ui(13, FontWeight.Medium, .04).copy(color = s.fg),
                    modifier = Modifier.fillMaxWidth().clickable(onClick = f).padding(horizontal = 10.dp, vertical = 11.dp))
            if (!moving) {
                item("Open") { onDismiss(); repo.launch(app) }
                item("App info") { onDismiss(); repo.openInfo(app) }
                item("Move to rail…") { moving = true }
                item("Uninstall") { onDismiss(); repo.uninstall(app) }
            } else {
                for (c in Cat.entries) item((if (c == app.cat) "■ " else "□ ") + c.title + (if (c == app.autoCat) "  · auto" else "")) {
                    onDismiss(); repo.move(app, c); Toasts.show("Rail", "${app.label} moved to ${c.title}.")
                }
            }
        }
    }
}

/** Fixed-column grid that lays out inside a scrolling Column (no nested lazy lists). */
@Composable
fun <T> TileGrid(items: List<T>, minCell: Dp = 76.dp, maxWidth: Dp, spacing: Dp = 6.dp, cell: @Composable (T, Modifier) -> Unit) {
    val cols = ((maxWidth + spacing) / (minCell + spacing)).toInt().coerceAtLeast(1)
    Column(verticalArrangement = Arrangement.spacedBy(spacing)) {
        for (row in items.chunked(cols)) {
            Row(horizontalArrangement = Arrangement.spacedBy(spacing)) {
                for (it in row) cell(it, Modifier.weight(1f))
                repeat(cols - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}
