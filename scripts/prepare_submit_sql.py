#!/usr/bin/env python3
"""Write a submit-ready copy of a question SQL: all comments removed, except /*+ hints.

The clean-room server parses @macros inside comments, so commented-out source blocks
(digital_mapping, uber, the VMA partition filter) make question creation fail.

Usage: scripts/prepare_submit_sql.py <in.sql> <out.sql>
"""
from __future__ import annotations

import re
import sys
from pathlib import Path


def strip(sql: str) -> str:
    sql = re.sub(r"/\*(?!\+).*?\*/", "", sql, flags=re.S)
    sql = re.sub(r"--[^\n]*", "", sql)
    lines = [ln.rstrip() for ln in sql.splitlines()]
    out, blank = [], False
    for ln in lines:
        if not ln.strip():
            if not blank:
                out.append("")
            blank = True
        else:
            out.append(ln)
            blank = False
    return "\n".join(out).strip() + "\n"


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    Path(sys.argv[2]).write_text(strip(Path(sys.argv[1]).read_text()))
