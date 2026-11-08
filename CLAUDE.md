# Simple Snip

A macOS take on the Windows Snipping Tool workflow, with its own name and icon. Open source (MIT) at github.com/Pavloff207/simple-snip. Developer ID signing and notarization come later.

## What it does (and doesn't)
- Rectangle (default) or freeform snip (Settings → Snipping → Snip shape), on a frozen copy of every display.
- Editor: pen and highlighter (color palettes, size sliders; default pen red), eraser, crop, undo/redo, copy, save as PNG/JPEG, print.
- Settings: hotkey (default ⌘⇧2), launch at login, auto-copy edits, ask to save edits.
- Shown in the Dock and the menu bar. Each snip opens its own editor window, and that's intended (no "multiple windows" setting).
- Deliberately left out: delay timer, screen recording, OCR/text extraction, ruler.

## Tech
- Swift 5 mode, SwiftUI + AppKit, macOS 26+ deployment target. No third-party packages.
- ScreenCaptureKit freezes the screens; a borderless `.screenSaver`-level overlay takes the outline.
- Carbon `RegisterEventHotKey` for the global shortcut (no Accessibility permission needed).
- `SMAppService.mainApp` for launch at login.
- The pbxproj uses a file-system-synchronized group, so new files in `SimpleSnip/` are picked up automatically.
- The icon comes from `Tools/make_icon.swift`.

## Signing
- Manual signing, identity "Apple Development", team `6VU6S56WNT`, hardened runtime.
- A stable signature matters: screen recording permission is tied to it, and ad-hoc signing makes macOS ask again after every build.
- On a new Mac, sign in to Xcode → Settings → Accounts and create an Apple Development certificate for this team. If codesign says the certificate isn't trusted, add Apple's WWDR G3 intermediate certificate to the login keychain.

## Build and install
Keep DerivedData outside this Google Drive folder:

```bash
xcodebuild -project SimpleSnip.xcodeproj -scheme SimpleSnip -configuration Debug -derivedDataPath "$TMPDIR/SimpleSnipDerivedData" build
```

```bash
pkill -x SimpleSnip; sleep 1; rm -rf /Applications/SimpleSnip.app && ditto "$TMPDIR/SimpleSnipDerivedData/Build/Products/Debug/SimpleSnip.app" /Applications/SimpleSnip.app && open /Applications/SimpleSnip.app
```

## Releases
- Public builds are universal (`-destination 'generic/platform=macOS' ARCHS="arm64 x86_64"`) and ad-hoc signed until there's a Developer ID, so they don't carry the personal Apple Development certificate.
- Attach the build as `SimpleSnip.zip` so `releases/latest/download/SimpleSnip.zip` keeps working. Update CHANGELOG.md and MARKETING_VERSION.
- Regenerate README/site images with `Tools/demo/make_demo.sh` when the UI changes.
- The website is `docs/index.html` (GitHub Pages from `main` /docs). The Homebrew tap is github.com/Pavloff207/homebrew-tap.

## Working agreements
- After a change, rebuild and reinstall to /Applications without asking. Losing an in-progress snip is fine.
- Commit only when asked. Commit as Andrey Pavlov <andrey@pavloff.com>.
- The folder syncs through Google Drive. Don't work on it from two Macs at the same time.
- In zsh, `log` is a builtin, so use `/usr/bin/log` to read the app's logs (subsystem `com.pavloff.SimpleSnip`).
