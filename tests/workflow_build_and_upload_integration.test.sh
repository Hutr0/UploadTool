#!/usr/bin/env bash

TEST_DESCRIPTION="Workflow: интеграционный тест оркестрации build+upload (fastlane вызовы, статусы)"

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPLOAD_TOOL_DIR="$(cd "${TEST_DIR}/.." && pwd)"

# shellcheck disable=SC1090
source "${UPLOAD_TOOL_DIR}/lib/infra/runner.sh"
# shellcheck disable=SC1090
source "${UPLOAD_TOOL_DIR}/lib/infra/time.sh"
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

# Speed up polling in tests
uploadtool_sleep_override() { return 0; }

# Mock runner for flutter + fastlane
uploadtool_run_cmd_override() {
  if [[ "${1:-}" == "flutter" && "${2:-}" == "build" && "${3:-}" == "appbundle" ]]; then
    mkdir -p "${_tmp}/build/app/outputs/bundle/release"
    printf 'dummy-aab' > "${_tmp}/build/app/outputs/bundle/release/app-release.aab"
    return 0
  fi

  if [[ "${1:-}" == "flutter" && "${2:-}" == "build" && "${3:-}" == "ipa" ]]; then
    mkdir -p "${_tmp}/build/ios/ipa"
    printf 'dummy-ipa' > "${_tmp}/build/ios/ipa/app-release.ipa"
    return 0
  fi

  if [[ "${1:-}" == "bundle" && "${2:-}" == "exec" && "${3:-}" == "fastlane" ]]; then
    printf '%s\n' "$*" >> "${FASTLANE_CALLS_FILE}"
    return 0
  fi

  return 0
}

(
  cd "${_tmp}"

  ROOT_DIR="${_tmp}"
  export ROOT_DIR

  UPLOADTOOL_FASTLANE_ROOT="${_tmp}/fastlane"
  export UPLOADTOOL_FASTLANE_ROOT
  mkdir -p "${UPLOADTOOL_FASTLANE_ROOT}"
  # Достаточно пустого Gemfile, чтобы cd работал. bundler/fastlane не запускаются реально (мок).
  printf "source 'https://rubygems.org'\n" > "${UPLOADTOOL_FASTLANE_ROOT}/Gemfile"

  FASTLANE_CALLS_FILE="${_tmp}/fastlane_calls.txt"
  export FASTLANE_CALLS_FILE
  : > "${FASTLANE_CALLS_FILE}"

  UPLOAD_LOG_DIR="${_tmp}/logs"
  export UPLOAD_LOG_DIR
  mkdir -p "$UPLOAD_LOG_DIR"

  UPLOAD_STATE_DIR="${_tmp}/state"
  export UPLOAD_STATE_DIR
  mkdir -p "$UPLOAD_STATE_DIR"

  export BUILD_NAME="1.0.0"
  export BUILD_NUMBER="20260221.1.0"
  export ANDROID_BUILD_NUMBER="2026022101"
  supports_no_pub=0

  BUILD_ANDROID=1
  BUILD_IOS=1
  UPLOAD_ANDROID=1
  UPLOAD_IOS=1
  export BUILD_ANDROID BUILD_IOS UPLOAD_ANDROID UPLOAD_IOS

  state_dir="${UPLOAD_STATE_DIR}/dev"
  mkdir -p "$state_dir"
  printf '{"APP_ENV":"dev"}\n' > "${state_dir}/dart_defines.json"

  UPLOAD_STATUS_FILES=()
  UPLOAD_LABELS=()

  uploadtool_build_and_upload_for_env "dev" "$state_dir" 0 || exit 1

  assert_file_exists "${state_dir}/upload_android_exit_code.txt" "должен создаться android status file" || exit 1
  assert_file_exists "${state_dir}/upload_ios_exit_code.txt" "должен создаться ios status file" || exit 1

  rc_android="$(cat "${state_dir}/upload_android_exit_code.txt" | tr -d '\r\n')"
  rc_ios="$(cat "${state_dir}/upload_ios_exit_code.txt" | tr -d '\r\n')"
  check assert_eq "0" "$rc_android" "android upload rc должен быть 0"
  check assert_eq "0" "$rc_ios" "ios upload rc должен быть 0"

  assert_file_exists "${UPLOAD_LOG_DIR}/dev_android_upload.log" "должен создаться лог Android upload" || exit 1
  assert_file_exists "${UPLOAD_LOG_DIR}/dev_ios_upload.log" "должен создаться лог iOS upload" || exit 1

  # Проверяем, что fastlane вызывался для обеих платформ
  calls_count="$(wc -l < "${FASTLANE_CALLS_FILE}" | tr -d '[:space:]')"
  [[ "${calls_count:-0}" -ge 2 ]] || { echo "fastlane должен вызваться минимум 2 раза" >&2; exit 1; }
)
rc=$?
if [[ "$rc" -ne 0 ]]; then
  _failed=1
fi

rm -rf "${_tmp}"

return "${_failed}"
