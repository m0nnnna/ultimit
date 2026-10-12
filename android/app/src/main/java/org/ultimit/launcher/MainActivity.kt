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
        media.start()
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
