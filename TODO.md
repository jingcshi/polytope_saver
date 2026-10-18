# TODO

## Decided

- Visualisation: perspective and stereographic, morphing within each polytope's slot.
- Elements: edge tubes, vertex spheres, translucent faces; no cell rendering.
- Motion: Hopf-aligned isoclinic rotation (Petrie double rotation for the 5-cell) + slow drift.
- Extras: info card, clock, slideshow of all six, options sheet.
- Fly-through: stop rotation → camera to projection centre → 360° pan → withdraw; off / 120+600 / all; speed sliders: Animation (hold, pan, fades, morph), Motion (approach, withdraw), Rotation (ω; spin-up/down ∝ √ω).
- Packaging: ExtensionKit `.appex` (private API) inside a stub `/Applications/Polychora.app`. Legacy `.saver` kept as `make install-legacy`; its host clipped the canvas to the wrong display's size on the secondary monitor (~30% of sessions), which nothing inside the bundle could fix.

## Now

- [ ] Transition polish: the cross-fade is a plain fade to background; consider a 4D "dissolve" or zoom.
- [ ] Antialiasing of thin far tubes (MSAA 4× now); maybe line-width floor in pixels.
- [ ] Info card drift for burn-in safety on external OLEDs.
- [ ] Stereographic framing: choose the base orientation so a Hopf ring passes through the pole (tunnel fly-through) vs. ring-torus side view.
- [ ] EDR / wide gamut output for highlights.
- [ ] Polytope materials and textures (next round). Reference: the "Dimensions" film (Jos Leys, Étienne Ghys, Aurélien Alvarez), whose fly-in and pan our camera independently reproduces.
    - [ ] Glass / acrylic texture [reference media 1](https://en.wikipedia.org/wiki/120-cell#/media/File:120-cell_perspective-cell-first-02.png), [reference media 2](https://en.wikipedia.org/wiki/120-cell#/media/File:120-cell.gif)

## Later

- [ ] Theme backgrounds, phase 2 (scenes; background stays out of the perspective → stereographic morph):
  - [ ] Cosmos: Hubble-like star fields, nebulae, galaxies. Parallax during the fly-in, scene rotation for the pan, optional gravitational lensing.
  - [ ] Gallery: an infinite, Escher-style lit corridor of mathematical art. A real 3D scene, dynamically rendered; parallax or a backdrop cylinder can't cover the pan.
  - [ ] Cyber: remastered retro xscreensaver look. Floating equations, gear arcs and cube tessellations with background bokeh; info panels drawn as a HUD frame.
  - [ ] Void: pure black, a faint distant slate-grey 3D perspective grid as scale anchor, and a minimal distant key light.
- [ ] Optional cell rendering (shrunken cells, Hopf-ring colouring) as a mode.
- [ ] The 41 non-prismatic irregular uniform convex polychora
    - [ ] A₄ family (8)
        - Rectified 5-cell
        - Bitruncated 5-cell
        - Runcinated 5-cell
        - Cantellated 5-cell
        - Truncated 5-cell
        - Runcitruncated 5-cell
        - Cantitruncated 5-cell
        - Omnitruncated 5-cell
    - [ ] B₄ family (10)
        - Truncated 16-cell
        - Rectified tesseract
        - Bitruncated tesseract
        - Runcinated tesseract
        - Cantellated tesseract
        - Runcitruncated 16-cell
        - Truncated tesseract
        - Runcitruncated tesseract
        - Cantitruncated tesseract
        - Omnitruncated tesseract
    - [ ] F₄ family (9)
        - Rectified 24-cell
        - Bitruncated 24-cell
        - Runcinated 24-cell
        - Cantellated 24-cell
        - Truncated 24-cell
        - Runcitruncated 24-cell
        - Cantitruncated 24-cell
        - Omnitruncated 24-cell
        - Snub 24-cell
    - [ ] H₄ family (13)
        - Rectified 600-cell
        - Truncated 600-cell
        - Rectified 120-cell
        - Cantellated 600-cell
        - Bitruncated 120-cell
        - Cantitruncated 600-cell
        - Runcinated 120-cell
        - Cantellated 120-cell
        - Runcitruncated 600-cell
        - Truncated 120-cell
        - Runcitruncated 120-cell
        - Cantitruncated 120-cell
        - Omnitruncated 120-cell
    - [ ] Non-Wythoffian (1)
        - Grand antiprism
- [ ] The 10 regular star polychora, if rendering is feasible
    - Icosahedral 120-cell {3, 5, 5/2}
    - Small stellated 120-cell {5/2, 5, 3}
    - Great 120-cell {5, 5/2, 5}
    - Grand 120-cell {5, 3, 5/2}
    - Great stellated 120-cell {5/2, 3, 5}
    - Grand stellated 120-cell {5/2, 5, 5/2}
    - Great grand 120-cell {5, 5/2, 3}
    - Great icosahedral 120-cell {3, 5/2, 5}
    - Grand 600-cell {3, 3, 5/2}
    - Great grand stellated 120-cell {5/2, 3, 3}

## Done

- [x] Appex preview detection verified. The thumbnail gives `preview (no didstart, Settings in front)`; the Preview button and a hot corner give `full (didstart)`. Rule: `com.apple.screensaver.didstart` within 3 s of attach means full; otherwise wait 0.3 s, and System Settings frontmost means preview.
- [x] Theme backgrounds, phase 1: Sky added (two light, two dark themes). Ink and Sky have a horizontal glow band, calibrated. Porcelain and Brass have a warm backlight halo and a rim light; Porcelain as designed, Brass's halo cut to 65%.
- [x] Speed controls regrouped by perception: Animation / Motion / Rotation sliders (slow → fast, Flurry-style ticked sliders with captions); options sheet sized by its contents (fixed control widths) so System Settings no longer clips it.
- [x] Appex verified on macOS 27 with built-in + DELL: no display dysfunction over 20 hot-corner triggers and 20 settings previews (legacy host's wrong-canvas and post-rapid-trigger blackouts are gone).
- [x] Verified that the options sheet closes via `configureSheetDidEnd` and the host app's activation (PaperSaver) works.
- [x] Speed constants calibrated: spin 2 s × √ω, approach/withdraw 9 s, pan 36 s, hold 36 s (all at speed 1); slider range ¼×–4×.
- [x] Fly-through tuned