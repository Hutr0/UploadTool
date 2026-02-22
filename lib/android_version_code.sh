#!/usr/bin/env bash

uploadtool_compute_android_version_code() {
  local candidate="${1:-}"

  if [[ "$candidate" =~ ^([0-9]{8})\.([0-9]+)(\.[0-9]+)?$ ]]; then
    local date_part="${BASH_REMATCH[1]}"
    local n_part="${BASH_REMATCH[2]}"
    echo "$((10#${date_part} * 100 + 10#${n_part}))"
    return
  fi

  echo -n "$candidate" | tr -cd '0-9'
}
