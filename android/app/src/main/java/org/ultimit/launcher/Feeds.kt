package org.ultimit.launcher

import android.app.Notification
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.core.app.NotificationManagerCompat
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.lang.ref.WeakReference

/** One notification, flattened to what the ticker and panels show. */
data class Notif(
    val key: String,
    val pkg: String,
    val app: String,
    val title: String,
    val text: String,
    val time: Long,
    val intent: PendingIntent?,
    val category: String?,
    val autoCancel: Boolean,
)

/** Shared live feeds. The listener writes, the UI reads. */
object Feeds {
    val notifs = MutableStateFlow<List<Notif>>(emptyList())
    val connected = MutableStateFlow(false)
    internal var listener: WeakReference<TickerListener>? = null

    fun listenerEnabled(context: Context) =
        NotificationManagerCompat.getEnabledListenerPackages(context).contains(context.packageName)

    fun component(context: Context) = ComponentName(context, TickerListener::class.java)

    /** Opens the notification's target and dismisses it if it asked to be. */
    fun open(n: Notif) {
        runCatching { n.intent?.send() }
        if (n.autoCancel) dismiss(n)
    }

    fun dismiss(n: Notif) {
        runCatching { listener?.get()?.cancelNotification(n.key) }
    }
}

class TickerListener : NotificationListenerService() {
    override fun onListenerConnected() {
        Feeds.listener = WeakReference(this)
        Feeds.connected.value = true
        publish()
    }

    override fun onListenerDisconnected() {
        Feeds.connected.value = false
        Feeds.listener = null
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) = publish()
    override fun onNotificationRemoved(sbn: StatusBarNotification) = publish()

    private fun publish() {
        val list = runCatching { activeNotifications }.getOrNull() ?: return
        val pm = packageManager
        Feeds.notifs.value = list.asSequence()
            .filter { it.packageName != packageName }
            .filter { it.notification.flags and Notification.FLAG_GROUP_SUMMARY == 0 }
            .filter { !it.isOngoing || it.notification.category == Notification.CATEGORY_TRANSPORT }
            .mapNotNull { sbn ->
                val ex = sbn.notification.extras
                val title = ex.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
                val text = (ex.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: ex.getCharSequence(Notification.EXTRA_TEXT))?.toString().orEmpty()
                if (title.isBlank() && text.isBlank()) return@mapNotNull null
                val app = runCatching { pm.getApplicationLabel(pm.getApplicationInfo(sbn.packageName, 0)).toString() }.getOrDefault(sbn.packageName)
                Notif(
                    key = sbn.key, pkg = sbn.packageName, app = app, title = title, text = text,
                    time = sbn.postTime, intent = sbn.notification.contentIntent,
                    category = sbn.notification.category,
                    autoCancel = sbn.notification.flags and Notification.FLAG_AUTO_CANCEL != 0,
                )
            }
            .sortedByDescending { it.time }
            .toList()
    }
}

data class NowPlaying(
    val title: String,
    val artist: String,
    val app: String,
    val pkg: String,
    val art: Bitmap?,
    val playing: Boolean,
    val controller: MediaController,
)

/** Tracks the active media session so the Audio panel can show and drive it. */
class MediaFeed(private val context: Context) {
    private val msm = context.getSystemService(MediaSessionManager::class.java)
    private val handler = Handler(Looper.getMainLooper())
    private val _now = MutableStateFlow<NowPlaying?>(null)
    val now: StateFlow<NowPlaying?> = _now
    private var current: MediaController? = null
    private var started = false

    private val cb = object : MediaController.Callback() {
        override fun onMetadataChanged(metadata: MediaMetadata?) = emit()
        override fun onPlaybackStateChanged(state: PlaybackState?) = emit()
        override fun onSessionDestroyed() { pick() }
    }

    private val sessions = MediaSessionManager.OnActiveSessionsChangedListener { pick(it) }

    fun start() {
        if (started || !Feeds.listenerEnabled(context)) return
        runCatching {
            msm.addOnActiveSessionsChangedListener(sessions, Feeds.component(context), handler)
            started = true
            pick()
        }
    }

    fun stop() {
        if (!started) return
        runCatching { msm.removeOnActiveSessionsChangedListener(sessions) }
        current?.unregisterCallback(cb)
        current = null
        started = false
    }

    private fun pick(list: List<MediaController>? = null) {
        val all = list ?: runCatching { msm.getActiveSessions(Feeds.component(context)) }.getOrDefault(emptyList())
        val best = all.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING } ?: all.firstOrNull()
        if (best?.sessionToken != current?.sessionToken) {
            current?.unregisterCallback(cb)
            current = best
            best?.registerCallback(cb, handler)
        }
        emit()
    }

    private fun emit() {
        val c = current ?: run { _now.value = null; return }
        val md = c.metadata
        val pm = context.packageManager
        val app = runCatching { pm.getApplicationLabel(pm.getApplicationInfo(c.packageName, 0)).toString() }.getOrDefault(c.packageName)
        _now.value = NowPlaying(
            title = md?.getString(MediaMetadata.METADATA_KEY_TITLE) ?: "Nothing playing",
            artist = md?.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: md?.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST) ?: "",
            app = app, pkg = c.packageName,
            art = md?.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART) ?: md?.getBitmap(MediaMetadata.METADATA_KEY_ART),
            playing = c.playbackState?.state == PlaybackState.STATE_PLAYING,
            controller = c,
        )
    }

    fun toggle() { val c = _now.value?.controller ?: return; if (_now.value?.playing == true) c.transportControls.pause() else c.transportControls.play() }
    fun next() { _now.value?.controller?.transportControls?.skipToNext() }
    fun prev() { _now.value?.controller?.transportControls?.skipToPrevious() }
}
