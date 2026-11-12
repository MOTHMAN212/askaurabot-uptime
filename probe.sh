#!/usr/bin/env bash
# probe.sh — off-box uptime probe for AuraBot.
# Runs on GitHub's infrastructure (free, public repo), so it survives this Mac
# dying, the tunnel dying, or the whole LAN going away.
#
# Three checks, all of which have actually broken before:
#   1. the public front door renders  (CDN -> tunnel -> frontdoor -> gateway)
#   2. the answer path is alive       (/api/ask-count returns plan/limit JSON)
#   3. the BACKEND POOL is alive      (/api/healthz: gateway's own view of its workers)
#
# Check 3 is the one that tells "the site is up" from "the site can answer": the
# gateway serves the page from disk, so 1 and 2 stay green with every worker dead.
# It returns 503 (not 200) when nothing behind the edge can answer.
#
# A 200 with an empty or wrong body is a FAILURE: the frontdoor has served
# "200 with nothing" before, and that reads as healthy to a status-code check.
set -u
BASE="${BASE:-https://askaurabot.com}"
KEYWORD="${KEYWORD:-AuraBot}"
ATTEMPTS=3
SLEEP=20

fail=0
try() { # try <label> <url> <needle>
  local label="$1" url="$2" needle="$3" i body code
  for i in $(seq 1 $ATTEMPTS); do
    body=$(curl -sS --compressed -m 25 -w '\n%{http_code}' "$url" 2>/dev/null) || true
    code=$(printf '%s' "$body" | tail -n1)
    body=$(printf '%s' "$body" | sed '$d')
    if [ "$code" = "200" ] && printf '%s' "$body" | grep -q -- "$needle"; then
      echo "PASS $label ($url) on attempt $i"
      return 0
    fi
    echo "attempt $i/$ATTEMPTS: $label -> code=${code:-none} bytes=$(printf '%s' "$body" | wc -c | tr -d ' ')"
    [ "$i" -lt "$ATTEMPTS" ] && sleep $SLEEP
  done
  echo "FAIL $label ($url): expected 200 containing '$needle'"
  return 1
}

try "front door"  "$BASE/"             "$KEYWORD"      || fail=1
try "answer path" "$BASE/api/ask-count" '"limit"'      || fail=1
try "backend pool" "$BASE/api/healthz" '"ok": true'    || fail=1

if [ "$fail" -ne 0 ]; then
  echo "RESULT: DOWN"
  exit 1
fi
echo "RESULT: UP"
