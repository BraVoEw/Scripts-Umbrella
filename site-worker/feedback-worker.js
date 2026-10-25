// Cloudflare Worker: the site's "idea or bug" form + your Telegram bot.
// Secrets and vars (Worker → Settings → Variables and Secrets):
//   BOT_TOKEN     secret, token from @BotFather
//   CHAT_ID       secret, your numeric Telegram id (from @userinfobot)
//   SETUP_KEY     secret, any password you make up (used once to connect the bot buttons)
//   ALLOW_ORIGIN  text, https://bravoew.github.io
// KV binding (Worker → Bindings → KV namespace): DB  — keeps bans, the Thanks list and button info.
// Without DB the form still works, just without buttons and bans.

const LIMIT = 5;                       // messages per IP
const WINDOW = 60 * 60e3;              // per hour
const MSG_TTL = 60 * 60 * 24 * 90;     // buttons keep working for 90 days
const seen = new Map();                // rate limit memory (per instance)

const HELP = [
  "Команды:",
  "/bans — кто забанен",
  "/unban 2 или /unban @nick — разбанить",
  "/thanks — список «Спасибо» на сайте",
  "/addthanks @nick за что — добавить вручную",
  "/unthanks 2 — убрать из «Спасибо»",
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
