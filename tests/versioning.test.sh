#!/usr/bin/env bash

TEST_DESCRIPTION="Версионирование: извлечение/инкремент build number, форматирование под env"

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPLOAD_TOOL_DIR="$(cd "${TEST_DIR}/.." && pwd)"

# shellcheck disable=SC1090
source "${UPLOAD_TOOL_DIR}/lib/versioning.sh"

_failed=0
check() {
  if ! "$@"; then
    _failed=1
  fi
}

check assert_eq "20260220.4" "$(uploadtool_extract_core_build_number "20260220.4.1")" "extract_core_build_number YYYYMMDD.N.X"
check assert_eq "20260220.4" "$(uploadtool_extract_core_build_number "20260220.4")" "extract_core_build_number YYYYMMDD.N"
check assert_eq "123" "$(uploadtool_extract_core_build_number "123")" "extract_core_build_number integer"
check assert_eq "" "$(uploadtool_extract_core_build_number "abc")" "extract_core_build_number invalid"

check assert_eq "20260220.5" "$(uploadtool_bump_core_build_number_one "20260220.4")" "bump YYYYMMDD.N"
check assert_eq "20260220.5" "$(uploadtool_bump_core_build_number_one "20260220.4.1")" "bump YYYYMMDD.N.X"
check assert_eq "124" "$(uploadtool_bump_core_build_number_one "123")" "bump integer"
check assert_eq "" "$(uploadtool_bump_core_build_number_one "abc")" "bump invalid"

UPLOADTOOL_TODAY_YYYYMMDD="20260221"
export UPLOADTOOL_TODAY_YYYYMMDD
check assert_eq "20260221.2" "$(uploadtool_compute_next_core_build_number "20260221.1")" "compute next same-day"
check assert_eq "20260221.1" "$(uploadtool_compute_next_core_build_number "20260220.9")" "compute next new-day"
check assert_eq "20260221.1" "$(uploadtool_compute_next_core_build_number "")" "compute next empty"
check assert_eq "20260225.2" "$(uploadtool_compute_next_core_build_number "20260225.1")" "compute next future-date"

check assert_eq "20260220.4.0" "$(uploadtool_format_build_number_for_env "20260220.4" "dev")" "format for dev"
check assert_eq "20260220.4.1" "$(uploadtool_format_build_number_for_env "20260220.4" "prod")" "format for prod"
check assert_eq "" "$(uploadtool_format_build_number_for_env "" "dev")" "format empty"

return "${_failed}"
