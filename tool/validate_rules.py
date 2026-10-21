import json, sys, glob, io
from jsonschema import Draft202012Validator
schema = json.load(io.open('assets/fiqh/rules.schema.json', encoding='utf-8'))
rule_schema = {"$schema": schema["$schema"], "$defs": schema["$defs"], "$ref": "#/$defs/rule"}
v = Draft202012Validator(rule_schema)
files = sys.argv[1:] or sorted(glob.glob('assets/fiqh/parts/*.json'))
bad = 0
for f in files:
    data = json.load(io.open(f, encoding='utf-8'))
    ids = [r.get('id') for r in data]
    dup = {i for i in ids if ids.count(i) > 1}
    if dup: print(f, 'DUPLICATE ids:', dup); bad += 1
    for r in data:
        errs = sorted(v.iter_errors(r), key=lambda e: e.path)
        for e in errs:
            bad += 1
            print(f"{f} [{r.get('id')}] {'/'.join(map(str,e.path))}: {e.message[:160]}")
    print(f, len(data), 'rules', 'OK' if not errs and not dup else '')
sys.exit(1 if bad else 0)
