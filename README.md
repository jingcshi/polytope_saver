# polytope_saver

A macOS 26 (Tahoe) screensaver featuring the six convex regular 4-polytopes:
5-cell, 8-cell, 16-cell, 24-cell, 120-cell, 600-cell.

**Status: evaluation.** An off-the-shelf saver already exists (below). A custom
build only proceeds if it falls short. See `TODO.md`.

## Off-the-shelf: XScreenSaver `Polytopes`

[XScreenSaver](https://www.jwz.org/xscreensaver/) (jwz) ships `Polytopes`
(Carsten Steger, 2003) as a native `.saver`. Current release 6.17 (2026-10-15),
requires macOS 14.6+. Its author runs macOS 14, so Tahoe support isn't tested upstream.

- Install everything: `brew install --cask xscreensaver` (runs a `.pkg`, needs admin), or
- Install only this saver: open the DMG and copy `Polytopes.saver` into
  `~/Library/Screen Savers/` (no admin needed).

Capabilities ([manpage](https://man.archlinux.org/man/extra/xscreensaver/polytopes.6.en)):

| Aspect | Polytopes offers |
| --- | --- |
| Polytope | any one of the six, or random |
| 4D→3D | perspective or orthographic |
| 3D→2D | perspective or orthographic |
| Rendering | wireframe, solid faces, or transparent faces |
| Colour | single (red), or hue wheel by unrotated w-depth |
| Motion | constant-speed rotation in all six planes (XY XZ YZ XW YW ZW); simultaneous non-zero speeds give double rotations |

Not offered: slices, stereographic projection, camera fly-through, cell-wise
rendering or colouring, info overlay, clock, slideshow transitions,
themes. Renders with OpenGL, which Apple has deprecated but still ships.

## Building a custom saver on macOS 26 — what's needed

- **Xcode** (full app, not just CLT; this machine currently has CLT only).
  Template: *macOS → Screen Saver*. Output is a `.saver` bundle whose
  `NSPrincipalClass` subclasses `ScreenSaverView` (an `NSView`).
- **Install / enable:** copy the `.saver` to `~/Library/Screen Savers/` (or
  double-click it) → System Settings → Screen Saver → pick it. Options sheet
  = `hasConfigureSheet` / `configureSheet`. No admin needed.
- **Hosting:** third-party savers run inside `legacyScreenSaver.appex`, which
  is buggy in Sonoma/Sequoia/Tahoe. Known workarounds:
  - Drive rendering from your own `MTKView` / display link, not
    `animateOneFrame` (the host can stop calling it).
  - Load Metal shaders with `makeDefaultLibrary(bundle: Bundle(for: Self.self))`
    — the default library resolves against the host app.
  - Each activation creates a new `ScreenSaverView` without destroying the
    old one; `stopAnimation` is effectively preview-only. Observe the
    `com.apple.screensaver.willstop` distributed notification and exit the
    process ~1 s later (Tahoe fires it too early).
  - Iterate with `killall legacyScreenSaver` (sometimes
    `killall -m WallpaperAgent`) after each reinstall; settings cache aggressively.
  - Thumbnail: ship `thumbnail.png` *and* set `ScreenSaverThumbnail` in Info.plist.
- **Interactivity:** essentially none. Any key/mouse input dismisses the saver;
  only the configure sheet is interactive. A clock or info overlay is just
  drawn content.
- **SwiftUI** is unreliable for the main view (fine for the configure sheet);
  use AppKit + Metal.
- **Signing:** ad-hoc / local signing is fine for personal use; notarisation
  is needed only to distribute.

References:
[ScreenSaverMinimal (Aerial team template with Tahoe fixes)](https://github.com/AerialScreensaver/ScreenSaverMinimal),
[liquid-glass-screensaver (Metal example)](https://github.com/destefanis/liquid-glass-screensaver),
[zsmb.co Tahoe notes](https://zsmb.co/building-a-macos-screen-saver-in-kotlin/),
[Michael Tsai roundup](https://mjtsai.com/blog/2025/12/10/how-to-make-a-macos-screen-saver/).
Geometry/rendering prior art (not savers):
[mwalczyk/polychora](https://github.com/mwalczyk/polychora) (slices, tetrahedral cells),
Hollasch, *Four-Space Visualization of 4D Objects*.
