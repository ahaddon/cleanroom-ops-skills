#!/usr/bin/env python3
"""Validate a generated clean-room question SQL against the exposure-mapping template.

Usage: scripts/validate_question.py <generated.sql> [--template <template.sql>]

Exit 0 = PASS (warnings allowed), 1 = FAIL. Comments are stripped before comparing,
so toggling commented-out source blocks never trips the locked-region checks.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

DEFAULT_TEMPLATE = (
    Path(__file__).resolve().parent.parent
    / "skills/cleanroom-question-builder/references/cross-platform-exposure-mapping.sql"
)

PIVOTED_RE = re.compile(r"PivotedCuts AS \(.*?GROUP BY map_id\s*\)", re.S)
# Field 5 toggle: the bfmt_partition WHERE clause is the only part of PivotedCuts that may change.
PARTITION_RE = re.compile(r"WHERE @vma\.bfmt_partition = \(SELECT .*?\)\s*(?=GROUP BY map_id)", re.S)
META_FILTER = (
    "WHERE TO_DATE(TIMESTAMP_SECONDS(INT(@meta.ts))) "
    "BETWEEN '@START_DATE' AND '@END_DATE'"
)
FINAL_RE = re.compile(r"SELECT /\*\+ BROADCAST.*\Z", re.S)
MACRO_RE = re.compile(r"@[A-Za-z_][A-Za-z0-9_]*")


def strip_comments(sql: str) -> str:
    sql = re.sub(r"/\*(?!\+).*?\*/", " ", sql, flags=re.S)  # keep /*+ hints
    sql = re.sub(r"--[^\n]*", " ", sql)
    return sql


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def cte_names(sql: str) -> list[str]:
    return re.findall(r"(?:WITH|,)\s*([A-Za-z_][A-Za-z0-9_]*)\s+AS\s*\(", sql)


def unioned_sources(sql: str) -> list[str]:
    m = re.search(r"unioned_exposures AS \((.*?)\)\s*SELECT /\*\+", sql, re.S)
    return re.findall(r"\bFROM\s+([A-Za-z_][A-Za-z0-9_]*)", m.group(1)) if m else []


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("generated")
    ap.add_argument("--template", default=str(DEFAULT_TEMPLATE))
    ap.add_argument(
        "--submit",
        action="store_true",
        help="also require a submit-ready file: no comments except /*+ hints (the server parses @macros inside comments)",
    )
    args = ap.parse_args()

    tpl = norm(strip_comments(Path(args.template).read_text()))
    gen_raw = Path(args.generated).read_text()
    gen = norm(strip_comments(gen_raw))
    errors, warnings = [], []

    # 1. Locked: PivotedCuts must be verbatim.
    m = PIVOTED_RE.search(tpl)
    g = PIVOTED_RE.search(gen)
    if not m:
        errors.append("template is missing the PivotedCuts block (template problem)")
    elif not g or norm(m.group(0)) != norm(PARTITION_RE.sub(" ", g.group(0))):
        errors.append("LOCKED: PivotedCuts block was modified or removed")

    # 2. Locked: Meta date filter, when Meta is used.
    if "@meta" in gen and norm(META_FILTER) not in gen:
        errors.append("LOCKED: Meta @START_DATE/@END_DATE filter was modified or removed")

    # 3. Final SELECT should match the template (warning: review if changed).
    fm = FINAL_RE.search(tpl)
    if fm and norm(fm.group(0)) not in gen:
        warnings.append("final SELECT/VMA join differs from the template; confirm intentional")

    # 4. Every unioned source must be defined; every defined source should be unioned.
    ctes = set(cte_names(gen))
    unioned = unioned_sources(gen)
    if not unioned:
        errors.append("could not find unioned_exposures CTE or it has no sources")
    for s in unioned:
        if s not in ctes:
            errors.append(f"unioned_exposures references undefined source CTE '{s}'")
    infra = {"PivotedCuts", "unioned_exposures"}
    for c in sorted(ctes - infra - set(unioned)):
        warnings.append(f"source CTE '{c}' is defined but not unioned")

    # 5. Macros not present in the template (new sources are legitimate, so warn).
    tpl_macros = set(MACRO_RE.findall(tpl)) | set(
        MACRO_RE.findall(strip_comments(Path(args.template).read_text()))
    )
    for mac in sorted(set(MACRO_RE.findall(gen)) - tpl_macros):
        warnings.append(f"macro {mac} is not in the template; confirm it exists in the clean room config")

    # 5b. Submit mode: comments must be gone; list column macros that need declared fields.
    if args.submit:
        leftover = re.sub(r"/\*\+.*?\*/", " ", gen_raw, flags=re.S)
        if re.search(r"--|/\*", leftover):
            errors.append("SUBMIT: SQL still contains comments (the server reads @macros inside comments); run scripts/prepare_submit_sql.py")
        colmacros = sorted(set(re.findall(r"@([A-Za-z_][A-Za-z0-9_]*)\.@([A-Za-z_][A-Za-z0-9_]*)", gen)))
        for tbl, col in colmacros:
            warnings.append(f"column macro @{tbl}.@{col} needs '{col}' declared as a field on the '{tbl}' dataType")

    # 6. Placeholder left behind.
    if re.search(r"<[A-Z_ ]{3,}>|TODO|FIXME", gen_raw):
        errors.append("unresolved placeholder (<...>, TODO or FIXME) in SQL")

    for w in warnings:
        print(f"WARN: {w}")
    for e in errors:
        print(f"FAIL: {e}")
    print("PASS" if not errors else "FAILED")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
