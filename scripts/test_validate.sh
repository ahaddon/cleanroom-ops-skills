#!/usr/bin/env bash
# Run after any change to the template or validator; must print PASS.
set -euo pipefail
cd "$(dirname "$0")/.."
tpl=skills/cleanroom-question-builder/references/cross-platform-exposure-mapping.sql
v=scripts/validate_question.py
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# 1. The template validates against itself.
python3 "$v" "$tpl" >/dev/null || { echo "template does not validate against itself"; exit 1; }

# 2. Hand-modifying PivotedCuts (a mandatory cut renamed) must fail.
sed "s/cut_name = 'channel'/cut_name = 'chanel'/" "$tpl" > "$tmp/a.sql"
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

# 9. No ad server data: joins removed, still valid, no @adserver left after the submit prep.
python3 scripts/remove_adserver.py "$tpl" "$tmp/f.sql" >/dev/null || { echo "remove_adserver failed on the template"; exit 1; }
python3 "$v" "$tmp/f.sql" >/dev/null || { echo "SQL without ad server should validate"; exit 1; }
python3 scripts/prepare_submit_sql.py "$tmp/f.sql" "$tmp/g.sql"
python3 "$v" "$tmp/g.sql" --submit >/dev/null || { echo "SQL without ad server should pass --submit"; exit 1; }
grep -q '@adserver' "$tmp/g.sql" && { echo "@adserver still in SQL after removal"; exit 1; }
grep -q 'CAST(NULL AS STRING) AS creative_name' "$tmp/g.sql" || { echo "ad server columns were not nulled"; exit 1; }
sed "s/LEFT JOIN @adserver c_ads/LEFT JOIN @adserver c_x/" "$tpl" > "$tmp/h.sql"
python3 scripts/remove_adserver.py "$tmp/h.sql" "$tmp/i.sql" >/dev/null && { echo "expected FAIL when the template drifts"; exit 1; }

# 11. Custom exposure source: instantiated from the generic template, valid, summarized, collision-safe.
echo '{"name":"Snapchat","creative_id":"ad_id","property_id":"adgroup_id","campaign_id":"campaign_id","creative_name":"ad_name","date_column":"impression_ts","date_kind":"epoch_seconds","date_filter":"sql"}' > "$tmp/sc.json"
python3 scripts/add_exposure_source.py "$tpl" "$tmp/t1.sql" "$tmp/sc.json" >/dev/null || { echo "add_exposure_source failed"; exit 1; }
python3 "$v" "$tmp/t1.sql" >/dev/null || { echo "SQL with a custom source should validate"; exit 1; }
grep -q "BETWEEN '@START_DATE' AND '@END_DATE'" "$tmp/t1.sql" || { echo "sql date filter missing"; exit 1; }
grep -q "CAST(NULL AS STRING) AS placement_name" "$tmp/t1.sql" || { echo "absent name column should be NULL"; exit 1; }
python3 scripts/prepare_submit_sql.py "$tmp/t1.sql" "$tmp/t2.sql"
python3 "$v" "$tmp/t2.sql" --submit >/dev/null || { echo "custom source SQL should pass --submit"; exit 1; }
python3 scripts/summarize_question.py "$tmp/t2.sql" | grep -q '"snapchat"' || { echo "summarizer missed the custom source"; exit 1; }
# a second source stacks; a partition source has no SQL date filter; collisions and bad specs fail.
echo '{"name":"Snap","creative_id":"a","campaign_id":"c","date_column":"d","date_kind":"timestamp","date_filter":"partition"}' > "$tmp/sn.json"
python3 scripts/add_exposure_source.py "$tmp/t1.sql" "$tmp/t3.sql" "$tmp/sn.json" >/dev/null || { echo "second source failed"; exit 1; }
python3 "$v" "$tmp/t3.sql" >/dev/null || { echo "two custom sources should validate"; exit 1; }
[ "$(grep -c "BETWEEN '@START_DATE'" "$tmp/t3.sql")" = "2" ] || { echo "partition source must not add a SQL date filter (expect Meta + Snapchat only)"; exit 1; }
python3 scripts/add_exposure_source.py "$tmp/t1.sql" "$tmp/t4.sql" "$tmp/sc.json" >/dev/null && { echo "expected FAIL on duplicate source"; exit 1; }
echo '{"name":"Amazon","creative_id":"a","campaign_id":"c","date_column":"d","date_kind":"date"}' > "$tmp/am.json"
python3 scripts/add_exposure_source.py "$tpl" "$tmp/t5.sql" "$tmp/am.json" >/dev/null && { echo "expected FAIL on macro collision"; exit 1; }
echo '{"name":"X1","creative_id":"a b","campaign_id":"c","date_column":"d","date_kind":"date"}' > "$tmp/bad.json"
python3 scripts/add_exposure_source.py "$tpl" "$tmp/t6.sql" "$tmp/bad.json" >/dev/null && { echo "expected FAIL on bad column name"; exit 1; }
echo '{"name":"X2","creative_id":"a","campaign_id":"c","date_column":"d","date_kind":"epoch_seconds","date_filter":"partition"}' > "$tmp/bad2.json"
python3 scripts/add_exposure_source.py "$tpl" "$tmp/t7.sql" "$tmp/bad2.json" >/dev/null && { echo "expected FAIL on epoch partition"; exit 1; }

# 10. TikTok: uncommenting its CTE and union branch validates, passes --submit, and the summarizer reads its keys.
python3 - "$tpl" "$tmp/j.sql" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
def unc(t, start, end):
    i = t.index(start); j = t.index(end, i)
    blk = re.sub(r"^(\s*)-- ?", r"\1", t[i:j], flags=re.M)
    return t[:i] + blk + t[j:]
t = unc(t, "-- tiktok AS (", "unioned_exposures AS (")
t = unc(t, "    -- UNION ALL\n    -- SELECT exposure_source, creative_source_id, property_source_id, publisher_id, campaign_id,\n    --        creative_name, placement_name, campaign_name, exposures, min_date, max_date,\n    --        creative_source_id AS vma_creative_join_key\n    -- FROM tiktok", ")\n\n-- Final")
open(sys.argv[2], "w").write(t)
PY
python3 "$v" "$tmp/j.sql" >/dev/null || { echo "SQL with tiktok should validate"; exit 1; }
python3 scripts/prepare_submit_sql.py "$tmp/j.sql" "$tmp/k.sql"
python3 "$v" "$tmp/k.sql" --submit >/dev/null || { echo "SQL with tiktok should pass --submit"; exit 1; }
python3 scripts/summarize_question.py "$tmp/k.sql" > "$tmp/sum2.json"
grep -q '"@tiktok.adgroup_id"' "$tmp/sum2.json" || { echo "summarizer missed tiktok property key"; exit 1; }
grep -q 'FROM tiktok' "$tmp/k.sql" || { echo "tiktok union branch missing"; exit 1; }
echo '{"name":"TikTok","creative_id":"a","campaign_id":"c","date_column":"d","date_kind":"date"}' > "$tmp/tk.json"
python3 scripts/add_exposure_source.py "$tpl" "$tmp/t8.sql" "$tmp/tk.json" >/dev/null && { echo "expected FAIL: tiktok is a built-in source"; exit 1; }

# 11. Freshness gate (scripts/check_latest.sh), against throwaway repos.
fr="$tmp/fresh"; mkdir -p "$fr"
git -C "$fr" init -q -b main origin_repo 2>/dev/null || { git init -q -b main "$fr/origin_repo"; }
o="$fr/origin_repo"
git -C "$o" config user.email t@t; git -C "$o" config user.name t
mkdir -p "$o/skills" "$o/scripts" "$o/run-configs"; echo a > "$o/skills/a.md"; echo r > "$o/run-configs/r.json"
git -C "$o" add -A; git -C "$o" commit -qm one
git clone -q "$o" "$fr/user"; u="$fr/user"
git -C "$u" config user.email t@t; git -C "$u" config user.name t
chk() { bash scripts/check_latest.sh "$u" 2>&1; }
chk | grep -q '^FRESH' || { echo "fresh clone should pass the freshness gate"; exit 1; }
echo local > "$u/run-configs/r.json"
chk | grep -q '^FRESH' || { echo "run-configs edits must not block"; exit 1; }
git -C "$u" checkout -q -- run-configs
echo edit >> "$u/skills/a.md"
bash scripts/check_latest.sh "$u" >/dev/null 2>&1 && { echo "edited skill should be STALE"; exit 1; }
CLEANROOM_OPS_DEV=1 bash scripts/check_latest.sh "$u" >/dev/null 2>&1 || { echo "dev override should skip the local-edit check"; exit 1; }
git -C "$u" checkout -q -- skills
echo two >> "$o/skills/a.md"; git -C "$o" commit -qam two
out=$(bash scripts/check_latest.sh "$u" 2>&1 || true); echo "$out" | grep -q '^STALE: .*behind' || { echo "behind clone should be STALE"; exit 1; }
CLEANROOM_OPS_DEV=1 bash scripts/check_latest.sh "$u" >/dev/null 2>&1 && { echo "dev override must not skip the behind check"; exit 1; }
echo mine >> "$u/skills/b.md"; git -C "$u" add -A; git -C "$u" commit -qm mine
out=$(bash scripts/check_latest.sh "$u" 2>&1 || true); echo "$out" | grep -q '^STALE: .*diverged' || { echo "diverged clone should be STALE"; exit 1; }
git -C "$u" reset -q --hard origin/main; git -C "$u" pull -q --ff-only origin main
chk | grep -q '^FRESH' || { echo "updated clone should pass"; exit 1; }
echo extra > "$u/skills/c.md"; git -C "$u" add -A; git -C "$u" commit -qm ahead
chk | grep -q '^FRESH' || { echo "a clone ahead of main should pass"; exit 1; }
mv "$o" "$o.gone"
rc=0; bash scripts/check_latest.sh "$u" >/dev/null 2>&1 || rc=$?; [ "$rc" -eq 2 ] || { echo "unreachable origin should be UNVERIFIED (exit 2)"; exit 1; }
rc=0; bash scripts/check_latest.sh "$fr" >/dev/null 2>&1 || rc=$?; [ "$rc" -eq 2 ] || { echo "non-git dir should be UNVERIFIED (exit 2)"; exit 1; }

# 12. Every skill opens with the freshness gate.
for sk in skills/*/SKILL.md; do
  grep -q 'scripts/check_latest.sh' "$sk" || { echo "$sk is missing the freshness gate (step 0)"; exit 1; }
done

# 13. SessionStart hook: settings are valid JSON, point at a real script, and the wrapper always exits 0 with a message.
python3 - <<'PY' || { echo ".claude/settings.json hook is missing or invalid"; exit 1; }
import json, os
d = json.load(open(".claude/settings.json"))
cmd = d["hooks"]["SessionStart"][0]["hooks"][0]["command"]
assert "scripts/session_start_check.sh" in cmd, cmd
assert os.path.exists("scripts/session_start_check.sh")
PY
rc=0; out=$(bash scripts/session_start_check.sh 2>&1) || rc=$?
[ "$rc" -eq 0 ] || { echo "session_start_check.sh must always exit 0"; exit 1; }
echo "$out" | grep -q 'cleanroom-ops freshness' || { echo "session_start_check.sh printed no freshness message"; exit 1; }

# 12. VMA cuts: generated from a spec; mandatory cuts always present; rules enforced.
echo '{"standard":["campaign","subbrand","creative"],"custom":[{"name":"Media Type","slot":1},{"name":"audience_name","slot":3,"level":"creative"}]}' > "$tmp/c1.json"
python3 scripts/build_vma_cuts.py "$tpl" "$tmp/u1.sql" "$tmp/c1.json" >/dev/null || { echo "build_vma_cuts failed"; exit 1; }
python3 "$v" "$tmp/u1.sql" >/dev/null || { echo "generated cuts should validate"; exit 1; }
grep -q "cut_name = 'custom_cut_3' THEN map_name END) AS audience_name" "$tmp/u1.sql" || { echo "custom slot 3 not mapped"; exit 1; }
grep -q "ANY_VALUE(vma_cr.audience_name) AS audience_name" "$tmp/u1.sql" || { echo "creative-level custom cut should read vma_cr"; exit 1; }
python3 scripts/prepare_submit_sql.py "$tmp/u1.sql" "$tmp/u2.sql"
python3 "$v" "$tmp/u2.sql" --submit >/dev/null || { echo "generated cuts should pass --submit"; exit 1; }
python3 scripts/output_fields.py "$tmp/u2.sql" | grep -q '"media_type"' || { echo "output_fields missed the custom cut"; exit 1; }
python3 scripts/output_fields.py "$tmp/u2.sql" | grep -q '"subbrand"' || { echo "output_fields missed subbrand"; exit 1; }
# minimal cuts: only channel, property, publisher; the creative join and its hint entry disappear.
echo '{"standard":[]}' > "$tmp/c2.json"
python3 scripts/build_vma_cuts.py "$tpl" "$tmp/u3.sql" "$tmp/c2.json" >/dev/null || { echo "minimal cuts failed"; exit 1; }
python3 "$v" "$tmp/u3.sql" >/dev/null || { echo "minimal cuts should validate"; exit 1; }
grep -q "BROADCAST(vma_prop) " "$tmp/u3.sql" || { echo "hint should list only vma_prop"; exit 1; }
grep -q "LEFT JOIN PivotedCuts vma_cr" "$tmp/u3.sql" && { echo "unused vma_cr join should be removed"; exit 1; }
grep -q "AS campaign\b" "$tmp/u3.sql" && { echo "campaign should be absent when not selected"; exit 1; }
# validator rules (hand edits must fail).
grep -v "cut_name = 'publisher'" "$tpl" > "$tmp/n1.sql"
python3 "$v" "$tmp/n1.sql" >/dev/null && { echo "expected FAIL: publisher cut removed"; exit 1; }
sed "s/cut_name = 'creative'/cut_name = 'custom_cut_9'/" "$tpl" > "$tmp/n2.sql"
python3 "$v" "$tmp/n2.sql" >/dev/null && { echo "expected FAIL: custom_cut_9"; exit 1; }
sed "s/ANY_VALUE(vma_prop.campaign) AS campaign/CASE WHEN u.exposure_source = 'meta' THEN ANY_VALUE(vma_cr.campaign) ELSE ANY_VALUE(vma_prop.campaign) END AS campaign/" "$tpl" > "$tmp/n3.sql"
python3 "$v" "$tmp/n3.sql" >/dev/null && { echo "expected FAIL: hand-written CASE in the cut columns"; exit 1; }
grep -v "ANY_VALUE(vma_prop.subbrand)" "$tpl" > "$tmp/n4.sql"
python3 "$v" "$tmp/n4.sql" >/dev/null && { echo "expected FAIL: SELECT does not match PivotedCuts"; exit 1; }
sed "s/ANY_VALUE(vma_prop.channel) AS channel/ANY_VALUE(vma_cr.channel) AS channel/" "$tpl" > "$tmp/n5.sql"
python3 "$v" "$tmp/n5.sql" >/dev/null && { echo "expected FAIL: channel must read vma_prop"; exit 1; }
# generator rules.
for bad in '{"standard":[],"custom":[{"name":"channel","slot":1}]}' '{"standard":[],"custom":[{"name":"x","slot":8}]}' \
  '{"standard":[],"custom":[{"name":"a","slot":1},{"name":"b","slot":1}]}' '{"standard":["nope"]}' \
  '{"standard":[],"levels":{"channel":"creative"}}' '{"standard":[],"custom":[{"name":"a b!","slot":1,"level":"sideways"}]}' \
  '{"standard":[],"custom":[{"name":"c1","slot":1},{"name":"c2","slot":2},{"name":"c3","slot":3},{"name":"c4","slot":4},{"name":"c5","slot":5},{"name":"c6","slot":6},{"name":"c7","slot":7},{"name":"c8","slot":1}]}'; do
  echo "$bad" > "$tmp/bad.json"
  python3 scripts/build_vma_cuts.py "$tpl" "$tmp/x.sql" "$tmp/bad.json" >/dev/null && { echo "expected FAIL for cuts spec: $bad"; exit 1; }
done
# custom sources and ad server removal still compose with custom cuts.
python3 scripts/add_exposure_source.py "$tmp/u1.sql" "$tmp/u4.sql" "$tmp/sc.json" >/dev/null || { echo "source on top of custom cuts failed"; exit 1; }
python3 "$v" "$tmp/u4.sql" >/dev/null || { echo "source + custom cuts should validate"; exit 1; }

echo PASS
