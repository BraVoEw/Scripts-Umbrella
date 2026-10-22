import datetime
import json
import os
import sys
import urllib.request

REPO = os.environ.get("GITHUB_REPOSITORY", "BraVoEw/Scripts-Umbrella")
SCRIPTS = {"build-brain": "build_brain.lua", "history-changer": "history_changer.lua"}


def releases():
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "download-stats"}
    if os.environ.get("GH_TOKEN"):
        headers["Authorization"] = "Bearer " + os.environ["GH_TOKEN"]
    req = urllib.request.Request("https://api.github.com/repos/%s/releases?per_page=100" % REPO, headers=headers)
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode())


def main():
    path = sys.argv[1]
    rels = releases()
    if not isinstance(rels, list) or not rels:
        print("no releases in the answer, skip")
        return 0
    counts = {key: 0 for key in SCRIPTS}
    for rel in rels:
        for key, name in SCRIPTS.items():
            if rel.get("tag_name", "").startswith(key + "-v"):
                counts[key] += sum(a.get("download_count", 0) for a in rel.get("assets", []) if a.get("name") == name)
    data = {"points": []}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    if data["points"]:
        prev = data["points"][-1]["s"]
        if prev == counts:
            print("no change", counts)
            return 0
        if any(counts[k] < prev.get(k, 0) for k in counts):
            print("lower than the last snapshot, skip", counts, prev)
            return 0
    now = datetime.datetime.now(datetime.timezone.utc).replace(second=0, microsecond=0)
    data["points"].append({"t": now.isoformat().replace("+00:00", "Z"), "s": counts})
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, separators=(",", ":"))
    print("added", counts)
    return 0


if __name__ == "__main__":
    sys.exit(main())
