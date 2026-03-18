#!/usr/bin/env bash

TEST_DESCRIPTION="Infra time: mock sleep/wait"

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPLOAD_TOOL_DIR="$(cd "${TEST_DIR}/.." && pwd)"

# shellcheck disable=SC1090
source "${UPLOAD_TOOL_DIR}/lib/infra/time.sh"

_failed=0
check() {
  if ! "$@"; then
    _failed=1
  fi
}

_called=""
uploadtool_sleep_override() {
  _called="$*"
  return 0
}

uploadtool_sleep 5
check assert_eq "5" "$_called" "time override should capture sleep args"

return "${_failed}"
