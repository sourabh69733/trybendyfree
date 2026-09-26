# BendyFree

A free macOS menu-bar app that blurs and darkens your desktop as you close the
MacBook lid, plus its promotional website.

## Build and test

```sh
swift test --package-path BendyFreeApp
swift build --package-path BendyFreeApp -c release
```

The website lives in `site/` (`index.html`, `style.css`, `main.js`); it needs no
build step. Deploy with `npx wrangler deploy` (config in `wrangler.jsonc`). Run
`./make-dmg.sh` to rebuild `site/BendyFree.dmg` from the current source before
deploying — the DMG is a static file checked into `site/`, so it does not update
itself when the app code changes.

## Current behavior

The app polls the Apple hinge sensor on a serial background queue, smoothing
readings and slowing the poll rate while the lid is comfortably open. Below 110
degrees it fades in a live full-screen blur (`NSVisualEffectView`) with a
darkening overlay, reaching full strength at 30 degrees. It needs no Screen
Recording permission and does not capture or deform other apps' windows.

Three styles (Silk, Shade, Frost) share the same blur material but differ in
`appearance` (dark/light) and shadow tint — not the material itself, since
swapping materials between styles risked leaving the blur stuck.

Only the Escape key dismisses the effect early; ordinary clicks and keystrokes
elsewhere on the system do not. Reopening the lid past 110 degrees arms the next
fold. If sensor updates stop for 2 seconds, or the reading becomes invalid, the
overlay dismisses. Sleep and display changes also dismiss it. The menu shows the
live angle, its source (hardware/simulated/unavailable), and the current effect
status.

## Try it

1. Run `./clean-start.sh` to build, test, and install to `/Applications`.
2. Open the 📐 menu. Use **Test Fold** (drag left from 120 toward 25) to preview
   the effect without touching the lid. Check that an ordinary click elsewhere
   does *not* dismiss it, and Escape does.
3. Click **Resume Hardware Sensor**, then close the lid past 110 degrees with the
   Mac awake (`caffeinate -d` helps prevent display sleep from hiding it).
4. Try each style from the **Style** submenu, including switching back to Silk
   afterward, and confirm each looks distinct.

## Remaining work

- Validate on hardware other than the M3 Air this was built against.
- Notarize (needs a paid Apple Developer account) so first launch doesn't need
  right-click → Open.
- Publish the GitHub repo, or drop the "open source" claim from the site - the
  footer link is still a placeholder.
