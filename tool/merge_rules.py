"""يدمج assets/fiqh/parts/*.json في assets/fiqh/rules.json ويبني docs/fiqh/trace-matrix.md.

التشغيل من جذر المشروع:  python tool/merge_rules.py
"""
import glob
import io
import json
import re
import sys
from collections import Counter

from jsonschema import Draft202012Validator

SCHEMA = json.load(io.open("assets/fiqh/rules.schema.json", encoding="utf-8"))

SOURCES = {
    "MNHJ": {"title": "منهاج الصالحين ج١ (العبادات)", "marja": "sistani", "edition": "الطبعة المصححة ١٤٤٥هـ", "urlPattern": "https://www.sistani.org/arabic/book/23720/{chapter}/"},
    "JAMI": {"title": "توضیح المسائل جامع ج١", "marja": "sistani", "edition": "چاپ ١٤٠٣", "urlPattern": "https://www.sistani.org/persian/book/26575/{chapter}/"},
    "QA": {"title": "استفتاءات موقع السيستاني (عربي)", "marja": "sistani", "urlPattern": "https://www.sistani.org/arabic/qa/{n}/"},
    "ZANJ_R": {"title": "المسائل الشرعية — الزنجاني (ملف مصحح)", "marja": "zanjani", "note": "الإحالة بالعنوان والصفحة؛ الترقيم في الملف مضطرب"},
    "ZANJ_Q": {"title": "استفتاءات الزنجاني (القسم الفارسي)", "marja": "zanjani"},
    "ZANJ_QA": {"title": "استفتاءات الزنجاني (القسم العربي)", "marja": "zanjani"},
    "WAHD_M": {"title": "منهاج الصالحين ج٢ بهوامش الوحيد (متن الخوئي)", "marja": "wahid", "note": "«بلا هامش» = متن الخوئي مقرَّرًا على فتوى الوحيد"},
    "WAHD_Q": {"title": "استفتاءات الوحيد الخراساني", "marja": "wahid"},
    "MNTKH": {"title": "المسائل المنتخبة", "marja": "sistani", "urlPattern": "https://www.sistani.org/arabic/book/13/{chapter}/", "note": "قُرئ في تدقيق 10-audit؛ عند التعارض يُقدَّم المنهاج ١٤٤٥"},
    "BANOVAN": {"title": "آموزش احکام بانوان (فارسي مبسّط)", "marja": "sistani", "urlPattern": "https://www.sistani.org/persian/book/25936/{chapter}/", "note": "لا يُعتمد مصدرًا منفردًا لقاعدة؛ للتوثيق وصياغة نصوص الواجهة"},
    "COMPOSITE": {"title": "مركّب من سجلات أخرى في الاستخراج (مخرج وحدة)", "marja": "sistani", "note": "ليس مصدرًا أصليًا؛ issue يذكر السجلات المركَّب منها"},
}

ORDER = ["H0", "H1", "H2", "H3", "H4", "H5", "H6", "H7", "H8", "H9", "I1", "I2", "I3", "I", "N1", "N2", "N3", "N", "M", "C", "T"]


def unit_key(rule):
    u = rule["unit"]
    m = re.match(r"^(H[0-9]|I[0-9]?|N[0-9]?|M|C|T)-(\d+)([a-z]?)$", rule["id"])
    return (ORDER.index(u) if u in ORDER else 99, int(m.group(2)), m.group(3))


def main():
    parts = sorted(glob.glob("assets/fiqh/parts/*.json"))
    if not parts:
        print("no parts found", file=sys.stderr)
        return 1
    rules = []
    for p in parts:
        rules.extend(json.load(io.open(p, encoding="utf-8")))
    rules.sort(key=unit_key)

    dup = [k for k, c in Counter(r["id"] for r in rules).items() if c > 1]
    if dup:
        print("DUPLICATE ids:", dup, file=sys.stderr)
        return 1

    unknown_src = sorted({s["src"] for r in rules for s in r["sources"] if s["src"] not in SOURCES}
                         | {s["src"] for r in rules for a in r["alternatives"] for s in a.get("sources", []) if s["src"] not in SOURCES})
    if unknown_src:
        print("UNKNOWN source codes:", unknown_src, file=sys.stderr)
        return 1

    # قرار المالك (٢٠٢٦/١٠/٠١): الاحتياطات الاستحبابية لا تدخل البرنامج الآن؛ تُحفظ في ملف مؤجَّل.
    all_rules = rules
    deferred = [r for r in all_rules if r["classification"] == "ihtiyat_istihbabi"]
    rules = [r for r in all_rules if r["classification"] != "ihtiyat_istihbabi"]
    io.open("assets/fiqh/deferred-istihbabi.json", "w", encoding="utf-8", newline="\n").write(
        json.dumps({"note": "احتياطات استحبابية مؤجَّلة بقرار المالك ٢٠٢٦/١٠/٠١؛ ليست في rules.json ولا يقرؤها المحرك",
                    "rules": deferred}, ensure_ascii=False, indent=2) + "\n")

    doc = {
        "version": "0.1.0",
        "generated": "2026-10-01",
        "marja": "sistani",
        "sources": SOURCES,
        "rules": rules,
    }
    errors = list(Draft202012Validator(SCHEMA).iter_errors(doc))
    for e in errors[:50]:
        print("/".join(map(str, e.path)), e.message[:200], file=sys.stderr)
    if errors:
        return 1

    io.open("assets/fiqh/rules.json", "w", encoding="utf-8", newline="\n").write(
        json.dumps(doc, ensure_ascii=False, indent=2) + "\n")

    # مصفوفة التتبع: من ملفات الاستخراج مباشرة، فلا يفوت سجل
    headings = []
    for f in sorted(glob.glob("docs/fiqh/extraction/0[1-8]-*.md")):
        for line in io.open(f, encoding="utf-8"):
            m = re.match(r"^### \[([A-Z0-9]+-\d+)\]\s*(.*)$", line)
            if m:
                headings.append((f.split("/")[-1], m.group(1), m.group(2).strip()))
    by_base = {}
    for r in all_rules:
        base = re.sub(r"[a-z]$", "", r["id"])
        by_base.setdefault(base, []).append(r)

    cls = Counter(r["classification"] for r in rules)
    kinds = Counter(r["kind"] for r in rules)
    missing = [h for h in headings if h[1] not in by_base]
    extra = sorted(set(by_base) - {h[1] for h in headings})

    out = ["# مصفوفة التتبع — الاستخراج ↔ `rules.json`", "",
           f"مولَّد آليًا بـ `tool/merge_rules.py` في ٢٠٢٦/١٠/٠١. سجلات الاستخراج: {len(headings)}. عناصر القواعد: {len(rules)}.", "",
           "| الملف | السجل | العنوان | العناصر | kind | التصنيف | احتياط رقم | ✅ |", "|---|---|---|---|---|---|---|---|"]
    for f, rid, title in headings:
        rs = by_base.get(rid, [])
        out.append("| %s | %s | %s | %s | %s | %s | %s | %s |" % (
            f, rid, title,
            "، ".join(r["id"] for r in rs) or "**مفقود**",
            "، ".join(sorted({r["kind"] for r in rs})),
            "، ".join(sorted({r["classification"] for r in rs})),
            "، ".join(str(r["ihtiyatRegistryNo"]) for r in rs if r["ihtiyatRegistryNo"] is not None),
            ("✅" if rs and all(r["verified"] for r in rs) else ("⚠️" if rs else ""))
            + (" (مؤجَّل: " + "، ".join(r["id"] for r in rs if r["classification"] == "ihtiyat_istihbabi") + ")"
               if any(r["classification"] == "ihtiyat_istihbabi" for r in rs) else "")))
    out += ["", "## الإحصاء", "",
            "| البند | العدد |", "|---|---|",
            f"| سجلات الاستخراج | {len(headings)} |",
            f"| عناصر القواعد في rules.json | {len(rules)} |",
            f"| احتياطات استحبابية مؤجَّلة (deferred-istihbabi.json) | {len(deferred)} |",
            f"| سجلات بلا عنصر | {len(missing)} |",
            f"| عناصر بلا سجل | {len(extra)} |"]
    out += [f"| kind = {k} | {v} |" for k, v in sorted(kinds.items())]
    out += [f"| التصنيف = {k} | {v} |" for k, v in sorted(cls.items())]
    if missing:
        out += ["", "## سجلات بلا عنصر", ""] + [f"- {f} {rid} {t}" for f, rid, t in missing]
    if extra:
        out += ["", "## عناصر بلا سجل", ""] + [f"- {x}" for x in extra]
    io.open("docs/fiqh/trace-matrix.md", "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")

    print(f"deferred istihbabi: {len(deferred)}")
    print(f"rules.json: {len(rules)} rules; headings: {len(headings)}; missing: {len(missing)}; extra: {len(extra)}")
    print("kinds:", dict(kinds))
    print("classification:", dict(cls))
    return 0 if not missing and not extra else 2


if __name__ == "__main__":
    sys.exit(main())
