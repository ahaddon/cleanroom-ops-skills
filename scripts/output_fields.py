#!/usr/bin/env python3
"""Print the output dimensions and measures of a question SQL as JSON.

Usage: scripts/output_fields.py <question.submit.sql>

Reads the final SELECT, so the declared output fields (what the UI's Extract Output Fields
button produces) always match the SQL, including the user's cuts. Never list them from memory.

Output: {"dimensions": [{"name", "type"}], "measures": [{"name", "type"}]}
Types: total_exposures is the one measure (LONG); min_exposure_date / max_exposure_date are DATE
dimensions (dates are always dimensions); every other column is a STRING dimension.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

MEASURES = {"total_exposures": "LONG"}
DATE_DIMS = {"min_exposure_date", "max_exposure_date"}


def strip_comments(sql: str) -> str:
    sql = re.sub(r"/\*(?!\+).*?\*/", " ", sql, flags=re.S)
    return re.sub(r"--[^\n]*", " ", sql)


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    sql = strip_comments(Path(sys.argv[1]).read_text())
    m = re.search(r"SELECT /\*\+[^*]*\*/(.*?)\bFROM unioned_exposures u\b", sql, re.S)
    if not m:
        print("FAIL: final SELECT not found")
        return 1
    dims, measures = [], []
    for raw in m.group(1).split("\n"):
        line = raw.strip().rstrip(",").strip()
        if not line:
            continue
        am = re.search(r"\bAS\s+([A-Za-z_][A-Za-z0-9_]*)\s*$", line)
        name = am.group(1) if am else line.split(".")[-1]
        if name in MEASURES:
            measures.append({"name": name, "type": MEASURES[name]})
        else:
            dims.append({"name": name, "type": "DATE" if name in DATE_DIMS else "STRING"})
    json.dump({"dimensions": dims, "measures": measures}, sys.stdout, indent=2)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
