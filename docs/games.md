# Tested games

Games confirmed working on Ultimit, and the settings they needed. Add a row when you
confirm one; a game that runs with Steam's defaults is worth listing too (put "Default" in
the columns it didn't need).

Compatibility tools named here are installed with ProtonPlus (in GAMES) and picked per game in
Steam › Properties › Compatibility. Launch options go in Steam › Properties › General ›
Launch Options.

DLSS: on an NVIDIA card the Ultimit session tells Proton to use NVIDIA's newest DLSS and its newest
preset (see `session/ultimit-session`), so a game's own old DLSS isn't used. To turn DLSS's NVIDIA
side off for one game, use `PROTON_DISABLE_NVAPI=1 %command%`.

| Game | Store | Compatibility tool | Launch options | Notes | Tested on | Date |
|---|---|---|---|---|---|---|
| Neverness to Everness (NTE) | Steam | DW-Proton (ProtonPlus) | `PROTON_DISABLE_NVAPI=1 %command%` | Works. | RTX 4070, NVIDIA driver | 2026-10-14 |
| MapleStory / MapleStory Worlds | Steam ("MapleStory", 216150) | Proton Experimental | Default | Works, no tweaks needed. The one Steam entry launches both; tested with Worlds. | RTX 4070, NVIDIA driver | 2026-10-18 |
| AION 2 | Steam | Proton Experimental | Default (Ultimit's DLSS defaults; before them it needed `PROTON_ENABLE_NGX_UPDATER=1 DXVK_NVAPI_DRS_NGX_DLSS_SR_OVERRIDE=on DXVK_NVAPI_DRS_NGX_DLSS_SR_OVERRIDE_RENDER_PRESET_SELECTION=render_preset_latest %command%`) | Works with DLSS on. Its shipped DLSS left characters without legs. It rendered squashed at 1080x1920 until Ultimit marked the main display primary for XWayland. | RTX 4070, NVIDIA driver | 2026-10-18 |
