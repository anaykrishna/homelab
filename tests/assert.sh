#!/usr/bin/env bash
# Tiny zero-dependency assertion helper for plan tests.
# Sourced by tests/run.sh and by individual *_test.sh files.

ASSERT_PASS=0
ASSERT_FAIL=0

assert_eq() {
  local actual="$1" expected="$2" label="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "PASS: $label"
    ASSERT_PASS=$((ASSERT_PASS + 1))
  else
    echo "FAIL: $label"
    echo "  expected: [$expected]"
    echo "  actual:   [$actual]"
    ASSERT_FAIL=$((ASSERT_FAIL + 1))
  fi
}
