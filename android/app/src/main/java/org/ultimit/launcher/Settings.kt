package org.ultimit.launcher

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

// User settings, observable from Compose and persisted to SharedPreferences.
// Keys match the mockup's localStorage keys so the two read the same.
class Settings(context: Context) {
    private val sp = context.getSharedPreferences("ultimit", Context.MODE_PRIVATE)

    var skin by mutableStateOf(sp.getString("ultimit.skin", "mine") ?: "mine")
        private set
    var motion by mutableStateOf(sp.getBoolean("ultimit.motion", true))
        private set
    var density by mutableIntStateOf(sp.getInt("ultimit.density", 34))
        private set
    var ticker by mutableStateOf(sp.getBoolean("ultimit.ticker", true))
        private set
    var bootOnStart by mutableStateOf(sp.getBoolean("ultimit.bootOnStart", true))
        private set
    // Push the skin's palette into Android's system colors (QS, notifications, settings) with root.
    var rootSync by mutableStateOf(sp.getBoolean("ultimit.rootSync", true))
        private set
    // Set the system's dark/light mode to match the skin when rootSync is on.
    var syncNight by mutableStateOf(sp.getBoolean("ultimit.syncNight", true))
        private set

    fun updateSkin(v: String) { skin = v; sp.edit().putString("ultimit.skin", v).apply() }
    fun updateMotion(v: Boolean) { motion = v; sp.edit().putBoolean("ultimit.motion", v).apply() }
    fun updateDensity(v: Int) { density = v; sp.edit().putInt("ultimit.density", v).apply() }
    fun updateTicker(v: Boolean) { ticker = v; sp.edit().putBoolean("ultimit.ticker", v).apply() }
    fun updateBootOnStart(v: Boolean) { bootOnStart = v; sp.edit().putBoolean("ultimit.bootOnStart", v).apply() }
    fun updateRootSync(v: Boolean) { rootSync = v; sp.edit().putBoolean("ultimit.rootSync", v).apply() }
    fun updateSyncNight(v: Boolean) { syncNight = v; sp.edit().putBoolean("ultimit.syncNight", v).apply() }

    // Per-app rail category overrides: package -> category id ("" = automatic).
    fun categoryOverride(pkg: String): String? = sp.getString("cat.$pkg", null)
    fun setCategoryOverride(pkg: String, cat: String?) {
        val e = sp.edit()
        if (cat == null) e.remove("cat.$pkg") else e.putString("cat.$pkg", cat)
        e.apply()
    }

    companion object {
        fun peekSkin(context: Context): String =
            context.getSharedPreferences("ultimit", Context.MODE_PRIVATE).getString("ultimit.skin", "mine") ?: "mine"
        fun peekRootSync(context: Context): Boolean =
            context.getSharedPreferences("ultimit", Context.MODE_PRIVATE).getBoolean("ultimit.rootSync", true)
        fun peekSyncNight(context: Context): Boolean =
            context.getSharedPreferences("ultimit", Context.MODE_PRIVATE).getBoolean("ultimit.syncNight", true)
    }
}
