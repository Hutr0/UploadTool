#!/usr/bin/env bash

uploadtool_profiles_dir() {
  local base
  base="${UPLOADTOOL_PROFILES_DIR:-}"
  if [[ -n "$base" ]]; then
    echo "$base"
    return 0
  fi
  if [[ -n "${HOME:-}" ]]; then
    echo "$HOME/.uploadtool/projects"
    return 0
  fi
  echo ""
}

uploadtool_default_profile_file() {
  local base
  base="${UPLOADTOOL_DEFAULT_PROFILE_FILE:-}"
  if [[ -n "$base" ]]; then
    echo "$base"
    return 0
  fi
  if [[ -n "${HOME:-}" ]]; then
    echo "$HOME/.uploadtool/default_project"
    return 0
  fi
  echo ""
}

uploadtool_profile_path() {
  local name="$1"
  local dir
  dir="$(uploadtool_profiles_dir)"
  [[ -n "$dir" ]] || return 1
  echo "$dir/$name.env"
}

uploadtool_profile_exists() {
  local name="$1"
  local path
  path="$(uploadtool_profile_path "$name" 2>/dev/null || true)"
  [[ -n "$path" && -f "$path" ]]
}

uploadtool_list_profiles() {
  local dir
  dir="$(uploadtool_profiles_dir)"
  [[ -n "$dir" && -d "$dir" ]] || return 0

  local f
  for f in "$dir"/*.env; do
    [[ -f "$f" ]] || continue
    basename "$f" .env
  done | sort
}

uploadtool_load_profile() {
  local name="$1"
  local path
  path="$(uploadtool_profile_path "$name")"
  if [[ ! -f "$path" ]]; then
    return 1
  fi
  # shellcheck disable=SC1090
  source "$path"
}

uploadtool_save_profile() {
  local name="$1"
  local project_root="$2"
  local config_dir="$3"
  local fastlane_root="$4"
  local env_key="$5"

  local dir
  dir="$(uploadtool_profiles_dir)"
  [[ -n "$dir" ]] || return 1
  mkdir -p "$dir"

  local path
  path="$(uploadtool_profile_path "$name")"

  cat >"$path" <<EOF
UPLOADTOOL_CLI_PROJECT_ROOT="$project_root"
UPLOADTOOL_CLI_CONFIG_DIR="$config_dir"
UPLOADTOOL_CLI_FASTLANE_ROOT="$fastlane_root"
UPLOADTOOL_CLI_ENV_JSON_ENV_KEY="$env_key"
EOF
}

uploadtool_get_default_profile() {
  local f
  f="$(uploadtool_default_profile_file)"
  [[ -n "$f" && -f "$f" ]] || return 0
  tr -d '\r\n' <"$f"
}

uploadtool_set_default_profile() {
  local name="$1"
  local f
  f="$(uploadtool_default_profile_file)"
  [[ -n "$f" ]] || return 1
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$name" >"$f"
}

uploadtool_prompt_select_profile() {
  local profiles
  profiles="$(uploadtool_list_profiles || true)"
  if [[ -z "$profiles" ]]; then
    echo ""
    return 0
  fi

  echo >&2
  echo "$MSG_PROFILES_SAVED_LIST_TITLE" >&2

  local i=0
  local arr=()
  local p
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    arr+=("$p")
    i=$((i + 1))
    echo "   $i) $p" >&2
  done <<<"$profiles"

  echo >&2
  local choice
  printf '%s' "$MSG_PROFILES_PROMPT_SELECT" >&2
  read -r choice
  choice="${choice:-1}"
  if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    echo "";
    return 0
  fi
  if (( choice < 1 || choice > ${#arr[@]} )); then
    echo "";
    return 0
  fi

  echo "${arr[$((choice - 1))]}"
}
