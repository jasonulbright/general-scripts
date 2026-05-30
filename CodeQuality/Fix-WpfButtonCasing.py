#!/usr/bin/env python3
"""
Add Controls:ControlsHelper.ContentCharacterCasing="Normal" to every <Button
element in WPF XAML files that doesn't already have it set.

Usage:
    python Fix-WpfButtonCasing.py path\\to\\MainWindow.xaml [more.xaml ...]

Idempotent: skips buttons that already have the attribute.
"""
import re
import sys
from pathlib import Path

BUTTON_OPEN = re.compile(r'<Button\b')
CASING_ATTR = 'Controls:ControlsHelper.ContentCharacterCasing'


def find_tag_end(text, start):
    """Find the '>' that ends the opening tag starting at 'start'.
    Handles attributes with quoted values that may contain '>'."""
    i = start
    n = len(text)
    in_sq = False
    in_dq = False
    while i < n:
        c = text[i]
        if in_sq:
            if c == "'": in_sq = False
        elif in_dq:
            if c == '"': in_dq = False
        else:
            if c == "'": in_sq = True
            elif c == '"': in_dq = True
            elif c == '>':
                return i
        i += 1
    return -1


def fix(path: Path) -> int:
    src = path.read_text(encoding='utf-8')
    edits = []
    for m in BUTTON_OPEN.finditer(src):
        end = find_tag_end(src, m.end())
        if end < 0:
            continue
        tag = src[m.start():end + 1]
        if CASING_ATTR in tag:
            continue
        # Insert just after "<Button"
        insert_pos = m.end()
        edits.append((insert_pos, f' {CASING_ATTR}="Normal"'))
    if not edits:
        return 0
    edits.sort(key=lambda x: x[0], reverse=True)
    out = src
    for pos, ins in edits:
        out = out[:pos] + ins + out[pos:]
    path.write_text(out, encoding='utf-8')
    return len(edits)


def main():
    total = 0
    for p in sys.argv[1:]:
        path = Path(p)
        if not path.exists():
            print(f"skip: {path}")
            continue
        n = fix(path)
        print(f"{n:3d}  {path}")
        total += n
    print(f"Total: {total}")


if __name__ == '__main__':
    main()
