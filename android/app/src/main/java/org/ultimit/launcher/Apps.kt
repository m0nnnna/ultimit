package org.ultimit.launcher

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.LauncherActivityInfo
import android.content.pm.LauncherApps
import android.content.pm.PackageManager
import android.graphics.Rect
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.UserHandle
import android.os.UserManager
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.core.graphics.drawable.toBitmap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.ConcurrentHashMap

/** The six rail entries from the mockup. Each one collects the real apps that fit it. */
enum class Cat(val id: String, val label: String, val title: String) {
    GAMES("games", "GAMES", "Games"),
    MAILER("mailer", "MAILER", "Mailer"),
    NEWS("news", "NEWS", "News"),
    AUDIO("audio", "AUDIO", "Audio"),
    DATA("data", "DATA", "Data"),
    ACCESSORY("accessory", "ACCESSORY", "Accessory");

    companion object { fun of(id: String?) = entries.firstOrNull { it.id == id } }
}

data class AppEntry(
    val label: String,
    val pkg: String,
    val component: ComponentName,
    val user: UserHandle,
    val cat: Cat,
    val autoCat: Cat,
    val icon: ImageBitmap,
    val isWork: Boolean,
) {
    val key: String get() = "${component.flattenToShortString()}#${user.hashCode()}"
}

data class Usage(val totalMs: Long, val lastUsed: Long)

class AppRepository(private val context: Context, private val settings: Settings, private val scope: CoroutineScope) {
    private val la = context.getSystemService(LauncherApps::class.java)
    private val pm = context.packageManager
    private val um = context.getSystemService(UserManager::class.java)
    private val iconPx = (56 * context.resources.displayMetrics.density).toInt()
    private val iconCache = ConcurrentHashMap<String, ImageBitmap>()

    private val _apps = MutableStateFlow<List<AppEntry>>(emptyList())
    val apps: StateFlow<List<AppEntry>> = _apps
    private val _usage = MutableStateFlow<Map<String, Usage>>(emptyMap())
    val usage: StateFlow<Map<String, Usage>> = _usage
    private var job: Job? = null

    private val callback = object : LauncherApps.Callback() {
        override fun onPackageRemoved(packageName: String, user: UserHandle) { iconCache.keys.removeAll { it.startsWith("$packageName/") }; refresh() }
        override fun onPackageAdded(packageName: String, user: UserHandle) = refresh()
        override fun onPackageChanged(packageName: String, user: UserHandle) { iconCache.keys.removeAll { it.startsWith("$packageName/") }; refresh() }
        override fun onPackagesAvailable(packageNames: Array<out String>, user: UserHandle, replacing: Boolean) = refresh()
        override fun onPackagesUnavailable(packageNames: Array<out String>, user: UserHandle, replacing: Boolean) = refresh()
    }

    fun start() {
        la.registerCallback(callback, Handler(Looper.getMainLooper()))
        refresh()
    }

    fun stop() = la.unregisterCallback(callback)

    fun refresh() {
        job?.cancel()
        job = scope.launch {
            val list = withContext(Dispatchers.IO) { load() }
            _apps.value = list
            _usage.value = withContext(Dispatchers.IO) { loadUsage() }
        }
    }

    private fun load(): List<AppEntry> {
        val hints = intentHints()
        val me = Process.myUserHandle()
        val out = ArrayList<AppEntry>()
        for (user in la.profiles) {
            if (um.isQuietModeEnabled(user)) continue
            for (info in la.getActivityList(null, user)) {
                val pkg = info.applicationInfo.packageName
                if (pkg == context.packageName) continue
                val auto = classify(info, hints)
                val cat = Cat.of(settings.categoryOverride(pkg)) ?: auto
                out += AppEntry(
                    label = info.label.toString(), pkg = pkg, component = info.componentName, user = user,
                    cat = cat, autoCat = auto, icon = icon(info), isWork = user != me,
                )
            }
        }
        return out.sortedBy { it.label.lowercase() }
    }

    private fun icon(info: LauncherActivityInfo): ImageBitmap {
        val key = "${info.componentName.packageName}/${info.componentName.className}#${info.user.hashCode()}"
        return iconCache.getOrPut(key) {
            info.getBadgedIcon(0).toBitmap(iconPx, iconPx).asImageBitmap()
        }
    }

    /** Packages that answer well-known intents, which says more than any category flag. */
    private data class Hints(val mail: Set<String>, val music: Set<String>, val files: Set<String>, val browser: Set<String>, val tools: Set<String>)

    private fun pkgsFor(i: Intent): Set<String> =
        pm.queryIntentActivities(i, PackageManager.MATCH_ALL).map { it.activityInfo.packageName }.toSet()

    private fun categoryIntent(cat: String) = Intent(Intent.ACTION_MAIN).addCategory(cat)

    private fun intentHints(): Hints {
        val mail = pkgsFor(Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:"))) +
            pkgsFor(Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:"))) +
            pkgsFor(categoryIntent(Intent.CATEGORY_APP_EMAIL)) +
            pkgsFor(categoryIntent(Intent.CATEGORY_APP_MESSAGING)) +
            pkgsFor(Intent(Intent.ACTION_DIAL))
        val music = pkgsFor(categoryIntent(Intent.CATEGORY_APP_MUSIC)) +
            pkgsFor(Intent(Intent.ACTION_VIEW).setDataAndType(Uri.parse("file:///x.mp3"), "audio/*"))
        val files = pkgsFor(categoryIntent(Intent.CATEGORY_APP_FILES)) +
            pkgsFor(categoryIntent(Intent.CATEGORY_APP_GALLERY))
        val browser = pkgsFor(categoryIntent(Intent.CATEGORY_APP_BROWSER))
        val tools = pkgsFor(categoryIntent(Intent.CATEGORY_APP_CALCULATOR)) +
            pkgsFor(categoryIntent(Intent.CATEGORY_APP_CALENDAR)) +
            pkgsFor(categoryIntent(Intent.CATEGORY_APP_CONTACTS)) +
            pkgsFor(Intent(android.provider.MediaStore.ACTION_IMAGE_CAPTURE)) +
            pkgsFor(Intent(android.provider.Settings.ACTION_SETTINGS))
        return Hints(mail, music, files, browser, tools)
    }

    private fun classify(info: LauncherActivityInfo, h: Hints): Cat {
        val ai = info.applicationInfo
        val pkg = ai.packageName
        val n = pkg.lowercase() + " " + info.label.toString().lowercase()
        @Suppress("DEPRECATION")
        if (ai.category == ApplicationInfo.CATEGORY_GAME || ai.flags and ApplicationInfo.FLAG_IS_GAME != 0) return Cat.GAMES
        if (listOf("steam", "retroarch", "emulat", "dolphin", "yuzu", "ppsspp", "winlator", "gamehub", "moonlight").any { it in n }) return Cat.GAMES
        if (pkg in h.mail || ai.category == ApplicationInfo.CATEGORY_SOCIAL) return Cat.MAILER
        if (listOf("mail", "messag", "telegram", "whatsapp", "signal", "discord", "element", "matrix", "slack", "chat", "sms").any { it in n }) return Cat.MAILER
        if (pkg in h.music || ai.category == ApplicationInfo.CATEGORY_AUDIO || ai.category == ApplicationInfo.CATEGORY_VIDEO) return Cat.AUDIO
        if (listOf("music", "spotify", "podcast", "audio", "player", "youtube", "radio", "jellyfin", "plex", "tidal").any { it in n }) return Cat.AUDIO
        if (ai.category == ApplicationInfo.CATEGORY_NEWS || pkg in h.browser) return Cat.NEWS
        if (listOf("news", "reddit", "rss", "feed", "browser", "chrome", "firefox", "brave", "tusky", "misskey", "mastodon", "fedi").any { it in n }) return Cat.NEWS
        if (pkg in h.files || ai.category == ApplicationInfo.CATEGORY_PRODUCTIVITY || ai.category == ApplicationInfo.CATEGORY_IMAGE) return Cat.DATA
        if (listOf("file", "drive", "docs", "sheets", "notes", "office", "explorer", "photos", "gallery", "termux", "nextcloud", "syncthing").any { it in n }) return Cat.DATA
        return Cat.ACCESSORY
    }

    fun hasUsageAccess(): Boolean {
        val ops = context.getSystemService(AppOpsManager::class.java)
        return ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName) == AppOpsManager.MODE_ALLOWED
    }

    private fun loadUsage(): Map<String, Usage> {
        if (!hasUsageAccess()) return emptyMap()
        val usm = context.getSystemService(UsageStatsManager::class.java)
        val now = System.currentTimeMillis()
        return runCatching {
            usm.queryAndAggregateUsageStats(now - 365L * 24 * 3600 * 1000, now)
                .mapValues { (_, s) -> Usage(s.totalTimeInForeground, s.lastTimeUsed) }
        }.getOrDefault(emptyMap())
    }

    fun launch(app: AppEntry, bounds: Rect? = null) {
        runCatching { la.startMainActivity(app.component, app.user, bounds, null) }
            .onFailure { Toasts.show("Launch failed", "${app.label} could not start.") }
    }

    fun openInfo(app: AppEntry) = runCatching { la.startAppDetailsActivity(app.component, app.user, null, null) }

    fun uninstall(app: AppEntry) = runCatching {
        context.startActivity(Intent(Intent.ACTION_DELETE, Uri.parse("package:${app.pkg}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    fun move(app: AppEntry, cat: Cat?) {
        settings.setCategoryOverride(app.pkg, if (cat == null || cat == app.autoCat) null else cat.id)
        refresh()
    }

    fun findByPackage(pkg: String): AppEntry? = _apps.value.firstOrNull { it.pkg == pkg && !it.isWork }
}
