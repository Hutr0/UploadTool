#!/usr/bin/env bash

uploadtool_select_env_file() {
  local initial_env_file="${1:-}"
  local upload_config_dir="$2"

  if [[ -n "$initial_env_file" ]]; then
    printf '%s\n' "$initial_env_file"
    return 0
  fi

  if [[ -f "$upload_config_dir/release.env" ]]; then
    printf '%s\n' "$upload_config_dir/release.env"
    return 0
  fi

  printf '%s\n' ""
}

uploadtool_load_env_file_if_present() {
  local env_file="${1:-}"
  if [[ -n "$env_file" && -f "$env_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
  fi
}

uploadtool_load_wizard_env_if_present() {
  local wizard_env_file="$1"
  if [[ -f "$wizard_env_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$wizard_env_file"
    set +a
  fi
}

uploadtool_validate_config() {
  local upload_ios="${1:-${UPLOAD_IOS:-0}}"
  local upload_android="${2:-${UPLOAD_ANDROID:-0}}"

  local errors=()

  if [[ "$upload_ios" -eq 1 ]]; then
    local has_asc=0
    local has_apple_id=0

    local app_id="${IOS_APP_IDENTIFIER:-}"
    if [[ -z "$app_id" ]]; then
      app_id="${APP_IDENTIFIER:-}"
    fi
    if [[ -z "$app_id" ]]; then
      errors+=("$MSG_CONFIG_ERR_IOS_APP_ID_MISSING")
    fi

    if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_PATH:-}" ]]; then
      has_asc=1
    fi
    if [[ -n "${FASTLANE_USER:-}" && -n "${FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD:-}" ]]; then
      has_apple_id=1
    fi

    if [[ "$has_asc" -ne 1 && "$has_apple_id" -ne 1 ]]; then
      errors+=("$MSG_CONFIG_ERR_IOS_CREDS_MISSING")
    fi

    if [[ "$has_asc" -eq 1 ]]; then
      local p="${ASC_KEY_PATH}"
      if [[ "$p" == ~/* ]]; then p="$HOME/${p#~/}"; fi
      if [[ ! -f "$p" ]]; then
        errors+=($(printf "$MSG_CONFIG_ERR_IOS_ASC_KEY_MISSING" "$p"))
      fi
    fi
  fi

  if [[ "$upload_android" -eq 1 ]]; then
    local package_name="${ANDROID_PACKAGE_NAME:-}"
    if [[ -z "$package_name" ]]; then
      package_name="${APP_PACKAGE_NAME:-}"
    fi
    if [[ -z "$package_name" ]]; then
      errors+=("$MSG_CONFIG_ERR_ANDROID_PACKAGE_MISSING")
    fi

    local json_key_path="${PLAY_JSON_KEY_PATH:-}"
    if [[ -z "$json_key_path" ]]; then
      json_key_path="${SUPPLY_JSON_KEY:-}"
    fi
    if [[ -z "$json_key_path" ]]; then
      errors+=("$MSG_CONFIG_ERR_ANDROID_CREDS_MISSING")
    else
      if [[ "$json_key_path" == ~/* ]]; then json_key_path="$HOME/${json_key_path#~/}"; fi
      if [[ ! -f "$json_key_path" ]]; then
        errors+=($(printf "$MSG_CONFIG_ERR_ANDROID_KEY_FILE_MISSING" "$json_key_path"))
      fi
    fi
  fi

  if [[ "${#errors[@]}" -ne 0 ]]; then
    echo
    echo "$MSG_RUN_ERR_CONFIG_RELEASE_ENV"
    local e
    for e in "${errors[@]}"; do
      echo "   - $e"
    done
    return 1
  fi

  return 0
}
