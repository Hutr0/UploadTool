#!/usr/bin/env bash

TEST_DESCRIPTION="Release notes: формирование текста описания релиза"

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPLOAD_TOOL_DIR="$(cd "${TEST_DIR}/.." && pwd)"

# shellcheck disable=SC1090
source "${UPLOAD_TOOL_DIR}/lib/notes.sh"

_failed=0
check() {
  if ! "$@"; then
    _failed=1
  fi
}

check assert_eq "Тестовая сборка" "$(uploadtool_build_release_notes dev "")" "dev notes without changelog"
check assert_eq "Релизная сборка" "$(uploadtool_build_release_notes prod "")" "prod notes without changelog"

check assert_eq "Тестовая сборка" "$(uploadtool_build_release_notes dev "   ")" "spaces-only changelog treated as empty"

expected_dev_with=$'Тестовая сборка\n\nBug fixes'
check assert_eq "$expected_dev_with" "$(uploadtool_build_release_notes dev "Bug fixes")" "dev notes with changelog"

expected_prod_with=$'Релизная сборка\n\nImprovements'
check assert_eq "$expected_prod_with" "$(uploadtool_build_release_notes prod "Improvements")" "prod notes with changelog"

return "${_failed}"
