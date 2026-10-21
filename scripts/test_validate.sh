#!/usr/bin/env bash
# Run after any change to the template or validator; must print PASS.
set -euo pipefail
cd "$(dirname "$0")/.."
tpl=skills/cleanroom-question-builder/references/cross-platform-exposure-mapping.sql
v=scripts/validate_question.py
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# 1. The template validates against itself.
python3 "$v" "$tpl" >/dev/null || { echo "template does not validate against itself"; exit 1; }

# 2. Modifying PivotedCuts must fail.
sed "s/'custom_cut_1'/'custom_cut_9'/" "$tpl" > "$tmp/a.sql"
python3 "$v" "$tmp/a.sql" >/dev/null && { echo "expected FAIL on PivotedCuts edit"; exit 1; }

# 3. Changing the Meta date filter must fail.
sed "s/BETWEEN '@START_DATE'/BETWEEN '2024-01-01'/" "$tpl" > "$tmp/b.sql"
python3 "$v" "$tmp/b.sql" >/dev/null && { echo "expected FAIL on Meta filter edit"; exit 1; }

# 4. Unioning an undefined source must fail.
sed "s/    FROM dtv$/    FROM ghost/" "$tpl" > "$tmp/c.sql"
python3 "$v" "$tmp/c.sql" >/dev/null && { echo "expected FAIL on undefined source"; exit 1; }

# 5. Leftover placeholder must fail.
{ cat "$tpl"; echo "-- ok"; echo "SELECT <CLEAN_ROOM_ID>"; } > "$tmp/d.sql"
python3 "$v" "$tmp/d.sql" >/dev/null && { echo "expected FAIL on placeholder"; exit 1; }

# 6. Raw template must fail --submit (comments contain @macros); prepared copy must pass it.
python3 "$v" "$tpl" --submit >/dev/null && { echo "expected FAIL on --submit with comments"; exit 1; }
python3 scripts/prepare_submit_sql.py "$tpl" "$tmp/e.sql"
python3 "$v" "$tmp/e.sql" --submit >/dev/null || { echo "prepared SQL should pass --submit"; exit 1; }
grep -q '@digital_mapping\|@uber' "$tmp/e.sql" && { echo "prepared SQL still contains commented-source macros"; exit 1; }
grep -q 'BROADCAST' "$tmp/e.sql" || { echo "prepared SQL lost the BROADCAST hint"; exit 1; }

# 7. Summarizer reads join keys from the SQL.
python3 scripts/summarize_question.py "$tmp/e.sql" > "$tmp/sum.json"
grep -q '"se._ds_ad_name"' "$tmp/sum.json" || { echo "summarizer missed snowplow creative key"; exit 1; }
grep -q '"@meta.placement_type"' "$tmp/sum.json" || { echo "summarizer missed meta property key"; exit 1; }
grep -q '"vma"' "$tmp/sum.json" || { echo "summarizer missed the vma macro"; exit 1; }

# 8. Run-config checker: good file passes; date-like partition fails.
rc="$tmp/rc/11111111-1111-4111-8111-111111111111"; mkdir -p "$rc"
good='{"clean_room_id":"11111111-1111-4111-8111-111111111111","clean_room_name":"X","question_id":"22222222-2222-4222-8222-222222222222","question_title":"T","partitions":{"uber.brand":"A,B"},"updated_at":"2026-10-21"}'
echo "$good" > "$rc/22222222-2222-4222-8222-222222222222.json"
python3 scripts/check_run_configs.py "$tmp/rc" >/dev/null || { echo "good run-config should pass"; exit 1; }
echo "${good/uber.brand/uber.event_date_start}" > "$rc/22222222-2222-4222-8222-222222222222.json"
python3 scripts/check_run_configs.py "$tmp/rc" >/dev/null && { echo "date-like partition should fail"; exit 1; }
python3 scripts/check_run_configs.py >/dev/null || { echo "repo run-configs should pass"; exit 1; }

echo PASS
