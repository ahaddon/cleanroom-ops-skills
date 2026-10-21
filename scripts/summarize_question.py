#!/usr/bin/env python3
"""Summarize a submit-ready question SQL as JSON for the builder's setup summary table.

Usage: scripts/summarize_question.py <question.submit.sql>

Output: {"sources": [{"cte", "macro", "creative_key", "property_key"}], "macros": [...]}
- sources: every CTE that selects `... AS creative_source_id` and/or `... AS property_source_id`,
  with the SQL expression used for each join key (null when the CTE does not define one).
- macros: every distinct @macro (table-level, without the column part) in the SQL, in order of appearance.
Join keys are read from the SQL, never from memory, so the summary always matches what is submitted.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path


def strip_comments(sql: str) -> str:
    sql = re.sub(r"/\*(?!\+).*?\*/", " ", sql, flags=re.S)
    return re.sub(r"--[^\n]*", " ", sql)


def split_ctes(sql: str) -> list[tuple[str, str]]:
    """Return (name, body) for each top-level CTE, using paren depth."""
    m = re.match(r"\s*WITH\s+", sql, re.I)
    if not m:
        return []
    i, n, out = m.end(), len(sql), []
    while i < n:
        nm = re.match(r"\s*,?\s*([A-Za-z_][A-Za-z0-9_]*)\s+AS\s*\(", sql[i:])
        if not nm:
            break
        start = i + nm.end()
        depth, j = 1, start
        while j < n and depth:
            depth += {"(": 1, ")": -1}.get(sql[j], 0)
            j += 1
        out.append((nm.group(1), sql[start : j - 1]))
        i = j
    return out


def key_expr(body: str, alias: str) -> str | None:
    m = re.search(rf"(?:^|,|\bSELECT)\s*([^,\n]+?)\s+AS\s+{alias}\b", body, re.I)
    return re.sub(r"\s+", " ", m.group(1)).strip() if m else None


def main() -> int:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sql = strip_comments(Path(sys.argv[1]).read_text())
    sources = []
    for name, body in split_ctes(sql):
        c, p = key_expr(body, "creative_source_id"), key_expr(body, "property_source_id")
        fm = re.search(r"\bFROM\s+@([A-Za-z_][A-Za-z0-9_]*)", body)
        if (c or p) and fm:
            sources.append({"cte": name, "macro": fm.group(1), "creative_key": c, "property_key": p})
    macros = []
    for mac in re.findall(r"(?<![.\w])@([A-Za-z_][A-Za-z0-9_]*)", sql):
        if mac not in macros and not mac.isupper():
            macros.append(mac)
    print(json.dumps({"sources": sources, "macros": macros}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
