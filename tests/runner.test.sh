#!/usr/bin/env bash

TEST_DESCRIPTION="Infra runner: mock external commands and tracing"

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPLOAD_TOOL_DIR="$(cd "${TEST_DIR}/.." && pwd)"

# shellcheck disable=SC1090
source "${UPLOAD_TOOL_DIR}/lib/infra/runner.sh"

_failed=0
check() {
  if ! "$@"; then
    _failed=1
  fi
}

_called=""
uploadtool_run_cmd_override() {
  _called="$*"
  return 0
}

check assert_eq "echo hello" "$(uploadtool_run_cmd echo hello; printf '%s' "$_called")" "runner override should capture command"

return "${_failed}"
