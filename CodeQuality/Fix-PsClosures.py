#!/usr/bin/env python3
"""
Walk .ps1 files and add .GetNewClosure() to scriptblocks passed to .Add_Xxx(...)
event-handler methods. Uses a proper brace counter to find the matching '})'.

Only edits forms like:
    $ctrl.Add_Something({ ... })
into:
    $ctrl.Add_Something({ ... }.GetNewClosure())

Idempotent: if the block already ends with '}.GetNewClosure())', skip.
"""
import re
import sys
from pathlib import Path

ADD_CALL = re.compile(r'\.Add_[A-Za-z]+\(\s*\{')


def find_matching_brace(text, start):
    """Given text[start] == '{', return index of matching '}'.
    Tracks string/char literals and here-strings minimally."""
    depth = 1
    i = start + 1
    n = len(text)
    in_dq = False
    in_sq = False
    in_hd = False  # heredoc @" ... "@
    in_hs = False  # heredoc @' ... '@
    while i < n:
        c = text[i]
        if in_hd:
            if c == '"' and i + 1 < n and text[i + 1] == '@':
                in_hd = False
                i += 2
                continue
            i += 1
            continue
        if in_hs:
            if c == "'" and i + 1 < n and text[i + 1] == '@':
                in_hs = False
                i += 2
                continue
            i += 1
            continue
        if in_dq:
            if c == '`' and i + 1 < n:
                i += 2
                continue
            if c == '"':
                in_dq = False
            i += 1
            continue
        if in_sq:
            # PS single quotes: '' means literal quote
            if c == "'" and i + 1 < n and text[i + 1] == "'":
                i += 2
                continue
            if c == "'":
                in_sq = False
            i += 1
            continue
        # Not in any quote
        if c == '@' and i + 1 < n:
            nx = text[i + 1]
            if nx == '"':
                in_hd = True
                i += 2
                continue
            if nx == "'":
                in_hs = True
                i += 2
                continue
        if c == '"':
            in_dq = True
            i += 1
            continue
        if c == "'":
            in_sq = True
            i += 1
            continue
        if c == '#':
            # Line comment - skip to end of line
            while i < n and text[i] != '\n':
                i += 1
            continue
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def fix_file(path: Path) -> int:
    src = path.read_text(encoding='utf-8')
    edits = []
    for m in ADD_CALL.finditer(src):
        brace_start = m.end() - 1  # position of '{'
        brace_end = find_matching_brace(src, brace_start)
        if brace_end < 0:
            continue
        # After brace_end, expect optional whitespace then ')'
        j = brace_end + 1
        while j < len(src) and src[j] in ' \t\r\n':
            j += 1
        if j >= len(src) or src[j] != ')':
            continue
        # Skip if already has .GetNewClosure()
        between = src[brace_end + 1:j]
        if '.GetNewClosure()' in between:
            continue
        # We'll insert '.GetNewClosure()' right after the '}'
        edits.append((brace_end + 1, '.GetNewClosure()'))

    if not edits:
        return 0
    # Apply edits from end to start so offsets stay valid
    edits.sort(key=lambda x: x[0], reverse=True)
    out = src
    for pos, ins in edits:
        out = out[:pos] + ins + out[pos:]
    path.write_text(out, encoding='utf-8')
    return len(edits)


def main():
    targets = []
    for p in sys.argv[1:]:
        targets.append(Path(p))
    total = 0
    for t in targets:
        if not t.exists():
            print(f"skip (missing): {t}")
            continue
        n = fix_file(t)
        print(f"{n:3d}  {t}")
        total += n
    print(f"Total edits: {total}")


if __name__ == '__main__':
    main()
