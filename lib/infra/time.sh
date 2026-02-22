#!/usr/bin/env bash

uploadtool_sleep() {
  if declare -F uploadtool_sleep_override >/dev/null 2>&1; then
    uploadtool_sleep_override "$@"
    return $?
  fi
  sleep "$@"
}
