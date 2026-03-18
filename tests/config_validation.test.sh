#!/usr/bin/env bash

TEST_DESCRIPTION="Fail-fast: validation of required fields for iOS/Android uploads"

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPLOAD_TOOL_DIR="$(cd "${TEST_DIR}/.." && pwd)"

# shellcheck disable=SC1090
source "${UPLOAD_TOOL_DIR}/lib/i18n/en.sh"
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
  # iOS: missing creds -> fail
  unset ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH FASTLANE_USER FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD || true
  unset IOS_APP_IDENTIFIER APP_IDENTIFIER || true
  if uploadtool_validate_config 1 0; then
    echo "validate_config should fail when iOS upload enabled and creds missing" >&2
    exit 1
  fi

  # iOS: ASC creds but file missing -> fail
  ASC_KEY_ID="K"
  ASC_ISSUER_ID="I"
  ASC_KEY_PATH="${_tmp}/missing.p8"
  IOS_APP_IDENTIFIER="com.example.app"
  export ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH
  export IOS_APP_IDENTIFIER
  if uploadtool_validate_config 1 0; then
    echo "validate_config should fail when ASC_KEY_PATH missing" >&2
    exit 1
  fi

  # iOS: ASC creds and file exists -> ok
  printf 'key' > "${_tmp}/key.p8"
  ASC_KEY_PATH="${_tmp}/key.p8"
  export ASC_KEY_PATH
  uploadtool_validate_config 1 0 || exit 1

  # Android: missing creds -> fail
  unset PLAY_JSON_KEY_PATH SUPPLY_JSON_KEY || true
  unset ANDROID_PACKAGE_NAME APP_PACKAGE_NAME || true
  if uploadtool_validate_config 0 1; then
    echo "validate_config should fail when Android upload enabled and creds missing" >&2
    exit 1
  fi

  # Android: path set but file missing -> fail
  PLAY_JSON_KEY_PATH="${_tmp}/missing.json"
  ANDROID_PACKAGE_NAME="com.example.app"
  export PLAY_JSON_KEY_PATH
  export ANDROID_PACKAGE_NAME
  if uploadtool_validate_config 0 1; then
    echo "validate_config should fail when PLAY_JSON_KEY_PATH missing" >&2
    exit 1
  fi

  # Android: SUPPLY_JSON_KEY works too
  unset PLAY_JSON_KEY_PATH || true
  SUPPLY_JSON_KEY="${_tmp}/svc.json"
  export SUPPLY_JSON_KEY
  printf '{}' > "${_tmp}/svc.json"
  uploadtool_validate_config 0 1 || exit 1

  # Both enabled: should fail if either side missing
  unset ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH FASTLANE_USER FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD || true
  unset IOS_APP_IDENTIFIER APP_IDENTIFIER || true
  SUPPLY_JSON_KEY="${_tmp}/svc.json"
  export SUPPLY_JSON_KEY
  if uploadtool_validate_config 1 1; then
    echo "validate_config should fail if iOS missing even when Android OK" >&2
    exit 1
  fi
)
rc=$?
if [[ "$rc" -ne 0 ]]; then
  _failed=1
fi

rm -rf "${_tmp}"

return "${_failed}"
