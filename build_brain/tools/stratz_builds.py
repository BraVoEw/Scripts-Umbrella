import argparse
import collections
import json
import math
import os
import sys
import time
import urllib.error
import urllib.request

API = "https://api.stratz.com/graphql"
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
PATCH_GRACE = 2 * 86400
FULL_CRON = "0 3 * * 1,4"
SIT_MAX = 12
BUY_SHARE = 0.02
BUY_COST = 1000
MU_BRACKETS = "LEGEND_ANCIENT, DIVINE_IMMORTAL"
MU_PRIOR = 300
TRIES = 12
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


def item_parts():
    url = "https://raw.githubusercontent.com/odota/dotaconstants/master/build/items.json"
    req = urllib.request.Request(url, headers={"User-Agent": "build-brain"})
    with urllib.request.urlopen(req, timeout=120) as r:
        d = json.loads(r.read().decode())
    return {"item_" + k: ["item_" + c for c in (v.get("components") or []) if c] for k, v in d.items()}


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


def mainer_games(hero_id, version):
    d = gql('{ leaderboard { a: hero(request: {heroIds: [%d], bracketIds: [IMMORTAL], take: %d}) { steamAccountId } } }' % (hero_id, MAIN_PLAYERS))
    ids = [p["steamAccountId"] for p in (d.get("leaderboard") or {}).get("a") or []]
    games = []
    for k in range(0, len(ids), 5):
        chunk = ids[k:k + 5]
        parts = ['p%d: player(steamAccountId: %d) { matches(request: {heroIds: [%d], take: %d}) { gameVersionId players { steamAccountId heroId position isVictory stats { itemPurchases { time itemId } } } } }'
                 % (i, sid, hero_id, MAIN_PER) for i, sid in enumerate(chunk)]
        data = gql("{ " + " ".join(parts) + " }")
        for i, sid in enumerate(chunk):
            for m in (data.get("p%d" % i) or {}).get("matches") or []:
                if m.get("gameVersionId") != version:
                    continue
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
    loose = sorted([a for a in tal if a not in slots.values()], key=lambda a: -tal[a])
    tiers = []
    for tier in range(4):
        pair = []
        for slot in (tier * 2, tier * 2 + 1):
            aid = slots.get(slot)
            if aid is None and loose:
                aid = loose.pop(0)
            if aid is not None:
                pair.append(aid)
        best = max(pair, key=lambda a: tal.get(a, 0)) if pair else None
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
            if not it or c < n * 0.25 or it["name"] == "item_ward_dispenser":
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
            r["start"] = m["start"]
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
    c = constants()
    versions = sorted(c["gameVersions"], key=lambda v: v["asOfDateTime"])
    now = int(time.time())
    latest = versions[-1]
    if args.decide:
        old = ""
        if args.version_file and os.path.exists(args.version_file):
            with open(args.version_file, encoding="utf-8") as f:
                old = f.read().split("\t")[0].strip()
        run = args.event != "schedule" or args.schedule == FULL_CRON or not old
        if not run:
            run = old != latest["name"] and now - latest["asOfDateTime"] >= PATCH_GRACE
        out = os.environ.get("GITHUB_OUTPUT")
        if out:
            with open(out, "a", encoding="utf-8") as f:
                f.write("run=%s\n" % ("true" if run else "false"))
        print("latest patch", latest["name"], "stored", old or "none", "run", run)
        return 0
    patch = latest
    if now - latest["asOfDateTime"] < PATCH_GRACE and len(versions) > 1:
        patch = versions[-2]
    week_now = now // WEEK
    if patch is not latest:
        week_now = latest["asOfDateTime"] // WEEK - 1
    first_full = -(-patch["asOfDateTime"] // WEEK)
    weeks = [w for w in range(week_now - args.weeks + 1, week_now + 1) if w >= first_full] or [week_now]
    week_ts = [w * WEEK for w in weeks]
    items = {"by_id": {}, "by_name": {}, "parts": item_parts()}
    for it in c["items"]:
        st = it.get("stat") or {}
        e = {"name": "item_" + it["shortName"], "cost": st.get("cost") or 0, "recipe": bool(st.get("isRecipe"))}
        items["by_id"][it["id"]] = e
        items["by_name"][e["name"]] = e
    ab = {a["id"]: a for a in c["abilities"]}
    heroes = sorted(c["heroes"], key=lambda h: h["id"])
    if args.heroes:
        want = {int(x) for x in args.heroes.split(",")}
        heroes = [h for h in heroes if h["id"] in want]
    lines, vs_lines = [], []
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
            if cached.get("version") == patch["id"] and now - cached.get("at", 0) < args.main_age:
                games = cached["games"]
        if games is None:
            try:
                games = mainer_games(h["id"], patch["id"])
            except Exception as e:
                print("mainers failed", h["shortName"], e, flush=True)
                games = []
            if mfile:
                with open(mfile, "w", encoding="utf-8") as f:
                    json.dump({"version": patch["id"], "at": now, "games": games}, f)
        roles = summarize(h, data, week_ts, items, ab, mainer_builds(games, items))
        if roles:
            lines.append("%d\t%s" % (h["id"], json.dumps(roles, ensure_ascii=False, separators=(",", ":"))))
        try:
            vs = vs_line(hero_vs(h["id"], week_ts, args.cache))
        except Exception as e:
            print("matchups failed", h["shortName"], e, flush=True)
            vs = ""
        if vs:
            vs_lines.append("V\t%d\t%s" % (h["id"], vs))
        print("%3d/%d %s %s" % (i + 1, len(heroes), h["shortName"], " ".join("%s:%d/%d" % (k, v["n"], v.get("mg", 0)) for k, v in sorted(roles.items()))), flush=True)
    head = "BB1\t%s\t%d\t%s" % (patch["name"], now, ",".join(str(w) for w in week_ts))
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        f.write(head + "\n" + "\n".join(lines + vs_lines) + "\n")
    if args.version_file:
        with open(args.version_file, "w", encoding="utf-8", newline="\n") as f:
            f.write("%s\t%d\n" % (patch["name"], now))
    print("wrote", args.out, len(lines), "heroes", len(vs_lines), "matchup rows", os.path.getsize(args.out), "bytes")


if __name__ == "__main__":
    sys.exit(main())
