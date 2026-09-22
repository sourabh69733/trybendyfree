// ── BendyFree - Scroll-driven lid bend effect ──
(function () {
  'use strict';

  // DOM refs
  var screen = document.getElementById('screen');
  var blurred = document.querySelectorAll('.art.blurred');
  var shade = document.getElementById('shade');
  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Animation state
  var travel = 900;    // px of scroll for a full bend
  var current = 0;
  var target = 0;

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

  function progress(scrollY) {
    return Math.min(Math.max(scrollY / travel, 0), 1);
  }

  // ── Paint one frame: the lid starts closing first, the bend catches up and finishes it ──
  function paint(raw) {
    // Closing runs the full scroll so the motion is visible the whole time.
    var closeP = smoothstep(Math.min(Math.max(raw / 0.85, 0), 1));
    // The bend starts just after closing begins and overlaps it, so it is visible while closing.
    var bendP = smoothstep(Math.min(Math.max((raw - 0.15) / 0.85, 0), 1));

    screen.style.transform = 'perspective(1400px) rotateX(' + (-(closeP * 72)).toFixed(2) + 'deg)';

    // Progressive blur layers fade in
    for (var i = 0; i < blurred.length; i++) {
      blurred[i].style.opacity = bendP.toFixed(3);
    }

    // Top-edge feather mask - softens the silhouette as it bends
    var t = bendP * 22;
    var mask = 'linear-gradient(to bottom, transparent 0%, rgba(0,0,0,.25) ' +
      (t * 0.25).toFixed(2) + '%, rgba(0,0,0,.65) ' +
      (t * 0.55).toFixed(2) + '%, #000 ' +
      t.toFixed(2) + '%)';
    screen.style.webkitMaskImage = mask;
    screen.style.maskImage = mask;

    // Shadow overlay - a light shadow as it closes, deepening once it bends
    shade.style.opacity = (closeP * 0.35 + bendP * 0.55).toFixed(3);
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
    target = progress(window.scrollY);
  }

  // ── Init ──
  function start() {
    window.addEventListener('scroll', onScroll, { passive: true });
    target = current = progress(window.scrollY);
    paint(current);
    requestAnimationFrame(frame);
  }

  if (document.readyState === 'complete') {
    start();
  } else {
    window.addEventListener('load', start);
  }
})();
