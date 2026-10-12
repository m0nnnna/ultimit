package org.ultimit.launcher

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect
import androidx.lifecycle.Lifecycle
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.ui.unit.dp
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowInfoTracker
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private lateinit var settings: Settings
    private lateinit var repo: AppRepository
    private lateinit var media: MediaFeed
    private var desktop: DesktopState? = null

    private var hinge by mutableStateOf<Hinge?>(null)
    private var resumed by mutableStateOf(false)
    private var bootTick by mutableIntStateOf(0)

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)
        settings = Settings(this)
        repo = AppRepository(applicationContext, settings, lifecycleScope)
        media = MediaFeed(applicationContext)
        repo.start()
        if (settings.bootOnStart && !bootedThisProcess) { bootedThisProcess = true; bootTick = 1 }

        // Track the Duo's hinge. When the launcher spans both screens the hinge is a
        // separating fold, and each screen becomes its own pane.
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                WindowInfoTracker.getOrCreate(this@MainActivity).windowLayoutInfo(this@MainActivity).collect { info ->
                    val f = info.displayFeatures.filterIsInstance<FoldingFeature>().firstOrNull()
                    hinge = if (f != null && f.isSeparating) {
                        val b = f.bounds
                        Hinge(Rect(b.left.toFloat(), b.top.toFloat(), b.right.toFloat(), b.bottom.toFloat()), f.orientation == FoldingFeature.Orientation.VERTICAL)
                    } else null
                }
            }
        }

        // A launcher never finishes on back; back closes the top window instead.
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() { desktop?.back() }
        })

        setContent {
            var crash by remember { mutableStateOf(CrashLog.read(this)) }
            val c = crash
            if (c != null) {
                CrashScreen(
                    c,
                    onRetry = { CrashLog.clear(this); crash = null },
                    onSafe = {
                        settings.updateMotion(false); settings.updateBootOnStart(false); settings.updateTicker(false)
                        CrashLog.clear(this); crash = null
                    },
                    onStock = {
                        CrashLog.clear(this)
                        startActivity(Intent(android.provider.Settings.ACTION_HOME_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    },
                )
                return@setContent
            }
            val scope = rememberCoroutineScope()
            val state = remember { DesktopState(scope).also { desktop = it } }
            Desktop(
                settings = settings, repo = repo, media = media, hinge = hinge, resumed = resumed,
                state = state, bootTick = bootTick, onBootPlayed = {},
            )
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Pressing Home while already home tidies the desktop, like the stock launcher.
        if (intent.action == Intent.ACTION_MAIN && intent.hasCategory(Intent.CATEGORY_HOME) && resumed) desktop?.closeAll()
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        runCatching { media.start() }
        repo.refresh()
    }

    override fun onPause() {
        super.onPause()
        resumed = false
    }

    override fun onDestroy() {
        repo.stop()
        media.stop()
        super.onDestroy()
    }

    companion object {
        private var bootedThisProcess = false
    }
}

/** Shown on the launch after a crash, so the cause is visible and copyable. */
@androidx.compose.runtime.Composable
private fun CrashScreen(text: String, onRetry: () -> Unit, onSafe: () -> Unit, onStock: () -> Unit) {
    val ctx = androidx.compose.ui.platform.LocalContext.current
    val skin = Skins[0]
    androidx.compose.runtime.CompositionLocalProvider(LocalSkin provides skin) {
        androidx.compose.foundation.layout.Column(
            androidx.compose.ui.Modifier.fillMaxSize().background(skin.bg1)
                .windowInsetsPadding(androidx.compose.foundation.layout.WindowInsets.systemBars)
                .padding(16.dp),
            verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(12.dp),
        ) {
            androidx.compose.foundation.text.BasicText("[ ULTIMIT ]  CRASHED", style = Type.display(18, .1).copy(color = skin.fg))
            androidx.compose.foundation.text.BasicText(
                "The launcher stopped last time. Copy this and send it over, then try again or use safe mode (no animation, boot or ticker).",
                style = Type.ui(13).copy(color = skin.dim),
            )
            androidx.compose.foundation.layout.Row(horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp)) {
                UBtn("Copy log", primary = true) {
                    val cm = ctx.getSystemService(android.content.ClipboardManager::class.java)
                    cm.setPrimaryClip(android.content.ClipData.newPlainText("Ultimit crash", text))
                    Toasts.show("Crash", "Log copied.")
                }
                UBtn("Try again", onClick = onRetry)
            }
            androidx.compose.foundation.layout.Row(horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp)) {
                UBtn("Safe mode", onClick = onSafe)
                UBtn("Pick other home", onClick = onStock)
            }
            androidx.compose.foundation.layout.Box(
                androidx.compose.ui.Modifier.weight(1f).fillMaxWidth().border(1.dp, skin.line)
                    .verticalScroll(androidx.compose.foundation.rememberScrollState())
                    .horizontalScroll(androidx.compose.foundation.rememberScrollState())
                    .padding(10.dp)
            ) {
                androidx.compose.foundation.text.BasicText(text, style = Type.mono(10, 0.0).copy(color = skin.fg), softWrap = false)
            }
        }
    }
}
