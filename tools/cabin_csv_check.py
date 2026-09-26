#!/usr/bin/env python3
"""Mirror of CockpitLayout.validate() from src/cabin/cockpit_layout.gd,
runnable without Godot. Checks the CSV rows against CmCabin.PANELS and
channels.csv the same way the game does at startup (minus the per-param
scene probing, which needs the engine; CI's GUT suite covers that).

Also mirrors the JSON data gate (all data/*.json parse).
"""
import csv, json, sys

ROOT = "/home/hatch/workspace/apollo-csm-work"
PANELS = {"MDC1": (0.60, 0.50), "MDC2": (0.62, 0.56), "MDC3": (0.60, 0.50)}
TYPES = {
    "toggle": {"control": True, "takes": ["bool", "int"], "half": (15, 30)},
    "rotary": {"control": True, "takes": ["int"], "half": (15, 25)},
    "pushbutton": {"control": True, "takes": ["bool"], "half": (15, 25)},
    "lamp": {"control": False, "takes": ["bool", "float"], "half": (15, 10)},
    "numeric": {"control": False, "takes": ["float", "int"], "half": (25, 8)},
    "clock": {"control": False, "takes": ["float"], "half": (35, 8)},
    "fdai": {"control": False, "takes": ["quat"], "half": (55, 55)},
    "dsky": {"control": False, "takes": ["group"], "half": (100, 120)},
}
COLUMNS = ["id","panel","type","label","x_mm","y_mm","rot_deg","channel","params","source","confidence","status","role"]
CHANNEL_COLUMNS = ["channel","type","units","writer","description"]
CHANNEL_TYPES = ["bool","int","float","string","quat","group"]

errors = []

def read_csv(path):
    rows = []
    with open(path) as f:
        lines = [l for l in f if l.strip() and not l.startswith("#")]
    rdr = csv.DictReader(lines)
    for i, r in enumerate(rdr, start=2):
        r["_line"] = i
        rows.append(r)
    return rows, rdr.fieldnames

def parse_params(text):
    out = {}
    for kv in text.split(";"):
        if "=" in kv:
            k, v = kv.split("=", 1)
            out[k.strip()] = v.strip()
    return out

# --- channels ---
ch_rows, ch_fields = read_csv(f"{ROOT}/data/cockpit/channels.csv")
channels = {}
seen = set()
for r in ch_rows:
    where = f"channels.csv row {r['_line']} ({r['channel']})"
    if len(r) - 1 != len(CHANNEL_COLUMNS):
        errors.append(f"{where}: column count")
    if r["channel"] in seen:
        errors.append(f"{where}: listed twice")
    seen.add(r["channel"])
    channels[r["channel"]] = r
    if r["type"] not in CHANNEL_TYPES:
        errors.append(f"{where}: bad type {r['type']}")
    if not r["writer"]:
        errors.append(f"{where}: no writer")

def channel_type(ch):
    if ch in channels:
        return channels[ch]["type"]
    parts = ch.split(".")
    for pat, r in channels.items():
        p = pat.split(".")
        if len(p) != len(parts):
            continue
        if all(a == "*" or a == b for a, b in zip(p, parts)):
            return r["type"]
    return ""

# --- controls ---
rows, fields = read_csv(f"{ROOT}/data/cockpit/controls.csv")
assert fields == COLUMNS, f"header drift: {fields}"
seen_ids = set()
for r in rows:
    where = f"row {r['_line']} ({r['id']})"
    if not r["id"]:
        errors.append(f"{where}: empty id")
    if r["id"] in seen_ids:
        errors.append(f"{where}: duplicate id")
    seen_ids.add(r["id"])
    if r["panel"] not in PANELS:
        errors.append(f"{where}: unknown panel {r['panel']}")
    t = TYPES.get(r["type"])
    if not t:
        errors.append(f"{where}: unknown type {r['type']}")
        continue
    ct = channel_type(r["channel"])
    if not ct:
        errors.append(f"{where}: channel {r['channel']} not in channels.csv")
    elif ct not in t["takes"]:
        errors.append(f"{where}: {r['type']} can't bind {ct} channel {r['channel']}")
    if t["control"] and ct and (not r["channel"].startswith("ctl.") or channels.get(r["channel"], {}).get("writer") != "crew"):
        errors.append(f"{where}: control must publish a crew ctl.* channel")
    for c in ["x_mm", "y_mm", "rot_deg"]:
        try:
            float(r[c])
        except ValueError:
            errors.append(f"{where}: {c} not a number")
    # footprint on panel
    params = parse_params(r["params"])
    try:
        s = float(params.get("scale", "1"))
    except ValueError:
        s = 1.0
        errors.append(f"{where}: bad scale")
    hx, hy = t["half"][0] * s, t["half"][1] * s
    if r["panel"] in PANELS:
        px, py = PANELS[r["panel"]]
        x, y = float(r["x_mm"] or 0), float(r["y_mm"] or 0)
        if abs(x) + hx > px * 500 or abs(y) + hy > py * 500:
            errors.append(f"{where}: off the {r['panel']} face")
    if r["confidence"] not in "ABCD":
        errors.append(f"{where}: bad confidence")
    if r["status"] not in ["placeholder", "implemented", "validated"]:
        errors.append(f"{where}: bad status")
    if r["status"] == "validated" and r["confidence"] in "CD":
        errors.append(f"{where}: validated needs A/B")
    if r["role"] not in ["historical", "proxy"]:
        errors.append(f"{where}: bad role")
    if not r["source"]:
        errors.append(f"{where}: no source")

# overlaps
for i in range(len(rows)):
    for j in range(i + 1, len(rows)):
        a, b = rows[i], rows[j]
        if a["panel"] != b["panel"]:
            continue
        def fp(r):
            p = parse_params(r["params"])
            s = float(p.get("scale", "1"))
            return TYPES[r["type"]]["half"][0] * s, TYPES[r["type"]]["half"][1] * s
        ahx, ahy = fp(a)
        bhx, bhy = fp(b)
        dx = abs(float(a["x_mm"]) - float(b["x_mm"]))
        dy = abs(float(a["y_mm"]) - float(b["y_mm"]))
        if dx < ahx + bhx and dy < ahy + bhy:
            errors.append(f"row {a['_line']} ({a['id']}) overlaps row {b['_line']} ({b['id']})")

# --- JSON gate ---
import glob
for p in sorted(glob.glob(f"{ROOT}/data/**/*.json", recursive=True)):
    try:
        json.load(open(p))
    except Exception as e:
        errors.append(f"{p}: {e}")

print(f"rows: {len(rows)} controls, {len(ch_rows)} channels")
if errors:
    print("ERRORS:")
    for e in errors:
        print(" -", e)
    sys.exit(1)
print("CSV mirror checks: PASS; JSON gate: PASS")
