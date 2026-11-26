import argparse
import collections
import concurrent.futures
import json
import math
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.stratz.com/graphql"
GAME_FILES = "https://raw.githubusercontent.com/SteamDatabase/GameTracking-Dota2/master/game/dota/pak01_dir/scripts/npc/"
GAME_MIN_ITEMS = 300
PATCH_LIST = "https://www.dota2.com/datafeed/patchnoteslist?language=english"
WEEK = 604800
POSITIONS = ["POSITION_1", "POSITION_2", "POSITION_3", "POSITION_4", "POSITION_5"]
START_GOLD = 600
MIN_GAMES = 150
CORE_SHARE = 0.25
SIT_SHARE = 0.05
CORE_COST = 900
SIT_COST = 1000
CORE_MAX = 10
EARLY_SHARE = 0.25
EARLY_COST = 150
EARLY_TM = 900
EARLY_MAX = 6
LANE_TM = 720
LANE_COST = 150
LANE_COST_MAX = 1500
MAIN_PLAYERS = 25
MAIN_PER = 15
MAIN_MIN_GAMES = 15
START_SLOTS = 6
START_SHARE = 0.25
COPY_SHARE = 0.5
WARDS = {"item_ward_observer", "item_ward_sentry"}
STACKS = {"item_tango", "item_clarity", "item_flask", "item_enchanted_mango", "item_ward_observer", "item_ward_sentry",
          "item_blood_grenade", "item_dust"}
VISION_ITEMS = ("item_dust", "item_ward_sentry", "item_ward_observer")
VISION_Z = 3.0
VISION_MIN = 15
VISION_LIFT = 1.3
VISION_PRIOR = 10
PATCH_GRACE = 2 * 86400
READY_MAJOR = 3 * 86400
READY_MINOR = 7 * 86400
OD_API = "https://api.opendota.com/api/"
OD_MIN_GAMES = 10
OD_NEW_SHARE = 0.15
FULL_CRON = "0 3 * * 1,4"
SIT_MAX = 12
BUY_SHARE = 0.02
BUY_COST = 1000
MU_BRACKETS = "LEGEND_ANCIENT, DIVINE_IMMORTAL"
MU_PRIOR = 300
TRIES = 12
TAL_REACH = (0.92, 0.74, 0.44)
SKIP = {"item_tpscroll", "item_ward_observer", "item_ward_sentry", "item_ward_dispenser", "item_smoke_of_deceit", "item_dust",
        "item_tango", "item_clarity", "item_flask", "item_enchanted_mango", "item_faerie_fire", "item_blood_grenade",
        "item_aghanims_shard_roshan", "item_ultimate_scepter_roshan", "item_cheese", "item_refresher_shard", "item_aegis"}


def token():
    t = os.environ.get("STRATZ_TOKEN", "").strip()
    if t:
        return t
    with open(os.path.join(os.path.expanduser("~"), "stratz_token.txt"), encoding="utf-8") as f:
        return f.read().strip()


TOKEN = None


def gql(query):
    for attempt in range(TRIES):
        req = urllib.request.Request(API, data=json.dumps({"query": query}).encode(), headers={
            "Authorization": "Bearer " + TOKEN, "Content-Type": "application/json", "User-Agent": "STRATZ_API"})
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                d = json.loads(r.read().decode())
            if d.get("errors") and not d.get("data"):
                raise RuntimeError(json.dumps(d["errors"])[:400])
            return d["data"]
        except urllib.error.HTTPError as e:
            if (e.code == 429 or e.code >= 500) and attempt < TRIES - 1:
                time.sleep(min(120, 15 * (attempt + 1)))
                continue
            raise RuntimeError("http %d %s" % (e.code, e.read().decode(errors="replace")[:300]))
        except (urllib.error.URLError, TimeoutError):
            if attempt < TRIES - 1:
                time.sleep(min(120, 15 * (attempt + 1)))
                continue
            raise


def constants():
    d = gql("""{ constants {
      gameVersions { id name asOfDateTime }
      items { id shortName stat { cost isRecipe isPurchasable } components { componentId } }
      heroes { id shortName talents { abilityId slot } abilities { slot abilityId } }
      abilities { id name isTalent stat { isUltimate } }
    } }""")["constants"]
    return d


def hero_query(hero_id, week):
    parts = []
    for j, p in enumerate(POSITIONS):
        a = "heroId: %d, week: %d, bracketBasicIds: [DIVINE_IMMORTAL], positionIds: [%s]" % (hero_id, week, p)
        parts.append("""
      f{j}: itemFullPurchase({a}, matchLimit: 0) {{ itemId instance time matchCount }}
      s{j}: itemStartingPurchase({a}) {{ itemId instance matchCount }}
      b{j}: itemBootPurchase({a}) {{ itemId time matchCount }}
      t{j}: talent({a}) {{ abilityId matchCount }}
      m{j}: abilityMinLevel({a}) {{ abilityId level matchCount }}
      x{j}: abilityMaxLevel({a}) {{ abilityId level matchCount }}""".format(j=j, a=a))
    return "{ heroStats {" + "".join(parts) + "\n} }"


def mu_query(hero_id, weeks):
    parts = []
    for j, w in enumerate(weeks):
        parts.append("w%d: heroVsHeroMatchup(heroId: %d, week: %d, bracketBasicIds: [%s], take: 200) "
                     "{ advantage { vs { heroId2 matchCount winCount winRateHeroId1 winRateHeroId2 } } }" % (j, hero_id, w, MU_BRACKETS))
    return "{ heroStats { " + " ".join(parts) + " } }"


def logit(p):
    p = min(0.99, max(0.01, p))
    return math.log(p / (1 - p))


def vs_line(data):
    pairs = {}
    for week in data:
        for adv in week or []:
            for r in adv.get("vs") or []:
                g = r.get("matchCount") or 0
                if g <= 0 or not r.get("heroId2"):
                    continue
                d = logit(float(r.get("winRateHeroId1") or 0.5)) - logit(float(r.get("winRateHeroId2") or 0.5))
                e = 1 / (1 + math.exp(-d))
                p = pairs.setdefault(r["heroId2"], [0, 0, 0.0])
                p[0] += g
                p[1] += r.get("winCount") or 0
                p[2] += e * g
    out = []
    for h2, (g, w, eg) in sorted(pairs.items()):
        e = eg / g
        v = int(round((logit((w + MU_PRIOR * e) / (g + MU_PRIOR)) - logit(e)) * 1000))
        if v:
            out.append("%d:%d" % (h2, v))
    return ",".join(out)


def hero_wr(data):
    g = s = 0.0
    for week in data:
        for adv in week or []:
            for r in adv.get("vs") or []:
                c = r.get("matchCount") or 0
                if c > 0 and r.get("winRateHeroId1") is not None:
                    g += c
                    s += c * float(r["winRateHeroId1"])
    return s / g if g else None


def hero_vs(hero_id, week_ts, cache):
    vfile = os.path.join(cache, "vs_%d.json" % hero_id) if cache else ""
    if vfile and os.path.exists(vfile):
        with open(vfile, encoding="utf-8") as f:
            cached = json.load(f)
        if cached.get("weeks") == week_ts and cached.get("brackets") == MU_BRACKETS:
            return cached["data"]
    d = gql(mu_query(hero_id, week_ts))["heroStats"]
    data = [(d.get("w%d" % j) or {}).get("advantage") for j in range(len(week_ts))]
    if vfile:
        with open(vfile, "w", encoding="utf-8") as f:
            json.dump({"weeks": week_ts, "brackets": MU_BRACKETS, "data": data}, f)
    time.sleep(0.4)
    return data


def pos_stats(week_ts):
    out = collections.defaultdict(lambda: [0, 0])
    for w in week_ts:
        d = gql("{ heroStats { stats(week: %d, bracketBasicIds: [DIVINE_IMMORTAL], groupByPosition: true) "
                "{ heroId position matchCount winCount } } }" % w)["heroStats"]
        for r in d.get("stats") or []:
            if r.get("position") in POSITIONS:
                e = out[(r["heroId"], POSITIONS.index(r["position"]) + 1)]
                e[0] += r.get("matchCount") or 0
                e[1] += r.get("winCount") or 0
        time.sleep(0.4)
    return out


def with_wins(roles, hero_id, stats):
    for key in list(roles):
        g, w = stats.get((hero_id, int(key)), (0, 0))
        if g > 0:
            r = roles[key]
            roles[key] = dict([("n", r["n"]), ("g", g), ("w", w)] + [(k, v) for k, v in r.items() if k != "n"])
    return roles


def item_parts():
    url = "https://raw.githubusercontent.com/odota/dotaconstants/master/build/items.json"
    req = urllib.request.Request(url, headers={"User-Agent": "build-brain"})
    with urllib.request.urlopen(req, timeout=120) as r:
        d = json.loads(r.read().decode())
    return {"item_" + k: ["item_" + c for c in (v.get("components") or []) if c] for k, v in d.items()}


KV_TOKEN = re.compile(r'"((?:[^"\\]|\\.)*)"|([{}])|//[^\n]*|\[[^\]\n]*\]|([^\s{}"\[\]]+)')


def kv_parse(text):
    stack, key = [{}], None
    for m in KV_TOKEN.finditer(text):
        s, brace, bare = m.groups()
        if brace == "{":
            node = {}
            if key is not None:
                stack[-1][key] = node
            stack.append(node)
            key = None
        elif brace == "}":
            if len(stack) > 1:
                stack.pop()
            key = None
        elif s is not None or bare is not None:
            val = s if s is not None else bare
            if key is None:
                key = val
            else:
                stack[-1][key] = val
                key = None
    return stack[0]


def fetch_text(url):
    headers = {"User-Agent": "build-brain"}
    gh_token = os.environ.get("GITHUB_TOKEN", "").strip()
    if gh_token and url.startswith("https://api.github.com/"):
        headers["Authorization"] = "Bearer " + gh_token
    for n in range(4):
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=120) as r:
                return r.read().decode("utf-8", "replace")
        except Exception as e:
            print("fetch failed", url, e, flush=True)
            time.sleep(10 * (n + 1))
    return None


def item_ids(node, out):
    for k, v in node.items():
        if isinstance(v, dict):
            item_ids(v, out)
        elif k.startswith("item_") and str(v).isdigit():
            out[k] = int(v)
    return out


def game_items():
    text, ids_text = fetch_text(GAME_FILES + "items.txt"), fetch_text(GAME_FILES + "npc_ability_ids.txt")
    if not text or not ids_text:
        return None
    root = kv_parse(text).get("DOTAAbilities") or {}
    ids = item_ids((kv_parse(ids_text).get("DOTAAbilityIDs") or {}).get("ItemAbilities") or {}, {})
    out = {}
    for name, e in root.items():
        if not name.startswith("item_") or not isinstance(e, dict):
            continue
        iid = ids.get(name) or (int(e["ID"]) if str(e.get("ID", "")).isdigit() else None)
        if not iid:
            continue
        reqs = e.get("ItemRequirements") if isinstance(e.get("ItemRequirements"), dict) else {}
        req = reqs.get("01") or reqs.get("02") or reqs.get("03") or ""
        recipe = e.get("ItemRecipe") == "1"
        stock = e.get("ItemInitialStockTime") or "0"
        out[name] = {
            "id": iid,
            "cost": int(float(e.get("ItemCost") or 0)),
            "recipe": recipe,
            "gone": e.get("ItemPurchasable") == "0" or e.get("IsObsolete") == "1",
            "stack": e.get("ItemStackable") == "1",
            "stock": stock,
            "stock_turbo": e.get("ItemInitialStockTimeTurbo") or stock,
            "result": e.get("ItemResult", "") if recipe and isinstance(e.get("ItemResult"), str) else "",
            "req": req if recipe and isinstance(req, str) else "",
        }
    if len(out) < GAME_MIN_ITEMS:
        print("game items look broken", len(out), flush=True)
        return None
    return out


def game_parts(game):
    parts = {}
    for g in game.values():
        if g["result"] and g["req"]:
            parts[g["result"]] = [p.replace("*", "") for p in g["req"].split(";") if p.replace("*", "")]
    return parts


def apply_game(items, game):
    for name, g in game.items():
        e = items["by_name"].get(name)
        if e is None:
            e = {"name": name, "id": g["id"]}
            items["by_name"][name] = e
        e["cost"], e["recipe"] = g["cost"], g["recipe"]
        items["by_id"][g["id"]] = e
    for name, g in game.items():
        if g["gone"]:
            items["by_name"].pop(name, None)
            items["by_id"].pop(g["id"], None)
    for result, plist in game_parts(game).items():
        cur = items["parts"].setdefault(result, [])
        for p in plist:
            if p not in cur:
                cur.append(p)
    PARTS_MEMO.clear()


def parts_at(ts):
    path = "game/dota/pak01_dir/scripts/npc/items.txt"
    url = "https://api.github.com/repos/SteamDatabase/GameTracking-Dota2/commits?per_page=1&path=%s&until=%s" % (path, time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(ts)))
    try:
        sha = json.loads(fetch_text(url) or "[]")[0]["sha"]
    except Exception as e:
        print("old items lookup failed", e, flush=True)
        return None
    text = fetch_text("https://raw.githubusercontent.com/SteamDatabase/GameTracking-Dota2/%s/%s" % (sha, path))
    if not text:
        return None
    parts = {}
    for name, e in (kv_parse(text).get("DOTAAbilities") or {}).items():
        if not isinstance(e, dict) or e.get("ItemRecipe") != "1" or not isinstance(e.get("ItemResult"), str):
            continue
        reqs = e.get("ItemRequirements") if isinstance(e.get("ItemRequirements"), dict) else {}
        req = reqs.get("01") or reqs.get("02") or reqs.get("03") or ""
        if isinstance(req, str) and req:
            parts[e["ItemResult"]] = [p.replace("*", "") for p in req.split(";") if p.replace("*", "")]
    print("recipes as of", time.strftime("%Y-%m-%d %H:%M", time.gmtime(ts)), "from", sha[:8], len(parts), flush=True)
    return parts if len(parts) >= 50 else None


def valve_patches():
    try:
        d = json.loads(fetch_text(PATCH_LIST) or "{}")
        out = sorted(((p["patch_number"], int(p["patch_timestamp"])) for p in d.get("patches") or []
                      if p.get("patch_number") and str(p.get("patch_timestamp", "")).isdigit()), key=lambda p: p[1])
        return out or None
    except Exception as e:
        print("patch list failed", e, flush=True)
        return None


def major(name):
    m = re.match(r"\d+\.\d+", name or "")
    return m.group(0) if m else name


def patch_window(patches, now, n_weeks):
    for i in range(len(patches) - 1, -1, -1):
        name, since = patches[i]
        if since > now:
            continue
        until = next((ts for n2, ts in patches[i + 1:] if major(n2) != major(name)), None)
        end = min(now, until) if until else now
        weeks = [w for w in range(-(-since // WEEK), end // WEEK + 1)
                 if w * WEEK < end and (until is None or (w + 1) * WEEK <= until)]
        covered = sum(min(end, (w + 1) * WEEK) - w * WEEK for w in weeks)
        prev = patches[i - 1][0] if i > 0 else None
        need = READY_MINOR if prev and major(prev) == major(name) and i == len(patches) - 1 else READY_MAJOR
        if weeks and (covered >= need or i == 0):
            return {"name": name, "since": since, "until": until, "weeks": weeks[-n_weeks:]}
    return None


def stratz_window(c, now, n_weeks):
    versions = sorted(c["gameVersions"], key=lambda v: v["asOfDateTime"])
    latest = versions[-1]
    patch = latest
    if now - latest["asOfDateTime"] < PATCH_GRACE and len(versions) > 1:
        patch = versions[-2]
    week_now, until = now // WEEK, None
    if patch is not latest:
        week_now, until = latest["asOfDateTime"] // WEEK - 1, latest["asOfDateTime"]
    first_full = -(-patch["asOfDateTime"] // WEEK)
    weeks = [w for w in range(week_now - n_weeks + 1, week_now + 1) if w >= first_full] or [week_now]
    return {"name": patch["name"], "since": patch["asOfDateTime"], "until": until, "weeks": weeks}


def pick_window(now, n_weeks, c=None):
    patches = valve_patches()
    win = patch_window(patches, now, n_weeks) if patches else None
    if win:
        win["src"] = "valve"
        return win
    win = stratz_window(c if c is not None else constants(), now, n_weeks)
    win["src"] = "stratz"
    return win


def learnable(d):
    beh = d.get("AbilityBehavior") if isinstance(d.get("AbilityBehavior"), str) else ""
    return not (d.get("Innate") == "1" or d.get("IsGrantedByScepter") == "1" or d.get("IsGrantedByShard") == "1"
                or d.get("MaxLevel") == "1" or "HIDDEN" in beh or "NOT_LEARNABLE" in beh)


def game_heroes(heroes):
    ids_text = fetch_text(GAME_FILES + "npc_ability_ids.txt")
    if not ids_text:
        return None
    ids = {}

    def walk(node):
        for k, v in node.items():
            if isinstance(v, dict):
                walk(v)
            elif str(v).isdigit():
                ids[k] = int(v)

    walk(kv_parse(ids_text).get("DOTAAbilityIDs") or {})

    def one(h):
        return h, fetch_text(GAME_FILES + "heroes/npc_dota_hero_%s.txt" % h["shortName"])

    with concurrent.futures.ThreadPoolExecutor(8) as ex:
        texts = list(ex.map(one, heroes))
    out, ab = {}, {}
    for h, text in texts:
        node = (kv_parse(text or "").get("DOTAHeroes") or {}).get("npc_dota_hero_" + h["shortName"])
        if not isinstance(node, dict):
            continue
        defs = node.get("AbilityDefinitions") if isinstance(node.get("AbilityDefinitions"), dict) else {}
        skills, talents, learn, seen = [], [], [], {}
        slots = sorted(int(k[7:]) for k in node if k.startswith("Ability") and k[7:].isdigit())
        for i in slots:
            name = node.get("Ability%d" % i)
            if not isinstance(name, str) or not name or name.startswith("generic_") or name == "dota_empty" or name not in ids:
                continue
            aid = ids[name]
            d = defs.get(name) if isinstance(defs.get(name), dict) else None
            if name.startswith("special_bonus_"):
                if name != "special_bonus_attributes":
                    talents.append({"abilityId": aid, "slot": len(talents)})
                seen[aid] = {"id": aid, "name": name, "isTalent": True, "stat": {"isUltimate": False}}
                continue
            skills.append({"abilityId": aid, "slot": len(skills)})
            seen[aid] = {"id": aid, "name": name, "isTalent": False, "stat": {"isUltimate": bool(d) and d.get("AbilityType") == "ABILITY_TYPE_ULTIMATE"}}
            if d and learnable(d):
                learn.append(aid)
        if len(skills) >= 3 and len(talents) == 8:
            out[h["id"]] = {"abilities": skills, "talents": talents, "learn": learn}
            ab.update(seen)
        else:
            print("game hero skipped", h["shortName"], len(skills), len(talents), flush=True)
    if len(out) < len(heroes) * 0.8:
        print("game heroes look broken", len(out), flush=True)
        return None
    return out, ab


def od_explorer(sql):
    req = urllib.request.Request(OD_API + "explorer?sql=" + urllib.parse.quote(sql), headers={"User-Agent": "build-brain"})
    for n in range(4):
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                d = json.loads(r.read().decode())
            if d.get("err"):
                raise RuntimeError(str(d["err"])[:300])
            return d.get("rows") or []
        except Exception as e:
            print("opendota failed", e, flush=True)
            time.sleep(15 * (n + 1))
    return None


def od_new_items(names, since, until):
    keys = sorted(n[5:] for n in names if re.match(r"^item_[a-z0-9_]+$", n))
    if not keys:
        return {}
    cut = " AND m.start_time < %d" % until if until else ""
    rows = od_explorer(
        "WITH g AS (SELECT p.match_id, p.hero_id, p.purchase_log FROM player_matches p JOIN matches m USING(match_id) "
        "WHERE m.start_time >= %d%s AND p.purchase_log IS NOT NULL) "
        "SELECT hero_id, '' item, count(*) n FROM g GROUP BY 1 UNION ALL "
        "SELECT g.hero_id, x->>'key', count(DISTINCT g.match_id) FROM g, unnest(g.purchase_log) x "
        "WHERE x->>'key' IN (%s) GROUP BY 1, 2" % (since, cut, ",".join("'%s'" % k for k in keys)))
    out = {}
    for r in rows or []:
        e = out.setdefault(int(r["hero_id"]), {"n": 0, "items": {}})
        if r["item"]:
            e["items"]["item_" + r["item"]] = int(r["n"])
        else:
            e["n"] = int(r["n"])
    return out


def add_new_items(roles, od):
    if not od or od["n"] < OD_MIN_GAMES:
        return []
    got = sorted(((n, c / od["n"]) for n, c in od["items"].items() if c / od["n"] >= OD_NEW_SHARE), key=lambda x: -x[1])
    for r in roles.values():
        have = {x[0] for x in r["core"]} | {x[0] for x in r["sit"]}
        for name, share in got:
            if name not in have:
                r["sit"].append([name, round(share * 100)])
        r["sit"] = sorted(r["sit"], key=lambda x: -x[1])[:SIT_MAX]
    return [n for n, _ in got]


def catalog_lines(game):
    out = []
    for name in sorted(game):
        g = game[name]
        flags = ("r" if g["recipe"] else "") + ("g" if g["gone"] else "") + ("s" if g["stack"] else "")
        out.append("I\t%s\t%d\t%d\t%s\t%s\t%s\t%s\t%s" % (name, g["id"], g["cost"], flags, g["stock"], g["stock_turbo"], g["result"], g["req"]))
    return out


def median_level(dist):
    total = sum(dist.values())
    if not total:
        return 99
    acc = 0
    for lvl in sorted(dist):
        acc += dist[lvl]
        if acc * 2 >= total:
            return lvl
    return 99


def mainer_games(hero_id, win, matches=None):
    d = gql('{ leaderboard { a: hero(request: {heroIds: [%d], bracketIds: [IMMORTAL], take: %d}) { steamAccountId } } }' % (hero_id, MAIN_PLAYERS))
    ids = [p["steamAccountId"] for p in (d.get("leaderboard") or {}).get("a") or []]
    games = []
    for k in range(0, len(ids), 5):
        chunk = ids[k:k + 5]
        parts = ['p%d: player(steamAccountId: %d) { matches(request: {heroIds: [%d], take: %d}) { id gameVersionId startDateTime players { steamAccountId heroId position isRadiant isVictory stats { itemPurchases { time itemId } } } } }'
                 % (i, sid, hero_id, MAIN_PER) for i, sid in enumerate(chunk)]
        data = gql("{ " + " ".join(parts) + " }")
        for i, sid in enumerate(chunk):
            for m in (data.get("p%d" % i) or {}).get("matches") or []:
                st = m.get("startDateTime") or 0
                if st < win["since"] or (win["until"] and st >= win["until"]):
                    continue
                if matches is not None and m.get("id") and m["id"] not in matches:
                    matches[m["id"]] = [[p["heroId"], p.get("position") or "", bool(p.get("isRadiant")),
                                         sorted({e["itemId"] for e in ((p.get("stats") or {}).get("itemPurchases") or [])})]
                                        for p in m.get("players") or []]
                for p in m.get("players") or []:
                    if p["steamAccountId"] == sid and p["heroId"] == hero_id:
                        ev = (p.get("stats") or {}).get("itemPurchases") or []
                        if ev:
                            games.append({"pos": p["position"], "win": bool(p.get("isVictory")), "ev": [[e["time"], e["itemId"]] for e in ev]})
        time.sleep(0.4)
    return games


def mainer_builds(games, items):
    by_pos = collections.defaultdict(list)
    for g in games:
        by_pos[g["pos"]].append(g)
    out = {}
    for p, gl in by_pos.items():
        if len(gl) < MAIN_MIN_GAMES or p not in POSITIONS:
            continue
        starts, lanes = collections.Counter(), collections.Counter()
        times, have = collections.defaultdict(list), collections.Counter()
        for g in gl:
            st, lane = [], {}
            for t, iid in g["ev"]:
                it = items["by_id"].get(iid)
                if not it or it["recipe"]:
                    continue
                name = it["name"]
                if t <= 0:
                    if name != "item_tpscroll":
                        st.append(name)
                elif t <= LANE_TM and name not in SKIP and LANE_COST <= it["cost"] <= LANE_COST_MAX:
                    lane.setdefault(name, t)
            final = {n: t for n, t in lane.items() if not any(o != n and lane[o] >= t and n in components_of(items, o) for o in lane)}
            starts[tuple(sorted(st))] += 1
            if final:
                lanes[frozenset(final)] += 1
            for n, t in final.items():
                times[n].append(t)
                have[n] += 1
        start = list(starts.most_common(1)[0][0]) if starts else []
        lane = sorted(lanes.most_common(1)[0][0], key=lambda n: sorted(times[n])[len(times[n]) // 2]) if lanes else []
        out[str(POSITIONS.index(p) + 1)] = {
            "games": len(gl),
            "start": start,
            "early": [[n, sorted(times[n])[len(times[n]) // 2], round(have[n] * 100 / len(gl))] for n in lane],
        }
    return out


PARTS_MEMO = {}


def components_of(items, name, seen=None):
    if seen is None and name in PARTS_MEMO:
        return PARTS_MEMO[name]
    seen = seen or set()
    out = set()
    for cn in items["parts"].get(name, []):
        if cn not in seen:
            seen.add(cn)
            out.add(cn)
            out |= components_of(items, cn, seen)
    if len(seen) == len(out):
        PARTS_MEMO.setdefault(name, out)
    return out


def talent_tiers(hero, ab, tal):
    slots = {t["slot"]: t["abilityId"] for t in hero.get("talents") or []}
    loose = sorted([a for a in tal if a not in slots.values() and (ab.get(a) or {}).get("name") != "special_bonus_attributes"],
                   key=lambda a: -tal[a])
    pairs = []
    for tier in range(4):
        pair = []
        for slot in (tier * 2, tier * 2 + 1):
            aid = slots.get(slot)
            if aid is None and loose:
                aid = loose.pop(0)
            pair.append(aid)
        pairs.append(pair)
    totals = [sum(tal.get(a, 0) for a in p) if None not in p else None for p in pairs]
    tiers = []
    for tier, pair in enumerate(pairs):
        known = [a for a in pair if a is not None]
        best = max(known, key=lambda a: tal.get(a, 0)) if known else None
        if best is not None and len(known) == 1:
            reach = None
            if tier > 0 and totals[tier - 1] is not None:
                reach = totals[tier - 1] * TAL_REACH[tier - 1]
            elif tier < 3 and totals[tier + 1] is not None:
                reach = totals[tier + 1] / TAL_REACH[tier]
            if reach is None or tal.get(best, 0) < reach / 2:
                best = None
        tiers.append(ab[best]["name"] if best in ab and tal.get(best, 0) > 0 else None)
    return tiers


def build_skills(hero, ab, mins, maxs, n, tiers):
    skill = []
    for a in hero.get("abilities") or []:
        info = ab.get(a["abilityId"])
        if not info or info.get("isTalent") or info["name"].startswith("generic_"):
            continue
        dist = mins.get(a["abilityId"], {})
        if sum(dist.values()) < n * 0.2:
            continue
        first = median_level(dist)
        ult = bool((info.get("stat") or {}).get("isUltimate")) or first == 6
        skill.append({"id": a["abilityId"], "name": info["name"], "ult": ult, "first": first,
                      "maxl": median_level(maxs.get(a["abilityId"], {})), "max": 3 if ult else 4, "pts": 0})
    if not skill:
        return []
    seq = []
    taken = 0
    for lvl in range(1, 19):
        if lvl == 17:
            seq.append("")
            continue
        def cap(s):
            if s["ult"]:
                return 3 if lvl >= 18 else (2 if lvl >= 12 else (1 if lvl >= 6 else 0))
            return min(s["max"], (lvl + 1) // 2)

        free = [s for s in skill if s["pts"] < cap(s)]
        pick = None
        fresh = sorted([s for s in free if s["pts"] == 0 and s["first"] <= lvl], key=lambda s: (s["first"], s["maxl"]))
        if fresh and fresh[0]["first"] == lvl:
            pick = fresh[0]
        if not pick:
            ults = [s for s in free if s["ult"]]
            if ults:
                pick = ults[0]
        if not pick:
            ready = sorted([s for s in free if s["pts"] > 0], key=lambda s: (s["maxl"], s["first"]))
            pick = ready[0] if ready else (fresh[0] if fresh else None)
        if not pick:
            later = sorted(free, key=lambda s: (s["first"], s["maxl"]))
            pick = later[0] if later else None
        if pick:
            pick["pts"] += 1
            seq.append(pick["name"])
        elif taken < len(tiers) and tiers[taken] and lvl >= 10 + taken * 5:
            seq.append(tiers[taken])
            taken += 1
        else:
            seq.append("")
    return seq


def vision_lines(matches, items):
    ids = {items["by_name"][n]["id"]: n for n in VISION_ITEMS if n in items["by_name"] and "id" in items["by_name"][n]}
    rows = []
    for players in matches.values():
        if len(players) != 10:
            continue
        for hero, pos, radiant, bought in players:
            if pos not in POSITIONS:
                continue
            group = 1 if POSITIONS.index(pos) < 3 else 2
            have = {ids[i] for i in bought if i in ids}
            foes = [h for h, _, r, _ in players if r != radiant]
            rows.append((hero, pos, group, have, foes))
    n_key, c_key = collections.Counter(), collections.Counter()
    for hero, pos, group, have, foes in rows:
        n_key[(hero, pos)] += 1
        for it in have:
            c_key[(hero, pos, it)] += 1
    obs, exp, base_n, base_c = collections.Counter(), collections.Counter(), collections.Counter(), collections.Counter()
    for hero, pos, group, have, foes in rows:
        n = n_key[(hero, pos)]
        base_n[group] += 1
        for it in VISION_ITEMS:
            got = it in have
            if got:
                base_c[(group, it)] += 1
            if n < 2:
                continue
            pr = (c_key[(hero, pos, it)] - got) / (n - 1)
            for o in foes:
                exp[(it, group, o)] += pr
                if got:
                    obs[(it, group, o)] += 1
    out = []
    for it in VISION_ITEMS:
        for group in (1, 2):
            if not base_n[group]:
                continue
            good = []
            for (i2, g2, o), e in exp.items():
                if i2 != it or g2 != group:
                    continue
                ob = obs[(it, group, o)]
                lift = (ob + VISION_PRIOR) / (e + VISION_PRIOR)
                z = (ob - e) / (e + 1) ** 0.5
                if z >= VISION_Z and ob >= VISION_MIN and lift >= VISION_LIFT:
                    good.append((o, round(lift * 100)))
            good.sort(key=lambda x: -x[1])
            base = round(100 * base_c[(group, it)] / base_n[group])
            out.append("E\t%s\t%d\t%d\t%s" % (it, group, base, ",".join("%d:%d" % g for g in good)))
    return out


def start_slots(st):
    return sum(1 for i, n in enumerate(st) if n not in WARDS and (n not in STACKS or n not in st[:i]))


def start_copies(main, agg, items):
    st = list(main)
    cost = {n: (items["by_name"].get(n) or {}).get("cost", 0) for n in set(st) | set(agg)}
    gold = sum(cost[n] for n in st)
    for name, k in collections.Counter(agg).items():
        while name in st and st.count(name) < k and gold + cost[name] <= START_GOLD and start_slots(st + [name]) <= START_SLOTS:
            st.insert(st.index(name) + 1, name)
            gold += cost[name]
    for name in list(agg) + ["item_tango"]:
        price = cost.get(name, (items["by_name"].get(name) or {}).get("cost", 0))
        if name not in st and gold + price <= START_GOLD and start_slots(st + [name]) <= START_SLOTS:
            st.append(name)
            gold += price
    return st


def summarize(hero, data, weeks, items, ab, mainers=None):
    per = collections.defaultdict(lambda: {"full": collections.defaultdict(lambda: [0, 0]), "start": collections.Counter(),
                                           "boot": collections.defaultdict(lambda: [0, 0]), "tal": collections.Counter(),
                                           "min": collections.defaultdict(collections.Counter), "max": collections.defaultdict(collections.Counter)})
    for week in data:
        for j, p in enumerate(POSITIONS):
            for r in week.get("f%d" % j) or []:
                if r["instance"] == 0:
                    e = per[p]["full"][r["itemId"]]
                    e[0] += r["matchCount"]
                    e[1] += r["matchCount"] * r["time"] * 60
            for r in week.get("s%d" % j) or []:
                per[p]["start"][(r["itemId"], r["instance"])] += r["matchCount"]
            for r in week.get("b%d" % j) or []:
                e = per[p]["boot"][r["itemId"]]
                e[0] += r["matchCount"]
                e[1] += r["time"]
            for r in week.get("t%d" % j) or []:
                per[p]["tal"][r["abilityId"]] += r["matchCount"]
            for r in week.get("m%d" % j) or []:
                per[p]["min"][r["abilityId"]][r["level"]] += r["matchCount"]
            for r in week.get("x%d" % j) or []:
                per[p]["max"][r["abilityId"]][r["level"]] += r["matchCount"]

    out = {}
    for p, d in per.items():
        n = sum(c for dist in d["min"].values() for lvl, c in dist.items() if lvl == 1)
        if n < MIN_GAMES:
            continue
        start, gold = [], START_GOLD
        for (iid, inst), c in sorted(d["start"].items(), key=lambda kv: -kv[1]):
            it = items["by_id"].get(iid)
            if not it or c < n * (COPY_SHARE if inst > 0 else START_SHARE) or it["name"] == "item_ward_dispenser":
                continue
            if it["cost"] <= gold:
                gold -= it["cost"]
                start.append(it["name"])
        cand = []
        for iid, (c, tsum) in list(d["full"].items()) + list(d["boot"].items()):
            it = items["by_id"].get(iid)
            if not it or it["name"] in SKIP or it["recipe"]:
                continue
            share = min(1.0, c / n)
            tm = int(tsum / c) if c else 0
            if any(x["name"] == it["name"] for x in cand):
                continue
            cand.append({"name": it["name"], "share": share, "tm": tm, "cost": it["cost"], "boot": iid in d["boot"], "id": iid})
        buy = sorted([c for c in cand if c["share"] >= BUY_SHARE and c["cost"] >= BUY_COST], key=lambda c: -c["share"])
        boots = sorted([c for c in cand if c["boot"]], key=lambda c: -c["share"])
        cand = [c for c in cand if not c["boot"]] + boots[:1] + [dict(b, share=min(b["share"], CORE_SHARE - 0.01)) for b in boots[1:]]

        def covered(c):
            for o in cand:
                if o is not c and o["share"] >= max(0.15, c["share"] * 0.6) and o["tm"] >= c["tm"] and c["name"] in components_of(items, o["name"]):
                    return True
            return False

        core, sit = [], []
        for c in cand:
            if covered(c):
                continue
            if c["share"] >= CORE_SHARE and (c["cost"] >= CORE_COST or c["boot"]):
                core.append(c)
            elif c["share"] >= SIT_SHARE and c["cost"] >= SIT_COST:
                sit.append(c)
        start_set = set(start)
        early = []
        for c in cand:
            if c["boot"] or c["name"] in start_set or covered(c):
                continue
            if c["share"] >= EARLY_SHARE and EARLY_COST <= c["cost"] < CORE_COST and c["tm"] <= EARLY_TM:
                early.append(c)
        early.sort(key=lambda c: c["tm"])
        early = early[:EARLY_MAX]
        core.sort(key=lambda c: c["tm"])
        core = core[:CORE_MAX]
        sit.sort(key=lambda c: -c["share"])
        sit = sit[:SIT_MAX]
        skills = build_skills(hero, ab, d["min"], d["max"], n, talent_tiers(hero, ab, d["tal"]))
        blind = [a for a in hero.get("learn") or [] if not sum(d["min"].get(a, {}).values())]
        if blind:
            print("skills dropped", hero["shortName"], p, "no data for", ",".join(ab[a]["name"] for a in blind if a in ab), flush=True)
            skills = []
        out[str(POSITIONS.index(p) + 1)] = {
            "n": n,
            "start": start,
            "early": [[c["name"], c["tm"], round(c["share"] * 100)] for c in early],
            "core": [[c["name"], c["tm"], round(c["share"] * 100)] for c in core],
            "sit": [[c["name"], round(c["share"] * 100)] for c in sit],
            "buy": ",".join("%d:%d" % (c["id"], round(c["share"] * 100)) for c in buy),
            "skills": skills,
            "talents": {str(a): c for a, c in d["tal"].items()},
        }
    for key, m in (mainers or {}).items():
        r = out.get(key)
        if not r:
            continue
        if m["start"]:
            r["start"] = start_copies(m["start"], r["start"], items)
        if m["early"]:
            lane = {e[0] for e in m["early"]}
            r["early"] = m["early"]
            r["core"] = [x for x in r["core"] if x[0] not in lane]
            r["sit"] = [x for x in r["sit"] if x[0] not in lane]
        r["mg"] = m["games"]
    return out


def main():
    global TOKEN
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="")
    ap.add_argument("--version-file", default="")
    ap.add_argument("--decide", action="store_true")
    ap.add_argument("--schedule", default="")
    ap.add_argument("--event", default="")
    ap.add_argument("--heroes", default="")
    ap.add_argument("--weeks", type=int, default=2)
    ap.add_argument("--cache", default="")
    ap.add_argument("--main-age", type=int, default=86400)
    args = ap.parse_args()
    TOKEN = token()
    now = int(time.time())
    if args.decide:
        win = pick_window(now, args.weeks)
        old = ""
        if args.version_file and os.path.exists(args.version_file):
            with open(args.version_file, encoding="utf-8") as f:
                old = f.read().split("\t")[0].strip()
        run = args.event != "schedule" or args.schedule == FULL_CRON or not old or old != win["name"]
        out = os.environ.get("GITHUB_OUTPUT")
        if out:
            with open(out, "a", encoding="utf-8") as f:
                f.write("run=%s\n" % ("true" if run else "false"))
        print("patch", win["name"], "from", win["src"], "stored", old or "none", "run", run)
        return 0
    c = constants()
    win = pick_window(now, args.weeks, c)
    data_until = win["until"]
    week_ts = [w * WEEK for w in win["weeks"]]
    print("patch", win["name"], "from", win["src"], "weeks", " ".join(time.strftime("%Y-%m-%d", time.gmtime(t)) for t in week_ts),
          "until", time.strftime("%Y-%m-%d %H:%M", time.gmtime(data_until)) if data_until else "now", flush=True)
    game = None
    try:
        game = game_items()
    except Exception as e:
        print("game items failed", e, flush=True)
    try:
        parts = item_parts()
    except Exception as e:
        if not game:
            raise
        print("dotaconstants parts failed", e, flush=True)
        parts = {}
    items = {"by_id": {}, "by_name": {}, "parts": parts}
    for it in c["items"]:
        st = it.get("stat") or {}
        e = {"name": "item_" + it["shortName"], "cost": st.get("cost") or 0, "recipe": bool(st.get("isRecipe")), "id": it["id"]}
        items["by_id"][it["id"]] = e
        items["by_name"][e["name"]] = e
    unseen = set()
    if game:
        known = set(items["by_id"])
        unseen = {n for n, g in game.items() if g["id"] not in known and not g["gone"] and not g["recipe"] and g["cost"] >= SIT_COST}
        apply_game(items, game)
        print("game items", len(game), "gone", sum(1 for g in game.values() if g["gone"]), "unknown to STRATZ", ",".join(sorted(unseen)), flush=True)
    if data_until:
        old_parts = parts_at(data_until)
        if old_parts:
            items["parts"] = old_parts
            PARTS_MEMO.clear()
    ab = {a["id"]: a for a in c["abilities"]}
    heroes = sorted(c["heroes"], key=lambda h: h["id"])
    if args.heroes:
        want = {int(x) for x in args.heroes.split(",")}
        heroes = [h for h in heroes if h["id"] in want]
    gh = None
    try:
        gh = game_heroes(heroes)
    except Exception as e:
        print("game heroes failed", e, flush=True)
    if gh:
        by_hero, game_ab = gh
        ab.update(game_ab)
        heroes = [dict(h, **by_hero[h["id"]]) if h["id"] in by_hero else h for h in heroes]
        print("game heroes", len(by_hero), "of", len(heroes), flush=True)
    od_new = {}
    if unseen:
        od_new = od_new_items(unseen, win["since"], win["until"]) or {}
        print("opendota new items", len(od_new), "heroes", flush=True)
    mkey = "%s@%d" % (win["name"], win["since"])
    lines, vs_lines, wr_parts = [], [], []
    vision = {}
    try:
        wins = pos_stats(week_ts)
    except Exception as e:
        print("position win rates failed", e, flush=True)
        wins = {}
    for i, h in enumerate(heroes):
        cache_file = os.path.join(args.cache, "%d.json" % h["id"]) if args.cache else ""
        data = None
        if cache_file and os.path.exists(cache_file):
            with open(cache_file, encoding="utf-8") as f:
                cached = json.load(f)
            if cached.get("weeks") == week_ts:
                data = cached["data"]
        if data is None:
            data = []
            for w in week_ts:
                data.append(gql(hero_query(h["id"], w))["heroStats"])
                time.sleep(0.4)
            if cache_file:
                with open(cache_file, "w", encoding="utf-8") as f:
                    json.dump({"weeks": week_ts, "data": data}, f)
        mfile = os.path.join(args.cache, "m_%d.json" % h["id"]) if args.cache else ""
        games = None
        if mfile and os.path.exists(mfile):
            with open(mfile, encoding="utf-8") as f:
                cached = json.load(f)
            if cached.get("version") == mkey and now - cached.get("at", 0) < args.main_age and "matches" in cached:
                games = cached["games"]
                for k, v in cached["matches"].items():
                    vision.setdefault(int(k), v)
        if games is None:
            got = {}
            try:
                games = mainer_games(h["id"], win, got)
            except Exception as e:
                print("mainers failed", h["shortName"], e, flush=True)
                games = []
            for k, v in got.items():
                vision.setdefault(k, v)
            if mfile:
                with open(mfile, "w", encoding="utf-8") as f:
                    json.dump({"version": mkey, "at": now, "games": games, "matches": got}, f)
        roles = with_wins(summarize(h, data, week_ts, items, ab, mainer_builds(games, items)), h["id"], wins)
        added = add_new_items(roles, od_new.get(h["id"]))
        if added:
            print("new items from opendota", h["shortName"], ",".join(added), flush=True)
        if roles:
            lines.append("%d\t%s" % (h["id"], json.dumps(roles, ensure_ascii=False, separators=(",", ":"))))
        try:
            vsd = hero_vs(h["id"], week_ts, args.cache)
            vs = vs_line(vsd)
            wr = hero_wr(vsd)
            if wr:
                wr_parts.append("%d:%d" % (h["id"], round(wr * 1000)))
        except Exception as e:
            print("matchups failed", h["shortName"], e, flush=True)
            vs = ""
        if vs:
            vs_lines.append("V\t%d\t%s" % (h["id"], vs))
        print("%3d/%d %s %s" % (i + 1, len(heroes), h["shortName"], " ".join("%s:%d/%d" % (k, v["n"], v.get("mg", 0)) for k, v in sorted(roles.items()))), flush=True)
    try:
        e_lines = vision_lines(vision, items)
    except Exception as e:
        print("vision failed", e, flush=True)
        e_lines = []
    print("vision", len(vision), "matches,", sum(1 for x in e_lines if x.split("\t")[4]), "lines with heroes", flush=True)
    head = "BB1\t%s\t%d\t%s" % (win["name"], now, ",".join(str(w) for w in week_ts))
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        f.write(head + "\n" + "\n".join(lines + vs_lines + (["W\t" + ",".join(wr_parts)] if wr_parts else []) + e_lines + (catalog_lines(game) if game else [])) + "\n")
    if args.version_file:
        with open(args.version_file, "w", encoding="utf-8", newline="\n") as f:
            f.write("%s\t%d\n" % (win["name"], now))
    print("wrote", args.out, len(lines), "heroes", len(vs_lines), "matchup rows", len(wr_parts), "win rates", os.path.getsize(args.out), "bytes")


if __name__ == "__main__":
    sys.exit(main())
