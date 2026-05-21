#!/usr/bin/env python3
"""
Rebuild FocusPause/*.lproj/Localizable.strings from en using deep-translator batch API.
Usage: ./scripts/batch_localize.py fr ja ko ru
"""
from __future__ import annotations

import re
import sys
import time
from pathlib import Path

from deep_translator import GoogleTranslator

ROOT = Path(__file__).resolve().parents[1]
EN_PATH = ROOT / "FocusPause/en.lproj/Localizable.strings"


def unescape(raw: str) -> str:
    out: list[str] = []
    i = 0
    while i < len(raw):
        if raw[i] == "\\" and i + 1 < len(raw):
            c = raw[i + 1]
            if c == "n":
                out.append("\n")
                i += 2
            elif c == "t":
                out.append("\t")
                i += 2
            elif c in '"\\':
                out.append(c)
                i += 2
            else:
                out.append(raw[i])
                i += 1
        else:
            out.append(raw[i])
            i += 1
    return "".join(out)


def escape(raw: str) -> str:
    return raw.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")


def load_ordered_pairs(text: str) -> list[tuple[str, str]]:
    pairs: list[tuple[str, str]] = []
    for line in text.splitlines():
        m = re.match(r'^"((?:[^\\"]|\\.)*)"\s*=\s*"((?:[^\\"]|\\.)*)"\s*;\s*$', line.strip())
        if not m:
            continue
        pairs.append((unescape(m.group(1)), unescape(m.group(2))))
    return pairs


def translate_values(values: list[str], target: str, chunk: int = 16) -> list[str]:
    tr = GoogleTranslator(source="en", target=target)
    out: list[str] = []
    for i in range(0, len(values), chunk):
        part = values[i : i + chunk]
        for attempt in range(4):
            try:
                batch = tr.translate_batch(part)
                if len(batch) != len(part):
                    raise RuntimeError(f"batch len {len(batch)} != {len(part)}")
                out.extend(batch)
                break
            except Exception as e:
                wait = 2 ** attempt
                print(f"retry chunk {i//chunk} {target} after error {e!r}, sleep {wait}s", flush=True)
                time.sleep(wait)
        else:
            print(f"chunk failed, copying English for indices {i}-{i+len(part)}", flush=True)
            out.extend(part)
        time.sleep(0.35)
    return out


def rebuild_file(target: str) -> None:
    text = EN_PATH.read_text(encoding="utf-8")
    pairs = load_ordered_pairs(text)
    keys = [k for k, _ in pairs]
    vals_en = [v for _, v in pairs]
    print(f"{target}: translating {len(vals_en)} strings…", flush=True)
    vals_tr = translate_values(vals_en, target)
    mapping = dict(zip(keys, vals_tr))

    out_lines: list[str] = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("/*") or stripped.startswith("//"):
            out_lines.append(line)
            continue
        if stripped == "":
            out_lines.append("")
            continue
        m = re.match(r'^"((?:[^\\"]|\\.)*)"\s*=\s*"((?:[^\\"]|\\.)*)"\s*;\s*$', stripped)
        if not m:
            continue
        k = unescape(m.group(1))
        v = mapping.get(k)
        if v is None:
            continue
        out_lines.append(f'"{escape(k)}" = "{escape(v)}";')

    folder = {"es": "es", "fr": "fr", "ja": "ja", "ko": "ko", "ru": "ru"}[target]
    dest = ROOT / "FocusPause" / f"{folder}.lproj" / "Localizable.strings"
    dest.write_text("\n".join(out_lines) + "\n", encoding="utf-8")
    print(f"wrote {dest}", flush=True)


def main() -> None:
    targets = [t.strip() for t in sys.argv[1:] if t.strip()]
    if not targets:
        print("usage: batch_localize.py <lang> …", file=sys.stderr)
        sys.exit(2)
    for t in targets:
        rebuild_file(t)


if __name__ == "__main__":
    main()
