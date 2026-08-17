#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
checker="$repo_dir/bin/check-bind"
fixtures="$repo_dir/tests/fixtures"
passes=0

expect_status() {
  expected=$1
  pattern=$2
  shift 2

  set +e
  output=$("$checker" "$@" 2>&1)
  actual=$?
  set -e

  if [[ $actual -ne $expected ]]; then
    printf 'FAIL: expected exit %s, got %s\n%s\n' "$expected" "$actual" "$output" >&2
    exit 1
  fi
  if [[ $output != *"$pattern"* ]]; then
    printf 'FAIL: output does not contain %s\n%s\n' "$pattern" "$output" >&2
    exit 1
  fi
  passes=$((passes + 1))
}

expect_status 0 "PASS:" --address 127.0.0.1 --port 8080 --snapshot "$fixtures/exact-ipv4.txt"
expect_status 0 "PASS:" --address ::1 --port 9090 --snapshot "$fixtures/exact-ipv6.txt"
expect_status 1 "wildcard listener" --address 127.0.0.1 --port 8080 --snapshot "$fixtures/wildcard-ipv4.txt"
expect_status 1 "expected 127.0.0.1:8080" --address 127.0.0.1 --port 8080 --snapshot "$fixtures/wrong-address.txt"
expect_status 1 "no TCP listener" --address 127.0.0.1 --port 8080 --snapshot "$fixtures/missing-port.txt"
expect_status 2 "must be between" --address 127.0.0.1 --port 70000 --snapshot "$fixtures/exact-ipv4.txt"
expect_status 2 "literal address" --address '$(id)' --port 8080 --snapshot "$fixtures/exact-ipv4.txt"

printf 'PASS: %s deterministic checks\n' "$passes"
