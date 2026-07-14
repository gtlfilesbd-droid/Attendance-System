# BG Safe Fix — Phase-1 Manual Test Checklist

App version: **3.0.2+5**. Look for log tag `BG_SAFEFIX:` in `flutter run` / Logcat.

## Emulator / local

1. **Cold start, no prior duty** — expect `configure_ok`; Start Duty; points upload.
2. **Active duty → hot restart / `flutter run` without uninstall** — expect `configure_skipped_running` (or latch); app should not crash preferred.
3. **Active duty → swipe-kill → reopen** — duty/session still coherent with server.
4. **Rapid Start/End Duty ×10** — no crash; no zombie GPS loops.
5. **Sit still ≥5 min then walk/drive** — mode switch at most once per **60s** debounce; points continue via send timer/`getCurrentPosition` during debounce (`stream_restart_debounced` OK).
6. **Airplane / bad GPS** — `stream_error` → `stream_cooldown_entered` → `fallback_poll_*`; UI isolate stays alive.
7. **Clear storage then run** — `configure_ok` and normal duty work.

## Real devices (required before staged rollout)

8. Mid/high-end Android 12–14 — duty 30–60 min.
9. Low-end / older (8–10 if supported) — duty 30 min outdoor + indoor.
10. Poor signal — no crash loop; watchdog stop acceptable.

## Pass gates

- No process death on scenarios 2, 4, 6 on ≥2 physical devices.
- No location gap >5 min while duty active + permissions granted (healthy GPS).
- Server receives points under normal conditions.

## Rollout (approved)

Internal → Play staged **5% → 20% → 50% → 100%**. Halt on crash spike.  
**Phase-2 `forceLocationManager` not in this release.**
