"""يتحقق من حالات الاختبار الذهبية على المخطط ومن تفرّد المعرّفات.

التشغيل من جذر المشروع:  python tool/validate_golden.py [ملفات]
"""
import glob
import io
import json
import sys

from jsonschema import Draft202012Validator

schema = json.load(io.open("test/fiqh/golden/golden.schema.json", encoding="utf-8"))
v = Draft202012Validator(schema)
files = sys.argv[1:] or sorted(glob.glob("test/fiqh/golden/cases/*.json"))
known_rules = {r["id"] for r in json.load(io.open("assets/fiqh/rules.json", encoding="utf-8"))["rules"]}
known_rules |= {r["id"] for r in json.load(io.open("assets/fiqh/deferred-istihbabi.json", encoding="utf-8"))["rules"]}
import re
base = {re.sub(r"[a-z]$", "", r) for r in known_rules}
bad = 0
seen = {}
total = 0
for f in files:
    cases = json.load(io.open(f, encoding="utf-8"))
    if not isinstance(cases, list):
        print(f, "must be a JSON array")
        bad += 1
        continue
    for c in cases:
        total += 1
        cid = c.get("id")
        if cid in seen:
            print(f, "DUPLICATE id", cid, "also in", seen[cid])
            bad += 1
        seen[cid] = f
        for rid in c.get("rules", []):
            if rid not in known_rules and rid not in base:
                bad += 1
                print(f"{f} [{cid}] rules: unknown rule id {rid}")
        for e in sorted(v.iter_errors(c), key=lambda e: list(e.path)):
            bad += 1
            print(f"{f} [{cid}] {'/'.join(map(str, e.path))}: {e.message[:200]}")
    print(f, len(cases), "cases")
print("total", total, "cases;", "OK" if not bad else f"{bad} problems")
sys.exit(1 if bad else 0)
