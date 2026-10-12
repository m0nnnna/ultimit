package org.ultimit.launcher

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

// Port of the generative shard wallpaper in docs/design/mockup.html (genShards / genHex /
// drawWall). Same seeds, same geometry, so the phone matches the desktop shot for shot.

private class Shard(val a: Float, val r0: Float, val l: Float, val t: Float, val ph: Float, val al: Float)
private class Hex(val x: Float, val y: Float, val al: Float, val f: Float)

/** Deterministic PRNG, a straight port of the mockup's rng() (mulberry32). */
private fun rng(seed0: Int): () -> Float {
    var seed = seed0
    return {
        seed += 0x6D2B79F5
        var t = seed
        t = (t xor (t ushr 15)) * (1 or t)
        t = (t + ((t xor (t ushr 7)) * (61 or t))) xor t
        ((t xor (t ushr 14)).toUInt().toDouble() / 4294967296.0).toFloat()
    }
}

/** Where the shard burst sits and how big it is, in px. */
data class WallGeo(val px: Float, val py: Float, val r: Float, val sc: Float, val ringX: Float, val ringY: Float)

class WallScene(val width: Float, val height: Float, density: Int, private val railPx: Float, private val dp: Float) {
    private val shards = ArrayList<Shard>()
    private val hexes = ArrayList<Hex>()
    private var hexSize = 24f
    val geo: WallGeo

    init {
        val r = rng(7)
        val n = density.coerceIn(8, 80)
        for (i in 0 until n) {
            val k = i / (n - 1f)
            shards += Shard(
                a = -2.95f + k * 2.7f + (r() - .5f) * .08f,
                r0 = .06f + r() * .26f,
                l = (.45f + r() * .55f) * (.55f + .65f * k),
                t = 5f + r() * 17f, ph = r() * 6.28f, al = .55f + r() * .45f,
            )
        }
        repeat((n / 5f).roundToInt()) {
            shards += Shard(.15f + r() * .7f, .1f + r() * .2f, .2f + r() * .3f, 4f + r() * 8f, r() * 6.28f, .25f + r() * .25f)
        }

        // The mockup sizes everything in CSS px; scale by the display density so the
        // phone gets the same visual size rather than tiny shards on a 400 dpi panel.
        val w = width / dp; val h = height / dp
        val rh = rng(11)
        val s = 24f * max(.7f, min(w, h) / 800f)
        val hw = sqrt(3f) * s
        val cx = w * .8f; val cy = h * .2f
        var row = 0
        while (row * s * 1.5f < h * .7f) {
            var col = 0
            while (col * hw < w * .55f + hw) {
                val x = w * .45f + col * hw + (if (row % 2 == 1) hw / 2 else 0f)
                val y = row * s * 1.5f
                val d = hypot(x - cx, y - cy) / (min(w, h) * .5f)
                val al = .24f - d * .2f
                if (al > .02f) hexes += Hex(x * dp, y * dp, al, if (rh() < .1f) rh() * 6.28f else -1f)
                col++
            }
            row++
        }
        hexSize = s * dp

        val rw = railPx
        geo = WallGeo(
            px = rw + (width - rw) * .30f, py = height * .70f,
            r = min(width * .42f, height * .62f),
            sc = max(.6f, min(w, h) / 800f) * dp,
            ringX = width * .8f, ringY = height * .22f,
        )
    }

    fun hexPath(x: Float, y: Float, s: Float) = Path().apply {
        for (i in 0 until 6) {
            val a = PI / 6 + i * PI / 3
            val px = x + s * cos(a).toFloat(); val py = y + s * sin(a).toFloat()
            if (i == 0) moveTo(px, py) else lineTo(px, py)
        }
        close()
    }

    /** Draws the whole wallpaper. [t] is a millisecond clock; [motion] enables the light sweep. */
    fun draw(scope: DrawScope, skin: Skin, t: Float, motion: Boolean) = with(scope) {
        val w = width; val h = height
        drawRect(Brush.linearGradient(listOf(skin.bg1, skin.bg2), start = Offset(0f, h), end = Offset(w * .9f, 0f)), size = Size(w, h))
        drawRect(
            Brush.radialGradient(
                0f to Color.Transparent,
                1f to (if (skin.light) Color(40, 50, 65, 46) else Color(0, 0, 0, 115)),
                center = Offset(w * .5f, h * .5f), radius = max(w, h) * .75f,
            ),
            size = Size(w, h),
        )

        // Hex grid
        val hs = hexSize - 2f * (hexSize / 24f)
        for (x in hexes) {
            val p = hexPath(x.x, x.y, hs)
            drawPath(p, skin.hexc.copy(alpha = x.al), style = Stroke(width = 1f * (hexSize / 24f)))
            if (x.f >= 0 && sin(t * .0012f + x.f * 3) > .85f) drawPath(p, skin.hexc.copy(alpha = x.al * .7f))
        }

        // Rotating ring, top right
        val g = geo
        val rot = t * .00025f
        val ring = skin.hexc
        for (rr in intArrayOf(70, 98, 150)) drawCircle(ring.copy(alpha = .14f), rr * g.sc, Offset(g.ringX, g.ringY), style = Stroke(1f * g.sc / 1.2f))
        val arcR = 120 * g.sc
        val tl = Offset(g.ringX - arcR, g.ringY - arcR); val sz = Size(arcR * 2, arcR * 2)
        val deg = (180 / PI).toFloat()
        drawArc(ring.copy(alpha = .4f), rot * deg, 1.3f * deg, false, tl, sz, style = Stroke(2f * g.sc / 1.2f))
        drawArc(ring.copy(alpha = .4f), (rot + 3.2f) * deg, .4f * deg, false, tl, sz, style = Stroke(2f * g.sc / 1.2f))
        for (i in 0 until 72) {
            val a = i / 72f * 6.283f - rot * .5f
            val l = (if (i % 6 != 0) 4 else 9) * g.sc / 1.2f
            val r0 = 150 * g.sc
            drawLine(
                ring.copy(alpha = .22f),
                Offset(g.ringX + cos(a) * r0, g.ringY + sin(a) * r0),
                Offset(g.ringX + cos(a) * (r0 + l), g.ringY + sin(a) * (r0 + l)),
                strokeWidth = g.sc / 1.2f,
            )
        }

        // Shards
        val sweep = -3.1f + ((t * .00012f) % 1f) * 3.6f
        val sway = sin(t * .00018f) * .02f
        val add = if (skin.light) BlendMode.SrcOver else BlendMode.Plus
        for (s in shards) {
            val ang = s.a + sway + sin(t * .00025f + s.ph) * .012f
            val ux = cos(ang); val uy = sin(ang); val vx = -uy; val vy = ux
            val r0 = s.r0 * g.r; val len = s.l * g.r; val tw = s.t * g.sc
            fun pt(u: Float, v: Float) = Offset(g.px + ux * u + vx * v, g.py + uy * u + vy * v)
            val a = pt(r0, -tw); val b = pt(r0 + len * .92f, -tw * .25f); val c = pt(r0 + len, 0f); val d = pt(r0 + len * .3f, tw)
            val da = ang - sweep
            val boost = if (motion) exp(-(da * da) / .012f) * .4f else 0f
            val mid = ((.55f * s.al + boost) * (if (skin.light) 1f else .8f)).coerceIn(0f, 1f)
            val tip = (.9f * s.al + boost).coerceIn(0f, 1f)
            val brush = Brush.linearGradient(
                0f to skin.shard.copy(alpha = 0f), .55f to skin.shard.copy(alpha = mid), 1f to skin.shard.copy(alpha = tip),
                start = pt(r0, 0f), end = c,
            )
            val body = Path().apply { moveTo(a.x, a.y); lineTo(b.x, b.y); lineTo(c.x, c.y); lineTo(d.x, d.y); close() }
            drawPath(body, brush, blendMode = add)
            val shadow = Path().apply { moveTo(a.x, a.y); lineTo(c.x, c.y); lineTo(d.x, d.y); close() }
            drawPath(shadow, skin.shade.copy(alpha = if (skin.light) .12f else .22f))
            val edge = Path().apply { moveTo(a.x, a.y); lineTo(b.x, b.y); lineTo(c.x, c.y) }
            drawPath(edge, skin.edge.copy(alpha = if (skin.light) .45f else .35f * s.al), style = Stroke(width = .8f * g.sc / 1.2f))
        }
    }
}
