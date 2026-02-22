#!/usr/bin/env bash

uploadtool_extract_core_build_number() {
  local v="${1:-}"

  if [[ "$v" =~ ^([0-9]{8})\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
    return
  fi
  if [[ "$v" =~ ^([0-9]{8})\.([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
    return
  fi
  if [[ "$v" =~ ^[0-9]+$ ]]; then
    echo "$v"
    return
  fi
  echo ""
}

uploadtool_bump_core_build_number_one() {
  local v
  v="$(uploadtool_extract_core_build_number "${1:-}")"
  if [[ -z "$v" ]]; then
    echo ""
    return
  fi
  if [[ "$v" =~ ^([0-9]{8})\.([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}.$((BASH_REMATCH[2] + 1))"
    return
  fi
  if [[ "$v" =~ ^[0-9]+$ ]]; then
    echo "$((v + 1))"
    return
  fi
  echo ""
}

uploadtool_compute_next_core_build_number() {
  local current
  current="$(uploadtool_extract_core_build_number "${1:-}")"
  local today
  today="${UPLOADTOOL_TODAY_YYYYMMDD:-$(date +%Y%m%d)}"

  if [[ "$current" =~ ^([0-9]{8})\.([0-9]+)$ ]]; then
    local cur_date="${BASH_REMATCH[1]}"
    local cur_counter="${BASH_REMATCH[2]}"

    if [[ "$cur_date" == "$today" ]]; then
      echo "${cur_date}.$((cur_counter + 1))"
      return
    fi

    if [[ "$cur_date" < "$today" ]]; then
      echo "${today}.1"
      return
    fi

    echo "${cur_date}.$((cur_counter + 1))"
    return
  fi

  echo "${today}.1"
}

uploadtool_format_build_number_for_env() {
  local core="${1:-}"
  local env="${2:-}"
  if [[ -z "$core" ]]; then
    echo ""
    return
  fi
  local x="0"
  if [[ "$env" == "prod" ]]; then
    x="1"
  fi
  echo "${core}.${x}"
}
