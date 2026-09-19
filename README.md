# BendyFree

A macOS 14+ menu-bar desktop fold experiment, with a static promotional website.

## Build and test

```sh
swift test --package-path BendyFreeApp
swift build --package-path BendyFreeApp -c release
```

The website lives in `site/` (`index.html`, `style.css`, `main.js`); it needs no build step. Deploy with `npx wrangler deploy` (config in `wrangler.jsonc`). Run `./make-dmg.sh` to build `site/BendyFree.dmg` before deploying.

## Current behavior

The app polls the Apple hinge sensor on a serial background queue. Below 110 degrees
it fades in a live full-screen blur (`NSVisualEffectView`) with a darkening gradient,
reaching full strength at 30 degrees. It needs no Screen Recording permission. It does
not deform other apps' windows.

The overlay passes clicks through. Clicking dismisses it; reopening past 110 degrees
arms the next fold. Valid sensor updates keep the effect active during a slow close.
If updates stop for a second, the overlay dismisses. Preparing a capture has a separate
five-second timeout. Missing sensor data, sleep, or a display change also dismisses it.
Global keyboard dismissal may depend on macOS permissions; click dismissal and the
stale-sensor check do not require keyboard monitoring access. The menu shows effect
status and missing Screen Recording permission explicitly.

## Try the repaired app

1. Quit the old BendyFree process before opening the repaired bundle in `BendyFreeApp/dist/`.
2. Use **Allow Screen Recording…** in its menu and grant permission in System Settings.
   Relaunch if macOS requests it.
3. First use **Test Fold**, starting at 100 and moving left. Check that clicking
   dismisses the effect. The preview should stay visible while holding a folded angle.
   Reset the slider to 100 before another test.
4. Choose **Resume Hardware Sensor**. With the lid open, check that the menu reports
   a plausible changing hardware angle before slowly lowering the lid below 90 degrees.
   Check the status row beneath the angle if the effect does not appear.
5. Verify that reopening, clicking, and sleep/wake always restore the desktop.

The manual slider suspends hardware polling so real sensor readings cannot overwrite
the test. This repair is a responsiveness baseline, not a verified final visual effect.

## Remaining work

- Validate sensor readings and performance during physical lid movement on an M3 Air.
- Tune the blur material and strength on hardware.
- Update promotional claims, add a real DMG/release link, and document distribution signing.
