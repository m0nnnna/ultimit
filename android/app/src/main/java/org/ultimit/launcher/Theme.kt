package org.ultimit.launcher

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp

// Design tokens for every skin. Mirrors the :root / [data-skin] blocks in
// docs/design/mockup.html and shell/Theme.qml; keep the three in step.
@Immutable
data class Skin(
    val id: String,
    val name: String,
    val bg1: Color, val bg2: Color,
    val panel: Color, val panel2: Color, val rail: Color,
    val fg: Color, val dim: Color,
    val line: Color, val lineStrong: Color,
    val accent: Color, val onAccent: Color,
    val ok: Color, val warn: Color, val bad: Color,
    // Wallpaper colors; the painter composes its own alphas on top.
    val shard: Color, val edge: Color, val shade: Color, val hexc: Color,
    val light: Boolean,
)

private fun hex(s: String): Color = Color(android.graphics.Color.parseColor(s))
private fun rgba(r: Int, g: Int, b: Int, a: Float) = Color(r, g, b, (a * 255).toInt())
private fun rgb(r: Int, g: Int, b: Int) = Color(r, g, b)

private val okD = hex("#8fe3b0"); private val warnD = hex("#ffd98f"); private val badD = hex("#ff8a8a")

val Skins: List<Skin> = listOf(
    Skin(
        "mine", "Mine",
        hex("#050607"), hex("#1c2026"),
        rgba(13, 15, 18, .80f), rgba(255, 255, 255, .05f), rgba(7, 8, 10, .86f),
        hex("#eef1f4"), hex("#8d949e"),
        rgba(235, 240, 245, .16f), rgba(235, 240, 245, .48f),
        hex("#d4ebff"), hex("#07090b"),
        okD, warnD, badD,
        rgb(246, 248, 251), rgb(255, 255, 255), rgb(0, 0, 0), rgb(255, 255, 255),
        light = false,
    ),
    Skin(
        "amber", "Amber",
        hex("#b84d05"), hex("#f8cf96"),
        rgba(34, 17, 5, .78f), rgba(255, 220, 180, .07f), rgba(28, 13, 3, .86f),
        hex("#fff4e6"), hex("#dcb48c"),
        rgba(255, 226, 196, .2f), rgba(255, 226, 196, .55f),
        hex("#ffb04a"), hex("#2a1404"),
        okD, warnD, badD,
        rgb(255, 250, 242), rgb(255, 255, 255), rgb(120, 50, 0), rgb(255, 240, 220),
        light = false,
    ),
    Skin(
        "silver", "Silver",
        hex("#f6f7f9"), hex("#aeb5bf"),
        rgba(248, 249, 251, .82f), rgba(20, 30, 45, .05f), rgba(232, 235, 239, .9f),
        hex("#14171b"), hex("#5a626d"),
        rgba(20, 24, 30, .16f), rgba(20, 24, 30, .5f),
        hex("#2c5b88"), hex("#ffffff"),
        hex("#1f8a52"), hex("#a66b00"), hex("#c0392b"),
        rgb(255, 255, 255), rgb(70, 82, 98), rgb(60, 72, 90), rgb(40, 50, 65),
        light = true,
    ),
    Skin(
        "verdant", "Verdant",
        hex("#062a0c"), hex("#79d24f"),
        rgba(5, 20, 8, .78f), rgba(200, 255, 180, .06f), rgba(3, 14, 5, .86f),
        hex("#effbe9"), hex("#a3cc95"),
        rgba(220, 255, 205, .18f), rgba(220, 255, 205, .5f),
        hex("#b9ff8c"), hex("#082008"),
        okD, warnD, badD,
        rgb(242, 255, 236), rgb(255, 255, 255), rgb(0, 40, 0), rgb(230, 255, 220),
        light = false,
    ),
)

fun skinById(id: String): Skin = Skins.firstOrNull { it.id == id } ?: Skins[0]

val LocalSkin = staticCompositionLocalOf { Skins[0] }

object Type {
    val display = FontFamily(Font(R.font.michroma))
    val ui = FontFamily(
        Font(R.font.chakra_regular, FontWeight.Normal),
        Font(R.font.chakra_medium, FontWeight.Medium),
        Font(R.font.chakra_semibold, FontWeight.SemiBold),
        Font(R.font.chakra_bold, FontWeight.Bold),
    )
    val mono = FontFamily(Font(R.font.sharetech_mono))

    fun display(size: Int, tracking: Double = .05) =
        TextStyle(fontFamily = display, fontSize = size.sp, letterSpacing = tracking.em)
    fun ui(size: Int, weight: FontWeight = FontWeight.Normal, tracking: Double = 0.0) =
        TextStyle(fontFamily = ui, fontSize = size.sp, fontWeight = weight, letterSpacing = tracking.em)
    fun mono(size: Int, tracking: Double = .1) =
        TextStyle(fontFamily = mono, fontSize = size.sp, letterSpacing = tracking.em)
    val tight: TextUnit = 1.2.em
}
