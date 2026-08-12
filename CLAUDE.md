# Mica

A macOS menu bar app that hides your desktop — windows, Dock, menu bar icons,
wallpaper, desktop icons and notifications — on a keystroke, or by itself when it
detects the screen being shared or recorded.

Swift 6.2, SwiftUI + AppKit, no Xcode project. Built with SwiftPM and a Makefile.

## Layout

    Sources/Mica/          App target: SwiftUI scenes, menu bar popover, Settings
    Sources/MicaCore/      Everything testable — effects, monitors, persistence
      Core/                Mode, features, engagement decision (pure, unit-tested)
      Effects/             One type per hideable thing; all conform to PrivacyEffect
      Monitors/            Screen capture, displays, running apps, schedule
      SystemBridge/        The AppKit and private-ish plumbing each effect needs
    Scripts/               bundle / install / dmg / release
    Tools/mkicon.swift     Generates AppIcon.icns from the vector mark

The whole package is `defaultIsolation(MainActor)` — see Package.swift. Assume
main-actor isolation and don't add per-declaration annotations for it.

## The two ideas worth knowing

**Effects are reversible and crash-safe.** Every `PrivacyEffect` captures prior
state before mutating, and that snapshot is flushed to disk *before* anything
changes, so a crash mid-hide can be undone on next launch (`CrashRecovery`).
Effects whose side effects are process-local — the wallpaper cover window, the
menu bar spacer — declare `NoPriorState`, because they die with the process.

**Engagement is a pure function.** `EngagementEngine.decide` takes inputs and
returns a decision with no side effects, which is why it is the most heavily
tested thing here. `EngagementController` is the impure half that watches the
world and feeds it.

## Working on it

    make build     swift build
    make test      swift test          (also run by CI on every push)
    make install   build, sign, copy to /Applications
    make run       install then launch via LaunchServices
    make dmg       drag-to-Applications disk image in dist/

Always launch through `make run` or LaunchServices, never the binary directly:
macOS attributes TCC permission grants to the *launching* process, so running the
binary from a shell grants them to your terminal instead of to Mica.

`Local.mk` (gitignored) holds your signing identity. Copy `Local.mk.example`.
Without it the build is ad-hoc signed, which works but resets permission grants on
every rebuild, because an ad-hoc designated requirement is derived from the
cdhash.

## Releasing

`VERSION` is the source of truth. The tag is the trigger. They must agree — the
release workflow fails the build if they don't.

    make release BUMP=patch     0.1.0 -> 0.1.1   bug fixes
    make release BUMP=minor     0.1.0 -> 0.2.0   features
    make release BUMP=major     0.1.0 -> 1.0.0   breaking settings/bundle change

That bumps VERSION, commits, tags `vX.Y.Z`, and pushes. `.github/workflows/release.yml`
then runs the tests, builds a signed DMG, and publishes a GitHub Release with
`Mica.dmg` and its SHA-256 attached.

**Do not hand-edit VERSION or hand-create tags.** The script is the only thing
that sets both together, and a mismatch stops the release.

**Do not commit the DMG anywhere.** The website links to
`https://github.com/Vedant-29/mica/releases/latest/download/Mica.dmg`, a URL
GitHub resolves to the newest non-prerelease asset. Publishing a release is all
that is needed for the site to serve the new build; the site is not redeployed.

A tag containing a hyphen (`v0.3.0-rc1`) is published as a prerelease, so it is
downloadable but does not become `latest`.

### Signing in CI

Two optional repository secrets:

  MACOS_CERT_P12        base64 of a .p12 export of the codesigning identity
  MACOS_CERT_PASSWORD   its export password

Without them CI signs ad-hoc, and every update reads to macOS as a new app, so
users re-grant Screen Recording and Accessibility each time. With them the
designated requirement is stable and grants persist.

The app is **not notarized** — that needs a paid Developer ID, and the current
identity is Apple Development. First launch therefore requires right-click →
Open, which the website says. If a Developer ID is ever added, notarization and
stapling belong in the release workflow, and that instruction should come off the
site at the same time.

## House rules

- Comments explain *why*, especially where the code looks odd because macOS is
  odd. There is a lot of that here; match the register of what's already written.
- Anything that can be a pure function in `MicaCore/Core` should be, and should
  have a test.
- Never let a privacy feature fail open. If an effect cannot verify it did what
  it claimed, it undoes itself and says so — see `MenuBarSpacerController`, which
  refuses to hide Mica's own icon because doing so locks the user out of the app.
