"""يولّد docs/fiqh/rules-review.md: عرض مقروء لملف rules.json لمراجعة المالك.

التشغيل من جذر المشروع:  python tool/render_rules_review.py
"""
import io
import json
import sys
from collections import OrderedDict

CLS = {
    "fatwa": "فتوى",
    "ihtiyat_wujubi": "احتياط وجوبي",
    "ishkal": "محل إشكال",
    "ihtiyat_istihbabi": "احتياط استحبابي",
    "unspecified": "⚠️ غير محدد",
}
KIND = {"rule": "حكم", "definition": "تعريف", "input": "مدخل", "info": "معلوماتي"}
MARJA = {"zanjani": "الزنجاني", "wahid": "الوحيد"}
EXIT = {True: "مخرج", False: "لا مخرج", None: "⚠️ لم يُقرأ"}


def src_line(s, sources):
    code = s["src"]
    title = sources.get(code, {}).get("title", code)
    parts = [title]
    if s.get("issue"):
        parts.append("م" + s["issue"] if code in ("MNHJ", "JAMI", "MNTKH", "WAHD_M") else s["issue"])
    if s.get("page"):
        parts.append("ص" + s["page"])
    if s.get("footnote"):
        parts.append("هـ" + s["footnote"])
    line = " ".join(parts)
    if s.get("url"):
        line = f"[{line}]({s['url']})"
    if s.get("quote"):
        line += f" — «{s['quote']}»"
    return line


def main():
    doc = json.load(io.open("assets/fiqh/rules.json", encoding="utf-8"))
    sources = doc["sources"]
    rules = doc["rules"]
    units = OrderedDict()
    for r in rules:
        units.setdefault(r["unit"], []).append(r)

    out = ["# مراجعة ملف القواعد — «يطهرن»", "",
           f"مولَّد آليًا من `assets/fiqh/rules.json` (الإصدار {doc['version']}، {doc['generated']}) بـ `tool/render_rules_review.py`. "
           f"عدد العناصر: {len(rules)}. **التعديل يكون في ملفات الاستخراج ثم الأجزاء ثم إعادة الدمج، لا هنا.**", "",
           "## كيف تراجع", "",
           "- لكل عنصر: النص الحرفي، التصنيف، قاعدة التطبيق (ما سيفعله المحرك)، البدائل، وما يحتاج نظرك (⚠️).",
           "- ما تريد تغييره: اذكر المعرّف (مثل `H7-01`) وما يُصحَّح. لا حاجة لفتح JSON.",
           "- العناصر غير المحقَّقة أو المعلَّمة ⚠️ مجموعة في آخر الملف.", "",
           "## الفهرس", ""]
    for u, rs in units.items():
        out.append(f"- **{u}**: " + "، ".join(f"`{r['id']}`" for r in rs))
    out.append("")

    flagged = []
    for u, rs in units.items():
        out += [f"## الوحدة {u}", ""]
        for r in rs:
            tag = CLS.get(r["classification"], r["classification"])
            out += [f"### {r['id']} — {r['title']}", "",
                    f"**النوع:** {KIND.get(r['kind'], r['kind'])} · **التصنيف:** {tag}"
                    + (f" · **سجل الاحتياط:** {r['ihtiyatRegistryNo']}" if r["ihtiyatRegistryNo"] is not None else "")
                    + (" · ✅ محقَّق" if r["verified"] else " · ⚠️ غير محقَّق"), ""]
            if r.get("question"):
                out += [f"**السؤال:** {r['question']}", ""]
            out += ["**النص:**", ""] + ["> " + ln if ln.strip() else ">" for ln in r["text"].split("\n")] + [""]
            out += ["**المصادر:** " + "؛ ".join(src_line(s, sources) for s in r["sources"]), ""]
            a = r["applies"]
            out += [f"**ينطبق على:** {a['subject']} · الأنواع: {'، '.join(a['womanTypes'])} · المرحلة: {a['phase']}", ""]
            out += [f"**قاعدة التطبيق:** {r['effect']}", ""]
            if r["alternatives"]:
                out += ["**البدائل:**", ""]
                for alt in r["alternatives"]:
                    srcs = "؛ ".join(src_line(s, sources) for s in alt.get("sources", []))
                    out.append(f"- **{MARJA[alt['marja']]}** ({CLS.get(alt['classification'])}، {EXIT[alt['exit']]}): {alt['ruling']}"
                               + (f" — {srcs}" if srcs else "") + (f" — {alt['note']}" if alt.get("note") else ""))
                out.append("")
            if r["unknownPolicy"]:
                out += ["**عند «لا أعلم»:**", "", "| المدخل | لا أفهم السؤال | لا أتذكر |", "|---|---|---|"]
                out += [f"| {u_['input']} | {u_['dontUnderstand']} | {u_['dontRemember']} |" for u_ in r["unknownPolicy"]]
                out.append("")
            if r["flags"]:
                out += ["**تنبيهات:**", ""] + [f"- ⚠️ {f}" for f in r["flags"]] + [""]
            if r.get("notes"):
                out += [f"**ملاحظات المرمِّز:** {r['notes']}", ""]
            if r["flags"] or not r["verified"] or r["classification"] == "unspecified":
                flagged.append(r)

    out += ["## ما يحتاج نظرك خاصة", "",
            f"{len(flagged)} عنصرًا فيه تنبيه أو غير محقَّق أو بلا تصنيف محدد:", ""]
    for r in flagged:
        why = []
        if not r["verified"]:
            why.append("غير محقَّق")
        if r["classification"] == "unspecified":
            why.append("التصنيف غير محدد")
        if r["flags"]:
            why.append(f"{len(r['flags'])} تنبيه")
        out.append(f"- `{r['id']}` {r['title']} — {'، '.join(why)}")
    out.append("")
    io.open("docs/fiqh/rules-review.md", "w", encoding="utf-8", newline="\n").write("\n".join(out))
    print(f"rules-review.md: {len(rules)} rules, {len(flagged)} flagged")
    return 0


if __name__ == "__main__":
    sys.exit(main())
