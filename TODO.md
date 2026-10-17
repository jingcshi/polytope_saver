# TODO

## Decided

- Visualisation: perspective and stereographic, morphing within each polytope's slot.
- Elements: edge tubes, vertex spheres, translucent faces; no cell rendering.
- Motion: Hopf-aligned isoclinic rotation (Petrie double rotation for the 5-cell) + slow drift.
- Extras: info card, clock, slideshow of all six, options sheet.
- Packaging: legacy `.saver`.

## Now

- [ ] Verify the installed saver on macOS 27: fullscreen run, System Settings thumbnail/preview, options sheet, multiple monitors, no instance pile-up after several activations.
- [ ] Aesthetics pass in the preview app: pick / refine themes (Ink, Porcelain, Brass are placeholders), tube and vertex sizes per polytope, face opacity, ring colouring on/off.
- [ ] Stereographic framing: choose the base orientation so a Hopf ring passes through the pole (tunnel fly-through) vs. ring-torus side view.

## Later

- [ ] Transition polish: the cross-fade is a plain fade to background; consider a 4D "dissolve" or zoom.
- [ ] Antialiasing of thin far tubes (MSAA 4× now); maybe line-width floor in pixels.
- [ ] EDR / wide gamut output for highlights.
- [ ] Info card drift for burn-in safety on external OLEDs.
- [ ] Optional cell rendering (shrunken cells, Hopf-ring colouring) as a mode.
