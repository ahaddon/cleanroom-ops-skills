#!/usr/bin/env python3
"""Add a custom exposure source (a platform with no built-in block, for example Snapchat) to a question SQL.

Usage: scripts/add_exposure_source.py <in.sql> <out.sql> <spec.json>

spec.json (one source per call; run again for each extra source):
{
  "name": "Snapchat",                # free text; macro, label and publisher derive from it
  "macro": "snapchat",               # optional; default = snake_case of name
  "creative_id": "ad_id",            # required dataset columns
  "property_id": "adgroup_id",       # optional; defaults to creative_id (like amazon)
  "campaign_id": "campaign_id",      # required
  "creative_name": "ad_name",        # optional (null when absent)
  "placement_name": "adgroup_name",  # optional
  "campaign_name": "campaign_name",  # optional
  "date_column": "impression_date",  # required
  "date_kind": "date",               # date | timestamp | epoch_seconds
  "date_filter": "sql"               # sql (default) | partition
}

Fills references/exposure-source-template.sql, inserts the CTE before `unioned_exposures` and a
UNION ALL branch at the end of it. Exits 1 without writing on any problem (bad value, name
collision, template drift). Everything else in the SQL is untouched.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

TEMPLATE = (
    Path(__file__).resolve().parent.parent
    / "skills/cleanroom-question-builder/references/exposure-source-template.sql"
)
IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
MACRO = re.compile(r"^[a-z][a-z0-9_]*$")
DATE_EXPR = {
    "date": "CAST(@{m}.{c} AS DATE)",
    "timestamp": "CAST(@{m}.{c} AS DATE)",
    "epoch_seconds": "TO_DATE(TIMESTAMP_SECONDS(INT(@{m}.{c})))",
}


def strip_comments(sql: str) -> str:
    sql = re.sub(r"/\*(?!\+).*?\*/", " ", sql, flags=re.S)
    return re.sub(r"--[^\n]*", " ", sql)


def fail(msg: str) -> int:
    print(f"FAIL: {msg}")
    return 1


def fragments() -> tuple[str, str]:
    text = TEMPLATE.read_text()
    m = re.search(r"^-- @@ CTE\n(.*?)^-- @@ UNION\n(.*)\Z", text, re.S | re.M)
    if not m:
        raise ValueError("exposure-source-template.sql is missing its '-- @@ CTE' / '-- @@ UNION' markers")
    return m.group(1).rstrip("\n"), m.group(2).rstrip("\n")


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__)
        return 2
    src, dst, spec_path = map(Path, sys.argv[1:4])
    spec = json.loads(spec_path.read_text())

    name = str(spec.get("name", "")).strip()
    if not name:
        return fail("spec.name is required")
    macro = spec.get("macro") or re.sub(r"_+", "_", re.sub(r"[^a-z0-9]+", "_", name.lower())).strip("_")
    if not MACRO.match(macro):
        return fail(f"macro '{macro}' must be lower-case snake_case (letters, digits, underscore; start with a letter)")

    def col(key: str, required: bool, default: str | None = None) -> str | None:
        v = spec.get(key) or default
        if not v:
            if required:
                raise ValueError(f"spec.{key} is required")
            return None
        if not IDENT.match(str(v)):
            raise ValueError(f"spec.{key} '{v}' is not a plain column name")
        return str(v)

    try:
        creative = col("creative_id", True)
        prop = col("property_id", False, creative)
        campaign = col("campaign_id", True)
        names = {k: col(k, False) for k in ("creative_name", "placement_name", "campaign_name")}
        date_col = col("date_column", True)
    except ValueError as e:
        return fail(str(e))
    kind = spec.get("date_kind")
    if kind not in DATE_EXPR:
        return fail(f"spec.date_kind must be one of {sorted(DATE_EXPR)}")
    mode = spec.get("date_filter", "sql")
    if mode not in ("sql", "partition"):
        return fail("spec.date_filter must be 'sql' or 'partition'")
    if mode == "partition" and kind == "epoch_seconds":
        return fail("an epoch_seconds column cannot be a date partition; use date_filter 'sql'")

    sql = src.read_text()
    live = strip_comments(sql)
    taken = {c.lower() for c in re.findall(r"(?:WITH|,)\s*([A-Za-z_][A-Za-z0-9_]*)\s+AS\s*\(", live)}
    if re.search(rf"(?m)^\s*--\s*{macro} AS \(", sql):
        return fail(f"'{macro}' is a built-in source in the template (commented block); select it as an exposure source instead of adding it as a custom one")
    if macro in taken or re.search(rf"@{macro}\b", live):
        return fail(f"'{macro}' already exists in the SQL (CTE or @macro); choose another macro name")
    label = f"{macro}_direct"
    if f"'{label}'" in live:
        return fail(f"exposure_source label '{label}' already exists in the SQL")

    def nm(key: str) -> str:
        c = names[key]
        return f"CAST(@{macro}.{c} AS STRING)" if c else "CAST(NULL AS STRING)"

    date_expr = DATE_EXPR[kind].format(m=macro, c=date_col)
    fill = {
        "<MACRO>": macro,
        "<SOURCE_LABEL>": label,
        "<PUBLISHER>": macro,
        "<CREATIVE_ID_COLUMN>": creative,
        "<PROPERTY_ID_COLUMN>": prop,
        "<CAMPAIGN_ID_COLUMN>": campaign,
        "<CREATIVE_NAME_EXPR>": nm("creative_name"),
        "<PLACEMENT_NAME_EXPR>": nm("placement_name"),
        "<CAMPAIGN_NAME_EXPR>": nm("campaign_name"),
        "<DATE_EXPR>": date_expr,
        "<DATE_FILTER>": f"WHERE {date_expr} BETWEEN '@START_DATE' AND '@END_DATE'" if mode == "sql" else "",
    }
    try:
        cte, branch = fragments()
    except ValueError as e:
        return fail(str(e))
    for k, v in fill.items():
        cte, branch = cte.replace(k, v), branch.replace(k, v)
    cte = "\n".join(l for l in cte.split("\n") if l.strip())  # drop the blank line left by an empty <DATE_FILTER>
    if re.search(r"<[A-Z_]{3,}>", cte + branch):
        return fail("unresolved placeholder left in the generated source; template and script are out of sync")

    anchor = re.search(r"^unioned_exposures AS \(", sql, re.M)
    if not anchor:
        return fail("could not find the unioned_exposures CTE; template changed?")
    out = sql[: anchor.start()] + cte + ",\n\n" + sql[anchor.start() :]
    close = re.search(
        r"(unioned_exposures AS \(.*?)(\n\)\s*\n)(?=\s*(?:--[^\n]*\n\s*)*SELECT /\*\+)", out, re.S
    )
    if not close:
        return fail("could not find the end of unioned_exposures; template changed?")
    out = out[: close.end(1)] + "\n" + branch + out[close.end(1) :]
    dst.write_text(out)
    print(
        f"wrote {dst}: source '{macro}' (label '{label}', date filter: {mode}"
        + (f", partition keys {macro}.{date_col}_start / _end" if mode == "partition" else ", uses @START_DATE/@END_DATE")
        + ")"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
