#!/usr/bin/env bash
# Runs every tests/*_test.sh and reports a combined pass/fail total.
set -u
cd "$(dirname "$0")"
source ./assert.sh

for t in *_test.sh; do
  [[ -e "$t" ]] || continue
  echo "== $t =="
  # shellcheck disable=SC1090
  source "./$t"
done

echo "-----------------------------"
echo "PASS=$ASSERT_PASS FAIL=$ASSERT_FAIL"
[[ "$ASSERT_FAIL" -eq 0 ]]
