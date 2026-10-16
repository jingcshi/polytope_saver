# TODO

## Phase 0 — evaluate off-the-shelf

- [ ] Install `Polytopes.saver` from XScreenSaver 6.17 into `~/Library/Screen Savers/`.
- [ ] Check it on Tahoe 26.4: runs fullscreen, preview works, no `legacyScreenSaver` CPU pile-up after several activations.
- [ ] Decide whether it's good enough. If it is, stop here. If not, list the gaps that justify a custom build.

## Phase 1 — design (only if Phase 0 falls short)

Open questions. `Polytopes` defaults are in brackets.

1. Visualisation: slices / orthographic / perspective / stereographic / slideshow. [perspective or orthographic projection]
2. V/E/F/C rendering; whether cells are rendered at all. [wireframe or faces; no per-cell treatment]
3. Motion: camera fly-in to inner cells; XYZ-only vs XW/YW/ZW vs double rotations. [constant six-plane speeds; fixed camera]
4. Aesthetics: colour themes, textures. [red, or w-depth hue]
5. Extras: info panel (name, Schläfli symbol, V/E/F/C counts, symmetry group); clock. Interactivity is limited to the configure sheet. [none]

## Phase 2 — build prerequisites

- [ ] Install Xcode (only CLT present).
- [ ] Start from the ScreenSaverMinimal template; Swift + Metal; apply the Tahoe workarounds listed in README.
