// ── BendyFree - Scroll-driven lid bend effect ──
(function () {
  'use strict';

  // DOM refs
  var figure = document.querySelector('.figure');
  var lid = document.getElementById('lid');
  var wallpaperImg = document.getElementById('wallpaperImg');
  var shade = document.getElementById('shade');
  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Animation state
  var lead = 250;      // px: start closing this far before the figure reaches the top
  var travel = 400;     // px: scroll distance from start to fully closed
  var maxBlur = 14;     // px: blur radius at full close, applied uniformly to the whole wallpaper
  var anchor = 0;       // the figure's fixed position in the page (not affected by scroll)
  var current = 0;
  var target = 0;

  function computeAnchor() {
    anchor = figure ? figure.offsetTop : 0;
  }
  computeAnchor();

  // ── Clock ──
  function updateClock() {
    var now = new Date();
    var days = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
    var months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    var dateStr = days[now.getDay()] + ', ' + months[now.getMonth()] + ' ' + now.getDate();
    var h = now.getHours();
    var m = now.getMinutes();
    var timeStr = (h > 12 ? h - 12 : h || 12) + ':' + (m < 10 ? '0' : '') + m;

    var dateEl = document.getElementById('clockDate');
    var timeEl = document.getElementById('clockTime');
    if (dateEl) dateEl.textContent = dateStr;
    if (timeEl) timeEl.textContent = timeStr;
  }
  updateClock();
  setInterval(updateClock, 30000);

  // ── Year in footer ──
  var yearEl = document.getElementById('year');
  if (yearEl) yearEl.textContent = new Date().getFullYear();

  // ── Smoothstep for natural easing ──
  function smoothstep(t) {
    return t * t * (3 - 2 * t);
  }

  // Tied to the figure's fixed page position, not absolute scroll-from-top.
  // Closing and reopening both happen over the same short, bounded window
  // around that position - so reopening never means scrolling all the way
  // back to the top, however far down the page you went. At scrollY=0 this
  // is always 0 (fully open), since the figure sits below the top of the page.
  function progress() {
    var raw = (window.scrollY - (anchor - lead)) / travel;
    return Math.min(Math.max(raw, 0), 1);
  }

  // ── Paint one frame: the lid starts closing first, the bend catches up and finishes it ──
  function paint(raw) {
    // Closing runs the full scroll so the motion is visible the whole time.
    var closeP = smoothstep(Math.min(Math.max(raw / 0.85, 0), 1));
    // The bend starts just after closing begins and overlaps it, so it is visible while closing.
    var bendP = smoothstep(Math.min(Math.max((raw - 0.15) / 0.85, 0), 1));

    // Bezel, screen and notch tilt together - nothing rotates independently of the case.
    // A long perspective distance keeps the near edge from magnifying past the keyboard's width.
    // Stops just short of 90deg (perfectly edge-on): at exactly 90 the lid
    // vanishes into an invisible line instead of reading as closed.
    lid.style.transform = 'perspective(8000px) rotateX(' + (-(closeP * 86)).toFixed(2) + 'deg)';

    // One blur radius applied to the whole wallpaper at once - no masks, so
    // there is no region of the screen that can be left out.
    wallpaperImg.style.filter = 'blur(' + (bendP * maxBlur).toFixed(2) + 'px)';

    // Flat shadow, same opacity across the entire screen.
    shade.style.opacity = (closeP * 0.25 + bendP * 0.45).toFixed(3);
  }

  // ── Animation loop ──
  function frame() {
    if (!reduced) {
      // Lerp for smooth trailing
      current += (target - current) * 0.08;
      if (Math.abs(target - current) < 0.0005) current = target;
    } else {
      current = target;
    }
    paint(current);
    requestAnimationFrame(frame);
  }

  // ── Scroll listener ──
  function onScroll() {
    target = progress();
  }

  function onResize() {
    computeAnchor();
    target = progress();
  }

  // ── Init ──
  function start() {
    computeAnchor(); // re-measure once images/fonts have settled the layout
    window.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('resize', onResize, { passive: true });
    target = current = progress();
    paint(current);
    requestAnimationFrame(frame);
  }

  if (document.readyState === 'complete') {
    start();
  } else {
    window.addEventListener('load', start);
  }
})();

