# TODO

## Decided

- Visualisation: perspective and stereographic, morphing within each polytope's slot.
- Elements: edge tubes, vertex spheres, translucent faces; no cell rendering.
- Motion: Hopf-aligned isoclinic rotation (Petrie double rotation for the 5-cell) + slow drift.
- Extras: info card, clock, slideshow of all six, options sheet.
- Fly-through: stop rotation → camera to projection centre → 360° pan → withdraw; off / 120+600 / all; speed sliders: Animation (hold, pan, fades, morph), Motion (approach, withdraw), Rotation (ω; spin-up/down ∝ √ω).
- Packaging: ExtensionKit `.appex` (private API) inside a stub `/Applications/Polychora.app`. Legacy `.saver` kept as `make install-legacy`; its host clipped the canvas to the wrong display's size on the secondary monitor (~30% of sessions), which nothing inside the bundle could fix.

## Now

- [ ] Appex preview detection: `loadView()` gets the main screen's frame, so `isPreview` may be false in the System Settings thumbnail (full MSAA, 120 fps, overlay on). Check which `loadView` variant the framework calls.
- [ ] Aesthetics pass in the preview app: pick / refine themes (Ink, Porcelain, Brass are placeholders), tube and vertex sizes per polytope, face opacity, ring colouring on/off.
- [ ] Calibrate speed constants: spin 3 s × √ω, approach/withdraw 7 s, pan 18 s, hold 30 s (all at speed 1); slider range ¼×–4×.
- [ ] Fly-through tuning: near-camera tube occlusion at the centre, sparse view inside small polytopes (8-cell).
- [ ] Stereographic framing: choose the base orientation so a Hopf ring passes through the pole (tunnel fly-through) vs. ring-torus side view.

## Later

- [ ] Transition polish: the cross-fade is a plain fade to background; consider a 4D "dissolve" or zoom.
- [ ] Antialiasing of thin far tubes (MSAA 4× now); maybe line-width floor in pixels.
- [ ] EDR / wide gamut output for highlights.
- [ ] Info card drift for burn-in safety on external OLEDs.
- [ ] Optional cell rendering (shrunken cells, Hopf-ring colouring) as a mode.
- [ ] Additional themes: various flavors of glassy and metallic [reference media 1](https://en.wikipedia.org/wiki/120-cell#/media/File:120-cell_perspective-cell-first-02.png), [reference media 2](https://en.wikipedia.org/wiki/120-cell#/media/File:120-cell.gif)
- [ ] The 10 regular 4D star polychora, if rendering is feasible

## Done

- [x] Speed controls regrouped by perception: Animation / Motion / Rotation sliders (slow → fast, Flurry-style ticked sliders with captions); options sheet sized by its contents (fixed control widths) so System Settings no longer clips it.
- [x] Appex verified on macOS 27 with built-in + DELL: no display dysfunction over 20 hot-corner triggers and 20 settings previews (legacy host's wrong-canvas and post-rapid-trigger blackouts are gone).
- [x] Verified that the options sheet closes via `configureSheetDidEnd` and the host app's activation (PaperSaver) works.
