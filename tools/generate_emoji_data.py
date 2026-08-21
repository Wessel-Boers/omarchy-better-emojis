#!/usr/bin/env python3
"""Generate emojis.json for wessel.better-emojis.

Sources (fetched at run time, cached in /tmp):
  - unicode.org emoji-test.txt   : canonical ordering, groups/subgroups
  - CLDR annotations en.xml      : names + keywords per emoji
  - CLDR annotationsDerived.xml  : extra keywords for ZWJ sequences

Output entry shape:
  {"e": "<emoji>", "k": "<name> keyword1 keyword2 ...", "c": "<category>", "t": true}

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


def strip_modifiers(seq: tuple) -> tuple:
    return tuple(ch for ch in seq if ch not in MODIFIERS)


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
    qualified = {seq for seq, _ in entries}
    primary = {strip_modifiers(seq) for seq in qualified}
    ann = parse_annotations("annotations-en.xml")
    derived = parse_annotations("annotationsDerived-en.xml")

    out, skipped_variants, missing_kw = [], 0, 0
    for seq, group in entries:
        norm = strip_modifiers(seq)
        text = "".join(seq)
        # Drop bare modifiers and any row that is just a toned form of another row.
        if norm != seq and norm in qualified:
            skipped_variants += 1
            continue
        if norm != seq and norm not in qualified:
            # Toned ZWJ sequence without an untoned twin: keep it, but it must
            # not be reachable through the tone selector twice — mark no tone.
            pass
        if all(ch in MODIFIERS for ch in seq):
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
        if seq in primary and any(
            seq + (m,) in qualified for m in MODIFIERS
        ):
            item["t"] = True
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
