#!/usr/bin/env bash

TEST_DESCRIPTION="Workflow: run_for_env (подготовка ENV, build numbers, notes, оркестрация)"

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPLOAD_TOOL_DIR="$(cd "${TEST_DIR}/.." && pwd)"

# shellcheck disable=SC1090
source "${UPLOAD_TOOL_DIR}/lib/infra/runner.sh"
# shellcheck disable=SC1090
source "${UPLOAD_TOOL_DIR}/lib/infra/time.sh"
# shellcheck disable=SC1090
source "${UPLOAD_TOOL_DIR}/lib/env_json.sh"
# shellcheck disable=SC1090
source "${UPLOAD_TOOL_DIR}/lib/android_version_code.sh"
# shellcheck disable=SC1090
source "${UPLOAD_TOOL_DIR}/lib/notes.sh"
# shellcheck disable=SC1090
source "${UPLOAD_TOOL_DIR}/lib/workflow.sh"

_failed=0
check() {
  if ! "$@"; then
    _failed=1
  fi
}

assert_file_exists() {
  local path="$1"
  local msg="${2:-}"
  if [[ ! -f "$path" ]]; then
    echo "Missing file: $path" >&2
    [[ -n "$msg" ]] && echo "$msg" >&2
    return 1
  fi
}

_tmp="$(mktemp -d)"

# Don't actually build/upload in this test.
_called=""
uploadtool_build_and_upload_for_env() {
  _called="$*"
  return 0
}

(
  cd "${_tmp}"

  ROOT_DIR="${_tmp}"
  export ROOT_DIR

  UPLOAD_STATE_DIR="${_tmp}/state"
  export UPLOAD_STATE_DIR
  mkdir -p "$UPLOAD_STATE_DIR"

  UPLOAD_LOG_DIR="${_tmp}/logs"
  export UPLOAD_LOG_DIR
  mkdir -p "$UPLOAD_LOG_DIR"

  BUILD_NAME="1.0.0"
  export BUILD_NAME

  WAIT_IOS_CHOICE="0"
  export WAIT_IOS_CHOICE

  BUILD_ANDROID=1
  BUILD_IOS=0
  UPLOAD_ANDROID=0
  UPLOAD_IOS=1
  export BUILD_ANDROID BUILD_IOS UPLOAD_ANDROID UPLOAD_IOS

  ENV_TARGETS="dev"
  export ENV_TARGETS

  # run
  uploadtool_run_for_env "dev" "20260221.10.0" 1 "Hello" || exit 1

  # should have created per-env dart defines
  env_path="${UPLOAD_STATE_DIR}/dev/dart_defines.json"
  assert_file_exists "$env_path" "dart_defines.json должен быть создан" || exit 1

  got_env="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("CHOYS_ENV",""))' "$env_path" 2>/dev/null || true)"
  check assert_eq "dev" "$got_env" "CHOYS_ENV должен записаться в dart_defines.json"

  # should compute ANDROID_BUILD_NUMBER
  check assert_eq "2026022110" "${ANDROID_BUILD_NUMBER:-}" "ANDROID_BUILD_NUMBER должен считаться как date*100+N"

  # should set notes for uploads
  expected_notes=$'Тестовая сборка\n\nHello'
  check assert_eq "$expected_notes" "${TESTFLIGHT_CHANGELOG:-}" "TESTFLIGHT_CHANGELOG должен формироваться через notes.sh"

  # should call build+upload orchestration with tag+state_dir
  check assert_eq "dev ${UPLOAD_STATE_DIR}/dev 1" "${_called}" "должен быть вызван build_and_upload_for_env"
)
rc=$?
if [[ "$rc" -ne 0 ]]; then
  _failed=1
fi

rm -rf "${_tmp}"

return "${_failed}"
