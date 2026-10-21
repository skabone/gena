# Gena — native macOS app

A genuinely native macOS app for Gena: a tiny Swift + WKWebView wrapper.
No Electron, no Chromium, no dependencies to download, nothing to pay for — it
uses the WebKit engine already built into macOS and the Swift compiler that
ships with Xcode Command Line Tools.

## Build it

```bash
cd native
./build.sh
mv Gena.app /Applications/
```

Then launch **Gena** from Launchpad or Spotlight like any other app. It gets
its own Dock icon and window.

Requirements: macOS 11+ and Xcode Command Line Tools (`xcode-select --install`
if `swiftc` isn't found).

## What it does

- Opens the hosted Gena (`https://skabone.github.io/gena/`) in a native
  window, so it always runs the latest version and **Cloud sync** works.
- Keeps its **own private storage**, separate from any browser — connect Cloud
  sync once (⋯ menu) and your tasks follow you in.
- Native menus: ⌘C/⌘V/⌘X/⌘A editing, ⌘R reload, ⌘M minimize, ⌘Q quit.
- Links to other sites open in your real browser, not inside the app.
- **Mac Calendar (V6.9):** Gena can show and edit the calendars in the Mac's
  Calendar app (Google, iCloud, Outlook, On My Mac) through EventKit. macOS
  asks once ("Gena shows and edits the events in your calendars"); the answer
  can be changed in System Settings → Privacy & Security → Calendars. Only the
  hosted Gena page, in the main frame, can reach the calendars, through a
  narrow bridge in `Gena.swift`; the app keeps no event data of its own. The
  website, the PWA and the phone stay read-only (subscriptions).

`./build.sh` first runs the calendar bridge's self-check (the same file built with
`-D GENA_SELFCHECK`: its page gate and request checks, no window and no calendar)
and stops if a check fails.

## Notes

- The app is **ad-hoc signed** during the build, and because you compiled it
  yourself it isn't quarantined — so it opens without the "unidentified
  developer" warning. If macOS ever does complain, right-click the app →
  **Open** once.
- Want full offline use instead of loading the hosted site? The installable
  web app (Brave/Chrome → *Install Gena…*) already caches itself via a
  service worker; the native app here is the "always current + native window"
  option.

## Files

- `Gena.swift` — the app (window + WKWebView + menus) and the calendar bridge (EventKit).
- `makeicon.swift` — draws the app icon with Core Graphics.
- `build.sh` — compiles, generates the icon, and assembles `Gena.app`.

---

Required Notice: Copyright (c) 2026 Mintay Misgano (https://github.com/skabone) ·
PolyForm Noncommercial License 1.0.0
