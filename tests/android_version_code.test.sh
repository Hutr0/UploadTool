#!/usr/bin/env bash

TEST_DESCRIPTION="Android: вычисление versionCode из build number"

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPLOAD_TOOL_DIR="$(cd "${TEST_DIR}/.." && pwd)"

# shellcheck disable=SC1090
source "${UPLOAD_TOOL_DIR}/lib/android_version_code.sh"

_failed=0
check() {
  if ! "$@"; then
    _failed=1
  fi
}

check assert_eq "2026022101" "$(uploadtool_compute_android_version_code "20260221.1.0")" "YYYYMMDD.N.X -> date*100+N"
check assert_eq "2026022110" "$(uploadtool_compute_android_version_code "20260221.10")" "YYYYMMDD.N -> date*100+N"
check assert_eq "2026022110" "$(uploadtool_compute_android_version_code "20260221.10.1")" "YYYYMMDD.N.X -> date*100+N"
check assert_eq "123" "$(uploadtool_compute_android_version_code "123")" "integer passthrough"
check assert_eq "2026022004" "$(uploadtool_compute_android_version_code "20260220.4")" "date.N -> date*100+N"
check assert_eq "2026022004" "$(uploadtool_compute_android_version_code "20260220.4.1")" "date.N.X -> date*100+N"
check assert_eq "" "$(uploadtool_compute_android_version_code "")" "empty -> empty"
check assert_eq "12" "$(uploadtool_compute_android_version_code "a1b2")" "non-digits stripped"

return "${_failed}"
