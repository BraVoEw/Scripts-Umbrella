// Cloudflare Worker: the site's "idea or bug" form + your Telegram bot.
// Secrets and vars (Worker → Settings → Variables and Secrets):
//   BOT_TOKEN     secret, token from @BotFather
//   CHAT_ID       secret, your numeric Telegram id (from @userinfobot)
//   SETUP_KEY     secret, any password you make up (used once to connect the bot buttons)
//   ALLOW_ORIGIN  text, https://bravoew.github.io
//   DA_CLIENT_ID, DA_CLIENT_SECRET  secrets, DonationAlerts API client (then open /da-login?key=SETUP_KEY once)
//   DONATELLO_TOKEN                 secret, API key from your Donatello profile
// KV binding (Worker → Bindings → KV namespace): DB  — keeps bans, the Thanks list, button info and tokens.
// Without DB the form still works, just without buttons and bans.

const LIMIT = 5;                       // messages per IP
const WINDOW = 60 * 60e3;              // per hour
const MSG_TTL = 60 * 60 * 24 * 90;     // buttons keep working for 90 days
const seen = new Map();                // rate limit memory (per instance)
const FEED_TTL = 120e3;                // donations are re-read at most every 2 minutes
const FEED_MAX = 10;
const FEED_SINCE = Date.parse("2026-10-31T00:00:00Z"); // older donations on the accounts are not for the scripts
let feedCache = null;
const DN_EVERY = 300e3;                // Donatello answers 429 quickly: ask at most every 5 minutes, across all instances
let donatelloIssue = "";               // why Donatello failed, shown only in the bot's /dons
let donatelloWait = 0;                 // Retry-After from the last 429, ms

const HELP = [
  "Команды:",
  "/bans — кто забанен",
  "/unban 2 или /unban @nick — разбанить",
  "/thanks — список «Спасибо» на сайте",
  "/addthanks @nick за что — добавить вручную",
  "/unthanks 2 — убрать из «Спасибо»",
  "/dons — последние донаты на сайте",
  "/hidedon 2 — скрыть донат с сайта",
  "/help — эта подсказка",
  "",
  "Под каждым сообщением с сайта:",
  "⭐ В «Спасибо» — человек сразу появится на сайте",
  "🚫 Забанить — с его адреса и ника больше ничего не придёт, на сайте он увидит, что заблокирован",
  "",
  "Ответь на сообщение с сайта своим текстом, чтобы поменять его подпись в «Спасибо».",
].join("\n");

const COMMANDS = [
  { command: "help", description: "Команды и кнопки" },
  { command: "bans", description: "Кто забанен" },
  { command: "unban", description: "Разбанить: /unban 2 или /unban @nick" },
  { command: "thanks", description: "Список «Спасибо»" },
  { command: "addthanks", description: "Добавить: /addthanks @nick за что" },
  { command: "unthanks", description: "Убрать: /unthanks 2" },
  { command: "dons", description: "Последние донаты на сайте" },
  { command: "hidedon", description: "Скрыть донат: /hidedon 2" },
];

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const origin = req.headers.get("Origin") || "";
    const allowed = (env.ALLOW_ORIGIN || "").split(",").map((s) => s.trim()).filter(Boolean);
    const cors = {
      "Access-Control-Allow-Origin": allowed.includes(origin) ? origin : allowed[0] || "*",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
      "Vary": "Origin",
    };
    const reply = (body, status = 200, extra = {}) =>
      new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json", ...extra } });

    if (req.method === "OPTIONS") return new Response(null, { headers: cors });
    if (url.pathname === "/tg") return telegram(req, env);
    if (url.pathname === "/setup") return setup(url, env);
    if (url.pathname === "/da-login") return daLogin(url, env);
    if (url.pathname === "/da-callback") return daCallback(url, env);
    if (url.pathname === "/donations" && req.method === "GET") {
      const feed = await donations(env);
      return reply({ donations: feed.list.map(({ id, ...x }) => x), sources: feed.sources }, 200, { "Cache-Control": "public, max-age=60" });
    }
    if (url.pathname === "/thanks" && req.method === "GET") {
      const list = (await getThanks(env)).map((x) => ({ name: x.name, link: x.link, ru: x.ru, en: x.en }));
      return reply({ thanks: list }, 200, { "Cache-Control": "public, max-age=60" });
    }
    if (url.pathname !== "/" || req.method !== "POST") return reply({ ok: false }, 405);
    if (allowed.length && !allowed.includes(origin)) return reply({ ok: false }, 403);

    let d;
    try { d = await req.json(); } catch { return reply({ ok: false }, 400); }
    if (d.website) return reply({ ok: true }); // honeypot filled = bot, pretend success

    const kind = d.kind === "bug" ? "bug" : "idea";
    const text = String(d.text || "").trim().slice(0, 2000);
    const script = String(d.script || "").slice(0, 40);
    const version = String(d.version || "").slice(0, 20);
    const tg = String(d.tg || "").replace(/^@/, "");
    if (text.length < 5) return reply({ ok: false }, 400);
    if (tg && !/^[A-Za-z0-9_]{4,32}$/.test(tg)) return reply({ ok: false }, 400);

    const ip = await sha(`ip:${req.headers.get("CF-Connecting-IP") || "?"}:${env.SETUP_KEY || ""}`, 16);
    if (await isBanned(env, ip, tg)) return reply({ ok: false, error: "banned" }, 403);

    const now = Date.now();
    const hits = (seen.get(ip) || []).filter((t) => now - t < WINDOW);
    if (hits.length >= LIMIT) return reply({ ok: false, error: "rate" }, 429);
    hits.push(now);
    seen.set(ip, hits);

    const head = kind === "bug" ? "🐞 Баг" : "💡 Идея";
    const body = [
      `${head} · ${script}${version ? " v" + version : ""}`,
      "",
      text,
      "",
      tg ? `От: @${tg} (t.me/${tg})` : "От: аноним",
      `Язык: ${d.lang === "en" ? "EN" : "RU"}`,
    ].join("\n");

    const msg = { body: { chat_id: chatId(env), text: body, disable_web_page_preview: true } };
    let id = null, meta = null;
    if (env.DB) {
      id = crypto.randomUUID().replace(/-/g, "").slice(0, 10);
      meta = { ip, tg, kind, script, text: text.slice(0, 80), at: now };
      await env.DB.put("msg:" + id, JSON.stringify(meta), { expirationTtl: MSG_TTL });
      msg.body.reply_markup = await keyboard(env, id, meta);
    }
    const r = await api(env, "sendMessage", msg.body);
    if (r.ok) {
      if (env.DB && r.result) await env.DB.put("tgmsg:" + r.result.message_id, id, { expirationTtl: MSG_TTL });
      return reply({ ok: true });
    }
    return reply({ ok: false, error: r.description || "telegram" }, 502);
  },
};

/* ---------- helpers ---------- */

function chatId(env) { return String(env.CHAT_ID || "").replace(/[^\d-]/g, ""); }

async function api(env, method, body) {
  const r = await fetch(`https://api.telegram.org/bot${String(env.BOT_TOKEN || "").trim()}/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  try { return await r.json(); } catch { return { ok: false, description: "telegram " + r.status }; }
}

async function sha(s, len = 64) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("").slice(0, len);
}

const webhookSecret = (env) => sha(`tg:${env.SETUP_KEY || ""}`);
const nick = (s) => String(s || "").replace(/^@/, "").toLowerCase();
const day = (t) => new Date(t).toISOString().slice(0, 10).split("-").reverse().join(".");

async function getJSON(env, key, fallback) {
  try { return JSON.parse((await env.DB.get(key)) || "null") ?? fallback; } catch { return fallback; }
}

/* ---------- bans ---------- */

async function isBanned(env, ip, tg) {
  if (!env.DB) return false;
  if (await env.DB.get("ban:ip:" + ip)) return true;
  return !!(tg && (await env.DB.get("ban:tg:" + nick(tg))));
}

async function ban(env, meta) {
  const rec = JSON.stringify({ ip: meta.ip, tg: meta.tg || "", text: meta.text || "", at: Date.now() });
  await env.DB.put("ban:ip:" + meta.ip, rec);
  if (meta.tg) await env.DB.put("ban:tg:" + nick(meta.tg), rec);
}

async function unban(env, rec) {
  if (rec.ip) await env.DB.delete("ban:ip:" + rec.ip);
  if (rec.tg) await env.DB.delete("ban:tg:" + nick(rec.tg));
}

async function banList(env) {
  const out = [];
  let cursor;
  do {
    const page = await env.DB.list({ prefix: "ban:ip:", cursor });
    for (const k of page.keys) {
      const rec = await getJSON(env, k.name, null);
      if (rec) out.push(rec);
    }
    cursor = page.list_complete ? null : page.cursor;
  } while (cursor);
  return out.sort((a, b) => a.at - b.at);
}

/* ---------- thanks ---------- */

async function getThanks(env) { return env.DB ? await getJSON(env, "thanks", []) : []; }

function autoText(meta) {
  const s = meta.script, site = s === "site", other = !s || s === "other";
  if (meta.kind === "bug") {
    return {
      ru: other ? "нашёл баг" : site ? "нашёл баг на сайте" : `нашёл баг в ${s}`,
      en: other ? "found a bug" : site ? "found a bug on the website" : `found a bug in ${s}`,
    };
  }
  return {
    ru: other ? "подкинул идею" : site ? "идея для сайта" : `идея для ${s}`,
    en: other ? "gave an idea" : site ? "idea for the website" : `idea for ${s}`,
  };
}

async function addThanks(env, tg, text) {
  const list = await getThanks(env), key = nick(tg);
  if (list.some((x) => nick(x.tg) === key)) return false;
  list.unshift({ tg, name: "@" + tg, link: "https://t.me/" + tg, ru: text.ru, en: text.en, at: Date.now() });
  await env.DB.put("thanks", JSON.stringify(list));
  return true;
}

async function removeThanks(env, tg) {
  const list = await getThanks(env), key = nick(tg);
  const rest = list.filter((x) => nick(x.tg) !== key);
  await env.DB.put("thanks", JSON.stringify(rest));
  return rest.length !== list.length;
}

/* ---------- donations: DonationAlerts + Donatello, cleaned up for a public page ---------- */

const LINK = /(https?:\/\/|www\.|t\.me\/|discord\.gg\/)\S*|\b[\w-]+\.(com|ru|net|org|gg|tv|me|io|xyz|ua|su|cc)\b\S*/gi;
const BAD = /(?<![а-яё])(ху[йеёя]|пизд|еба[нтл]|ёба|бля|сук[аи]|муда|долбо[её]|гандон|пид[оа]р|нахуй|заеб|уеб[аоик])|\b(fuck|shit|bitch|cunt|nigg|faggot)/i;

function cleanName(v) {
  const t = String(v || "").trim();
  if (!t || /^(anonymous|аноним)$/i.test(t) || BAD.test(t) || t.search(LINK) >= 0) return "";
  return t.slice(0, 32);
}
function cleanMessage(v) {
  const t = String(v || "").replace(LINK, "").replace(/\s+/g, " ").trim();
  return !t || BAD.test(t) ? "" : t.slice(0, 120);
}
function when(v) {
  const t = Date.parse(String(v || "").replace(" ", "T") + (/[zZ]|[+-]\d\d:?\d\d$/.test(String(v || "")) ? "" : "Z"));
  return isNaN(t) ? 0 : t;
}

async function daRefresh(env, tok) {
  const r = await fetch("https://www.donationalerts.com/oauth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: tok.refresh, client_id: env.DA_CLIENT_ID, client_secret: env.DA_CLIENT_SECRET, scope: "oauth-donation-index" }),
  });
  if (!r.ok) return null;
  const d = await r.json();
  const next = { access: d.access_token, refresh: d.refresh_token || tok.refresh, exp: Date.now() + (d.expires_in || 0) * 1000 };
  await env.DB.put("da_token", JSON.stringify(next));
  return next;
}

async function fromDonationAlerts(env) {
  if (!env.DB) return null;
  let tok = await getJSON(env, "da_token", null);
  if (!tok) return null;
  if (tok.exp && tok.exp - Date.now() < 86400e3) tok = (await daRefresh(env, tok)) || tok;
  const get = () => fetch("https://www.donationalerts.com/api/v1/alerts/donations", { headers: { Authorization: "Bearer " + tok.access } });
  let r = await get();
  if (r.status === 401) {
    tok = await daRefresh(env, tok);
    if (!tok) return null;
    r = await get();
  }
  if (!r.ok) return null;
  const d = await r.json();
  return (d.data || []).map((x) => ({
    id: "da:" + x.id,
    name: cleanName(x.username),
    amount: Number(x.amount) || 0,
    currency: String(x.currency || ""),
    message: x.message_type === "audio" ? "" : cleanMessage(x.message),
    at: when(x.created_at),
  }));
}

async function fromDonatello(env) {
  donatelloIssue = "";
  donatelloWait = 0;
  const r = await fetch("https://donatello.to/api/v1/donates?size=" + FEED_MAX, { headers: { "X-Token": String(env.DONATELLO_TOKEN).trim(), "User-Agent": "scripts-umbrella-site", Accept: "application/json" } });
  if (!r.ok) {
    donatelloIssue = "Donatello ответил " + r.status;
    if (r.status === 429) donatelloWait = (Number(r.headers.get("Retry-After")) || 0) * 1000;
    return null;
  }
  const d = await r.json();
  const list = d.content || d.data || d.donates || [];
  return list.map((x) => ({
    id: "dn:" + (x.pubId || x.id || x.createdAt),
    name: cleanName(x.clientName || x.name || x.username),
    amount: Number(x.amount) || 0,
    currency: String(x.currency || "UAH"),
    message: cleanMessage(x.message),
    at: when(x.createdAt || x.created_at || x.date),
  }));
}

// Keeps the last good answer in KV, so a 429 or a short outage doesn't empty the feed.
async function donatelloSaved(env) {
  if (!env.DONATELLO_TOKEN) {
    donatelloIssue = "воркер не видит DONATELLO_TOKEN";
    return null;
  }
  const saved = env.DB ? await getJSON(env, "dn_cache", null) : null;
  if (saved && Date.now() < saved.next) {
    donatelloIssue = saved.issue;
    return saved.list;
  }
  const got = await fromDonatello(env).catch((e) => { donatelloIssue = "ошибка запроса: " + e.name; return null; });
  const list = got || (saved && saved.list) || null;
  if (env.DB) await env.DB.put("dn_cache", JSON.stringify({ next: Date.now() + Math.max(DN_EVERY, donatelloWait), list, issue: donatelloIssue }));
  return list;
}

async function donations(env, fresh) {
  if (!fresh && feedCache && Date.now() - feedCache.at < FEED_TTL) return feedCache.value;
  const [da, dn] = await Promise.all([fromDonationAlerts(env).catch(() => null), donatelloSaved(env).catch(() => null)]);
  const hidden = env.DB ? await getJSON(env, "hidden_donations", []) : [];
  const list = [...(da || []), ...(dn || [])].filter((x) => x.at >= FEED_SINCE && !hidden.includes(x.id)).sort((a, b) => b.at - a.at).slice(0, FEED_MAX);
  const value = { list, sources: { donationalerts: da ? da.length : null, donatello: dn ? dn.length : null } };
  feedCache = { at: Date.now(), value };
  return value;
}

// One-time DonationAlerts sign-in: the worker keeps and refreshes the token itself.
const html = (text, status = 200) => new Response("<!doctype html><meta charset=utf-8><body style='background:#000;color:#fff;font:18px system-ui;padding:40px'>" + text, { status, headers: { "Content-Type": "text/html; charset=utf-8" } });

async function daLogin(url, env) {
  if (!env.SETUP_KEY || url.searchParams.get("key") !== env.SETUP_KEY) return html("Неверный ключ", 403);
  if (!env.DB || !env.DA_CLIENT_ID || !env.DA_CLIENT_SECRET) return html("Нет DB, DA_CLIENT_ID или DA_CLIENT_SECRET", 500);
  const q = new URLSearchParams({ client_id: env.DA_CLIENT_ID, redirect_uri: url.origin + "/da-callback", response_type: "code", scope: "oauth-donation-index", state: await sha("da:" + env.SETUP_KEY) });
  return Response.redirect("https://www.donationalerts.com/oauth/authorize?" + q, 302);
}

async function daCallback(url, env) {
  if (!env.SETUP_KEY || url.searchParams.get("state") !== (await sha("da:" + env.SETUP_KEY))) return html("Неверный запрос", 403);
  const code = url.searchParams.get("code");
  if (!code) return html("DonationAlerts не дал доступ", 400);
  const r = await fetch("https://www.donationalerts.com/oauth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "authorization_code", client_id: env.DA_CLIENT_ID, client_secret: env.DA_CLIENT_SECRET, redirect_uri: url.origin + "/da-callback", code }),
  });
  if (!r.ok) return html("Не получилось получить доступ (" + r.status + ")", 502);
  const d = await r.json();
  await env.DB.put("da_token", JSON.stringify({ access: d.access_token, refresh: d.refresh_token, exp: Date.now() + (d.expires_in || 0) * 1000 }));
  feedCache = null;
  return html("DonationAlerts подключён, можно закрыть страницу.");
}

/* ---------- bot ---------- */

async function keyboard(env, id, meta) {
  const row = [];
  if (meta.tg) {
    const inThanks = (await getThanks(env)).some((x) => nick(x.tg) === nick(meta.tg));
    row.push(inThanks ? { text: "✖ Убрать из «Спасибо»", callback_data: "r:" + id } : { text: "⭐ В «Спасибо»", callback_data: "t:" + id });
  }
  const banned = !!(await env.DB.get("ban:ip:" + meta.ip));
  row.push(banned ? { text: "✅ Разбанить", callback_data: "u:" + id } : { text: "🚫 Забанить", callback_data: "b:" + id });
  return { inline_keyboard: [row] };
}

async function telegram(req, env) {
  if (req.method !== "POST" || !env.DB) return new Response("no", { status: 405 });
  if (req.headers.get("X-Telegram-Bot-Api-Secret-Token") !== (await webhookSecret(env))) return new Response("no", { status: 403 });
  let u = null;
  try { u = await req.json(); } catch {}
  try {
    if (u && u.callback_query) await onButton(env, u.callback_query);
    else if (u && u.message) await onMessage(env, u.message);
  } catch (e) {
    // always answer 200, otherwise Telegram keeps resending the same update
  }
  return new Response("ok");
}

async function onButton(env, q) {
  if (String(q.from && q.from.id) !== chatId(env)) return api(env, "answerCallbackQuery", { callback_query_id: q.id });
  const [act, id] = String(q.data || "").split(":");
  const meta = await getJSON(env, "msg:" + id, null);
  if (!meta) return api(env, "answerCallbackQuery", { callback_query_id: q.id, text: "Сообщение слишком старое, используй команды /help" });
  let note = "";
  if (act === "b") { await ban(env, meta); note = "Забанен"; }
  else if (act === "u") { await unban(env, meta); note = "Разбанен"; }
  else if (act === "t" && meta.tg) { await addThanks(env, meta.tg, autoText(meta)); note = "Добавлен в «Спасибо». Ответь на сообщение текстом, чтобы поменять подпись"; }
  else if (act === "r" && meta.tg) { await removeThanks(env, meta.tg); note = "Убран из «Спасибо»"; }
  await api(env, "answerCallbackQuery", { callback_query_id: q.id, text: note });
  if (q.message) {
    await api(env, "editMessageReplyMarkup", { chat_id: q.message.chat.id, message_id: q.message.message_id, reply_markup: await keyboard(env, id, meta) });
  }
}

async function onMessage(env, m) {
  if (String(m.from && m.from.id) !== chatId(env)) return; // the bot only talks to you
  const say = (text) => api(env, "sendMessage", { chat_id: m.chat.id, text, disable_web_page_preview: true });
  const text = String(m.text || "").trim();

  if (m.reply_to_message && text && !text.startsWith("/")) {
    const id = await env.DB.get("tgmsg:" + m.reply_to_message.message_id);
    const meta = id && (await getJSON(env, "msg:" + id, null));
    if (!meta || !meta.tg) return say("Это сообщение без ника, в «Спасибо» его не добавить.");
    const list = await getThanks(env), item = list.find((x) => nick(x.tg) === nick(meta.tg));
    if (!item) return say("Сначала добавь его в «Спасибо» кнопкой ⭐ под сообщением.");
    item.ru = item.en = text.slice(0, 80);
    await env.DB.put("thanks", JSON.stringify(list));
    return say(`Подпись для @${meta.tg} обновлена: ${item.ru}`);
  }

  const [rawCmd, ...rest] = text.split(/\s+/);
  const cmd = (rawCmd || "").split("@")[0].toLowerCase();
  const arg = rest.join(" ").trim();

  if (cmd === "/start" || cmd === "/help") return say(HELP);

  if (cmd === "/bans") {
    const list = await banList(env);
    if (!list.length) return say("Забаненных нет.");
    return say(["Забанены:", ...list.map((b, i) => `${i + 1}. ${b.tg ? "@" + b.tg : "аноним"} · ${day(b.at)}${b.text ? " · «" + b.text + "»" : ""}`), "", "Разбанить: /unban номер или /unban @nick"].join("\n"));
  }

  if (cmd === "/unban") {
    if (!arg) return say("Напиши так: /unban 2 или /unban @nick");
    const list = await banList(env);
    const rec = /^\d+$/.test(arg) ? list[+arg - 1] : await getJSON(env, "ban:tg:" + nick(arg), null);
    if (!rec) return say("Такого в бан-листе нет. Список: /bans");
    await unban(env, rec);
    return say(`Разбанен: ${rec.tg ? "@" + rec.tg : "аноним"}`);
  }

  if (cmd === "/thanks") {
    const list = await getThanks(env);
    if (!list.length) return say("В «Спасибо» пока никого. Добавляй кнопкой ⭐ под сообщением или /addthanks @nick за что");
    return say(["«Спасибо» на сайте:", ...list.map((x, i) => `${i + 1}. ${x.name} — ${x.ru}`), "", "Убрать: /unthanks номер"].join("\n"));
  }

  if (cmd === "/addthanks") {
    const m2 = arg.match(/^@?([A-Za-z0-9_]{4,32})\s*(.*)$/);
    if (!m2) return say("Напиши так: /addthanks @nick за что");
    const why = (m2[2] || "помог со скриптами").slice(0, 80);
    const ok = await addThanks(env, m2[1], { ru: why, en: why });
    return say(ok ? `Добавлен: @${m2[1]} — ${why}` : `@${m2[1]} уже в «Спасибо».`);
  }

  if (cmd === "/unthanks") {
    const list = await getThanks(env), n = parseInt(arg, 10);
    const item = n >= 1 ? list[n - 1] : list.find((x) => nick(x.tg) === nick(arg));
    if (!item) return say("Такого номера нет. Список: /thanks");
    await removeThanks(env, item.tg);
    return say(`Убран из «Спасибо»: ${item.name}`);
  }

  if (cmd === "/dons") {
    const { list, sources } = await donations(env, true);
    const off = Object.keys(sources).filter((k) => sources[k] === null);
    const notes = [off.length ? "Не подключено: " + off.join(", ") : "", donatelloIssue ? "Donatello: " + donatelloIssue : ""].filter(Boolean);
    const head = notes.length ? notes.join("\n") + "\n\n" : "";
    if (!list.length) return say(head + "Донатов пока нет.");
    return say(head + ["Донаты на сайте:", ...list.map((x, i) => `${i + 1}. ${x.name || "Аноним"} · ${x.amount} ${x.currency}${x.message ? " · " + x.message : ""}`), "", "Скрыть: /hidedon номер"].join("\n"));
  }

  if (cmd === "/hidedon") {
    const { list } = await donations(env, true);
    const item = list[parseInt(arg, 10) - 1];
    if (!item) return say("Такого номера нет. Список: /dons");
    const hidden = await getJSON(env, "hidden_donations", []);
    hidden.push(item.id);
    await env.DB.put("hidden_donations", JSON.stringify(hidden));
    feedCache = null;
    return say(`Скрыт с сайта: ${item.name || "Аноним"} · ${item.amount} ${item.currency}`);
  }

  if (text.startsWith("/")) return say("Не знаю такую команду. Все команды: /help");
}

/* ---------- one-time setup: connects the bot's buttons and commands to this worker ---------- */

async function setup(url, env) {
  const json = (o, s = 200) => new Response(JSON.stringify(o, null, 2), { status: s, headers: { "Content-Type": "application/json; charset=utf-8" } });
  if (!env.SETUP_KEY || url.searchParams.get("key") !== env.SETUP_KEY) return json({ ok: false, error: "wrong key" }, 403);
  if (!env.DB) return json({ ok: false, error: "KV binding DB is missing" }, 500);
  const hook = await api(env, "setWebhook", {
    url: url.origin + "/tg",
    secret_token: await webhookSecret(env),
    allowed_updates: ["message", "callback_query"],
    drop_pending_updates: true,
  });
  const cmds = await api(env, "setMyCommands", { commands: COMMANDS, scope: { type: "chat", chat_id: chatId(env) } });
  return json({ webhook: hook.ok ? "подключён" : hook.description, commands: cmds.ok ? "добавлены" : cmds.description });
}
