#!/usr/bin/env bash
set -euo pipefail

repo=${1:-.}
repo=$(cd -- "$repo" && pwd)

failures=0
warnings=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

warn() {
  printf 'WARN: %s\n' "$1" >&2
  warnings=$((warnings + 1))
}

pass() {
  printf 'PASS: %s\n' "$1"
}

if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: target is not a Git repository" >&2
  exit 1
fi

tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$tmp_dir"' EXIT
tracked="$tmp_dir/tracked"
secret_files="$tmp_dir/secret-files"
environment_files="$tmp_dir/environment-files"

git -C "$repo" ls-files -z >"$tracked"

if [[ -n $(git -C "$repo" status --porcelain=v1) ]]; then
  fail "working tree is not clean; review and commit the exact publication state"
else
  pass "working tree is clean"
fi

manifest="$repo/.publication.yml"
if [[ ! -f $manifest ]]; then
  fail ".publication.yml is missing"
else
  required_manifest_lines=(
    "schema_version: 1"
    "history_origin: clean-export"
    "contains_real_credentials: false"
    "contains_client_data: false"
    "contains_private_infrastructure: false"
    "owner_approved: true"
  )
  for expected in "${required_manifest_lines[@]}"; do
    if ! grep -Fxq -- "$expected" "$manifest"; then
      fail ".publication.yml must contain: $expected"
    fi
  done
fi

for required in README.md SECURITY.md CONTRIBUTING.md .gitignore .env.example; do
  if [[ ! -f $repo/$required ]]; then
    fail "required publication file is missing: $required"
  fi
done

if [[ -f $repo/.gitignore ]]; then
  for rule in '.env' '.env.*' '*.pem' '*.key'; do
    if ! grep -Fxq -- "$rule" "$repo/.gitignore"; then
      fail ".gitignore is missing required rule: $rule"
    fi
  done
fi

while IFS= read -r -d '' path; do
  base=${path##*/}
  case "$base" in
    .env.example|.env.sample|.env.template)
      ;;
    .env|.env.*|*.pem|*.key|*.p12|*.pfx|*.jks|*.keystore|id_rsa*|id_ed25519*|credentials.json|service-account*.json|*.dump|*.sql|*.sqlite|*.sqlite3|*.zip|*.tar|*.tar.gz)
      fail "forbidden tracked file: $path"
      ;;
  esac
done <"$tracked"

while IFS= read -r -d '' path; do
  base=${path##*/}
  case "$base" in
    .env.example|.env.sample|.env.template)
      ;;
    .env|.env.*)
      fail "local environment file exists in publication workspace: ${path#"$repo"/}"
      ;;
  esac
done < <(find "$repo" -path "$repo/.git" -prune -o -type f -name '.env*' -print0)

high_confidence_patterns=(
  '-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'
  'AKIA[0-9A-Z]{16}'
  'ASIA[0-9A-Z]{16}'
  'github_pat_[A-Za-z0-9_]{20,}'
  'gh[pousr]_[A-Za-z0-9]{20,}'
  'sk-[A-Za-z0-9_-]{20,}'
  '[0-9]{8,10}:[A-Za-z0-9_-]{35}'
  'xox[baprs]-[A-Za-z0-9-]{10,}'
  'AIza[0-9A-Za-z_-]{30,}'
  'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
  '(postgres|postgresql|mysql|mongodb(\+srv)?|redis)://[^[:space:]/]+:[^[:space:]@]+@'
  "(?i)(api[_-]?key|api[_-]?secret|access[_-]?token|auth[_-]?token|password|passwd|client[_-]?secret|private[_-]?key)[[:space:]]*[:=][[:space:]]*[\"']?(?!(replace_me|change_me|changeme|example|placeholder|your_|<|\\\$\\\{))[A-Za-z0-9_./+=-]{12,}"
)

: >"$secret_files"
for pattern in "${high_confidence_patterns[@]}"; do
  git -C "$repo" grep -I -l -P -e "$pattern" -- . >>"$secret_files" 2>/dev/null || true
done

if [[ -s $secret_files ]]; then
  sort -u "$secret_files" | while IFS= read -r path; do
    printf '  suspicious file: %s\n' "$path" >&2
  done
  fail "high-confidence secret pattern found; values are intentionally hidden"
else
  pass "no high-confidence secret pattern found in tracked files"
fi

history_secret=0
for pattern in "${high_confidence_patterns[@]}"; do
  if grep -Pq -- "$pattern" < <(git -C "$repo" log -p --all --no-ext-diff --no-textconv --pretty=format:); then
    history_secret=1
    break
  fi
done
if [[ $history_secret -eq 1 ]]; then
  fail "secret-like material exists in Git history; rebuild from a new clean export"
else
  pass "no high-confidence secret pattern found in Git history"
fi

if git -C "$repo" rev-list --objects --all | awk '{print $2}' | grep -E '(^|/)\.env($|\.)' | grep -Ev '(^|/)\.env\.(example|sample|template)$' >/dev/null; then
  fail "a forbidden .env path exists in Git history; rebuild from a new clean export"
else
  pass "no forbidden .env path found in Git history"
fi

: >"$environment_files"
environment_patterns=(
  '/root/'
  '/home/[A-Za-z0-9._-]+/'
  '[A-Za-z0-9.-]+\.ts\.net'
  '(?<![0-9])([0-9]{1,3}\.){3}[0-9]{1,3}(?![0-9])'
)
for pattern in "${environment_patterns[@]}"; do
  git -C "$repo" grep -I -l -P -e "$pattern" -- . ':(exclude)scripts/prepublish-gate.sh' >>"$environment_files" 2>/dev/null || true
done
if [[ -s $environment_files ]]; then
  sort -u "$environment_files" | while IFS= read -r path; do
    printf '  review environment identifier in: %s\n' "$path" >&2
  done
  warn "environment-like identifiers require manual review; values are intentionally hidden"
else
  pass "no obvious environment identifiers found"
fi

private_patterns_file=${PUBLICATION_PRIVATE_PATTERNS_FILE:-}
if [[ -n $private_patterns_file ]]; then
  if [[ ! -r $private_patterns_file ]]; then
    fail "PUBLICATION_PRIVATE_PATTERNS_FILE is not readable"
  else
    private_match=0
    while IFS= read -r pattern; do
      [[ -z $pattern || $pattern == \#* ]] && continue
      if git -C "$repo" grep -I -q -E -e "$pattern" -- . 2>/dev/null; then
        private_match=1
      fi
    done <"$private_patterns_file"
    if [[ $private_match -eq 1 ]]; then
      fail "a private identifier matched the local blocklist; value is intentionally hidden"
    else
      pass "no identifier from the local private blocklist found"
    fi
  fi
fi

if [[ $failures -gt 0 ]]; then
  printf '\nPublication blocked: %d failure(s), %d warning(s).\n' "$failures" "$warnings" >&2
  exit 1
fi

printf '\nPublication gate passed with %d warning(s). Manual owner review is still required.\n' "$warnings"
