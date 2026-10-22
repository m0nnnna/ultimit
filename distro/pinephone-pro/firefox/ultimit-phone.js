// Ultimit on the PinePhone Pro: Firefox ESR defaults that spend less GPU (Mali-T860) and RAM
// (4 GB) on heavy sites. Installed to /usr/lib/firefox-esr/defaults/pref/; about:config overrides.

// one content process per tab group instead of one per site: hundreds of MB less with a few tabs
pref("fission.autostart", false);
pref("dom.ipc.processCount", 2);
pref("browser.tabs.unloadOnLowMemory", true);
// don't keep rendered pages around for Back
pref("browser.sessionhistory.max_total_viewers", 0);
pref("browser.cache.memory.capacity", 65536);
pref("browser.sessionstore.interval", 60000);

// sites drop their animations; no blur behind elements (a full-screen GPU pass per frame)
pref("ui.prefersReducedMotion", 1);
pref("layout.css.backdrop-filter.enabled", false);

// no autoplay; H.264 over VP9/AV1, the cheapest to decode on the CPU (YouTube follows this)
pref("media.autoplay.default", 5);
pref("media.autoplay.blocking_policy", 2);
pref("media.av1.enabled", false);
pref("media.mediasource.vp9.enabled", false);

pref("network.prefetch-next", false);
pref("browser.urlbar.speculativeConnect.enabled", false);
