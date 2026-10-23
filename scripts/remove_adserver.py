#!/usr/bin/env python3
"""Remove the ad server joins from the snowplow CTE of a question SQL.

Usage: scripts/remove_adserver.py <in.sql> <out.sql>

Used when the user is not using ad server data (question-inputs.md field 5 = no).
Drops both `LEFT JOIN @adserver` clauses and replaces the three ad server columns
(creative_name, placement_name, campaign_name) with typed NULLs. Everything else is
untouched. Exits 1 without writing if the expected template text is not found
(template drifted) and the SQL still references @adserver.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

JOIN_RE = re.compile(
    r"FROM @snowplow_exposures se LEFT JOIN @adserver p_ads on se\._ds_placement_id = p_ads\.placement_id\s*\n"
    r"\s*LEFT JOIN @adserver c_ads on se\._ds_ad_name = c_ads\.creative_id"
)
COLUMNS = [
    ("c_ads.creative AS creative_name", "CAST(NULL AS STRING) AS creative_name"),
    ("p_ads.placement AS placement_name", "CAST(NULL AS STRING) AS placement_name"),
    ("p_ads.campaign AS campaign_name", "CAST(NULL AS STRING) AS campaign_name"),
]


def uses_adserver(sql: str) -> bool:
    live = re.sub(r"/\*(?!\+).*?\*/", " ", sql, flags=re.S)
    live = re.sub(r"--[^\n]*", " ", live)
    return "@adserver" in live


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    sql = src.read_text()
    out, n = JOIN_RE.subn("FROM @snowplow_exposures se", sql)
    for old, new in COLUMNS:
        out = out.replace(old, new)
    if n != 1 or uses_adserver(out):
        print("FAIL: expected ad server joins not found in the snowplow CTE, or @adserver still referenced; template changed?")
        return 1
    dst.write_text(out)
    print(f"wrote {dst} (ad server joins removed)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
