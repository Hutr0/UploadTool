#!/usr/bin/env bash

uploadtool_build_release_notes() {
  local env="$1"
  local changelog="${2:-}"

  local header
  if [[ "$env" == "prod" ]]; then
    header="Релизная сборка"
  else
    header="Тестовая сборка"
  fi

  if [[ -n "${changelog// /}" ]]; then
    printf '%s\n\n%s\n' "$header" "$changelog"
    return
  fi

  printf '%s\n' "$header"
}
