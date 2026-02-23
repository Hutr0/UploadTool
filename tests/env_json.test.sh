#!/usr/bin/env bash

TEST_DESCRIPTION="env.json: запись APP_ENV и сохранение остальных ключей (с backward-compat)"

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPLOAD_TOOL_DIR="$(cd "${TEST_DIR}/.." && pwd)"

# shellcheck disable=SC1090
source "${UPLOAD_TOOL_DIR}/lib/env_json.sh"

_failed=0
check() {
  if ! "$@"; then
    _failed=1
  fi
}

assert_file_exists() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "Missing file: $path" >&2
    return 1
  fi
}

_tmp="$(mktemp -d)"

path="${_tmp}/env.json"
# start with existing keys (universal)
cat > "$path" <<'JSON'
{"APP_ENV":"prod","BASE_URL":"https://x"}
JSON

uploadtool_write_env_to_file "$path" "dev"

assert_file_exists "$path" || _failed=1

# validate JSON contains updated env and keeps base url
got_env="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("APP_ENV","") )' "$path" 2>/dev/null || true)"
got_url="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("BASE_URL","") )' "$path" 2>/dev/null || true)"
check assert_eq "dev" "$got_env" "APP_ENV должен обновиться"
check assert_eq "https://x" "$got_url" "BASE_URL должен сохраниться"

# Backward compatibility: keep CHOYS_ENV if file already uses it
path2="${_tmp}/env_legacy.json"
cat > "$path2" <<'JSON'
{"CHOYS_ENV":"prod","CHOYS_BASE_URL":"https://legacy"}
JSON

uploadtool_write_env_to_file "$path2" "dev"

got_env2="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("CHOYS_ENV",""))' "$path2" 2>/dev/null || true)"
got_url2="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("CHOYS_BASE_URL",""))' "$path2" 2>/dev/null || true)"
got_new_key="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("APP_ENV",""))' "$path2" 2>/dev/null || true)"
check assert_eq "dev" "$got_env2" "CHOYS_ENV должен обновиться в legacy-файле"
check assert_eq "https://legacy" "$got_url2" "CHOYS_BASE_URL должен сохраниться в legacy-файле"
check assert_eq "" "$got_new_key" "APP_ENV не должен появляться в legacy-файле"

rm -rf "${_tmp}"

return "${_failed}"
