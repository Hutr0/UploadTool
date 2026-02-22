#!/usr/bin/env bash

TEST_DESCRIPTION="Workflow: интеграционный тест сборки iOS/Android (flutter аргументы, артефакты)"

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPLOAD_TOOL_DIR="$(cd "${TEST_DIR}/.." && pwd)"

# shellcheck disable=SC1090
source "${UPLOAD_TOOL_DIR}/lib/infra/runner.sh"
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

# Mock flutter builds: create expected artifacts in build/...
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

  return 0
}

(
  cd "${_tmp}"

  UPLOAD_LOG_DIR="${_tmp}/logs"
  export UPLOAD_LOG_DIR
  mkdir -p "$UPLOAD_LOG_DIR"

  export BUILD_NAME="1.0.0"
  export BUILD_NUMBER="20260221.1.0"
  export ANDROID_BUILD_NUMBER="2026022101"
  supports_no_pub=0

  state_dir_android="${_tmp}/state/dev"
  mkdir -p "${state_dir_android}"
  printf '{"CHOYS_ENV":"dev"}\n' > "${state_dir_android}/dart_defines.json"

  uploadtool_build_android "dev" "${state_dir_android}" || exit 1
  aab_path="$(cat "${state_dir_android}/android_aab_path.txt")"
  assert_file_exists "$aab_path" "android_aab_path.txt должен указывать на существующий файл" || exit 1
  assert_file_exists "${UPLOAD_LOG_DIR}/dev_android.log" "должен быть создан лог Android сборки" || exit 1

  state_dir_ios="${_tmp}/state/dev"
  mkdir -p "${state_dir_ios}"
  printf '{"CHOYS_ENV":"dev"}\n' > "${state_dir_ios}/dart_defines.json"

  uploadtool_build_ios "dev" "${state_dir_ios}" || exit 1
  ipa_path="$(cat "${state_dir_ios}/ios_ipa_path.txt")"
  assert_file_exists "$ipa_path" "ios_ipa_path.txt должен указывать на существующий файл" || exit 1
  assert_file_exists "${UPLOAD_LOG_DIR}/dev_ios.log" "должен быть создан лог iOS сборки" || exit 1
)
rc=$?
if [[ "$rc" -ne 0 ]]; then
  _failed=1
fi

rm -rf "${_tmp}"

return "${_failed}"
