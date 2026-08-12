# Mica

A macOS menu bar app that hides your desktop before anyone else sees it.

One keystroke (⌥⌘S) — or automatically, the moment your screen starts being shared or
recorded — Mica silences notifications, hides your open windows, the Dock, your menu bar
icons, your wallpaper, and your desktop icons and widgets. When the call ends, it puts
everything back exactly as it was.

A free, open-source, non-sandboxed alternative to [Stealthly](https://stealthly.app/).

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

## Download

A signed disk image is published with every release:

**[Download the latest release](https://github.com/Vedant-29/mica/releases/latest/download/Mica.dmg)**
 · [all releases](https://github.com/Vedant-29/mica/releases) · [mica.vedantagrw.com](https://mica.vedantagrw.com)

Drag Mica to Applications, then **right-click the app → Open** the first time. The build is
signed but not notarized — notarization needs a paid Developer ID — so Gatekeeper asks once.
Each release also ships a `.sha256` if you want to check the download.

Or build it yourself; see [Build](#build).

## Requirements

macOS 15 or later. **Developed and tested only on macOS 26.6 (Tahoe)** — earlier versions
should work but are unverified, and several of the underlying APIs are version-sensitive.

## Build

Needs Swift 6.2 (Xcode 26 or later) — `Package.swift` declares tools version 6.2 and
older toolchains refuse to resolve the package. Then:

```sh
make install     # build and install to /Applications
make run         # …and launch it
make test        # run the state-machine tests
```

That's the whole build. No paid Apple Developer account is required to build and run it
yourself.

### Keeping permission grants (optional)

By default Mica is **ad-hoc signed**, which is fine to run but has one quirk: macOS keys
permission grants to the code signature, and ad-hoc signing produces a new signature every
build — so any permissions you grant reset on the next `make install`. To keep them, sign
with a stable identity by creating a `Local.mk` (copy `Local.mk.example`):

```make
SIGN_IDENTITY = Apple Development: Your Name (TEAMID)
```

List identities with `security find-identity -v -p codesigning`. `Local.mk` is gitignored,
so your identity never lands in the repo. Run `make verify` after two installs — a stable
designated requirement means grants will stick; a `cdhash` means it fell back to ad-hoc.

Always launch from `/Applications` (`make run` or the Finder), never the built binary from
a shell — macOS attributes permissions to the *calling* process, so a terminal launch
grants them to your terminal instead of to Mica.

### Releasing

Maintainers only. `VERSION` is the source of truth and the tag is the trigger:

```sh
make release BUMP=patch     # or minor / major
```

That bumps `VERSION`, commits, tags `vX.Y.Z` and pushes. CI then runs the tests, builds a
signed DMG and publishes a GitHub release with the disk image and its checksum attached.
The website needs no redeploy — its download link always resolves to the newest release.

A tag containing a hyphen (`v0.3.0-rc1`) publishes as a prerelease, so it is downloadable
but does not become `latest`.

## First run — what you'll need to do

Mica avoids permission prompts wherever it can, so there's very little. But a few things
are on you, because macOS gives an app no other way:

- **Do Not Disturb** (only if you want it) — create two Shortcuts once. Mica walks you
  through it in Settings → Features; details below. Skip it and the other five features
  work with zero setup.
- **Hide Menu Bar Icons** (only if you enable it) — drag Mica's `‹` marker into your menu
  bar where you want the cut-off (hold ⌘ and drag). Everything left of it hides.
- **macOS 26 "Allow in Menu Bar"** — Tahoe can hide a new app's menu bar icon by default.
  If Mica's icon doesn't appear, enable it in System Settings → Control Center → Menu Bar,
  or the "Allow in the Menu Bar" list.
- **If you downloaded a build** (rather than building it yourself) — an ad-hoc or
  Developer-ID-less app is quarantined by Gatekeeper. Right-click the app → **Open** the
  first time, or run `xattr -cr /Applications/Mica.app`.

No Accessibility, Screen Recording, or Full Disk Access permission is required for any
feature.

### Setting up Do Not Disturb

macOS 26 has no API that lets a third-party app turn Focus on, so Mica runs a Shortcut you
create once. In the Shortcuts app:

1. New shortcut → add the **Set Focus** action. It already reads *Do Not Disturb, On* —
   leave it. Name it exactly **`Mica Do Not Disturb On`**.
2. Another new shortcut → **Set Focus** → switch it to *Off*. Name it exactly
   **`Mica Do Not Disturb Off`**.

Then in Mica → Settings → Features, both show a checkmark. Hit **Test** and confirm the
menu-bar moon appears. (The Shortcuts editor may *label* the first one "Off" — that's a
display glitch in Shortcuts; the Test confirms what it actually does.)

## Settings

Click the menu bar icon → **Settings**, or open a URL:

```sh
open mica://settings     # or mica://windows, mica://features, mica://triggers
```

Four tabs: **General** (startup, keyboard shortcut), **Features** (what gets hidden, and
the Do Not Disturb setup), **Windows** (which apps Hide Active Windows acts on), and
**Triggers** (what turns Auto on, and what blocks it).

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
  reachable API sets Focus on macOS 26. Mica runs two Shortcuts you create once (see
  above), found by name.
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

**Do Not Disturb needs two hand-made Shortcuts.** There is no reachable API for setting
Focus on macOS 26 — the private service is gated behind an Apple-only entitlement, the
Intents API is read-only, and writing the Focus database needs Full Disk Access and races
the daemon that owns it. A generated shortcut imports in a broken state and can't be read
back to verify, so Mica has you create them by hand (30 seconds) and confirm with the Test
button. See "Setting up Do Not Disturb" above.

**A few captures are invisible.** The window server lets some Apple-internal streams
exempt themselves from the count Mica reads. The design errs toward false positives.

**The whole menu bar can't be auto-hidden at runtime**, only the icons. macOS 26 moved
that setting into Control Center's preferences, read at login, and the app-facing API only
applies while the calling app is frontmost — which a menu bar utility never is.

## Make it your own

Fork it, rename it, change the icon — it's MIT licensed. Two things to set for a clean
fork: your own `BUNDLE_ID` in `Local.mk`, and your own signing identity (see Build). The
bundle identifier must be unique per app; don't ship two apps sharing one.

## License

MIT — see [LICENSE](LICENSE).
