# Mica

A macOS menu bar app that hides your desktop before anyone else sees it. Press Option-Command-S, or let it turn on by itself when your screen starts being shared or recorded. Mica silences notifications and hides your windows, Dock, menu bar icons, wallpaper, and desktop icons. When the call ends, it puts everything back the way it was.

[Download](https://github.com/Vedant-29/mica/releases/latest/download/Mica.dmg) · [All releases](https://github.com/Vedant-29/mica/releases) · [Website](https://mica.vedantagrw.com) ([source](https://github.com/Vedant-29/mica-web))

A free, open-source, non-sandboxed alternative to [Stealthly](https://stealthly.app/).

## Features

- Do Not Disturb for the duration of a call
- Hide windows: all, all except the frontmost, only apps you pick, or all except apps you pick
- Hide the Dock, menu bar icons, wallpaper, and desktop icons and widgets
- Three modes: On, Off, and Auto
- Auto turns on when screen sharing or recording starts, a display is mirrored or extended, a trigger app launches, or a scheduled time window begins. An excluded app blocks it.
- Crash safe: prior state is saved to disk first and restored on the next launch if Mica is killed

## Requirements

- macOS 15 or later (developed and tested only on macOS 26.6 Tahoe)
- Swift 6.2 (Xcode 26 or later) to build from source

## Install

Download `Mica.dmg` from the latest release and drag Mica to Applications. The build is signed but not notarized, so right-click the app and choose Open the first time (or run `xattr -cr /Applications/Mica.app`). Each release also ships a `.sha256` checksum.

## Build from source

```sh
git clone https://github.com/Vedant-29/mica.git
cd mica
make install   # build and install to /Applications
make run       # install and launch
make test      # run the tests
```

No paid Apple Developer account is needed. Always launch from `/Applications`, not the built binary from a shell, or macOS gives the permissions to your terminal instead of Mica.

By default the app is ad-hoc signed, so permission grants reset on every install. To keep them, copy `Local.mk.example` to `Local.mk` and set a stable identity:

```make
SIGN_IDENTITY = Apple Development: Your Name (TEAMID)
```

List identities with `security find-identity -v -p codesigning`. Run `make verify` to check the signature. `Local.mk` is gitignored. If you fork the app, also set your own `BUNDLE_ID` there.

## First run

Mica needs no Accessibility, Screen Recording, or Full Disk Access permission. A few things are still up to you:

1. Do Not Disturb (optional). macOS 26 has no API to turn Focus on, so Mica runs two Shortcuts you create once. In the Shortcuts app, make a shortcut with the Set Focus action (Do Not Disturb, On) named exactly `Mica Do Not Disturb On`, and another set to Off named exactly `Mica Do Not Disturb Off`. Then press Test in Mica > Settings > Features.
2. Hide Menu Bar Icons (optional). Hold Command and drag Mica's `‹` marker in the menu bar to where you want the cut-off. Everything to its left hides.
3. If Mica's icon does not appear on macOS 26, allow it in System Settings > Control Center > Menu Bar.

Settings open from the menu bar icon, or by URL:

```sh
open mica://settings   # also mica://windows, mica://features, mica://triggers
```

## Releasing

`VERSION` is the source of truth. Run:

```sh
make release BUMP=patch   # or minor / major
```

This bumps `VERSION`, commits, tags `vX.Y.Z`, and pushes. GitHub Actions runs the tests, builds a signed DMG, and publishes a release. A tag with a hyphen (`v0.3.0-rc1`) is published as a prerelease. The website needs no redeploy because its download link always points to the latest release.

## Notes

- Reminders use Mica's own banner. macOS only grants notification access to notarized Developer ID apps.
- Some Apple-internal screen captures are not counted by the window server, so Mica cannot detect them.
- Only menu bar icons can be hidden, not the whole menu bar, because macOS 26 reads that setting at login.
- Dock and screen capture detection use private APIs (`CoreDockSetAutoHideEnabled`, `CGSIsScreenWatcherPresent`), which may change between macOS versions.
- After a reboot, crash recovery skips restoring windows, since hidden-app state does not survive a restart.

## License

MIT. See [LICENSE](LICENSE).
