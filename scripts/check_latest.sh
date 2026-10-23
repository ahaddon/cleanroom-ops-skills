#!/usr/bin/env bash
# Freshness gate: the checkout must contain the latest origin/main and have no local edits
# to the skills or scripts. Run as the first step of every skill.
#
# Usage: scripts/check_latest.sh [repo_dir]
# Exit 0 = FRESH. Exit 1 = STALE (behind, diverged, or locally edited). Exit 2 = UNVERIFIED
# (could not reach origin or not a git checkout). Both non-zero exits mean: stop, do not continue.
#
# Allowed: being ahead of origin/main (the checkout still contains everything on main), and
# edits under run-configs/ (the runner writes saved partition values there).
# Maintainers editing the skills themselves set CLEANROOM_OPS_DEV=1 to skip the local-edit check;
# it never skips the behind/diverged/unverified checks.
set -uo pipefail

dir="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
git_() { git -C "$dir" "$@"; }

if ! git_ rev-parse --git-dir >/dev/null 2>&1; then
  echo "UNVERIFIED: $dir is not a git checkout, so it cannot be compared with main. Clone the repo and run from there."
  exit 2
fi

if ! GIT_TERMINAL_PROMPT=0 git_ -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=20 \
     fetch --quiet origin main 2>/dev/null; then
  echo "UNVERIFIED: could not fetch origin/main (offline or no access). Reconnect and try again; nothing was run."
  exit 2
fi

head=$(git_ rev-parse HEAD)
main=$(git_ rev-parse FETCH_HEAD)

if [ "$head" != "$main" ]; then
  if git_ merge-base --is-ancestor "$head" "$main"; then
    n=$(git_ rev-list --count "$head..$main")
    echo "STALE: this checkout is $n commit(s) behind origin/main. Run: git pull --ff-only origin main"
    exit 1
  elif ! git_ merge-base --is-ancestor "$main" "$head"; then
    echo "STALE: this checkout has diverged from origin/main (it does not contain the latest main). Update it with: git fetch origin main && git rebase origin/main"
    exit 1
  fi
  # HEAD contains origin/main (ahead): fine.
fi

if [ "${CLEANROOM_OPS_DEV:-}" != "1" ]; then
  changed=$(git_ status --porcelain --untracked-files=normal -- skills scripts docs CLAUDE.md .claude/skills \
            ':(exclude)run-configs' | head -5)
  if [ -n "$changed" ]; then
    echo "STALE: local edits to the skills or scripts, so this is not the version on main. Discard them (git restore <file>) or move them to a branch. Changed:"
    echo "$changed"
    exit 1
  fi
fi

echo "FRESH: contains origin/main ($(git_ rev-parse --short "$main"))."
exit 0
