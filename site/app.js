(function () {
  "use strict";

  // Themes mirror Sources/SheepdogCore/Palette.swift: bg, surface, text, muted, accent, late.
  var themes = [
    ["Harbor", "#0f1012", "#0f1012", "#ffffff", "#aaa59b", "#f3e3b8", "#ff7361"],
    ["Dragonsgale", "#0d0a08", "#1a1310", "#f4e6d8", "#b89c86", "#ff7a1a", "#ff7361"],
    ["Greek Fire", "#120805", "#24100a", "#ffe9c2", "#c99a6b", "#ffb000", "#ff7361"],
    ["Phosphor", "#050a05", "#0b160b", "#b8ffb0", "#5fae5a", "#33ff33", "#ff7361"],
    ["Redcoat", "#0e0c0c", "#1c1919", "#f4f1ee", "#a9a3a0", "#d6282f", "#ff7361"],
    ["Hussar", "#1a0608", "#2b0c10", "#f3e3c0", "#c2a272", "#d4a63a", "#ff7361"],
    ["Tyrian", "#140816", "#231027", "#f0e2f5", "#b597bf", "#b04cc8", "#ff7361"],
    ["Ultramarine", "#060b1f", "#0e1736", "#e3e9ff", "#8e9cc9", "#4f78ff", "#ff7361"],
    ["Verdigris", "#0a1614", "#12241f", "#dff3ec", "#86b3a5", "#43b39a", "#ff7361"],
    ["Old Ironsides", "#0c0c0d", "#18181a", "#f5f5f2", "#a8a8a3", "#c07a44", "#ff7361"],
    ["Bletchley", "#ece4cf", "#f6f0dd", "#1a1a17", "#5c5748", "#7a2e12", "#9c1c14"]
  ];

  function lum(hex) {
    var v = [1, 3, 5].map(function (i) {
      var c = parseInt(hex.substr(i, 2), 16) / 255;
      return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    });
    return 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2];
  }
  function contrast(a, b) {
    var x = lum(a), y = lum(b);
    return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
  }
  // Same rule as Palette.onAccent: the background when it passes AA, else black or white.
  function onAccent(bg, accent) {
    if (contrast(bg, accent) >= 4.5) return bg;
    return contrast("#ffffff", accent) >= contrast("#000000", accent) ? "#ffffff" : "#000000";
  }

  var root = document.documentElement;
  function apply(t) {
    var s = root.style;
    s.setProperty("--bg", t[1]);
    s.setProperty("--surface", t[2]);
    s.setProperty("--text", t[3]);
    s.setProperty("--muted", t[4]);
    s.setProperty("--accent", t[5]);
    s.setProperty("--late", t[6]);
    s.setProperty("--on", onAccent(t[1], t[5]));
    s.colorScheme = lum(t[1]) > 0.4 ? "light" : "dark";
    s.setProperty("--glyph-invert", lum(t[1]) > 0.4 ? "0" : "1");
    s.setProperty("--rule", "color-mix(in srgb, " + t[3] + " 22%, transparent)");
    try { localStorage.setItem("theme", t[0]); } catch (e) {}
  }

  var tiles = document.getElementById("tiles");
  var order = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  var buttons = [];
  order.forEach(function (idx) {
    var t = themes[idx];
    var b = document.createElement("button");
    b.type = "button";
    b.className = "tile";
    b.setAttribute("aria-pressed", "false");
    b.style.background = t[1];
    b.style.color = t[3];
    b.innerHTML = '<span class="aa" style="color:' + t[5] + '">Aa</span><span>' + t[0] + '</span>';
    b.addEventListener("click", function () {
      apply(t);
      buttons.forEach(function (x) { x.setAttribute("aria-pressed", x === b ? "true" : "false"); });
    });
    tiles.appendChild(b);
    buttons.push(b);
  });
  var saved = null;
  try { saved = localStorage.getItem("theme"); } catch (e) {}
  var pick = 0;
  order.forEach(function (idx, i) { if (themes[idx][0] === saved) pick = i; });
  if (pick) apply(themes[order[pick]]);
  buttons[pick].setAttribute("aria-pressed", "true");

  // The alarm sequence: idle, chime, pill, takeover, join, then it starts over.
  var screen = document.getElementById("screen");
  var take = document.getElementById("take");
  var pg = document.getElementById("pg");
  var pt = document.getElementById("pt");
  var tcd = document.getElementById("tcd");
  var mclock = document.getElementById("mclock");
  var rail = document.getElementById("rail").querySelectorAll("button");
  var stages = [
    { n: "idle", ms: 1800 }, { n: "chime", ms: 2600 }, { n: "pill", ms: 4200 },
    { n: "take", ms: 5200 }, { n: "join", ms: 3000 }
  ];
  var cur = 0, timer = null, tick = null, held = false;
  var still = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  function fmt(sec) { return Math.floor(sec / 60) + ":" + (sec % 60 < 10 ? "0" : "") + (sec % 60); }
  function show(i) {
    cur = i;
    var n = stages[i].n;
    screen.dataset.stage = n;
    Array.prototype.forEach.call(rail, function (b) {
      b.setAttribute("aria-current", b.dataset.go === n ? "true" : "false");
    });
    mclock.textContent = n === "idle" ? "9:55 AM" : n === "chime" ? "9:55 AM" : n === "pill" ? "9:58 AM" : "9:59 AM";
    clearInterval(tick);
    var left, total;
    if (n === "pill") {
      left = 125; pt.textContent = fmt(left);
      tick = setInterval(function () { left -= 7; pt.textContent = fmt(Math.max(left, 0)); }, 600);
    }
    if (n === "take") {
      total = 40; left = 40; take.classList.remove("late");
      pg.setAttribute("stroke-dashoffset", "0"); tcd.textContent = "Starts in " + fmt(left);
      tick = setInterval(function () {
        left = Math.max(left - 4, 0);
        tcd.textContent = "Starts in " + fmt(left);
        pg.setAttribute("stroke-dashoffset", String(100 - (left / total) * 100));
      }, 480);
    }
    if (!still && !held) {
      clearTimeout(timer);
      timer = setTimeout(function () { show((cur + 1) % stages.length); }, stages[i].ms);
    }
  }
  Array.prototype.forEach.call(rail, function (b) {
    b.addEventListener("click", function () {
      held = true; clearTimeout(timer);
      show(stages.map(function (s) { return s.n; }).indexOf(b.dataset.go));
      clearTimeout(timer);
      timer = setTimeout(function () { held = false; show(cur); }, 6000);
    });
  });
  if (still) { show(3); } else { show(0); }

  // Copy buttons.
  Array.prototype.forEach.call(document.querySelectorAll("[data-copy]"), function (b) {
    b.addEventListener("click", function () {
      var done = function () { b.textContent = "Copied"; setTimeout(function () { b.textContent = "Copy"; }, 1400); };
      if (navigator.clipboard) navigator.clipboard.writeText(b.dataset.copy).then(done);
    });
  });

  // Show the newest version. The download links use the fixed-name asset on the latest release.
  fetch("https://api.github.com/repos/dcadolph/sheepdog/releases/latest")
    .then(function (r) { return r.ok ? r.json() : Promise.reject(); })
    .then(function (rel) {
      document.getElementById("ver").textContent =
        rel.tag_name + ". Signed and notarized. Open source under Apache 2.0.";
    })
    .catch(function () {});
})();
