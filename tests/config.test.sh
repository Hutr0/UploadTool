#!/usr/bin/env bash

TEST_DESCRIPTION="Configs: select and load release.env/wizard.env (regression)"

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPLOAD_TOOL_DIR="$(cd "${TEST_DIR}/.." && pwd)"

# shellcheck disable=SC1090
source "${UPLOAD_TOOL_DIR}/lib/config.sh"

_failed=0
check() {
  if ! "$@"; then
    _failed=1
  fi
}

_tmp="$(mktemp -d)"

(
  # Priority: explicit ENV_FILE wins
  root="${_tmp}/repo1"
  cfg="${root}/UploadTool/config"
  mkdir -p "$cfg"
  printf 'A=1\n' > "${cfg}/release.env"
  printf 'A=2\n' > "${root}/.env.release"
  printf 'A=3\n' > "${_tmp}/explicit.env"

  selected="$(uploadtool_select_env_file "${_tmp}/explicit.env" "$cfg" "$root")"
  check assert_eq "${_tmp}/explicit.env" "$selected" "explicit env file should win"

  unset A || true
  uploadtool_load_env_file_if_present "$selected"
  check assert_eq "3" "${A:-}" "should load explicit env file"

  # Priority: UploadTool/config/release.env
  selected2="$(uploadtool_select_env_file "" "$cfg" "$root")"
  check assert_eq "${cfg}/release.env" "$selected2" "config/release.env should be selected"

  unset A || true
  uploadtool_load_env_file_if_present "$selected2"
  check assert_eq "1" "${A:-}" "should load config/release.env"

  # When no config/release.env, nothing is selected by default
  root2="${_tmp}/repo2"
  cfg2="${root2}/UploadTool/config"
  mkdir -p "$cfg2"

  selected3="$(uploadtool_select_env_file "" "$cfg2" "$root2")"
  check assert_eq "" "$selected3" "should return empty when no config/release.env"

  # Wizard env loading is optional
  wizard="${_tmp}/wizard.env"
  printf 'WIZARD_SKIP_TARGETS=1\n' > "$wizard"
  unset WIZARD_SKIP_TARGETS || true
  uploadtool_load_wizard_env_if_present "$wizard"
  check assert_eq "1" "${WIZARD_SKIP_TARGETS:-}" "should load wizard env"

  unset WIZARD_SKIP_TARGETS || true
  uploadtool_load_wizard_env_if_present "${_tmp}/missing_wizard.env"
  check assert_eq "" "${WIZARD_SKIP_TARGETS:-}" "missing wizard env should not set vars"
)

rm -rf "${_tmp}"

return "${_failed}"
