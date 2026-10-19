# Installing Polychora

Polychora is a macOS screensaver of the six regular 4D polytopes.

## Requirements

- A Mac with Apple Silicon (M1 or later). Intel Macs are not supported.
- macOS 27. Versions 15 to 26 may work but are untested.
- An administrator account, to put the app in `/Applications`.

## Install

1. Download `Polychora-1.0.0.zip` and double-click it to unzip.
2. Drag `Polychora.app` into the **Applications** folder. It must be there: macOS ignores third-party screensavers anywhere else.
3. Open `Polychora.app`. The app isn't notarised by Apple, so the first launch is blocked with a message that Apple could not verify it. Click **Done**, then:
   - Open **System Settings → Privacy & Security**, scroll down to **Security**, and click **Open Anyway** next to the note about Polychora.
   - Authenticate, then click **Open** in the confirmation that follows.

   Alternatively, in Terminal: `xattr -dr com.apple.quarantine /Applications/Polychora.app`, then open the app normally.
4. Opening the app makes Polychora the screensaver on every display and Space. No window appears. The desktop may flicker once while macOS reloads its wallpaper service.

To pick it by hand instead, choose **Polychora** under **System Settings → Wallpaper → Screen Saver → Other**.

## Options

**System Settings → Wallpaper → Screen Saver**, select Polychora, then **Options…**:

| Option | What it does |
| --- | --- |
| Projection | Perspective, stereographic, or alternating between the two |
| Fly-through | Camera flies into the polytope and pans 360°: off, 120- and 600-cell only, or all |
| Theme | Ink, Sky, Porcelain, Brass |
| Surfaces | None (frame only), Faces (glass, bubbles in stereographic), or Cells (one Hopf ring at a time) |
| Frame colors | Neutral steel, or each polytope's signature colour |
| Speed sliders | Animation, pan, camera motion and rotation, each ¼× to 4× |
| Target frame rate | 30 to 180 fps, default 60 |
| Show info card / clock / frame rate | Text overlays |

**Choosing a frame rate.** Hover over the slider for a reminder. A display can only show whole divisors of its refresh rate, so other values drop to the next lower one: 90 fps on a 120 Hz display runs at 60. Higher rates draw more power and heat. 60 is smooth on any Apple Silicon Mac. 120 makes the camera pans fully smooth on a ProMotion or other 120 Hz display, if the GPU keeps up. **Faces** is the most demanding surface style. On a base M1 or M2, try **Cells** or **None** first if 60 fps isn't sustained (turn on *Show frame rate* to check).

## Uninstall

Pick another screensaver in System Settings, then move `/Applications/Polychora.app` to the Bin.

## Troubleshooting

- **Polychora isn't listed under Other.** Check that the app is in `/Applications` itself, not a subfolder, and open it once. If it still doesn't appear, log out and back in.
- **Stutter or a hot Mac.** Lower the target frame rate, or set Surfaces to Cells or None.
- **Checking the download.** `shasum -a 256 Polychora-1.0.0.zip` should match the checksum on the release page.
