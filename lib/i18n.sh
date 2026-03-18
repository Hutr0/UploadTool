#!/usr/bin/env bash

# UploadTool i18n bootstrap.
# Uses UPLOADTOOL_LANG (env or config) with fallback to English.

uploadtool_detect_lang() {
  local lang="${UPLOADTOOL_LANG:-}"

  # 1) Explicit env var has highest priority
  if [[ -z "$lang" ]]; then
    # 2) Explicit i18n env file if provided
    if [[ -n "${UPLOADTOOL_I18N_ENV_FILE:-}" && -f "$UPLOADTOOL_I18N_ENV_FILE" ]]; then
      set -a
      # shellcheck disable=SC1090
      source "$UPLOADTOOL_I18N_ENV_FILE"
      set +a
      lang="${UPLOADTOOL_LANG:-}"
    # 3) i18n.env inside config directory (same place as release.env/env.json/wizard.env)
    elif [[ -n "${UPLOADTOOL_CONFIG_DIR:-}" && -f "${UPLOADTOOL_CONFIG_DIR}/i18n.env" ]]; then
      set -a
      # shellcheck disable=SC1090
      source "${UPLOADTOOL_CONFIG_DIR}/i18n.env"
      set +a
      lang="${UPLOADTOOL_LANG:-}"
    fi
  fi

  # Fallback and validation
  case "$lang" in
    en|EN|En|eN)
      lang="en"
      ;;
    ru|RU|Ru|rU)
      lang="ru"
      ;;
    *)
      lang="en"
      ;;
  esac

  export UPLOADTOOL_LANG="$lang"
}

uploadtool_i18n_init() {
  uploadtool_detect_lang

  # UPLOAD_TOOL_DIR is defined in entry scripts (run.sh, init.sh)
  local i18n_dir="${UPLOAD_TOOL_DIR:-$SCRIPT_DIR}/lib/i18n"

  case "$UPLOADTOOL_LANG" in
    ru)
      # shellcheck disable=SC1090
      source "$i18n_dir/ru.sh"
      ;;
    *)
      # shellcheck disable=SC1090
      source "$i18n_dir/en.sh"
      ;;
  esac
}

