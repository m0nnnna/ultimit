package org.ultimit.launcher

import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.TimeUnit

/**
 * Everything that needs root. Runs `su` (Magisk) and talks to Android's shell commands.
 * Nothing here is required for the launcher to work; each feature degrades to the
 * normal Android settings screen when root is missing or refused.
 */
object Root {
    data class Result(val code: Int, val out: String) { val ok get() = code == 0 }

    @Volatile private var cached: Boolean? = null

    suspend fun available(): Boolean = cached ?: withContext(Dispatchers.IO) {
        val r = run("id")
        (r.ok && "uid=0" in r.out).also { cached = it }
    }

    /** Runs a shell script as root and returns its exit code and combined output. */
    fun run(script: String, timeoutSec: Long = 20): Result = try {
        val p = ProcessBuilder("su").redirectErrorStream(true).start()
        p.outputStream.bufferedWriter().use { it.write(script); it.write("\nexit\n") }
        val out = p.inputStream.bufferedReader().readText()
        if (!p.waitFor(timeoutSec, TimeUnit.SECONDS)) { p.destroy(); Result(-1, "timeout") } else Result(p.exitValue(), out.trim())
    } catch (e: Exception) {
        Result(-1, e.message ?: "su failed")
    }

    suspend fun runAsync(script: String) = withContext(Dispatchers.IO) { run(script) }

    private fun pkg(c: Context) = c.packageName
    private fun home(c: Context) = "${pkg(c)}/${MainActivity::class.java.name}"
    private fun listener(c: Context) = "${pkg(c)}/${TickerListener::class.java.name}"

    /** Makes Ultimit the default home app, grants the notification listener and usage access. */
    suspend fun setUp(c: Context): Result = runAsync(
        """
        cmd package set-home-activity --user 0 ${home(c)} || cmd package set-home-activity ${home(c)}
        cmd notification allow_listener ${listener(c)}
        appops set ${pkg(c)} GET_USAGE_STATS allow
        """.trimIndent()
    )

    suspend fun setHome(c: Context) = runAsync("cmd package set-home-activity --user 0 ${home(c)} || cmd package set-home-activity ${home(c)}")
    suspend fun grantListener(c: Context) = runAsync("cmd notification allow_listener ${listener(c)}")
    suspend fun grantUsage(c: Context) = runAsync("appops set ${pkg(c)} GET_USAGE_STATS allow")
    suspend fun expandNotifications() = runAsync("cmd statusbar expand-notifications")
    suspend fun expandQuickSettings() = runAsync("cmd statusbar expand-settings")

    /**
     * Pushes the skin into Android's own Material You palette, so quick settings, the
     * notification shade, Settings and every dynamic-color app pick up the skin.
     * Uses the same secure setting the system wallpaper picker writes, so it is undone
     * by choosing a color in Wallpaper & style, or with [resetPalette].
     */
    suspend fun applySkin(skin: Skin, night: Boolean): Result {
        val seed = argb(skin.accent)
        val style = when (skin.id) {
            "mine" -> when {
                Build.VERSION.SDK_INT >= 34 -> "MONOCHROMATIC"
                Build.VERSION.SDK_INT >= 33 -> "SPRITZ"
                else -> "TONAL_SPOT"
            }
            "amber", "verdant" -> "VIBRANT"
            else -> "TONAL_SPOT"
        }
        val json = buildString {
            append("{")
            append("\"android.theme.customization.system_palette\":\"$seed\",")
            append("\"android.theme.customization.accent_color\":\"$seed\",")
            if (Build.VERSION.SDK_INT >= 33) append("\"android.theme.customization.color_source\":\"preset\",")
            append("\"android.theme.customization.theme_style\":\"$style\",")
            append("\"_applied_timestamp\":${System.currentTimeMillis()}")
            append("}")
        }
        val nightCmd = if (night) "cmd uimode night ${if (skin.light) "no" else "yes"}" else ":"
        return runAsync("settings put secure theme_customization_overlay_packages '$json'\n$nightCmd")
    }

    suspend fun resetPalette() = runAsync("settings delete secure theme_customization_overlay_packages")

    @SuppressLint("DefaultLocale")
    private fun argb(c: androidx.compose.ui.graphics.Color): String {
        val a = (c.alpha * 255).toInt(); val r = (c.red * 255).toInt(); val g = (c.green * 255).toInt(); val b = (c.blue * 255).toInt()
        return String.format("%02X%02X%02X%02X", a, r, g, b)
    }
}

/** Re-applies the skin palette after boot, in case another app or an OTA reset it. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED || !Settings.peekRootSync(context)) return
        val pending = goAsync()
        val skin = skinById(Settings.peekSkin(context))
        val night = Settings.peekSyncNight(context)
        Thread {
            kotlinx.coroutines.runBlocking { Root.applySkin(skin, night) }
            pending.finish()
        }.start()
    }
}
