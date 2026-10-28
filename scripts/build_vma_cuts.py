#!/usr/bin/env python3
"""Generate the VMA cuts of a question SQL from a cuts spec.

Usage: scripts/build_vma_cuts.py <in.sql> <out.sql> <cuts.json>

cuts.json:
{
  "standard": ["campaign", "creative"],        # optional standard cuts: campaign, subbrand, creative
  "levels":   {"creative": "creative"},        # optional per-cut join level: property (default) | creative
  "custom": [                                   # up to 7, named by the user
    {"name": "media_type", "slot": 1, "level": "property"}
  ]
}

channel, property and publisher are ALWAYS included (property level, not changeable).
Standard cuts come out in PRD order (campaign, channel, property, publisher, subbrand,
creative), then custom cuts in slot order. Standard `creative` defaults to the creative
level, every other cut to the property level.

Rewrites only: the cut lines inside PivotedCuts, the cut columns of the final SELECT, the
BROADCAST hint and the vma_cr join (kept only when some cut reads from it). Nothing else in
the SQL changes. Exits 1 without writing on any bad value or if the template text drifted.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

STANDARD_ORDER = ["campaign", "channel", "property", "publisher", "subbrand", "creative"]
MANDATORY = ["channel", "property", "publisher"]
OPTIONAL = ["campaign", "subbrand", "creative"]
LEVELS = ("property", "creative")
JOIN_ALIAS = {"property": "vma_prop", "creative": "vma_cr"}
RESERVED = {
    "exposure_source", "creative_source_id", "property_source_id", "publisher_id", "campaign_id",
    "creative_name", "placement_name", "campaign_name", "total_exposures", "min_exposure_date",
    "max_exposure_date", "run_id", "is_deleted", "map_id", "exposures", "min_date", "max_date",
} | set(STANDARD_ORDER)
NAME_RE = re.compile(r"^[a-z][a-z0-9_]*$")


def fail(msg: str) -> int:
    print(f"FAIL: {msg}")
    return 1


def normalize_name(raw: str) -> str:
    return re.sub(r"_+", "_", re.sub(r"[^a-z0-9]+", "_", str(raw).strip().lower())).strip("_")


def build_cuts(spec: dict) -> list[dict]:
    """Return ordered cuts: {cut_name, alias, level}. Raises ValueError on a bad spec."""
    levels_in = spec.get("levels") or {}
    std = set(spec.get("standard") or []) | set(MANDATORY)
    bad = std - set(STANDARD_ORDER)
    if bad:
        raise ValueError(f"unknown standard cut(s) {sorted(bad)}; allowed: {STANDARD_ORDER}")
    for k, v in levels_in.items():
        if k in MANDATORY:
            raise ValueError(f"'{k}' is always property level and cannot be changed")
        if k not in OPTIONAL:
            raise ValueError(f"levels: unknown cut '{k}' (custom cut levels go in the custom entry)")
        if v not in LEVELS:
            raise ValueError(f"levels.{k} must be one of {LEVELS}")
    cuts = []
    for c in STANDARD_ORDER:
        if c in std:
            default = "creative" if c == "creative" else "property"
            cuts.append({"cut_name": c, "alias": c, "level": levels_in.get(c, default)})
    custom = spec.get("custom") or []
    if len(custom) > 7:
        raise ValueError("at most 7 custom cuts are allowed")
    slots, aliases = set(), {c["alias"] for c in cuts}
    for i, item in enumerate(sorted(custom, key=lambda x: int(x.get("slot", 0)))):
        try:
            slot = int(item["slot"])
        except (KeyError, TypeError, ValueError):
            raise ValueError(f"custom[{i}] needs an integer slot 1-7") from None
        if not 1 <= slot <= 7:
            raise ValueError(f"custom cut slot {slot} is out of range (1-7)")
        if slot in slots:
            raise ValueError(f"custom cut slot {slot} is used twice")
        slots.add(slot)
        name = normalize_name(item.get("name", ""))
        if not NAME_RE.match(name):
            raise ValueError(f"custom cut name '{item.get('name')}' cannot be turned into a column name")
        if name in RESERVED or name in aliases:
            raise ValueError(f"custom cut name '{name}' is reserved or already used")
        level = item.get("level", "property")
        if level not in LEVELS:
            raise ValueError(f"custom cut '{name}': level must be one of {LEVELS}")
        aliases.add(name)
        cuts.append({"cut_name": f"custom_cut_{slot}", "alias": name, "level": level})
    return cuts


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__)
        return 2
    src, dst, spec_path = map(Path, sys.argv[1:4])
    try:
        cuts = build_cuts(json.loads(spec_path.read_text()))
    except (ValueError, json.JSONDecodeError) as e:
        return fail(str(e))
    sql = src.read_text()

    pivot_re = re.compile(r"(PivotedCuts AS \(\s*SELECT\s*map_id,\s*\n)(.*?)(\n\s*FROM @vma)", re.S)
    if not pivot_re.search(sql):
        return fail("could not find the PivotedCuts cut lines; template changed?")
    pivot_lines = ",\n".join(
        f"        MAX(CASE WHEN cut_name = '{c['cut_name']}' THEN map_name END) AS {c['alias']}" for c in cuts
    )
    sql = pivot_re.sub(lambda m: m.group(1) + pivot_lines + m.group(3), sql, count=1)

    final_re = re.compile(
        r"(SELECT /\*\+ BROADCAST\()[^)]*(\) \*/.*?MAX\(u\.max_date\) AS max_exposure_date,\n)(.*?)"
        r"(\nFROM unioned_exposures u\n)(.*?)(GROUP BY 1, 2, 3, 4, 5, 6, 7, 8\s*)\Z",
        re.S,
    )
    m = final_re.search(sql)
    if not m:
        return fail("could not find the final SELECT / joins; template changed?")
    used = []
    for c in cuts:
        if JOIN_ALIAS[c["level"]] not in used:
            used.append(JOIN_ALIAS[c["level"]])
    if "vma_prop" not in used:
        used.insert(0, "vma_prop")
    select_lines = ",\n".join(f"    ANY_VALUE({JOIN_ALIAS[c['level']]}.{c['alias']}) AS {c['alias']}" for c in cuts)
    joins = "LEFT JOIN PivotedCuts vma_prop ON u.property_source_id = vma_prop.map_id\n"
    if "vma_cr" in used:
        joins += "LEFT JOIN PivotedCuts vma_cr ON u.vma_creative_join_key = vma_cr.map_id\n"
    new_final = (
        m.group(1) + ", ".join(sorted(used, key=lambda a: ["vma_prop", "vma_cr"].index(a))) + m.group(2)
        + select_lines + m.group(4) + joins + m.group(6)
    )
    sql = sql[: m.start()] + new_final
    dst.write_text(sql if sql.endswith("\n") else sql + "\n")
    cols = ", ".join(f"{c['alias']}({'cr' if c['level'] == 'creative' else 'prop'})" for c in cuts)
    print(f"wrote {dst}: cuts {cols}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
