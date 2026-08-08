# Mica

A macOS menu bar app that hides your desktop before anyone else sees it.

One keystroke (⌥⌘S) — or automatically, the moment your screen starts being shared or
recorded — Mica silences notifications, hides your open windows, the Dock, your menu bar
icons, your wallpaper, and your desktop icons and widgets. When the call ends, it puts
everything back exactly as it was.

Built for my own machine, as a replacement for [Stealthly](https://stealthly.app/).

## Features

| | |
|---|---|
| **Do Not Disturb** | Silences notifications for the duration |
| **Hide Active Windows** | All windows, all except the frontmost, only apps you pick, or everything except apps you pick |
| **Hide Dock** | |
| **Hide Menu Bar Icons** | Everything left of Mica's `‹` indicator |
| **Hide Wallpaper** | |
| **Hide Desktop Icons & Widgets** | Wallpaper stays visible |

Three modes — **On** forces everything on, **Off** disables it entirely, and **Auto**
engages when a trigger fires:

- your screen starts being shared or recorded
- a display is mirrored or extended
- a **Trigger App** launches (each one set to either activate Mica or just remind you)
- a scheduled time window begins

…unless an **Excluded App** is running, which blocks auto-activation.

## Requirements

macOS 15 or later. **Developed and tested only on macOS 26.6 (Tahoe)** — earlier versions
should work but are unverified, and several of the underlying APIs are version-sensitive.

## Build

```sh
make install     # build, sign, and install to /Applications
make run         # …and launch it
make test        # run the state-machine tests
```

`make install` signs with a real certificate rather than ad-hoc. This matters: macOS keys
permission grants to an app's code signature, and ad-hoc signing produces a new hash on
every build, so grants would evaporate each time you rebuilt. Point `SIGN_IDENTITY` at any
codesigning identity you have:

```sh
make install SIGN_IDENTITY="Apple Development: Your Name (TEAMID)"
```

Run `make verify` after two consecutive installs — if the designated requirement is
identical both times, permissions will stick. If it contains a `cdhash`, signing fell back
to ad-hoc.

Always launch from `/Applications` (`make run` or the Finder), never by executing the
binary from a shell — macOS attributes permissions to the *calling* process, so running it
from a terminal grants them to your terminal instead of to Mica.

## How it works

Mica is not sandboxed, which lets it use the underlying system APIs directly instead of
driving System Events, Finder, and Shortcuts over AppleScript. In practice that means
**no permission prompts**, nothing destructive, and cleaner restoration:

- **Dock** — `CoreDockSetAutoHideEnabled`. Private, but prompt-free. (These symbols live in
  `HIServices` on macOS 26; `CoreDock.framework` no longer exists.)
- **Windows** — `NSRunningApplication.hide()`, recording exactly which apps were visible so
  restore only un-hides those. An app you had already hidden stays hidden.
- **Desktop icons & widgets** — the real `com.apple.WindowManager` settings, so your live
  wallpaper keeps animating underneath rather than being covered by a blur.
- **Wallpaper** — a borderless window per display, positioned above the wallpaper but below
  the desktop icons, so the two features stay genuinely independent.
- **Menu bar icons** — an expanding spacer `NSStatusItem`, the Bartender/Ice technique. No
  Accessibility permission required.
- **Do Not Disturb** — the one feature needing a one-time setup, because no public or
  reachable API sets Focus on macOS 26. Mica runs a Shortcut you create once; a guided
  first-run flow walks you through it.
- **Screen capture detection** — `CGSIsScreenWatcherPresent`, which reads the window
  server's own capture-stream count. One signal covers Zoom, Meet, Teams, QuickTime, ⌘⇧5,
  OBS, and Screen Sharing alike; there is no public equivalent.

### Crash safety

Before touching anything, Mica writes a snapshot of your prior system state to disk and
flushes it with `F_FULLFSYNC`. If it's killed while engaged, the next launch finds that
snapshot, restores everything, and deletes it. Without this a crash would leave your Dock
hidden and Do Not Disturb stuck on with no indication why.

Recovery deliberately skips window restore if the machine rebooted in between (detected
via the kernel's boot session UUID). Hidden-application state doesn't survive a restart,
so replaying it could only ever wrongly un-hide something *you* hid after logging back in.

`SIGTERM`, termination and power-off are all trapped so the normal path runs. `SIGKILL`
can't be, which is exactly what the snapshot is for.

## Known limitations

**Reminders use Mica's own banner, not system notifications.** macOS only grants
notification access to apps that pass Gatekeeper assessment, which means a notarized
Developer ID signature — a locally-built app signed with an Apple Development certificate
is rejected, and `UNUserNotificationCenter` refuses authorization without even prompting.
Mica detects this and draws an equivalent banner itself, which needs no permission. Sign
with a Developer ID and notarize, and it switches to real notifications automatically.

**Do Not Disturb needs a one-time setup.** There is no reachable API for setting Focus on
macOS 26 — the private service is gated behind an Apple-only entitlement, the Intents API
is read-only, and writing the Focus database needs Full Disk Access and races the daemon
that owns it. Create two Shortcuts, pick them in Settings → Features, done.

**A few captures are invisible.** The window server lets some Apple-internal streams
exempt themselves from the count Mica reads. The design errs toward false positives.

**The whole menu bar can't be auto-hidden at runtime**, only the icons. macOS 26 moved
that setting into Control Center's preferences, read at login, and the app-facing API only
applies while the calling app is frontmost — which a menu bar utility never is.
