/* Shared logic for the site design variants: script catalog, RU/EN, theme,
   live release data (versions, downloads, dates), lightbox and the stats page.
   A variant page calls Site.mount(view) where view = { render(), route(hash), onData() }. */
(function () {
  "use strict";
  var REPO = "BraVoEw/Scripts-Umbrella";
  var ASSETS = window.SITE_ASSETS || "assets/";
  var HERO_IMG = "https://cdn.cloudflare.steamstatic.com/apps/dota2/images/dota_react/heroes/";
  var STATS_URL = "https://raw.githubusercontent.com/" + REPO + "/stats/stats.json";
  var LOCAL = /^(localhost|127\.0\.0\.1)$/.test(location.hostname);

  // One entry per script. A new script = a new entry here, the page builds itself from it.
  var CATALOG = [
    {
      key: "build-brain", name: "Build Brain", file: "build_brain.lua", folder: "build_brain",
      ver: "1.1.0", date: "2026-10-30T12:00:00Z", first: "2026-10-22T13:32:08Z",
      color: ["#3987e5", "#2a78d6"], tags: ["draft", "shop"], auto: true,
      video: "build-brain-1080.mp4", poster: "build-brain-poster-1080.webp",
      preview: "build-brain-720.mp4",
      shots: ["bb-pick.webp", "bb-draft.webp", "bb-build.webp", "bb-shop.webp"],
      ru: {
        tagline: "Кого пикнуть и что собрать против этих врагов",
        top: ["Пики по мете твоей позиции и матчапам", "Сборка с минутами прямо в магазине", "Контрпредметы против каждого врага"],
        desc: "Кого пикнуть на твою роль и что собрать против именно этих врагов. Сборки по свежим пабам Божества и Титана прямо в магазине.",
        shots: ["Панель на пиках", "Вкладка Драфт", "Вкладка Сборка", "Панель в магазине"],
        groups: [
          ["Пики", ["Панель сама открывается на выборе героев", "Шанс на победу и пики обеих команд", "Мета позиции или только твои герои", "Топ-3 подсвечены в сетке героев"]],
          ["Магазин", ["Старт, лайнинг и кор с минутами", "Против врагов: предмет и зачем он", "Прокачка на 18 уровней и таланты", "Клик в квикбай, ПКМ покупает"]],
          ["Окно", ["Таблица «кто кого» в процентах", "Пропустить или заменить любой предмет", "Кто тебя убивает и чем", "Ульты и BKB врагов в кд"]],
          ["Данные", ["STRATZ, текущий патч", "Матчапы от Легенды до Титана", "Обновление 2 раза в неделю и после патча", "Русский и английский"]]
        ]
      },
      en: {
        tagline: "Who to pick and what to buy against these enemies",
        top: ["Picks by your position's meta and matchups", "Build with timings right in the shop", "Counter items for every enemy"],
        desc: "Who to pick for your role and what to buy against these exact enemies. Builds from fresh Divine and Immortal pubs right in the shop.",
        shots: ["Hero pick panel", "Draft tab", "Build tab", "Shop panel"],
        groups: [
          ["Hero pick", ["Panel opens by itself on hero pick", "Win chance and both teams' picks", "Meta for your position or only your heroes", "Top 3 highlighted in the hero grid"]],
          ["Shop", ["Starting, laning and core items with timings", "Counters to your enemies and why", "Skill order for 18 levels and talents", "Click to quick buy, right click buys"]],
          ["Window", ["Who beats who table in percent", "Skip or replace any item", "Who kills you and with what", "Enemy ults and BKB on cooldown"]],
          ["Data", ["STRATZ, current patch", "Matchups from Legend to Immortal", "Updated twice a week and after patches", "Russian and English"]]
        ]
      }
    },
    {
      key: "history-changer", name: "History Changer", file: "history_changer.lua", folder: "history_changer",
      ver: "1.0.3", date: "2026-10-30T03:10:00Z", first: "2026-10-20T22:11:51Z",
      color: ["#d95926", "#eb6834"], tags: ["profile"],
      image: "hc-history.webp", poster: "hc-history.webp", focus: "50% 0%", shots: ["hc-history.webp"],
      ru: {
        tagline: "Настоящий MMR в истории матчей",
        shots: ["История матчей с MMR в каждой строке"],
        top: ["MMR и изменение в каждой строке истории", "Плашка с итогом за сутки, неделю или месяц", "Неон и RGB с переливом цветов"],
        desc: "Настоящий MMR после каждой игры прямо в истории матчей, вместо голого Win или Loss. Сверху плашка с итогом за сутки, неделю или месяц.",
        groups: [
          ["История", ["MMR и изменение в каждой строке", "Три формата: 1569 (+25), Победа 1569 (+25), +25", "Калибровка с итоговым MMR", "Свои цвета и текст вместо героя"]],
          ["Плашка", ["Вины, лузы и сумма MMR", "За 24 часа, 7 или 30 дней", "Сама догружает историю до 120 матчей", "Видно только тебе"]],
          ["Эффекты", ["Неон: светятся MMR и плашка", "RGB: перелив по строкам и рамке", "Радуга или три своих цвета", "Сила свечения и скорость перелива"]]
        ]
      },
      en: {
        tagline: "Your real MMR in the match history",
        shots: ["Match history with MMR in every row"],
        top: ["MMR and change in every history row", "A pill with totals for a day, week or month", "Neon and RGB with a color flow"],
        desc: "Your real MMR after every match right in the match history instead of a bare Win or Loss. Plus a pill with totals for a day, week or month.",
        groups: [
          ["History", ["MMR and change in every row", "Three formats: 1569 (+25), Win 1569 (+25), +25", "Calibration games with the final MMR", "Your own colors and text instead of the hero"]],
          ["Pill", ["Wins, losses and MMR total", "For 24 hours, 7 or 30 days", "Loads up to 120 matches by itself", "Only you can see it"]],
          ["Effects", ["Neon: MMR and the pill glow", "RGB: color flow across rows and the frame", "Rainbow or three colors of your own", "Glow strength and flow speed"]]
        ]
      }
    }
  ];

  var T = {
    ru: {
      title: "BraVoEw · Скрипты для Umbrella",
      nav_scripts: "Скрипты", nav_stats: "Статистика", nav_install: "Установка",
      hero_title: "Скрипты для <em>Umbrella</em>",
      hero_lead: "Dota 2. Делаю то, чего самому не хватало в игре, и выкладываю для всех. Бесплатно и с открытым кодом.",
      cta_scripts: "Смотреть скрипты",
      scripts: ["скрипт", "скрипта", "скриптов"], downloads: ["загрузка", "загрузки", "загрузок"],
      stat_updated: "последнее обновление", updated: "обновлено",
      sec_scripts: "Скрипты", tag_auto: "обновляется сам", tag_all: "Все",
      tag_draft: "Драфт", tag_shop: "Магазин", tag_profile: "Профиль",
      download: "Скачать", more: "Подробнее", changes: "Что нового", close: "Закрыть",
      sec_install: "Установка", sec_install_sub: "одинаково для всех скриптов",
      s1_t: "Скачай", s1_d: "Кнопка «Скачать» у нужного скрипта, файл <code>.lua</code>.",
      s2_t: "Положи в scripts", s2_d: "В папку <code>scripts</code> Umbrella.",
      s3_t: "Перезагрузи", s3_d: "Перезагрузи Lua-скрипты в меню Umbrella.",
      s4_t: "Включи", s4_d: "Скрипт появится в <code>Scripts → Scripts</code>.",
      note_upd: "Build Brain обновляется сам: новая версия скачается в фоне и заработает после перезагрузки скриптов. Выключается в его настройках.",
      hc_mock_period: "24 часа",
      st_title: "Статистика", st_total: "Всего загрузок", st_time: "Загрузки со временем",
      st_dl: "загрузок", st_day_fmt: "+%s за сутки", st_release: "релиз",
      st_r1: "24 ч", st_r7: "7 дней", st_r0: "Всё",
      st_r1_since: "сейчас · за 24 часа", st_r7_since: "сейчас · за 7 дней", st_r0_since: "сейчас · с первого релиза",
      st_heat: "Активность по дням", st_heat_hint: "чем ярче, тем больше загрузок",
      nav_feedback: "Идея / баг",
      fb_title: "Идея или баг", fb_idea: "Идея", fb_bug: "Баг", fb_script: "Скрипт", fb_site: "Сайт", fb_other: "Другое",
      fb_text: "Сообщение", fb_ph_idea: "Что добавить или поменять", fb_ph_bug: "Что случилось и как повторить",
      fb_tg: "Твой Telegram, чтобы я мог связаться", fb_send: "Отправить", fb_sending: "Отправляю…",
      fb_kicker: "Идеи и баги", fb_pay: "За хорошую идею платим",
      fb_pay_lead: "Напиши, чего не хватает в скриптах или что сломалось. Если идея зайдёт в обновление, заплачу за неё и добавлю тебя в «Спасибо».",
      fb_btn_idea: "Предложить идею", fb_btn_bug: "Сообщить о баге",
      fb_how1: "Пишешь идею или баг", fb_how2: "Смотрю каждое сообщение", fb_how3: "Зашло в скрипт: платим и пишем тебя в «Спасибо»",
      thanks_empty: "Здесь будут те, чьи идеи и найденные баги попали в скрипты.",
      dn_side: "Скрипты бесплатные", dn_side_lead: "Если пригодились, можно закинуть на развитие. Донаты с сообщением появляются на сайте.",
      dn_tab_ru: "Россия / СНГ", dn_tab_ua: "Україна", dn_tab_world: "World",
      dn_ru_desc: "DonationAlerts: карты РФ, СБП", dn_ua_desc: "Donatello: картки України", dn_world_desc: "USDT в сети TRC20, из любой страны",
      dn_go: "Задонатить", dn_soon: "Скоро", dn_copy: "Скопировать", dn_copied: "Скопировано",
      dn_warn: "Только USDT и только в сети TRC20, другие монеты и сети потеряются.",
      dn_feed: "Последние донаты", dn_anon: "Аноним", dn_none: "Пока пусто",
      st_day: "за сутки", st_week: "за неделю", st_releases: "Все релизы", st_latest: "актуальная",
      st_share: "%s% всех", releases: ["релиз", "релиза", "релизов"],
      fb_ok: "Отправлено, спасибо!", fb_err: "Не отправилось, попробуй ещё раз", fb_off: "Форма пока не подключена к Telegram",
      fb_short: "Напиши хотя бы пару слов", fb_badtg: "Ник в Telegram: латиница, цифры и _",
      fb_banned: "Ты заблокирован и не можешь отправлять сообщения", fb_rate: "Слишком много сообщений, попробуй через час",
      cta_fb_title: "Есть идея или нашёл баг?", cta_fb_lead: "Сообщение придёт мне в Telegram. Оставь ник, если хочешь ответ.", cta_fb_btn: "Написать",
      donate_title: "Поддержать", donate_lead: "Скрипты бесплатные. Если пригодились, можно закинуть на развитие.", donate_btn: "Поддержать",
      thanks_title: "Спасибо"
    },
    en: {
      title: "BraVoEw · Scripts for Umbrella",
      nav_scripts: "Scripts", nav_stats: "Stats", nav_install: "Install",
      hero_title: "Scripts for <em>Umbrella</em>",
      hero_lead: "Dota 2. I make what I was missing in the game myself and share it with everyone. Free and open source.",
      cta_scripts: "Browse scripts",
      scripts: ["script", "scripts"], downloads: ["download", "downloads"],
      stat_updated: "last update", updated: "updated",
      sec_scripts: "Scripts", tag_auto: "self-updating", tag_all: "All",
      tag_draft: "Draft", tag_shop: "Shop", tag_profile: "Profile",
      download: "Download", more: "Details", changes: "What's new", close: "Close",
      sec_install: "Install", sec_install_sub: "the same for every script",
      s1_t: "Download", s1_d: "Hit Download on the script you want, it is a <code>.lua</code> file.",
      s2_t: "Put into scripts", s2_d: "Into the Umbrella <code>scripts</code> folder.",
      s3_t: "Reload", s3_d: "Reload Lua scripts in the Umbrella menu.",
      s4_t: "Turn on", s4_d: "The script shows up in <code>Scripts → Scripts</code>.",
      note_upd: "Build Brain updates itself: a new version downloads in the background and starts after you reload scripts. You can turn it off in its settings.",
      hc_mock_period: "24 hours",
      st_title: "Stats", st_total: "Total downloads", st_time: "Downloads over time",
      st_dl: "downloads", st_day_fmt: "+%s in 24 hours", st_release: "released",
      st_r1: "24h", st_r7: "7 days", st_r0: "All",
      st_r1_since: "now · last 24 hours", st_r7_since: "now · last 7 days", st_r0_since: "now · since the first release",
      st_heat: "Daily activity", st_heat_hint: "brighter means more downloads",
      nav_feedback: "Idea / bug",
      fb_title: "Idea or bug", fb_idea: "Idea", fb_bug: "Bug", fb_script: "Script", fb_site: "Website", fb_other: "Other",
      fb_text: "Message", fb_ph_idea: "What to add or change", fb_ph_bug: "What happened and how to repeat it",
      fb_tg: "Your Telegram so I can reach you", fb_send: "Send", fb_sending: "Sending…",
      fb_kicker: "Ideas and bugs", fb_pay: "We pay for good ideas",
      fb_pay_lead: "Tell me what the scripts are missing or what broke. If your idea makes it into an update, I'll pay for it and add you to Thanks.",
      fb_btn_idea: "Suggest an idea", fb_btn_bug: "Report a bug",
      fb_how1: "You send an idea or a bug", fb_how2: "I read every message", fb_how3: "Made it into a script: you get paid and listed in Thanks",
      thanks_empty: "People whose ideas and bug reports made it into the scripts will be listed here.",
      dn_side: "The scripts are free", dn_side_lead: "If they helped, you can chip in. Donations with a message show up on the site.",
      dn_tab_ru: "Russia / CIS", dn_tab_ua: "Ukraine", dn_tab_world: "World",
      dn_ru_desc: "DonationAlerts: Russian cards, SBP", dn_ua_desc: "Donatello: Ukrainian cards", dn_world_desc: "USDT on TRC20, from any country",
      dn_go: "Donate", dn_soon: "Soon", dn_copy: "Copy", dn_copied: "Copied",
      dn_warn: "USDT on TRC20 only, other coins or networks will be lost.",
      dn_feed: "Recent donations", dn_anon: "Anonymous", dn_none: "Nothing yet",
      st_day: "in 24 hours", st_week: "in 7 days", st_releases: "All releases", st_latest: "latest",
      st_share: "%s% of all", releases: ["release", "releases"],
      fb_ok: "Sent, thank you!", fb_err: "Could not send, try again", fb_off: "The form is not connected to Telegram yet",
      fb_short: "Write at least a few words", fb_badtg: "Telegram username: latin letters, digits and _",
      fb_banned: "You are blocked and can't send messages", fb_rate: "Too many messages, try again in an hour",
      cta_fb_title: "Got an idea or found a bug?", cta_fb_lead: "The message goes straight to my Telegram. Leave your username if you want a reply.", cta_fb_btn: "Write",
      donate_title: "Support", donate_lead: "The scripts are free. If they helped, you can chip in.", donate_btn: "Support",
      thanks_title: "Thanks"
    }
  };

  var REAL = CATALOG;
  var KEYS = REAL.map(function (e) { return e.key; });

  // feedback: URL of the Cloudflare worker that forwards the form to Telegram (empty = not connected)
  // donate: links per region (empty = "soon"), usdt = TRC20 address, feed = worker URL with recent donations
  // donations: [{ name, amount, currency, message, at }] shown until the feed is connected
  // thanks: [{ name, link, ru, en }] people who reported bugs or gave ideas
  var CFG = {
    feedback: "https://late-sound-19d9bravoew-feedback.bravoyt11.workers.dev",
    donate: {
      ru: "https://www.donationalerts.com/r/brvezka",
      ua: "https://donatello.to/brvezka",
      usdt: "TNPQWb4zHXFqfn4XqkCmHDxJkqDfJK2ehs",
      feed: "https://late-sound-19d9bravoew-feedback.bravoyt11.workers.dev/donations"
    },
    donations: [],
    thanks: []
  };

  var Site = window.Site = {
    catalog: CATALOG, cfg: CFG, lang: "ru", info: {}, total: null, last: null,
    byKey: function (k) { for (var i = 0; i < CATALOG.length; i++) if (CATALOG[i].key === k) return CATALOG[i]; return null; },
    t: function (k) { var v = T[Site.lang][k]; return v === undefined ? k : v; },
    L: function (e) { return e[Site.lang] || e.ru; },
    asset: function (p) { return ASSETS + p; }
  };

  var view = null, home = null, statsView = null;
  var rels = null, live = null, hist = null, statsLoading = false;

  function $(id) { return document.getElementById(id); }
  function each(root, sel, fn) { Array.prototype.forEach.call(root.querySelectorAll(sel), fn); }
  function esc(s) { return String(s).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; }); }
  function store(key, value) {
    try {
      if (value === undefined) return localStorage.getItem(key);
      localStorage.setItem(key, value);
    } catch (e) { return null; }
  }
  function nf(n) { return n.toLocaleString(Site.lang === "ru" ? "ru-RU" : "en-US"); }
  function fmt(iso, short) {
    var d = new Date(iso);
    if (isNaN(d)) return "";
    var dd = String(d.getDate()).padStart(2, "0"), mm = String(d.getMonth() + 1).padStart(2, "0");
    return short ? dd + "." + mm : dd + "." + mm + "." + d.getFullYear();
  }
  function plural(n, key) {
    var f = T[Site.lang][key];
    if (!Array.isArray(f)) return f || "";
    if (Site.lang !== "ru") return f[n === 1 ? 0 : 1];
    var a = Math.abs(n) % 100, b = a % 10;
    return f[a > 10 && a < 20 ? 2 : b === 1 ? 0 : b >= 2 && b <= 4 ? 1 : 2];
  }
  Site.nf = nf; Site.fmt = fmt; Site.plural = plural; Site.esc = esc;

  function relUrl(key, ver, file) { return "https://github.com/" + REPO + "/releases/download/" + key + "-v" + ver + "/" + file; }
  CATALOG.forEach(function (e) {
    Site.info[e.key] = { ver: e.ver, dl: null, date: e.date, href: relUrl(e.key, e.ver, e.file) };
    if (!Site.last || e.date > Site.last) Site.last = e.date;
  });
  Site.count = REAL.length;

  /* ---------- small HTML helpers shared by the variants ---------- */

  var ICONS = {
    download: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12m0 0 5-5m-5 5-5-5M4 19h16"/></svg>',
    calendar: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/></svg>',
    arrow: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14m-6-6 6 6-6 6"/></svg>',
    close: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M6 6l12 12M18 6 6 18"/></svg>',
    refresh: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M21 12a9 9 0 1 1-3-6.7M21 4v5h-5"/></svg>',
    play: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M8 5.5v13a1 1 0 0 0 1.5.86l10.5-6.5a1 1 0 0 0 0-1.72L9.5 4.64A1 1 0 0 0 8 5.5z"/></svg>'
  };
  Site.icon = function (n) { return ICONS[n] || ""; };

  Site.mono = function (e) { return e.mono || e.name.split(/\s+/).map(function (w) { return w.charAt(0); }).join("").slice(0, 2).toUpperCase(); };

  var MOCK_ROWS = [
    ["phantom_lancer", "Phantom Lancer", "4571 (+27)", "up", "38:12"],
    ["juggernaut", "Juggernaut", "4544 (-26)", "down", "45:03"],
    ["luna", "Luna", "4570 (+25)", "up", "31:47"],
    ["slark", "Slark", "4545 (+26)", "up", "40:20"]
  ];
  function mockHistory(compact) {
    var rows = MOCK_ROWS.map(function (r) {
      return "<tr><td><img src=\"" + HERO_IMG + r[0] + ".png\" alt=\"\" loading=\"lazy\"><span class=\"hname\">" + r[1] + "</span></td><td class=\"" + r[3] + "\">" + r[2] + "</td>" +
        (compact ? "" : "<td>Ranked</td><td>" + r[4] + "</td>") + "</tr>";
    }).join("");
    return "<div class=\"mock" + (compact ? " compact" : "") + "\" aria-hidden=\"true\"><div class=\"mpill\"><span>" + Site.t("hc_mock_period") +
      "</span><span class=\"w\">5 W</span><span class=\"l\">2 L</span><span class=\"s\">+79 MMR</span></div><table>" + rows + "</table></div>";
  }

  // Big media of a script: the video, or a CSS mock when there are no captures yet.
  Site.media = function (e, o) {
    o = o || {};
    if (e.video) {
      return "<video src=\"" + Site.asset(e.video) + "\" poster=\"" + Site.asset(e.poster) + "\" muted loop playsinline preload=\"metadata\"" +
        (o.autoplay ? " autoplay" : "") + (o.controls ? " controls" : "") + "></video>";
    }
    if (e.image) return "<img src=\"" + Site.asset(e.image) + "\" alt=\"\" loading=\"lazy\"" + focusStyle(e) + ">";
    return e.mock === "history" ? mockHistory(o.compact) : "";
  };
  // Still preview for cards: poster image, or the compact mock.
  function focusStyle(e) { return e.focus ? " style=\"object-position:" + e.focus + "\"" : ""; }
  Site.cover = function (e) {
    if (e.poster) return "<img src=\"" + Site.asset(e.poster) + "\" alt=\"\" loading=\"lazy\"" + focusStyle(e) + ">";
    return e.mock === "history" ? mockHistory(true) : "";
  };
  Site.thumbs = function (e) {
    if (!e.shots || !e.shots.length) return "";
    var alts = Site.L(e).shots || [];
    return "<div class=\"thumbs\">" + e.shots.map(function (s, i) {
      return "<button type=\"button\" data-full=\"" + Site.asset(s) + "\"><img src=\"" + Site.asset(s) + "\" alt=\"" + esc(e.name + ": " + (alts[i] || "")) + "\" loading=\"lazy\"></button>";
    }).join("") + "</div>";
  };
  Site.groups = function (e) {
    return "<div class=\"groups\">" + Site.L(e).groups.map(function (g) {
      return "<div class=\"group\"><h4>" + esc(g[0]) + "</h4><ul>" + g[1].map(function (li) { return "<li>" + esc(li) + "</li>"; }).join("") + "</ul></div>";
    }).join("") + "</div>";
  };
  Site.links = function (e) {
    var base = "https://github.com/" + REPO;
    return { more: base + "/tree/main/" + e.folder, changes: base + "/blob/main/" + e.folder + "/CHANGELOG.md" };
  };
  Site.actions = function (e, cls) {
    cls = cls || { primary: "btn primary", plain: "btn" };
    var l = Site.links(e);
    return "<a class=\"" + cls.primary + "\" data-href=\"" + e.key + "\" href=\"" + Site.info[e.key].href + "\">" + ICONS.download + "<span>" + Site.t("download") + "</span></a>" +
      "<a class=\"" + cls.plain + "\" href=\"" + l.more + "\" target=\"_blank\" rel=\"noopener\">" + Site.t("more") + "</a>" +
      "<a class=\"" + cls.plain + "\" href=\"" + l.changes + "\" target=\"_blank\" rel=\"noopener\">" + Site.t("changes") + "</a>";
  };
  Site.meta = function (e) {
    return "<div class=\"meta\"><div>" + ICONS.download + "<span><b data-dl=\"" + e.key + "\">—</b> <span data-pl=\"downloads\" data-pl-n=\"" + e.key + "\"></span></span></div>" +
      "<div>" + ICONS.calendar + "<b data-date=\"" + e.key + "\"></b></div></div>";
  };
  Site.tagNames = function (e) { return (e.tags || []).map(function (t) { return Site.t("tag_" + t); }); };
  Site.allTags = function () {
    var seen = [];
    CATALOG.forEach(function (e) { (e.tags || []).forEach(function (t) { if (seen.indexOf(t) < 0) seen.push(t); }); });
    return seen;
  };

  /* ---------- fill live values into whatever the variant rendered ---------- */

  function fill(root) {
    root = root || document;
    CATALOG.forEach(function (e) {
      var i = Site.info[e.key];
      each(root, '[data-dl="' + e.key + '"]', function (el) { el.textContent = i.dl === null ? "—" : nf(i.dl); });
      each(root, '[data-ver="' + e.key + '"]', function (el) { el.textContent = "v" + i.ver; });
      each(root, '[data-href="' + e.key + '"]', function (el) { el.href = i.href; });
      each(root, '[data-date="' + e.key + '"]', function (el) { el.textContent = fmt(i.date, el.hasAttribute("data-short")); });
    });
    each(root, "[data-total]", function (el) { el.textContent = Site.total === null ? "—" : nf(Site.total); });
    each(root, "[data-last]", function (el) { el.textContent = fmt(Site.last, true); });
    each(root, "[data-count]", function (el) { el.textContent = nf(Site.count); });
    each(root, "[data-pl]", function (el) {
      var src = el.getAttribute("data-pl-n"), n;
      if (src === "total") n = Site.total || 0;
      else if (src === "count") n = Site.count;
      else n = (Site.info[src] && Site.info[src].dl) || 0;
      el.textContent = plural(n, el.getAttribute("data-pl"));
    });
  }
  Site.fill = fill;

  function translate(root) {
    var d = T[Site.lang];
    each(root, "[data-i18n]", function (el) { var v = d[el.getAttribute("data-i18n")]; if (typeof v === "string") el.textContent = v; });
    each(root, "[data-i18n-html]", function (el) { var v = d[el.getAttribute("data-i18n-html")]; if (typeof v === "string") el.innerHTML = v; });
  }
  Site.translate = translate;

  function applyLang(l) {
    Site.lang = l;
    document.documentElement.lang = l;
    document.title = T[l].title;
    store("lang", l);
    if (view && view.render) view.render();
    translate(document);
    each(document, "[data-lang]", function (b) { b.classList.toggle("on", b.getAttribute("data-lang") === l); });
    fill(document);
    if (statsView && !statsView.hidden) renderStats();
  }
  Site.rerender = function () { applyLang(Site.lang); };

  /* ---------- releases from the GitHub API ---------- */

  function apply(list) {
    rels = list;
    live = {};
    var total = 0, last = null;
    CATALOG.forEach(function (e) {
      var sum = 0, latest = null, i = Site.info[e.key];
      list.forEach(function (r) {
        if (!r.tag_name || r.tag_name.indexOf(e.key + "-v") !== 0 || r.draft) return;
        (r.assets || []).forEach(function (a) { if (a.name === e.file) sum += a.download_count || 0; });
        if (!r.prerelease && (!latest || r.published_at > latest.published_at)) latest = r;
      });
      i.dl = sum;
      live[e.key] = sum;
      total += sum;
      if (latest) {
        i.ver = latest.tag_name.slice(e.key.length + 2);
        i.href = relUrl(e.key, i.ver, e.file);
        i.date = latest.published_at;
      }
      if (!last || i.date > last) last = i.date;
    });
    Site.total = total;
    Site.last = last;
    fill(document);
    if (view && view.onData) view.onData();
    if (statsView && !statsView.hidden) renderStats();
  }

  function load(attempt) {
    attempt = attempt || 0;
    var cached = null;
    try { cached = JSON.parse(store("rel") || "null"); } catch (e) {}
    if (cached && (!cached.list || !cached.list.length)) cached = null;
    if (!attempt && cached && Date.now() - cached.at < 10 * 60 * 1000) { apply(cached.list); return; }
    fetch("https://api.github.com/repos/" + REPO + "/releases?per_page=100" + (attempt ? "&_=" + Date.now() : ""))
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (list) {
        if (!Array.isArray(list) || !list.length) return Promise.reject("empty");
        var slim = list.map(function (r) {
          return { tag_name: r.tag_name, draft: r.draft, prerelease: r.prerelease, published_at: r.published_at,
            assets: (r.assets || []).map(function (a) { return { name: a.name, download_count: a.download_count }; }) };
        });
        store("rel", JSON.stringify({ at: Date.now(), list: slim }));
        apply(slim);
      })
      .catch(function () {
        if (cached && !attempt) apply(cached.list);
        if (attempt < 3) setTimeout(function () { load(attempt + 1); }, 1500 * (attempt + 1));
      });
  }

  /* ---------- lightbox ---------- */

  document.addEventListener("click", function (ev) {
    var b = ev.target.closest && ev.target.closest("[data-full]");
    if (!b) return;
    var box = document.createElement("div");
    box.className = "lightbox";
    var img = document.createElement("img");
    img.src = b.getAttribute("data-full");
    var small = b.querySelector("img");
    img.alt = small ? small.alt : "";
    box.appendChild(img);
    function close() { box.remove(); document.removeEventListener("keydown", onKey, true); }
    function onKey(e) { if (e.key === "Escape") { e.stopPropagation(); close(); } }
    box.addEventListener("click", close);
    document.addEventListener("keydown", onKey, true);
    document.body.appendChild(box);
  });

  /* ---------- stats page: big total, a card per script, every release ---------- */

  function buildStats() {
    statsView.innerHTML =
      "<section class=\"stats-page\"><div class=\"wrap\">" +
      "<div class=\"sx-hero\"><div class=\"sx-main\"><span class=\"sx-kick\" data-i18n=\"st_title\"></span><b id=\"sx-total\">—</b><span class=\"sx-cap\" data-i18n=\"st_total\"></span></div>" +
      "<div class=\"sx-pills\"><div class=\"sx-pill up\"><b id=\"sx-day\">—</b><span data-i18n=\"st_day\"></span></div>" +
      "<div class=\"sx-pill up\"><b id=\"sx-week\">—</b><span data-i18n=\"st_week\"></span></div>" +
      "<div class=\"sx-pill\"><b id=\"sx-rels\">—</b><span id=\"sx-rels-l\"></span></div></div></div>" +
      "<div class=\"sx-grid\" id=\"sx-grid\"></div>" +
      "<div class=\"sx-releases\"><h3 data-i18n=\"st_releases\"></h3><ol id=\"sx-list\"></ol></div>" +
      "</div></section>";
  }

  function colorStyles() {
    var css = CATALOG.map(function (e) {
      return ".k-" + e.key + "{--c:" + e.color[0] + "}:root[data-theme=\"light\"] .k-" + e.key + "{--c:" + e.color[1] + "}";
    }).join("");
    var st = document.createElement("style");
    st.textContent = css;
    document.head.appendChild(st);
  }

  function sum(sv) { var n = 0; KEYS.forEach(function (k) { n += (sv && sv[k]) || 0; }); return n; }

  function points() {
    var pts = (hist || []).map(function (p) { return { t: Date.parse(p.t), s: p.s || {} }; })
      .filter(function (p) { return !isNaN(p.t); }).sort(function (a, b) { return a.t - b.t; });
    if (live && !LOCAL && (!pts.length || sum(live) >= sum(pts[pts.length - 1].s))) {
      var now = Date.now();
      if (!pts.length || now - pts[pts.length - 1].t > 60000) pts.push({ t: now, s: live });
    }
    return pts;
  }

  function firstRelease(k) {
    var best = null;
    (rels || []).forEach(function (r) {
      if (r.tag_name && r.tag_name.indexOf(k + "-v") === 0 && !r.draft && (!best || r.published_at < best)) best = r.published_at;
    });
    return Date.parse(best || Site.byKey(k).first);
  }

  // Totals as they were at time t: the last snapshot before t, zeros if every script came out after t, else unknown.
  function baseAt(pts, t) {
    var p = null;
    pts.forEach(function (q) { if (q.t <= t) p = q; });
    if (p) return p.s;
    return KEYS.every(function (k) { return firstRelease(k) >= t; }) ? {} : null;
  }

  function smoothPath(P) {
    var n = P.length;
    if (n < 3) return P.map(function (q, i) { return (i ? "L" : "M") + q[0].toFixed(1) + "," + q[1].toFixed(1); }).join("");
    var dx = [], m = [], t = [];
    for (var i = 0; i < n - 1; i++) { dx[i] = P[i + 1][0] - P[i][0]; m[i] = dx[i] ? (P[i + 1][1] - P[i][1]) / dx[i] : 0; }
    t[0] = m[0]; t[n - 1] = m[n - 2];
    for (i = 1; i < n - 1; i++) t[i] = m[i - 1] * m[i] <= 0 ? 0 : (m[i - 1] + m[i]) / 2;
    for (i = 0; i < n - 1; i++) {
      if (!m[i]) { t[i] = 0; t[i + 1] = 0; continue; }
      var a = t[i] / m[i], b = t[i + 1] / m[i], q2 = a * a + b * b;
      if (q2 > 9) { var k = 3 / Math.sqrt(q2); t[i] = k * a * m[i]; t[i + 1] = k * b * m[i]; }
    }
    var d = "M" + P[0][0].toFixed(1) + "," + P[0][1].toFixed(1);
    for (i = 0; i < n - 1; i++) {
      var h = dx[i] / 3;
      d += "C" + (P[i][0] + h).toFixed(1) + "," + (P[i][1] + t[i] * h).toFixed(1) + " " + (P[i + 1][0] - h).toFixed(1) + "," + (P[i + 1][1] - t[i + 1] * h).toFixed(1) + " " + P[i + 1][0].toFixed(1) + "," + P[i + 1][1].toFixed(1);
    }
    return d;
  }

  // Soft area of one script's growth since its release, drawn edge to edge at the bottom of its card.
  function wave(pts, k) {
    var W = 300, H = 70, t0 = firstRelease(k);
    var ser = [{ t: t0, v: 0 }].concat(pts.filter(function (p) { return p.t > t0; }).map(function (p) { return { t: p.t, v: p.s[k] || 0 }; }));
    if (ser.length < 2) return "";
    var t1 = ser[ser.length - 1].t, vmax = Math.max(1, ser[ser.length - 1].v);
    var P = ser.map(function (p) { return [(p.t - t0) / Math.max(1, t1 - t0) * W, H - 4 - p.v / vmax * (H - 14)]; });
    var d = smoothPath(P);
    return "<svg viewBox=\"0 0 " + W + " " + H + "\" preserveAspectRatio=\"none\" aria-hidden=\"true\"><path class=\"a\" d=\"" + d + "L" + W + "," + H + "L0," + H + "Z\"/><path class=\"l\" d=\"" + d + "\"/></svg>";
  }

  function renderStats() {
    if (hist === null) { loadStats(); return; }
    var pts = points(), last = pts.length ? pts[pts.length - 1] : null;
    var cur = LOCAL && last ? last.s : (live || (last ? last.s : {}));
    var now = LOCAL && last ? last.t : Date.now();
    var d1 = baseAt(pts, now - 864e5), d7 = baseAt(pts, now - 7 * 864e5), total = sum(cur);
    function delta(base, k) { if (!base) return null; return Math.max(0, k ? (cur[k] || 0) - (base[k] || 0) : total - sum(base)); }
    function plus(n) { return n === null ? "—" : "+" + nf(n); }
    $("sx-total").textContent = nf(total);
    $("sx-day").textContent = plus(delta(d1));
    $("sx-week").textContent = plus(delta(d7));

    var list = (rels || []).filter(function (r) {
      return r.tag_name && !r.draft && KEYS.some(function (k) { return r.tag_name.indexOf(k + "-v") === 0; });
    }).sort(function (a, b) { return a.published_at < b.published_at ? 1 : -1; });
    $("sx-rels").textContent = rels ? nf(list.length) : "—";
    $("sx-rels-l").textContent = plural(list.length, "releases");

    $("sx-grid").innerHTML = REAL.map(function (e) {
      var v = cur[e.key] || 0, share = total ? Math.round(v / total * 100) : 0;
      return "<article class=\"sx-card k-" + e.key + "\"><div class=\"sx-top\"><i class=\"sx-dot\"></i><h4>" + esc(e.name) + "</h4><span class=\"sx-ver\">v" + esc(Site.info[e.key].ver) + "</span></div>" +
        "<b class=\"sx-num\">" + nf(v) + "</b><span class=\"sx-cap\">" + plural(v, "downloads") + " · " + T[Site.lang].st_share.replace("%s", share) + "</span>" +
        "<div class=\"sx-deltas\"><span><em>" + plus(delta(d1, e.key)) + "</em>" + T[Site.lang].st_day + "</span><span><em>" + plus(delta(d7, e.key)) + "</em>" + T[Site.lang].st_week + "</span></div>" +
        "<div class=\"sx-spark\">" + wave(pts, e.key) + "</div></article>";
    }).join("");

    var seen = {}, loc = Site.lang === "ru" ? "ru-RU" : "en-US";
    $("sx-list").innerHTML = list.map(function (r) {
      var k = KEYS.filter(function (x) { return r.tag_name.indexOf(x + "-v") === 0; })[0], e = Site.byKey(k), n = 0;
      (r.assets || []).forEach(function (a) { if (a.name === e.file) n += a.download_count || 0; });
      var latest = !seen[k] && !r.prerelease;
      seen[k] = true;
      var when = new Date(r.published_at).toLocaleDateString(loc, { day: "numeric", month: "long", year: "numeric" });
      return "<li class=\"k-" + k + "\"><i></i><div><b>" + esc(e.name) + " " + esc(r.tag_name.slice(k.length + 2)) + "</b>" +
        (latest ? "<small>" + T[Site.lang].st_latest + "</small>" : "") + "<span>" + when + "</span></div>" +
        "<em>" + nf(n) + " <span>" + plural(n, "downloads") + "</span></em>" +
        "<a href=\"https://github.com/" + REPO + "/releases/tag/" + encodeURIComponent(r.tag_name) + "\" target=\"_blank\" rel=\"noopener\">" + T[Site.lang].changes + "</a></li>";
    }).join("");
  }

  function loadStats() {
    if (statsLoading) return;
    statsLoading = true;
    fetch(STATS_URL, { cache: "no-store" })
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (d) { hist = (d && d.points) || []; })
      .catch(function () { hist = []; })
      .then(function () { statsLoading = false; renderStats(); });
  }

  /* ---------- routing ---------- */

  function route() {
    var h = location.hash, stats = h === "#stats";
    home.hidden = stats;
    statsView.hidden = !stats;
    each(document, "[data-nav]", function (a) { a.classList.toggle("on", a.getAttribute("data-nav") === "stats" && stats); });
    if (view && view.route && view.route(stats ? "#stats" : h)) return;
    if (stats) {
      window.scrollTo(0, 0);
      renderStats();
    } else if (h.length > 1) {
      var el = document.getElementById(h.slice(1));
      if (el) el.scrollIntoView();
    }
  }
  Site.statsShown = function () { return statsView && !statsView.hidden; };
  Site.renderStats = renderStats;

  /* ---------- mount ---------- */

  Site.mount = function (v) {
    view = v;
    home = $("home");
    statsView = $("stats-view");
    colorStyles();
    buildStats();
    document.addEventListener("click", function (ev) {
      var b = ev.target.closest && ev.target.closest("[data-lang]");
      if (b) { applyLang(b.getAttribute("data-lang")); return; }
      if (ev.target.closest && ev.target.closest("[data-theme-toggle]")) {
        var t = document.documentElement.getAttribute("data-theme") === "dark" ? "light" : "dark";
        document.documentElement.setAttribute("data-theme", t);
        store("theme", t);
        if (Site.statsShown()) renderStats();
      }
    });
    var lang = store("lang") || ((navigator.language || "ru").toLowerCase().indexOf("ru") === 0 ? "ru" : "en");
    applyLang(lang);
    window.addEventListener("hashchange", route);
    route();
    load();
    var resizeTimer = null, lastW = 0;
    function onWidth(w) {
      if (w === lastW) return;
      lastW = w;
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(function () { if (Site.statsShown()) renderStats(); }, 120);
    }
    var wrap = statsView.querySelector(".wrap");
    if ("ResizeObserver" in window && wrap) new ResizeObserver(function (es) { onWidth(Math.round(es[0].contentRect.width)); }).observe(wrap);
    else window.addEventListener("resize", function () { onWidth(window.innerWidth); });
  };
})();
