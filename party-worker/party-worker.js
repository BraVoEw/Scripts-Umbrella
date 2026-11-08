// Build Brain party finder.
// D1 binding: DB (tables are created on first request).
// Routes (JSON in, JSON out):
//   GET  /parties?mode=&lang=          open parties
//   POST /party   {sid,name,rank,mode,roles,lang,spread,auto,size}  -> {id,token}
//   POST /close   {token}
//   POST /extend  {token}                -> {now,expires}
//   GET  /host?token=                  join requests for my party
//   POST /decide  {token,join,ok}      manual approve or decline
//   POST /invited {token,join,group}   host sent the invite, group = party id from the game
//   POST /join    {party,sid,name,rank,role}  -> {id,secret}
//   GET  /status?id=&secret=           -> {status,group}
//   GET  /avatars?ids=a,b              -> {sid: base64 jpg}, needs secret STEAM_KEY
//   GET  /stats                        daily counters for the last 14 days

const PARTY_TTL = 600;
const JOIN_TTL = 120;
const LIST_MAX = 60;
const MODES = 4;
const LANGS = ["ru", "en"];
const SPREADS = [1, 2, 99];
const AVATAR_MAX = 10;
const AVATAR_TTL = 86400;

let ready = false;
const hits = new Map();
const seenMem = new Set();

async function setup(db) {
  if (ready) return;
  await db.batch([
    db.prepare("CREATE TABLE IF NOT EXISTS parties (id TEXT PRIMARY KEY, token TEXT, sid TEXT UNIQUE, name TEXT, rank INTEGER, mode INTEGER, roles INTEGER, lang TEXT, spread INTEGER, auto INTEGER, size INTEGER, expires INTEGER)"),
    db.prepare("CREATE TABLE IF NOT EXISTS joins (id TEXT PRIMARY KEY, secret TEXT, party TEXT, sid TEXT, name TEXT, rank INTEGER, role INTEGER, status TEXT, grp TEXT, expires INTEGER)"),
    db.prepare("CREATE INDEX IF NOT EXISTS joins_party ON joins (party)"),
    db.prepare("CREATE TABLE IF NOT EXISTS stats (day TEXT, key TEXT, n INTEGER, PRIMARY KEY (day, key))"),
    db.prepare("CREATE TABLE IF NOT EXISTS seen (day TEXT, h TEXT, PRIMARY KEY (day, h))"),
  ]);
  ready = true;
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
}

function rid(n = 16) {
  const a = new Uint8Array(n);
  crypto.getRandomValues(a);
  return [...a].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function now() {
  return Math.floor(Date.now() / 1000);
}

function limited(ip, max, win) {
  const t = Date.now();
  const h = hits.get(ip) || { n: 0, reset: t + win * 1000 };
  if (t > h.reset) {
    h.n = 0;
    h.reset = t + win * 1000;
  }
  h.n += 1;
  hits.set(ip, h);
  if (hits.size > 5000) hits.clear();
  return h.n > max;
}

const sidOk = (s) => typeof s === "string" && /^7656119\d{10}$/.test(s);
const int = (v, lo, hi) => {
  if (v === null || v === undefined || v === "" || typeof v === "boolean") return null;
  const n = Number(v);
  return Number.isInteger(n) && n >= lo && n <= hi ? n : null;
};
const clean = (s) => String(s || "").replace(/[\u0000-\u001f<>]/g, "").trim().slice(0, 24) || "?";
const medal = (r) => Math.floor(r / 10);
const today = (t) => new Date(t * 1000).toISOString().slice(0, 10);

async function bump(db, t, key) {
  await db.prepare("INSERT INTO stats (day, key, n) VALUES (?, ?, 1) ON CONFLICT (day, key) DO UPDATE SET n = n + 1").bind(today(t), key).run();
}

async function viewer(db, t, ip) {
  const day = today(t);
  const raw = new TextEncoder().encode("bb-party:" + day + ":" + ip);
  const h = [...new Uint8Array(await crypto.subtle.digest("SHA-256", raw))].slice(0, 8).map((b) => b.toString(16).padStart(2, "0")).join("");
  const key = day + ":" + h;
  if (seenMem.has(key)) return;
  seenMem.add(key);
  if (seenMem.size > 20000) seenMem.clear();
  const r = await db.prepare("INSERT OR IGNORE INTO seen (day, h) VALUES (?, ?)").bind(day, h).run();
  if (r && r.meta && r.meta.changes > 0) await bump(db, t, "viewers");
}

function b64(buf) {
  const bytes = new Uint8Array(buf);
  let bin = "";
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(bin);
}

async function avatars(ids, env) {
  const cache = caches.default;
  const out = {};
  const miss = [];
  for (const sid of ids) {
    const hit = await cache.match(new Request("https://bb-avatar.cache/" + sid));
    if (hit) out[sid] = await hit.text();
    else miss.push(sid);
  }
  if (miss.length === 0 || !env.STEAM_KEY) return out;
  const r = await fetch("https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/?key=" + encodeURIComponent(env.STEAM_KEY) + "&steamids=" + miss.join(","));
  if (!r.ok) return out;
  const players = ((await r.json()).response || {}).players || [];
  await Promise.all(players.map(async (pl) => {
    const sid = String(pl.steamid || "");
    const link = String(pl.avatarmedium || "");
    if (!miss.includes(sid) || !/^https:\/\/avatars\.[a-z.]*steamstatic\.com\//.test(link)) return;
    const img = await fetch(link);
    if (!img.ok) return;
    const data = b64(await img.arrayBuffer());
    out[sid] = data;
    await cache.put(new Request("https://bb-avatar.cache/" + sid), new Response(data, { headers: { "cache-control": "max-age=" + AVATAR_TTL } }));
  }));
  return out;
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const ip = req.headers.get("CF-Connecting-IP") || "?";
    if (limited(ip, 90, 60)) return json({ error: "slow" }, 429);
    if (!env.DB) return json({ error: "no db" }, 500);
    await setup(env.DB);
    const db = env.DB;
    const t = now();
    let body = {};
    if (req.method === "POST") {
      try {
        body = await req.json();
      } catch {
        return json({ error: "bad json" }, 400);
      }
    }
    const q = url.searchParams;

    if (url.pathname === "/parties" && req.method === "GET") {
      if (Math.random() < 0.05) {
        await db.batch([
          db.prepare("DELETE FROM parties WHERE expires < ?").bind(t),
          db.prepare("DELETE FROM joins WHERE expires < ?").bind(t),
          db.prepare("DELETE FROM seen WHERE day < ?").bind(today(t - 2 * 86400)),
        ]);
      }
      await viewer(db, t, ip);
      const mode = int(q.get("mode"), 0, MODES - 1);
      const lang = LANGS.includes(q.get("lang")) ? q.get("lang") : null;
      let sql = "SELECT id, sid, name, rank, mode, roles, lang, spread, auto, size, expires FROM parties WHERE expires > ?";
      const args = [t];
      if (mode !== null) {
        sql += " AND mode = ?";
        args.push(mode);
      }
      if (lang) {
        sql += " AND lang = ?";
        args.push(lang);
      }
      sql += " ORDER BY expires DESC LIMIT " + LIST_MAX;
      const rows = await db.prepare(sql).bind(...args).all();
      const parties = rows.results || [];
      if (parties.length > 0) {
        const ids = parties.map((p) => p.id);
        const marks = ids.map(() => "?").join(",");
        const mem = await db.prepare("SELECT party, sid FROM joins WHERE status = 'invited' AND party IN (" + marks + ")").bind(...ids).all();
        const by = {};
        for (const m of mem.results || []) (by[m.party] = by[m.party] || []).push(m.sid);
        for (const p of parties) p.members = [p.sid, ...(by[p.id] || [])].slice(0, 5);
      }
      return json({ now: t, parties });
    }

    if (url.pathname === "/party" && req.method === "POST") {
      const sid = body.sid;
      const rank = int(body.rank, 0, 99);
      const mode = int(body.mode, 0, MODES - 1);
      const roles = int(body.roles, 1, 31);
      const spread = int(body.spread, 0, SPREADS.length - 1);
      const size = int(body.size, 1, 4) || 1;
      if (!sidOk(sid) || rank === null || mode === null || roles === null || spread === null || !LANGS.includes(body.lang)) {
        return json({ error: "bad party" }, 400);
      }
      const id = rid(6);
      const token = rid(16);
      await db.prepare("INSERT OR REPLACE INTO parties (id, token, sid, name, rank, mode, roles, lang, spread, auto, size, expires) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
        .bind(id, token, sid, clean(body.name), rank, mode, roles, body.lang, spread, body.auto ? 1 : 0, size, t + PARTY_TTL).run();
      await bump(db, t, "parties");
      return json({ id, token, expires: t + PARTY_TTL });
    }

    if (url.pathname === "/extend" && req.method === "POST") {
      const token = String(body.token || "");
      const party = await db.prepare("SELECT id FROM parties WHERE token = ? AND expires > ?").bind(token, t).first();
      if (!party) return json({ error: "gone" }, 404);
      await db.batch([
        db.prepare("UPDATE parties SET expires = ? WHERE id = ?").bind(t + PARTY_TTL, party.id),
        db.prepare("UPDATE joins SET expires = ? WHERE party = ? AND status = 'invited'").bind(t + PARTY_TTL, party.id),
      ]);
      return json({ now: t, expires: t + PARTY_TTL });
    }

    if (url.pathname === "/close" && req.method === "POST") {
      await db.prepare("DELETE FROM parties WHERE token = ?").bind(String(body.token || "")).run();
      return json({ ok: true });
    }

    if (url.pathname === "/host" && req.method === "GET") {
      const party = await db.prepare("SELECT id, sid, size, expires FROM parties WHERE token = ? AND expires > ?").bind(q.get("token") || "", t).first();
      if (!party) return json({ error: "gone" }, 404);
      const rows = await db.prepare("SELECT id, sid, name, rank, role, status FROM joins WHERE party = ? AND expires > ? AND status IN ('wait', 'ask', 'invited')").bind(party.id, t).all();
      const all = rows.results || [];
      const members = [party.sid, ...all.filter((j) => j.status === "invited").map((j) => j.sid)].slice(0, 5);
      return json({ now: t, party: { id: party.id, size: party.size, expires: party.expires }, members, joins: all.filter((j) => j.status !== "invited") });
    }

    if ((url.pathname === "/decide" || url.pathname === "/invited") && req.method === "POST") {
      const party = await db.prepare("SELECT id, size FROM parties WHERE token = ? AND expires > ?").bind(String(body.token || ""), t).first();
      if (!party) return json({ error: "gone" }, 404);
      const join = String(body.join || "");
      const row = await db.prepare("SELECT status FROM joins WHERE id = ? AND party = ? AND expires > ?").bind(join, party.id, t).first();
      if (!row) return json({ error: "no join" }, 404);
      if (url.pathname === "/decide") {
        if (row.status !== "ask") return json({ error: "state" }, 409);
        await db.prepare("UPDATE joins SET status = ? WHERE id = ?").bind(body.ok ? "wait" : "no", join).run();
        return json({ ok: true });
      }
      if (row.status !== "wait") return json({ error: "state" }, 409);
      const grp = String(body.group || "");
      if (!/^\d{1,20}$/.test(grp)) return json({ error: "bad group" }, 400);
      await db.batch([
        db.prepare("UPDATE joins SET status = 'invited', grp = ?, expires = (SELECT expires FROM parties WHERE id = ?) WHERE id = ? AND party = ?").bind(grp, party.id, join, party.id),
        db.prepare("UPDATE parties SET size = MIN(size + 1, 5) WHERE id = ?").bind(party.id),
      ]);
      await bump(db, t, "joined");
      return json({ ok: true });
    }

    if (url.pathname === "/join" && req.method === "POST") {
      const sid = body.sid;
      const rank = int(body.rank, 0, 99);
      const role = int(body.role, 0, 5);
      if (!sidOk(sid) || rank === null || role === null) return json({ error: "bad join" }, 400);
      const party = await db.prepare("SELECT id, sid, rank, spread, auto, size FROM parties WHERE id = ? AND expires > ?").bind(String(body.party || ""), t).first();
      if (!party) return json({ error: "gone" }, 404);
      if (party.sid === sid) return json({ error: "own" }, 400);
      if (party.size >= 5) return json({ error: "full" }, 409);
      if (Math.abs(medal(rank) - medal(party.rank)) > SPREADS[party.spread]) return json({ error: "rank" }, 403);
      const open = await db.prepare("SELECT COUNT(*) AS n FROM joins WHERE sid = ? AND expires > ? AND status IN ('wait', 'ask')").bind(sid, t).first();
      if (open && open.n > 0) return json({ error: "busy" }, 409);
      const id = rid(8);
      const secret = rid(16);
      await db.prepare("INSERT INTO joins (id, secret, party, sid, name, rank, role, status, grp, expires) VALUES (?, ?, ?, ?, ?, ?, ?, ?, '', ?)")
        .bind(id, secret, party.id, sid, clean(body.name), rank, role, party.auto ? "wait" : "ask", t + JOIN_TTL).run();
      await bump(db, t, "joins");
      return json({ id, secret });
    }

    if (url.pathname === "/status" && req.method === "GET") {
      const row = await db.prepare("SELECT status, grp FROM joins WHERE id = ? AND secret = ?").bind(q.get("id") || "", q.get("secret") || "").first();
      if (!row) return json({ error: "gone" }, 404);
      return json({ status: row.status, group: row.grp });
    }

    if (url.pathname === "/avatars" && req.method === "GET") {
      const ids = [...new Set((q.get("ids") || "").split(",").filter(sidOk))].slice(0, AVATAR_MAX);
      if (ids.length === 0) return json({});
      return json(await avatars(ids, env));
    }

    if (url.pathname === "/stats" && req.method === "GET") {
      const rows = await db.prepare("SELECT day, key, n FROM stats WHERE day >= ? ORDER BY day DESC").bind(today(t - 13 * 86400)).all();
      const days = {};
      for (const r of rows.results || []) (days[r.day] = days[r.day] || { viewers: 0, parties: 0, joins: 0, joined: 0 })[r.key] = r.n;
      return json({ days });
    }

    return json({ error: "not found" }, 404);
  },
};
