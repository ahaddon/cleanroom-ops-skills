#!/usr/bin/env python3
"""Validate a generated clean-room question SQL against the exposure-mapping template.

Usage: scripts/validate_question.py <generated.sql> [--template <template.sql>]

Exit 0 = PASS (warnings allowed), 1 = FAIL. Comments are stripped before comparing,
so toggling commented-out source blocks never trips the locked-region checks.
VMA cuts are checked by rule (generated form, mandatory channel/property/publisher), not verbatim.
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

PIVOTED_RE = re.compile(r"PivotedCuts AS \((.*?)GROUP BY map_id\s*\)", re.S)
CUT_LINE_RE = re.compile(r"MAX\(CASE WHEN cut_name = '([a-z0-9_]+)' THEN map_name END\) AS ([a-z][a-z0-9_]*)")
STANDARD_CUTS = ["campaign", "channel", "property", "publisher", "subbrand", "creative"]
MANDATORY_CUTS = {"channel", "property", "publisher"}
CUSTOM_CUT_RE = re.compile(r"^custom_cut_[1-7]$")
RESERVED_ALIASES = {
    "exposure_source", "creative_source_id", "property_source_id", "publisher_id", "campaign_id",
    "creative_name", "placement_name", "campaign_name", "total_exposures", "min_exposure_date",
    "max_exposure_date", "run_id", "is_deleted", "map_id", "exposures", "min_date", "max_date",
} | set(STANDARD_CUTS)
ALIAS_RE = re.compile(r"^[a-z][a-z0-9_]*$")
PROP_JOIN = "LEFT JOIN PivotedCuts vma_prop ON u.property_source_id = vma_prop.map_id"
CR_JOIN = "LEFT JOIN PivotedCuts vma_cr ON u.vma_creative_join_key = vma_cr.map_id"
META_FILTER = (
    "WHERE TO_DATE(TIMESTAMP_SECONDS(INT(@meta.ts))) "
    "BETWEEN '@START_DATE' AND '@END_DATE'"
)
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


def check_cuts(gen: str) -> list[str]:
    """VMA cuts: PivotedCuts holds only generated cut lines, the final SELECT agrees with it."""
    errs: list[str] = []
    m = PIVOTED_RE.search(gen)
    if not m:
        return ["LOCKED: PivotedCuts block is missing"]
    body = norm(m.group(1))
    cuts = CUT_LINE_RE.findall(body)
    skeleton = norm(CUT_LINE_RE.sub("X", body))
    if not cuts or skeleton != "SELECT map_id, " + ", ".join(["X"] * len(cuts)) + " FROM @vma":
        errs.append("LOCKED: PivotedCuts contains something other than generated cut lines (use scripts/build_vma_cuts.py)")
        return errs
    names = [c for c, _ in cuts]
    aliases = [a for _, a in cuts]
    if len(set(names)) != len(names):
        errs.append("PivotedCuts: a cut_name appears twice")
    if len(set(aliases)) != len(aliases):
        errs.append("PivotedCuts: an output column name appears twice")
    for name, alias in cuts:
        if name in STANDARD_CUTS:
            if alias != name:
                errs.append(f"PivotedCuts: standard cut '{name}' must be named '{name}', not '{alias}'")
        elif CUSTOM_CUT_RE.match(name):
            if not ALIAS_RE.match(alias) or alias in RESERVED_ALIASES:
                errs.append(f"PivotedCuts: custom cut '{name}' has a reserved or invalid column name '{alias}'")
        else:
            errs.append(f"PivotedCuts: unknown cut_name '{name}' (standard cuts or custom_cut_1..custom_cut_7)")
    missing = MANDATORY_CUTS - set(names)
    if missing:
        errs.append(f"PivotedCuts: channel, property and publisher are always required; missing {sorted(missing)}")
    if sum(1 for n in names if CUSTOM_CUT_RE.match(n)) > 7:
        errs.append("PivotedCuts: at most 7 custom cuts")

    f = re.search(r"SELECT /\*\+ BROADCAST\(([^)]*)\) \*/(.*?)\bFROM unioned_exposures u\b(.*)\Z", gen, re.S)
    if not f or "MAX(u.max_date) AS max_exposure_date," not in f.group(2):
        return errs + ["final SELECT not found or changed; cut columns cannot be checked"]
    hint = {h.strip() for h in f.group(1).split(",") if h.strip()}
    tail = f.group(2).split("MAX(u.max_date) AS max_exposure_date,", 1)[1]
    item_re = re.compile(r"ANY_VALUE\((vma_prop|vma_cr)\.([a-z][a-z0-9_]*)\) AS ([a-z][a-z0-9_]*)")
    items = item_re.findall(tail)
    if norm(item_re.sub("X", tail)).replace(" ", "") != ",".join(["X"] * len(items)):
        errs.append("LOCKED: final SELECT cut columns are not in the generated form `ANY_VALUE(vma_prop|vma_cr.col) AS col`")
    if [a for _, _, a in items] != aliases:
        errs.append("final SELECT cut columns do not match PivotedCuts (same names, same order)")
    used = set()
    for join, col, out in items:
        used.add(join)
        if col != out:
            errs.append(f"final SELECT: {join}.{col} must be aliased '{col}', not '{out}'")
        if out in MANDATORY_CUTS and join != "vma_prop":
            errs.append(f"final SELECT: '{out}' must read from the property-level join (vma_prop)")
    used.add("vma_prop")
    if hint != used:
        errs.append(f"BROADCAST hint {sorted(hint)} must list exactly the joins in use {sorted(used)}")
    rest = f.group(3)
    if PROP_JOIN not in rest:
        errs.append("LOCKED: the vma_prop join is missing or changed")
    if ("vma_cr" in used) != (CR_JOIN in rest):
        errs.append("the vma_cr join must be present exactly when a cut reads from vma_cr")
    return errs


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

    # 1. VMA cuts: generated form only (see check_cuts).
    errors.extend(check_cuts(gen))

    # 2. Locked: Meta date filter, when Meta is used.
    if "@meta" in gen and norm(META_FILTER) not in gen:
        errors.append("LOCKED: Meta @START_DATE/@END_DATE filter was modified or removed")

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
