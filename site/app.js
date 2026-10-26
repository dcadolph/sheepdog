(function () {
  "use strict";

  // Collars mirror Sources/SheepdogCore/Palette.swift: bg, surface, text, muted, accent, late.
  var themes = [
    ["Harbor", "#0f1012", "#0f1012", "#ffffff", "#aaa59b", "#f3e3b8", "#ff7361"],
    ["Rose", "#0e0c0c", "#1c1919", "#f4f1ee", "#a9a3a0", "#d6282f", "#ff7361"],
    ["Wildfire", "#120805", "#24100a", "#ffe9c2", "#c99a6b", "#ffb000", "#ff7361"],
    ["Verdigris", "#0a1614", "#12241f", "#dff3ec", "#86b3a5", "#43b39a", "#ff7361"],
    ["Coast", "#060b1f", "#0e1736", "#e3e9ff", "#8e9cc9", "#4f78ff", "#ff7361"],
    ["Grapes", "#140816", "#231027", "#f0e2f5", "#b597bf", "#b04cc8", "#ff7361"],
    ["Concierge", "#ece4cf", "#f6f0dd", "#1a1a17", "#5c5748", "#7a2e12", "#9c1c14"]
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

  // Tug's collar is the only blue in the drawings. It takes the theme's accent, keeping its shading.
  var tugImages = [];
  Array.prototype.forEach.call(document.querySelectorAll('img[src="/assets/tug.png"], img[src="/assets/tug-head.png"]'), function (img) {
    var src = new Image();
    src.onload = function () { tugImages.push({ img: img, src: src }); recolor(currentAccent); };
    src.src = img.getAttribute("src");
  });
  var currentAccent = null;
  function recolor(accent) {
    if (!accent) return;
    if (accent === "orig") { tugImages.forEach(function (o) { o.img.src = o.src.src; }); return; }
    var ar = parseInt(accent.substr(1, 2), 16), ag = parseInt(accent.substr(3, 2), 16), ab = parseInt(accent.substr(5, 2), 16);
    tugImages.forEach(function (o) {
      var c = document.createElement("canvas");
      c.width = o.src.naturalWidth; c.height = o.src.naturalHeight;
      var x = c.getContext("2d");
      x.drawImage(o.src, 0, 0);
      try {
        var d = x.getImageData(0, 0, c.width, c.height), p = d.data;
        for (var i = 0; i < p.length; i += 4) {
          if (p[i + 3] < 204 || p[i + 2] <= p[i] + 30 || p[i + 2] < p[i + 1]) continue;
          var k = (0.299 * p[i] + 0.587 * p[i + 1] + 0.114 * p[i + 2]) / 127;
          p[i] = Math.min(255, ar * k); p[i + 1] = Math.min(255, ag * k); p[i + 2] = Math.min(255, ab * k);
        }
        x.putImageData(d, 0, 0);
        o.img.src = c.toDataURL();
      } catch (e) {}
    });
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
    currentAccent = t[0] === "Harbor" ? "orig" : t[5];
    recolor(currentAccent);
    try { localStorage.setItem("theme", t[0]); } catch (e) {}
  }

  var tiles = document.getElementById("tiles");
  var order = themes.map(function (_, i) { return i; });
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
  // The editor line types itself while the screen is quiet, so the alarm interrupts real work.
  var typed = document.getElementById("typed");
  var line = "backoff = min(backoff*2, q.ceiling)";
  var typer = null;
  function type(n) {
    if (n === "chime") return;
    clearInterval(typer);
    if (n !== "idle" || still) { typed.textContent = line; return; }
    typed.textContent = "";
    typer = setInterval(function () {
      typed.textContent = line.slice(0, typed.textContent.length + 1);
      if (typed.textContent === line) clearInterval(typer);
    }, 105);
  }
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
    type(n);
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

  // Tug's outfits mirror Sources/SheepdogCore/Outfit.swift: the same windows in the same order, read
  // from the viewer's local date. Change both together. ?outfit=<name> forces one to check the art.
  function easterSunday(y) {
    var a = y % 19, b = Math.floor(y / 100), c = y % 100, d = Math.floor(b / 4), e = b % 4;
    var f = Math.floor((b + 8) / 25), g = Math.floor((b - f + 1) / 3), h = (19 * a + b - d - g + 15) % 30;
    var i = Math.floor(c / 4), k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7;
    var m = Math.floor((a + 11 * h + 22 * l) / 451), n = h + l - 7 * m + 114;
    return new Date(y, Math.floor(n / 31) - 1, n % 31 + 1);
  }
  // The nth weekday of a month, with weekday 0 as Sunday (Swift counts Sunday as 1).
  function nthWeekday(y, month, weekday, n) {
    var first = new Date(y, month - 1, 1).getDay();
    return new Date(y, month - 1, 1 + (weekday - first + 7) % 7 + 7 * (n - 1));
  }
  function fixed(sm, sd, em, ed) {
    return function (day) {
      var v = (day.getMonth() + 1) * 100 + day.getDate(), s = sm * 100 + sd, e = em * 100 + ed;
      return s <= e ? v >= s && v <= e : v >= s || v <= e;
    };
  }
  function around(anchor, from, through) {
    return function (day) {
      var o = Math.round((day - anchor(day.getFullYear())) / 864e5);
      return o >= from && o <= through;
    };
  }
  var outfits = [
    ["party", fixed(12, 27, 1, 2)],
    ["heart", fixed(2, 10, 2, 14)],
    ["shamrock", fixed(3, 13, 3, 17)],
    ["easter", around(easterSunday, -1, 2)],
    ["halloween", fixed(10, 24, 10, 31)],
    ["thanksgiving", around(function (y) { return nthWeekday(y, 11, 4, 4); }, -3, 3)],
    ["santa", fixed(12, 18, 12, 26)]
  ];
  var now = new Date(), today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  var forced = new URLSearchParams(location.search).get("outfit");
  var outfit = outfits.filter(function (o) { return forced ? o[0] === forced : o[1](today); })[0];
  if (outfit) {
    [[".take .ring", ""], [".pill .head", "-head"]].forEach(function (p) {
      var img = document.createElement("img");
      img.className = "outfit";
      img.alt = "";
      img.src = "/assets/outfit-" + outfit[0] + p[1] + ".png";
      document.querySelector(p[0]).appendChild(img);
    });
  }

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
