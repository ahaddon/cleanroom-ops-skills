#!/usr/bin/env python3
"""Validate run-configs/<clean_room_id>/<question_id>.json files.

Usage: scripts/check_run_configs.py [run-configs-dir]
Exit 0 = PASS. Fails on a bad shape, a file name that does not match its ids,
date-like partition keys or values (dates are asked at every run), or unknown keys.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REQUIRED = {"clean_room_id", "clean_room_name", "question_id", "question_title", "partitions", "updated_at"}
DATE_KEY = re.compile(r"(start|end|date)", re.I)
DATE_VAL = re.compile(r"^\d{4}-\d{2}-\d{2}")
UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")


def check(path: Path, root: Path) -> list[str]:
    errs = []
    try:
        d = json.loads(path.read_text())
    except Exception as e:  # noqa: BLE001
        return [f"{path}: invalid JSON ({e})"]
    if not isinstance(d, dict):
        return [f"{path}: top level must be an object"]
    missing, extra = REQUIRED - d.keys(), d.keys() - REQUIRED
    if missing:
        errs.append(f"{path}: missing keys {sorted(missing)}")
    if extra:
        errs.append(f"{path}: unknown keys {sorted(extra)} (only partition values are stored)")
    for k in ("clean_room_id", "question_id"):
        if k in d and not UUID.match(str(d[k])):
            errs.append(f"{path}: {k} is not a UUID")
    rel = path.relative_to(root).parts
    if len(rel) != 2 or rel[0] != d.get("clean_room_id") or rel[1] != f"{d.get('question_id')}.json":
        errs.append(f"{path}: must be <clean_room_id>/<question_id>.json matching its contents")
    parts = d.get("partitions", {})
    if not isinstance(parts, dict) or not all(isinstance(v, str) for v in parts.values()):
        errs.append(f"{path}: partitions must map names to string values")
    else:
        for k, v in parts.items():
            if DATE_KEY.search(k.split(".")[-1]) or DATE_VAL.match(v):
                errs.append(f"{path}: '{k}' looks like a date; dates are asked at every run, do not store them")
    return errs


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "run-configs")
    errs = []
    for f in sorted(root.rglob("*.json")):
        errs += check(f, root)
    for e in errs:
        print(f"FAIL: {e}")
    print("PASS" if not errs else "FAILED")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
