#!/usr/bin/env bash

TEST_DESCRIPTION="Workflow: wait for uploads + update pubspec version"

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPLOAD_TOOL_DIR="$(cd "${TEST_DIR}/.." && pwd)"

# shellcheck disable=SC1090
source "${UPLOAD_TOOL_DIR}/lib/infra/time.sh"
# shellcheck disable=SC1090
source "${UPLOAD_TOOL_DIR}/lib/i18n/en.sh"
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

(
  cd "${_tmp}"

  ROOT_DIR="${_tmp}"
  export ROOT_DIR

  UPLOAD_STATE_DIR="${_tmp}/state"
  export UPLOAD_STATE_DIR
  mkdir -p "$UPLOAD_STATE_DIR"

  BUILD_NAME="1.0.0"
  export BUILD_NAME

  cat > "${_tmp}/pubspec.yaml" <<'YAML'
name: dummy
version: 0.1.0+1
YAML

  uploadtool_update_pubspec_version "20260221.1.0" "test"

  # pubspec updated
  got_ver_line="$(grep -E '^version:' "${_tmp}/pubspec.yaml" | head -n 1 | tr -d '\r\n')"
  check assert_eq "version: 1.0.0+20260221.1.0" "$got_ver_line" "pubspec.yaml version should update"

  marker="${UPLOAD_STATE_DIR}/pubspec_updated_to.txt"
  assert_file_exists "$marker" "marker file should be created" || exit 1
  marker_content="$(cat "$marker" | tr -d '\r\n')"
  check assert_eq "1.0.0+20260221.1.0 (test)" "$marker_content" "marker should contain resulting version and reason"

  # wait_for_all_uploads: polling
  status1="${_tmp}/status1.txt"
  UPLOAD_STATUS_FILES=("$status1")
  UPLOAD_LABELS=("dev:ios")

  _sleep_calls=0
  uploadtool_sleep_override() {
    _sleep_calls=$((_sleep_calls + 1))
    printf '0\n' > "$status1"
    return 0
  }

  if ! uploadtool_wait_for_all_uploads; then
    echo "wait_for_all_uploads should return 0 when status file appears" >&2
    exit 1
  fi
  check assert_eq "1" "${_sleep_calls}" "should perform at least one polling sleep"

  unset -f uploadtool_sleep_override

  # at_least_one_upload_succeeded
  status_ok="${_tmp}/status_ok.txt"
  status_fail="${_tmp}/status_fail.txt"
  printf '1\n' > "$status_fail"
  printf '0\n' > "$status_ok"
  UPLOAD_STATUS_FILES=("$status_fail" "$status_ok")
  UPLOAD_LABELS=("x" "y")
  if ! uploadtool_at_least_one_upload_succeeded; then
    echo "at_least_one_upload_succeeded should return 0 when there is at least one rc=0" >&2
    exit 1
  fi

  # wait_for_all_uploads: fail when rc != 0
  UPLOAD_STATUS_FILES=("$status_fail")
  UPLOAD_LABELS=("dev:android")
  if uploadtool_wait_for_all_uploads; then
    echo "wait_for_all_uploads should return non-zero when rc != 0" >&2
    exit 1
  fi
)
rc=$?
if [[ "$rc" -ne 0 ]]; then
  _failed=1
fi

rm -rf "${_tmp}"

return "${_failed}"
