#!/usr/bin/env python3
"""Generate emojis.json for wessel.better-emojis.

Sources (fetched at run time, cached in /tmp):
  - unicode.org emoji-test.txt   : canonical ordering, groups/subgroups
  - CLDR annotations en.xml      : names + keywords per emoji
  - CLDR annotationsDerived.xml  : extra keywords for ZWJ sequences

Output entry shape:
  {"e": "<emoji>", "k": "<name> keyword1 keyword2 ...", "c": "<category>", "t": true, "v": [...]}

`t` marks emojis that accept a single skin-tone modifier (U+1F3FB..U+1F3FF).
Tone-variant rows themselves are dropped from the grid; they are reached via
the plugin's skin-tone selector instead.
"""

import sys
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

CACHE = Path("/tmp/opencode/emoji")
OUT = Path(__file__).resolve().parent.parent / "emojis.json"

CLDR_TAG = "release-48"

SOURCES = {
    "emoji-test.txt": "https://www.unicode.org/Public/emoji/latest/emoji-test.txt",
    "annotations-en.xml": f"https://raw.githubusercontent.com/unicode-org/cldr/{CLDR_TAG}/common/annotations/en.xml",
    "annotationsDerived-en.xml": f"https://raw.githubusercontent.com/unicode-org/cldr/{CLDR_TAG}/common/annotationsDerived/en.xml",
}

MODIFIERS = [chr(c) for c in range(0x1F3FB, 0x1F400)]
GENDER_MARKERS = {chr(0x1F468): "gm", chr(0x1F469): "gf", chr(0x1F9D1): "gp"}
GENDER_SIGN_MARKERS = {chr(0x2640): "gf", chr(0x2642): "gm"}
SPECIAL_GENDER_GROUPS = [
    {"gp": "\U0001fac4", "gf": "\U0001f930", "gm": "\U0001fac3"},
    {"gp": "\U0001f9d1\u200d\U0001f384", "gf": "\U0001f936", "gm": "\U0001f385"},
    {"gp": "\U0001fac5", "gf": "\U0001f478", "gm": "\U0001f934"},
    {
        "gp": "\U0001f48f",
        "gf": "\U0001f469\u200d\u2764\ufe0f\u200d\U0001f48b\u200d\U0001f469",
        "gm": "\U0001f468\u200d\u2764\ufe0f\u200d\U0001f48b\u200d\U0001f468",
        "extra": ["\U0001f469\u200d\u2764\ufe0f\u200d\U0001f48b\u200d\U0001f468"],
    },
]


def fetch(name: str) -> str:
    path = CACHE / name
    if not path.exists():
        print(f"downloading {name} ...")
        path.parent.mkdir(parents=True, exist_ok=True)
        req = urllib.request.Request(SOURCES[name], headers={"User-Agent": "curl/8"})
        path.write_bytes(urllib.request.urlopen(req, timeout=60).read())
    return path.read_text(encoding="utf-8")


def parse_codepoints(cps: str) -> tuple:
    return tuple(chr(int(cp, 16)) for cp in cps.strip().split())


def parse_test_file(raw: str):
    """Return ordered [(emoji_tuple, group)], plus the fully-qualified set."""
    entries, group = [], None
    for line in raw.splitlines():
        line = line.rstrip()
        if line.startswith("# group:"):
            group = line.split(":", 1)[1].strip()
            continue
        if not line or line.startswith("#"):
            continue
        body, _, comment = line.partition("#")
        status = body.split(";")[1].strip()
        if status != "fully-qualified":
            continue
        emoji = parse_codepoints(body.split(";")[0])
        entries.append((emoji, group))
    return entries


def canonical_key(seq: tuple) -> tuple:
    return tuple(ch for ch in seq if ch not in MODIFIERS and ch != "\ufe0f")


def gender_member(seq: tuple):
    """Return (group key, member role, base) for a gendered emoji."""
    if any(ch in MODIFIERS for ch in seq):
        return None
    canonical = canonical_key(seq)
    person_markers = [ch for ch in canonical if ch in GENDER_MARKERS]
    if len(person_markers) == 1 and not any(ch in GENDER_SIGN_MARKERS for ch in canonical):
        marker = person_markers[0]
        return (
            tuple("{gender}" if ch == marker else ch for ch in canonical),
            GENDER_MARKERS[marker],
            None,
        )

    sign_markers = [ch for ch in canonical if ch in GENDER_SIGN_MARKERS]
    if len(sign_markers) != 1 or len(canonical) < 2:
        return None
    marker_index = canonical.index(sign_markers[0])
    if marker_index == 0 or canonical[marker_index - 1] != "\u200d":
        return None
    marker = sign_markers[0]
    group_key = tuple(
        "{gender}" if ch == marker else ch for ch in canonical
    )
    base = canonical[:marker_index - 1] + canonical[marker_index + 1:]
    return (
        group_key,
        GENDER_SIGN_MARKERS[marker],
        base,
    )


def parse_annotations(path: str):
    """Return {emoji_string: (tts_name, [keywords])}."""
    root = ET.fromstring(fetch(path))
    out = {}
    for ann in root.iter("annotation"):
        cp = ann.get("cp")
        if not cp:
            continue
        text = (ann.text or "").strip()
        if ann.get("type") == "tts":
            # <annotation cp="X" type="tts">proper name</annotation>
            entry = out.get(cp)
            if entry is None:
                out[cp] = [text, []]
            elif not entry[0]:
                entry[0] = text
        else:
            words = [w.strip() for w in text.split("|") if w.strip()]
            entry = out.get(cp)
            if entry is None:
                out[cp] = ["", words]
            else:
                entry[1].extend(words)
    return {cp: (v[0], v[1]) for cp, v in out.items()}


def lookup(annotations, text):
    """Exact match first, else VS16-stripped (CLDR keys omit U+FE0F)."""
    hit = annotations.get(text)
    if hit is None:
        hit = annotations.get(text.replace("\ufe0f", ""))
    return hit or ("", [])


def build_keywords(name: str, words: list) -> str:
    seen, parts = set(), []
    for token in ([name] if name else []) + words:
        token = " ".join(token.lower().split())
        if token and token not in seen:
            seen.add(token)
            parts.append(token)
    return " ".join(parts)


def main() -> int:
    entries = parse_test_file(fetch("emoji-test.txt"))
    variants = {}
    for seq, _ in entries:
        modifiers = {ch for ch in seq if ch in MODIFIERS}
        if len(modifiers) != 1:
            continue
        modifier = modifiers.pop()
        variants.setdefault(canonical_key(seq), {})[
            MODIFIERS.index(modifier) + 1
        ] = "".join(seq)
    gender_groups = {}
    gender_group_for = {}
    for seq, _ in entries:
        member = gender_member(seq)
        if member is None:
            continue
        key, role, base = member
        group = gender_groups.setdefault(key, {})
        text = "".join(seq)
        group[role] = text
        gender_group_for[text] = key
        gender_group_for["".join(canonical_key(seq))] = key
        if base is not None:
            base_text = "".join(base)
            group["gp"] = base_text
            gender_group_for[base_text] = key
    gender_groups = {
        key: value for key, value in gender_groups.items()
        if len(value) >= 2
    }
    gender_group_for = {
        text: key for text, key in gender_group_for.items() if key in gender_groups
    }
    for index, special in enumerate(SPECIAL_GENDER_GROUPS):
        if not all(any("".join(seq) == special[role] for seq, _ in entries) for role in ("gp", "gf", "gm")):
            continue
        key = ("{special-gender}", str(index))
        gender_groups[key] = {role: special[role] for role in ("gp", "gf", "gm")}
        for role in ("gp", "gf", "gm"):
            gender_group_for[special[role]] = key
        for text in special.get("extra", []):
            gender_group_for[text] = key
    ann = parse_annotations("annotations-en.xml")
    derived = parse_annotations("annotationsDerived-en.xml")

    out, skipped_variants, missing_kw = [], 0, 0
    for seq, group in entries:
        text = "".join(seq)
        if any(ch in MODIFIERS for ch in seq):
            skipped_variants += 1
            continue

        name, words = lookup(ann, text)
        dname, dwords = lookup(derived, text)
        name = name or dname
        merged = list(dict.fromkeys(words + dwords))
        if not name and not merged:
            missing_kw += 1
        k = build_keywords(name, merged)
        if not k:
            k = " ".join(f"u+{ord(ch):x}" for ch in seq)

        item = {"e": text, "k": k, "c": group or "Symbols"}
        if name:
            item["n"] = name
        exact_variants = variants.get(canonical_key(seq), {})
        if all(tone in exact_variants for tone in range(1, 6)):
            item["t"] = True
            item["v"] = [exact_variants[tone] for tone in range(1, 6)]
        gkey = gender_group_for.get(text) or gender_group_for.get("".join(canonical_key(seq)))
        if gkey in gender_groups:
            group_members = gender_groups[gkey]
            item["gg"] = "".join(gkey)
            if "gp" in group_members:
                item["gp"] = group_members["gp"]
            if "gf" in group_members:
                item["gf"] = group_members["gf"]
            if "gm" in group_members:
                item["gm"] = group_members["gm"]
        out.append(item)

    OUT.write_text(json_dumps(out), encoding="utf-8")
    cats = {}
    for item in out:
        cats[item["c"]] = cats.get(item["c"], 0) + 1
    print(f"wrote {OUT} ({OUT.stat().st_size // 1024} KB)")
    print(f"emojis: {len(out)}  tone-variants skipped: {skipped_variants}  no-keywords: {missing_kw}")
    for cat, n in cats.items():
        print(f"  {cat}: {n}")
    return 0


def json_dumps(items) -> str:
    import json

    return json.dumps(items, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    sys.exit(main())
