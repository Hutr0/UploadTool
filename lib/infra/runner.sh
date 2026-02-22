#!/usr/bin/env bash

uploadtool_run_cmd() {
  if declare -F uploadtool_run_cmd_override >/dev/null 2>&1; then
    uploadtool_run_cmd_override "$@"
    return $?
  fi

  if [[ "${UPLOADTOOL_TRACE:-}" == "1" ]]; then
    printf '+ %q' "$1"
    shift
    for a in "$@"; do printf ' %q' "$a"; done
    printf '\n'
  fi

  "$@"
}

uploadtool_run_cmd_in_dir() {
  local dir="$1"
  shift
  (
    cd "$dir"
    uploadtool_run_cmd "$@"
  )
}
