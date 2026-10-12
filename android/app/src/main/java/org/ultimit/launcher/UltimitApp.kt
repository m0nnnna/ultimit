package org.ultimit.launcher

import android.app.Application
import android.content.Context
import android.os.Build
import android.util.Log
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Catches any crash, writes it to a file, and lets the next launch show it on screen
 * (see [CrashLog] and MainActivity) instead of the launcher silently restarting forever.
 */
class UltimitApp : Application() {
    override fun onCreate() {
        super.onCreate()
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, e ->
            runCatching { CrashLog.write(this, thread, e) }
            previous?.uncaughtException(thread, e)
        }
    }
}

object CrashLog {
    private fun file(c: Context) = File(c.filesDir, "last_crash.txt")

    fun write(c: Context, thread: Thread, e: Throwable) {
        val sw = StringWriter()
        e.printStackTrace(PrintWriter(sw))
        val v = runCatching { c.packageManager.getPackageInfo(c.packageName, 0).versionName }.getOrNull()
        val text = buildString {
            appendLine("Ultimit $v crashed ${SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())}")
            appendLine("${Build.MANUFACTURER} ${Build.MODEL} · Android ${Build.VERSION.RELEASE} (sdk ${Build.VERSION.SDK_INT}) · thread ${thread.name}")
            appendLine()
            append(sw.toString())
        }
        Log.e("Ultimit", text)
        file(c).writeText(text)
    }

    fun read(c: Context): String? = file(c).takeIf { it.exists() }?.readText()
    fun clear(c: Context) { file(c).delete() }
}
