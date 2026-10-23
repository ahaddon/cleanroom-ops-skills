#!/usr/bin/env bash
# SessionStart hook: run the freshness gate and put the result in the session context.
# A hook cannot block a session, so on STALE / UNVERIFIED it tells the model to use no
# cleanroom-ops skill until the checkout is fixed. Each skill's step 0 is the hard stop.
# Always exits 0 so Claude Code adds this output to the context.
cd "$(dirname "$0")/.." || exit 0
out=$(bash scripts/check_latest.sh 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
  echo "cleanroom-ops freshness: $out"
else
  echo "cleanroom-ops freshness check FAILED. Tell the user this first, in your first reply, and do not run any cleanroom-ops skill or clean-room tool until it is fixed:"
  echo "$out"
fi
exit 0
