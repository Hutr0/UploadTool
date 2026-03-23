#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${BASH_VERSION:-}" ]]; then
  exec bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

UPLOAD_TOOL_DIR="$SCRIPT_DIR"
if [[ ! -d "$UPLOAD_TOOL_DIR/lib" ]]; then
  echo "❌ Could not find lib directory next to run.sh: $UPLOAD_TOOL_DIR/lib" >&2
  exit 1
fi

source "$UPLOAD_TOOL_DIR/lib/i18n.sh"
uploadtool_i18n_init

# CLI overrides
PROJECT_ROOT_ARG=""
CONFIG_DIR_ARG=""
FASTLANE_ROOT_ARG=""
PROJECT_PROFILE_ARG=""
CLI_ENV_FILE="${UPLOADTOOL_CLI_ENV_FILE:-}"
ENV_FILE="${ENV_FILE:-}"

INIT_FORCE="${UPLOADTOOL_INIT_FORCE:-0}"
INIT_SAVE_DEFAULTS="${UPLOADTOOL_INIT_SAVE_DEFAULTS:-0}"
INIT_LANG="${UPLOADTOOL_INIT_LANG:-}"

declare -a PARSED_REST=()
parse_cli_overrides() {
  while [[ "${1:-}" == --* ]]; do
    case "${1:-}" in
      --env-file)
        ENV_FILE="${2:-}"
        shift 2
        ;;
      --project-root)
        PROJECT_ROOT_ARG="${2:-}"
        shift 2
        ;;
      --config-dir)
        CONFIG_DIR_ARG="${2:-}"
        shift 2
        ;;
      --fastlane-root)
        FASTLANE_ROOT_ARG="${2:-}"
        shift 2
        ;;
      --env-json-env-key|--env-key)
        export UPLOADTOOL_ENV_JSON_ENV_KEY="${2:-}"
        shift 2
        ;;
      --project)
        PROJECT_PROFILE_ARG="${2:-}"
        shift 2
        ;;
      --cli-env-file)
        CLI_ENV_FILE="${2:-}"
        shift 2
        ;;
      --save-defaults)
        INIT_SAVE_DEFAULTS="1"
        shift 1
        ;;
      --no-save-defaults)
        INIT_SAVE_DEFAULTS="0"
        shift 1
        ;;
      --lang)
        INIT_LANG="${2:-}"
        shift 2
        ;;
      --force)
        INIT_FORCE="1"
        shift 1
        ;;
      --no-force)
        INIT_FORCE="0"
        shift 1
        ;;
      *)
        break
        ;;
    esac
  done
  PARSED_REST=("$@")
}

uploadtool_write_cli_env_file() {
  local file_path="$1"
  local project_root="$2"
  local config_dir="$3"
  local fastlane_root="${4:-}"
  local env_key="${5:-}"
  local lang="${6:-}"

  local dir_name
  dir_name="$(dirname "$file_path")"
  mkdir -p "$dir_name"

  cat >"$file_path" <<EOF
UPLOADTOOL_CLI_PROJECT_ROOT="$project_root"
UPLOADTOOL_CLI_CONFIG_DIR="$config_dir"
EOF

  if [[ -n "$fastlane_root" ]]; then
    printf '%s\n' "UPLOADTOOL_CLI_FASTLANE_ROOT=\"$fastlane_root\"" >>"$file_path"
  fi
  if [[ -n "$env_key" ]]; then
    printf '%s\n' "UPLOADTOOL_CLI_ENV_JSON_ENV_KEY=\"$env_key\"" >>"$file_path"
  fi
  if [[ -n "$lang" ]]; then
    printf '%s\n' "UPLOADTOOL_LANG=\"$lang\"" >>"$file_path"
  fi
}

uploadtool_write_i18n_env_file() {
  local file_path="$1"
  local lang="$2"

  local dir_name
  dir_name="$(dirname "$file_path")"
  mkdir -p "$dir_name"

  printf 'UPLOADTOOL_LANG=%s\n' "$lang" >"$file_path"
}

uploadtool_cli_init() {
  if [[ "${#@}" -ne 0 ]]; then
    printf "$MSG_RUN_ERR_UNKNOWN_INIT_ARGS\n" "$*" >&2
    return 1
  fi

  local project_root
  project_root="${PROJECT_ROOT_ARG:-${UPLOADTOOL_PROJECT_ROOT:-${UPLOADTOOL_CLI_PROJECT_ROOT:-}}}"
  if [[ -z "$project_root" ]]; then
    if [[ -f "${PWD}/pubspec.yaml" ]]; then
      project_root="$PWD"
    else
      printf '%s: ' "$MSG_INIT_PROMPT_PROJECT_ROOT"
      read -r project_root
    fi
  fi
  if [[ -z "$project_root" ]]; then
    echo "$MSG_INIT_ERR_PROJECT_PATH_EMPTY" >&2
    return 1
  fi
  if [[ ! -d "$project_root" ]]; then
    printf "$MSG_INIT_ERR_PROJECT_DIR_NOT_FOUND\n" "$project_root" >&2
    return 1
  fi
  project_root="$(cd "$project_root" && pwd)"
  if [[ ! -f "$project_root/pubspec.yaml" ]]; then
    printf "$MSG_INIT_ERR_PUBSPEC_NOT_FOUND\n" "$project_root" >&2
    return 1
  fi

  local config_dir
  config_dir="${CONFIG_DIR_ARG:-${UPLOADTOOL_CONFIG_DIR:-${UPLOADTOOL_CLI_CONFIG_DIR:-$project_root/.uploadtool}}}"
  if [[ "$config_dir" != /* ]]; then
    config_dir="$project_root/$config_dir"
  fi

  mkdir -p "$config_dir"
  config_dir="$(cd "$config_dir" && pwd)"

  local src_dir
  src_dir="$UPLOAD_TOOL_DIR/config"
  if [[ ! -d "$src_dir" ]]; then
    printf "$MSG_RUN_INIT_TEMPLATE_DIR_NOT_FOUND\n" "$src_dir" >&2
    return 1
  fi

  local init_lang
  init_lang="${INIT_LANG:-${UPLOADTOOL_LANG:-en}}"
  init_lang="$(printf '%s' "$init_lang" | tr '[:upper:]' '[:lower:]')"
  case "$init_lang" in
    ru)
      init_lang="ru"
      ;;
    *)
      init_lang="en"
      ;;
  esac

  echo
  echo "🧰 UploadTool init"
  echo "   Project: $project_root"
  echo "   Config:  $config_dir"

  _copy_example() {
    local src="$1"
    local dst="$2"
    local label="$3"

    if [[ -f "$dst" && "${INIT_FORCE:-0}" != "1" ]]; then
      printf "$MSG_RUN_INIT_TEMPLATE_EXISTS\n" "$label" "$dst"
      return 0
    fi
    cp -f "$src" "$dst"
    echo "   ➕ $label: $dst"
  }

  _copy_example "$src_dir/env.json.example" "$config_dir/env.json" "env.json"
  _copy_example "$src_dir/release.env.example" "$config_dir/release.env" "release.env"
  _copy_example "$src_dir/wizard.env.example" "$config_dir/wizard.env" "wizard.env"
  uploadtool_write_i18n_env_file "$config_dir/i18n.env" "$init_lang"
  printf "$MSG_RUN_INIT_I18N_SAVED\n" "$config_dir/i18n.env"

  if [[ "${INIT_SAVE_DEFAULTS:-0}" == "1" ]]; then
    local cli_file
    cli_file="$CLI_ENV_FILE"
    if [[ -z "$cli_file" ]]; then
      cli_file="$config_dir/cli.env"
    fi
    if [[ -z "$cli_file" ]]; then
      echo "$MSG_RUN_INIT_ERR_CLI_ENV_PATH" >&2
      return 1
    fi

    uploadtool_write_cli_env_file "$cli_file" "$project_root" "$config_dir" "${FASTLANE_ROOT_ARG:-}" "${UPLOADTOOL_ENV_JSON_ENV_KEY:-}" "$init_lang"
    printf "$MSG_RUN_INIT_CLI_DEFAULTS_SAVED\n" "$cli_file"
  fi

  echo
  echo "$MSG_RUN_INIT_DONE_HEADER"
  printf "$MSG_RUN_INIT_DONE_RELEASE_ENV_ITEM\n" "$config_dir"
  echo
  echo "$MSG_RUN_INIT_RUN_HEADER"
  printf "$MSG_RUN_INIT_RUN_COMMAND\n" "$UPLOAD_TOOL_DIR" "$project_root" "$config_dir"
  echo
  return 0
}

parse_cli_overrides "$@"
if (( ${#PARSED_REST[@]} )); then
  set -- "${PARSED_REST[@]}"
else
  set --
fi

source "$UPLOAD_TOOL_DIR/lib/profiles.sh"
source "$UPLOAD_TOOL_DIR/lib/i18n.sh"
uploadtool_i18n_init

# Load explicit cli.env early (flag/env) to allow overriding project/config paths before profile selection.
if [[ -n "$CLI_ENV_FILE" && -f "$CLI_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CLI_ENV_FILE"
fi

COMMAND="${1:-}"
if [[ "$COMMAND" == "init" || "$COMMAND" == "setup" ]]; then
  shift
  parse_cli_overrides "$@"
  if (( ${#PARSED_REST[@]} )); then
    set -- "${PARSED_REST[@]}"
  else
    set --
  fi

  uploadtool_cli_init "$@"
  exit $?
fi

# Flutter project root (ROOT_DIR)
# Use internal variable only to avoid picking up an unrelated project.
PROJECT_ROOT="${PROJECT_ROOT_ARG:-${UPLOADTOOL_CLI_PROJECT_ROOT:-${UPLOADTOOL_PROJECT_ROOT:-}}}"

if [[ -z "$PROJECT_ROOT" && -n "$PROJECT_PROFILE_ARG" ]]; then
  if uploadtool_load_profile "$PROJECT_PROFILE_ARG"; then
    export UPLOADTOOL_SELECTED_PROJECT="$PROJECT_PROFILE_ARG"
    PROJECT_ROOT="${UPLOADTOOL_CLI_PROJECT_ROOT:-}"
    if [[ -z "$CONFIG_DIR_ARG" && -z "${UPLOADTOOL_CONFIG_DIR:-}" && -n "${UPLOADTOOL_CLI_CONFIG_DIR:-}" ]]; then
      CONFIG_DIR_ARG="$UPLOADTOOL_CLI_CONFIG_DIR"
    fi
    if [[ -z "$FASTLANE_ROOT_ARG" && -z "${UPLOADTOOL_FASTLANE_ROOT:-}" && -n "${UPLOADTOOL_CLI_FASTLANE_ROOT:-}" ]]; then
      FASTLANE_ROOT_ARG="$UPLOADTOOL_CLI_FASTLANE_ROOT"
    fi
    if [[ -z "${UPLOADTOOL_ENV_JSON_ENV_KEY:-}" && -n "${UPLOADTOOL_CLI_ENV_JSON_ENV_KEY:-}" ]]; then
      export UPLOADTOOL_ENV_JSON_ENV_KEY="$UPLOADTOOL_CLI_ENV_JSON_ENV_KEY"
    fi
  else
    printf "$MSG_RUN_ERR_PROFILE_LOAD_FAILED\n" "$PROJECT_PROFILE_ARG" >&2
    exit 1
  fi
fi

if [[ -z "$PROJECT_ROOT" ]]; then
  default_candidate="$(cd "$UPLOAD_TOOL_DIR/.." && pwd)"
  if [[ -f "$default_candidate/pubspec.yaml" ]]; then
    PROJECT_ROOT="$default_candidate"
  elif [[ -f "${PWD}/pubspec.yaml" ]]; then
    PROJECT_ROOT="$PWD"
  fi
fi

if [[ -z "$PROJECT_ROOT" ]]; then
  selected_profile=""
  if [[ -n "$PROJECT_PROFILE_ARG" ]]; then
    selected_profile="$PROJECT_PROFILE_ARG"
  else
    selected_profile="$(uploadtool_get_default_profile || true)"
  fi

  if [[ -z "$selected_profile" ]]; then
    if [[ -t 0 ]]; then
      selected_profile="$(uploadtool_prompt_select_profile || true)"
    fi
  fi

  if [[ -n "$selected_profile" ]]; then
    if uploadtool_load_profile "$selected_profile"; then
      export UPLOADTOOL_SELECTED_PROJECT="$selected_profile"
      PROJECT_ROOT="${UPLOADTOOL_CLI_PROJECT_ROOT:-}"
      if [[ -z "$CONFIG_DIR_ARG" && -z "${UPLOADTOOL_CONFIG_DIR:-}" && -n "${UPLOADTOOL_CLI_CONFIG_DIR:-}" ]]; then
        CONFIG_DIR_ARG="$UPLOADTOOL_CLI_CONFIG_DIR"
      fi
      if [[ -z "$FASTLANE_ROOT_ARG" && -z "${UPLOADTOOL_FASTLANE_ROOT:-}" && -n "${UPLOADTOOL_CLI_FASTLANE_ROOT:-}" ]]; then
        FASTLANE_ROOT_ARG="$UPLOADTOOL_CLI_FASTLANE_ROOT"
      fi
      if [[ -z "${UPLOADTOOL_ENV_JSON_ENV_KEY:-}" && -n "${UPLOADTOOL_CLI_ENV_JSON_ENV_KEY:-}" ]]; then
        export UPLOADTOOL_ENV_JSON_ENV_KEY="$UPLOADTOOL_CLI_ENV_JSON_ENV_KEY"
      fi
    else
      printf "$MSG_RUN_ERR_PROFILE_LOAD_FAILED\n" "$selected_profile" >&2
      exit 1
    fi
  fi
fi

if [[ -z "$PROJECT_ROOT" ]]; then
  PROJECT_ROOT="${UPLOADTOOL_CLI_PROJECT_ROOT:-}"
fi
if [[ -z "$PROJECT_ROOT" ]]; then
  echo "$MSG_RUN_ERR_PROJECT_ROOT_UNRESOLVED" >&2
  echo "$MSG_RUN_HINT_SET_PROJECT_ROOT" >&2
  echo "$MSG_RUN_HINT_USE_PROFILE" >&2
  exit 1
fi

ROOT_DIR="$(cd "$PROJECT_ROOT" && pwd)"
export ROOT_DIR
export UPLOADTOOL_PROJECT_ROOT="$ROOT_DIR"
cd "$ROOT_DIR"

if [[ "${UPLOADTOOL_SKIP_SAFE_PATH:-}" != "1" ]]; then
  export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
fi

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf "$MSG_RUN_ERR_DEPENDENCY_NOT_FOUND\n" "$cmd" >&2
    exit 1
  fi
}

require_cmd python3
require_cmd flutter

# Config/logs/state are tied to a specific Flutter project, so default to <project>/.uploadtool.
UPLOAD_CONFIG_DIR="${CONFIG_DIR_ARG:-${UPLOADTOOL_CONFIG_DIR:-${UPLOADTOOL_CLI_CONFIG_DIR:-}}}"
UPLOAD_CONFIG_DIR_DEFAULTED="0"
if [[ -z "$UPLOAD_CONFIG_DIR" ]]; then
  UPLOAD_CONFIG_DIR_DEFAULTED="1"
  if [[ -f "$ROOT_DIR/pubspec.yaml" ]]; then
    UPLOAD_CONFIG_DIR="$ROOT_DIR/.uploadtool"
  else
    UPLOAD_CONFIG_DIR="$UPLOAD_TOOL_DIR/config"
  fi
fi

# Convert relative config path to absolute (relative to ROOT_DIR).
if [[ "$UPLOAD_CONFIG_DIR" != /* ]]; then
  UPLOAD_CONFIG_DIR="$ROOT_DIR/$UPLOAD_CONFIG_DIR"
fi

if [[ -z "$CLI_ENV_FILE" ]]; then
  if [[ -f "$UPLOAD_CONFIG_DIR/cli.env" ]]; then
    CLI_ENV_FILE="$UPLOAD_CONFIG_DIR/cli.env"
  elif [[ -n "${HOME:-}" && -f "$HOME/.uploadtool/cli.env" ]]; then
    CLI_ENV_FILE="$HOME/.uploadtool/cli.env"
  fi
fi

if [[ -n "$CLI_ENV_FILE" && -f "$CLI_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CLI_ENV_FILE"
fi

if [[ -z "${UPLOADTOOL_ENV_JSON_ENV_KEY:-}" && -n "${UPLOADTOOL_CLI_ENV_JSON_ENV_KEY:-}" ]]; then
  export UPLOADTOOL_ENV_JSON_ENV_KEY="$UPLOADTOOL_CLI_ENV_JSON_ENV_KEY"
fi

if [[ ! -d "$UPLOAD_CONFIG_DIR" ]]; then
  # Auto-create default project config directory; otherwise fail-fast.
  if [[ "$UPLOAD_CONFIG_DIR_DEFAULTED" == "1" && "$UPLOAD_CONFIG_DIR" == "$ROOT_DIR/.uploadtool" ]]; then
    mkdir -p "$UPLOAD_CONFIG_DIR"
  else
    printf "$MSG_RUN_ERR_CONFIG_DIR_NOT_FOUND\n" "$UPLOAD_CONFIG_DIR" >&2
    echo "$MSG_RUN_ERR_CONFIG_DIR_HINT_CREATE" >&2
    exit 1
  fi
fi

# Canonicalize config path for consistent printing/comparison.
UPLOAD_CONFIG_DIR="$(cd "$UPLOAD_CONFIG_DIR" && pwd)"
export UPLOADTOOL_CONFIG_DIR="$UPLOAD_CONFIG_DIR"

# Local FASTLANE_SESSION storage (per project, gitignored).
FASTLANE_SESSION_FILE="$UPLOAD_CONFIG_DIR/fastlane_session.env"

runtime_root="$UPLOAD_TOOL_DIR"
if [[ "$UPLOAD_CONFIG_DIR" != "$UPLOAD_TOOL_DIR/config" ]]; then
  runtime_root="$UPLOAD_CONFIG_DIR"
fi

UPLOAD_LOG_DIR="${UPLOADTOOL_LOG_DIR:-$runtime_root/logs}"
UPLOAD_STATE_DIR="${UPLOADTOOL_STATE_DIR:-$runtime_root/state}"

default_fastlane_root="$UPLOAD_TOOL_DIR/fastlane"
if [[ ! -f "$default_fastlane_root/Gemfile" ]]; then
  default_fastlane_root="$ROOT_DIR/ios"
fi
UPLOADTOOL_FASTLANE_ROOT="${FASTLANE_ROOT_ARG:-${UPLOADTOOL_FASTLANE_ROOT:-${UPLOADTOOL_CLI_FASTLANE_ROOT:-$default_fastlane_root}}}"
export UPLOADTOOL_FASTLANE_ROOT

source "$UPLOAD_TOOL_DIR/lib/versioning.sh"
source "$UPLOAD_TOOL_DIR/lib/infra/runner.sh"
source "$UPLOAD_TOOL_DIR/lib/infra/time.sh"
source "$UPLOAD_TOOL_DIR/lib/workflow.sh"
source "$UPLOAD_TOOL_DIR/lib/env_json.sh"
source "$UPLOAD_TOOL_DIR/lib/android_version_code.sh"
source "$UPLOAD_TOOL_DIR/lib/notes.sh"
source "$UPLOAD_TOOL_DIR/lib/config.sh"
source "$UPLOAD_TOOL_DIR/lib/i18n.sh"
uploadtool_i18n_init

TARGET_ARG="${1:-}"
if [[ "$TARGET_ARG" == "ios" || "$TARGET_ARG" == "android" || "$TARGET_ARG" == "both" ]]; then
  shift
else
  TARGET_ARG=""
fi

# release.env is the single source of credentials/build settings.
ENV_FILE="$(uploadtool_select_env_file "${ENV_FILE:-}" "$UPLOAD_CONFIG_DIR")"
uploadtool_load_env_file_if_present "$ENV_FILE"

# Optional wizard behavior overrides (defaults/skip flags). See config/wizard.env.example
uploadtool_load_wizard_env_if_present "$UPLOAD_CONFIG_DIR/wizard.env"

pubspec_version_line="$(sed -nE 's/^version:[[:space:]]*([^[:space:]]+).*/\1/p' pubspec.yaml | head -n 1 || true)"
default_build_name=""
default_build_number=""
if [[ -n "$pubspec_version_line" ]]; then
  default_build_name="${pubspec_version_line%%+*}"
  if [[ "$pubspec_version_line" == *"+"* ]]; then
    default_build_number="${pubspec_version_line##*+}"
  fi
fi

echo
echo "$MSG_RUN_WIZARD_HEADER"
printf "$MSG_RUN_WIZARD_PROJECT\n" "$ROOT_DIR"
printf "$MSG_RUN_WIZARD_TOOL\n" "$UPLOAD_TOOL_DIR"
printf "$MSG_RUN_WIZARD_CONFIG\n" "$UPLOAD_CONFIG_DIR"
printf "$MSG_RUN_WIZARD_LOGS\n" "$UPLOAD_LOG_DIR"
printf "$MSG_RUN_WIZARD_STATE\n" "$UPLOAD_STATE_DIR"
printf "$MSG_RUN_WIZARD_FASTLANE\n" "$UPLOADTOOL_FASTLANE_ROOT"
printf "$MSG_RUN_WIZARD_RELEASE\n" "${ENV_FILE:-<none>}"
printf "$MSG_RUN_WIZARD_ENV_KEY\n" "${UPLOADTOOL_ENV_JSON_ENV_KEY:-APP_ENV}"
if [[ -f "$UPLOAD_CONFIG_DIR/wizard.env" ]]; then
  printf "$MSG_RUN_WIZARD_WIZARD_ENV\n" "$UPLOAD_CONFIG_DIR/wizard.env"
fi
echo

targets="${RELEASE_TARGETS:-}"
if [[ -z "$targets" ]]; then
  targets="$TARGET_ARG"
fi

# Reuse saved FASTLANE_SESSION before any fastlane calls.
if [[ -f "$FASTLANE_SESSION_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$FASTLANE_SESSION_FILE"
fi

# Default “what to build” choice (1=ios, 2=android, 3=both)
wizard_default_targets="${WIZARD_DEFAULT_TARGETS:-both}"
default_t="3"
[[ "$wizard_default_targets" == "ios" ]] && default_t="1"
[[ "$wizard_default_targets" == "android" ]] && default_t="2"

if [[ -n "${WIZARD_SKIP_TARGETS:-}" && "${WIZARD_SKIP_TARGETS}" == "1" ]]; then
  targets="$wizard_default_targets"
  printf "$MSG_RUN_TARGETS_FROM_WIZARD_ENV\n" "$targets"
elif [[ -z "$targets" ]]; then
  echo "$MSG_RUN_TARGETS_QUESTION_TITLE"
  echo "$MSG_RUN_TARGETS_IOS_OPTION"
  echo "$MSG_RUN_TARGETS_ANDROID_OPTION"
  echo "$MSG_RUN_TARGETS_BOTH_OPTION"
  printf "$MSG_RUN_TARGETS_PROMPT_CHOICE" "$default_t"
  read -r t
  t="${t:-$default_t}"
  case "$t" in
    1) targets="ios" ;;
    2) targets="android" ;;
    3) targets="both" ;;
    *) printf "$MSG_RUN_TARGETS_ERR_INVALID_CHOICE\n" "$t"; exit 1 ;;
  esac
fi

echo
ENV_JSON="$UPLOAD_CONFIG_DIR/env.json"
CURRENT_ENV=""
ENV_JSON_ENV_KEY="${UPLOADTOOL_ENV_JSON_ENV_KEY:-}"
if [[ -f "$ENV_JSON" ]]; then
  if [[ -z "$ENV_JSON_ENV_KEY" ]]; then
    ENV_JSON_ENV_KEY="$(python3 -c 'import json,sys
p=sys.argv[1]
try:
  d=json.load(open(p,"r",encoding="utf-8"))
except Exception:
  d={}
k=""
if isinstance(d,dict):
  if "APP_ENV" in d: k="APP_ENV"
  elif "CHOYS_ENV" in d: k="CHOYS_ENV"
print(k)
' "$ENV_JSON" 2>/dev/null || true)"
  fi

  CURRENT_ENV="$(python3 -c 'import json,sys
p=sys.argv[1]
key=sys.argv[2]
try:
  d=json.load(open(p,"r",encoding="utf-8"))
except Exception:
  d={}
v=""
if isinstance(d,dict):
  if key and key in d and d.get(key):
    v=d.get(key) or ""
  else:
    v=d.get("APP_ENV") or d.get("CHOYS_ENV") or ""
print(v)
' "$ENV_JSON" "$ENV_JSON_ENV_KEY" 2>/dev/null || true)"
fi
if [[ -z "$ENV_JSON_ENV_KEY" ]]; then
  ENV_JSON_ENV_KEY="APP_ENV"
fi
export UPLOADTOOL_ENV_JSON_ENV_KEY="$ENV_JSON_ENV_KEY"
if [[ "$CURRENT_ENV" != "dev" && "$CURRENT_ENV" != "prod" ]]; then
  CURRENT_ENV="prod"
fi

write_env_json() {
  local env="$1"
  write_env_to_file "$ENV_JSON" "$env"
}

# Write env key (and any other keys from current ENV_JSON) to a given path.
# Used so each build (dev/prod) has its own dart_defines file and never reads a shared file that gets overwritten.
write_env_to_file() {
  local path="$1"
  local env="$2"
  uploadtool_write_env_to_file "$path" "$env"
}

extract_core_build_number() {
  # Accept:
  # - YYYYMMDD.N.X  -> core YYYYMMDD.N
  # - YYYYMMDD.N    -> core YYYYMMDD.N
  # - integer       -> core integer
  uploadtool_extract_core_build_number "${1:-}"
}

bump_core_build_number_one() {
  local v
  v="$(uploadtool_bump_core_build_number_one "${1:-}")"
  printf '%s\n' "$v"
}

# Default environment selection (1=dev, 2=prod, 3=both)
wizard_default_env="${WIZARD_DEFAULT_ENV:-both}"
default_e="3"
[[ "$wizard_default_env" == "dev" ]] && default_e="1"
[[ "$wizard_default_env" == "prod" ]] && default_e="2"

if [[ -n "${WIZARD_SKIP_ENV:-}" && "${WIZARD_SKIP_ENV}" == "1" ]]; then
  ENV_TARGETS="$wizard_default_env"
  printf "$MSG_RUN_ENV_FROM_WIZARD_ENV\n" "$ENV_TARGETS"
else
  echo "$MSG_RUN_ENV_TITLE"
  echo "$MSG_RUN_ENV_DEV_ONLY"
  echo "$MSG_RUN_ENV_PROD_ONLY"
  echo "$MSG_RUN_ENV_BOTH"
  printf "$MSG_RUN_ENV_PROMPT_CHOICE" "$default_e"
  read -r env_choice
  env_choice="${env_choice:-$default_e}"
  case "$env_choice" in
    1) ENV_TARGETS="dev" ;;
    2) ENV_TARGETS="prod" ;;
    3) ENV_TARGETS="both" ;;
    *) printf "$MSG_RUN_ENV_ERR_INVALID_CHOICE\n" "$env_choice"; exit 1 ;;
  esac
fi

echo
echo "$MSG_RUN_BUILD_VERSION_TITLE"
printf "$MSG_RUN_BUILD_NAME_PROMPT" "${default_build_name:-from pubspec.yaml}"
read -r build_name
printf "$MSG_RUN_BUILD_NUMBER_PROMPT" "${default_build_number:-from pubspec.yaml}"
read -r build_number

compute_next_core_build_number() {
  uploadtool_compute_next_core_build_number "${1:-}"
}

format_build_number_for_env() {
  uploadtool_format_build_number_for_env "${1:-}" "${2:-}"
}

FINAL_BUILD_NAME="$default_build_name"
if [[ -n "${build_name// /}" ]]; then
  FINAL_BUILD_NAME="$build_name"
fi
if [[ -z "$FINAL_BUILD_NAME" ]]; then
  echo "$MSG_RUN_ERR_BUILD_NAME_EMPTY"
  exit 1
fi
export BUILD_NAME="$FINAL_BUILD_NAME"

BASE_CORE_BUILD_NUMBER=""
if [[ -n "${build_number// /}" ]]; then
  BASE_CORE_BUILD_NUMBER="$(extract_core_build_number "$build_number")"
else
  BASE_CORE_BUILD_NUMBER="$(compute_next_core_build_number "$default_build_number")"
fi
if [[ -z "$BASE_CORE_BUILD_NUMBER" ]]; then
  echo "$MSG_RUN_ERR_BUILD_NUMBER_EMPTY"
  exit 1
fi

DEV_BUILD_NUMBER=""
PROD_BUILD_NUMBER=""
if [[ "$ENV_TARGETS" == "both" ]]; then
  dev_core="$BASE_CORE_BUILD_NUMBER"
  prod_core="$(bump_core_build_number_one "$dev_core")"
  if [[ -z "$prod_core" ]]; then
    printf "$MSG_RUN_ERR_BUILD_NUMBER_BOTH_INVALID\n" "$BASE_CORE_BUILD_NUMBER"
    exit 1
  fi
  DEV_BUILD_NUMBER="$(format_build_number_for_env "$dev_core" "dev")"
  PROD_BUILD_NUMBER="$(format_build_number_for_env "$prod_core" "prod")"
else
  DEV_BUILD_NUMBER="$(format_build_number_for_env "$BASE_CORE_BUILD_NUMBER" "$ENV_TARGETS")"
fi

BUILD_IOS=0
BUILD_ANDROID=0
UPLOAD_IOS=0
UPLOAD_ANDROID=0

case "$targets" in
  ios) BUILD_IOS=1 ;;
  android) BUILD_ANDROID=1 ;;
  both) BUILD_IOS=1; BUILD_ANDROID=1 ;;
  *) printf "$MSG_RUN_ERR_TARGETS_INVALID\n" "$targets"; exit 1 ;;
esac

echo
echo "$MSG_RUN_UPLOAD_TITLE"
UPLOAD_IOS=0
UPLOAD_ANDROID=0
wizard_upload_ios="${WIZARD_DEFAULT_UPLOAD_IOS:-1}"
wizard_upload_android="${WIZARD_DEFAULT_UPLOAD_ANDROID:-1}"
if [[ -n "${WIZARD_SKIP_UPLOAD_PROMPTS:-}" && "${WIZARD_SKIP_UPLOAD_PROMPTS}" == "1" ]]; then
  [[ "$BUILD_IOS" -eq 1 ]] && UPLOAD_IOS="$wizard_upload_ios"
  [[ "$BUILD_ANDROID" -eq 1 ]] && UPLOAD_ANDROID="$wizard_upload_android"
  printf "$MSG_RUN_UPLOAD_WIZARD_SKIPPED\n" "$UPLOAD_IOS" "$UPLOAD_ANDROID"
else
  if [[ "$BUILD_IOS" -eq 1 ]]; then
    def_ios="Y"; [[ "$wizard_upload_ios" == "0" ]] && def_ios="n"
    printf "$MSG_RUN_UPLOAD_IOS_PROMPT" "$(echo "$def_ios" | tr '[:upper:]' '[:lower:]')"
    read -r ans
    case "${ans:-$def_ios}" in n|N|no|NO) UPLOAD_IOS=0 ;; *) UPLOAD_IOS=1 ;; esac
  fi
  if [[ "$BUILD_ANDROID" -eq 1 ]]; then
    def_android="Y"; [[ "$wizard_upload_android" == "0" ]] && def_android="n"
    printf "$MSG_RUN_UPLOAD_ANDROID_PROMPT" "$(echo "$def_android" | tr '[:upper:]' '[:lower:]')"
    read -r ans
    case "${ans:-$def_android}" in n|N|no|NO) UPLOAD_ANDROID=0 ;; *) UPLOAD_ANDROID=1 ;; esac
  fi
fi

uploadtool_validate_config "$UPLOAD_IOS" "$UPLOAD_ANDROID"

echo
echo "$MSG_RUN_CHANGELOG_TITLE"
printf "%s" "$MSG_RUN_CHANGELOG_PROMPT"
read -r changelog

echo
wizard_wait_ios="${WIZARD_DEFAULT_WAIT_IOS:-1}"
WAIT_IOS_CHOICE="0"
if [[ "$UPLOAD_IOS" -eq 1 ]]; then
  if [[ -n "${WIZARD_SKIP_WAIT_IOS_PROMPT:-}" && "${WIZARD_SKIP_WAIT_IOS_PROMPT}" == "1" ]]; then
    WAIT_IOS_CHOICE="$wizard_wait_ios"
    printf "$MSG_RUN_WAIT_IOS_FROM_WIZARD\n" "$WAIT_IOS_CHOICE"
  else
    def_wait="Y"; [[ "$wizard_wait_ios" == "0" ]] && def_wait="n"
    printf "$MSG_RUN_WAIT_IOS_PROMPT" "$(echo "$def_wait" | tr '[:upper:]' '[:lower:]')"
    read -r wait_choice
    case "${wait_choice:-$def_wait}" in n|N|no|NO) WAIT_IOS_CHOICE="0" ;; *) WAIT_IOS_CHOICE="1" ;; esac
  fi
fi

echo
echo "$MSG_RUN_SUMMARY_TITLE"
printf "$MSG_RUN_SUMMARY_TARGETS\n" "$targets"
printf "$MSG_RUN_SUMMARY_ENV\n" "$ENV_TARGETS"
printf "$MSG_RUN_SUMMARY_BUILD_NAME\n" "${BUILD_NAME}"
if [[ "$ENV_TARGETS" == "both" ]]; then
  printf "$MSG_RUN_SUMMARY_DEV_BUILD\n" "${DEV_BUILD_NUMBER}"
  printf "$MSG_RUN_SUMMARY_PROD_BUILD\n" "${PROD_BUILD_NUMBER}"
else
  printf "$MSG_RUN_SUMMARY_BUILD_NUM\n" "${DEV_BUILD_NUMBER}"
fi
build_notes_preview() {
  local env="$1"
  local header
  if [[ "$env" == "prod" ]]; then header="Release build"; else header="Test build"; fi
  if [[ -n "${changelog// /}" ]]; then
    printf '%s\n\n%s\n' "$header" "$changelog"
  else
    printf '%s\n' "$header"
  fi
}

if [[ -n "${changelog// /}" ]]; then
  echo "$MSG_RUN_NOTES_TITLE"
  printf '%s\n' "$changelog" | sed 's/^/      /'
else
  echo "$MSG_RUN_NOTES_EMPTY"
fi

echo "$MSG_RUN_NOTES_PREVIEW_TITLE"
if [[ "$ENV_TARGETS" == "both" ]]; then
  echo "$MSG_RUN_NOTES_DEV_HEADER"
  build_notes_preview "dev" | sed 's/^/        /'
  echo "$MSG_RUN_NOTES_PROD_HEADER"
  build_notes_preview "prod" | sed 's/^/        /'
else
  printf "$MSG_RUN_NOTES_ENV_HEADER\n" "$ENV_TARGETS"
  build_notes_preview "$ENV_TARGETS" | sed 's/^/        /'
fi
if [[ "$UPLOAD_IOS" -eq 1 && "$WAIT_IOS_CHOICE" == "1" ]]; then
  echo "$MSG_RUN_SUMMARY_WAIT_IOS_YES"
else
  echo "$MSG_RUN_SUMMARY_WAIT_IOS_NO"
fi
printf "$MSG_RUN_SUMMARY_IOS_UPLOAD\n" "$UPLOAD_IOS"
printf "$MSG_RUN_SUMMARY_ANDROID_UPLOAD\n" "$UPLOAD_ANDROID"
if [[ "$ENV_TARGETS" == "both" ]]; then
  printf "$MSG_RUN_SUMMARY_PUBSPEC_PROD\n" "${BUILD_NAME}" "${PROD_BUILD_NUMBER}"
else
  printf "$MSG_RUN_SUMMARY_PUBSPEC_SINGLE\n" "${BUILD_NAME}" "${DEV_BUILD_NUMBER}"
fi
echo
if [[ -n "${WIZARD_SKIP_FINAL_CONFIRM:-}" && "${WIZARD_SKIP_FINAL_CONFIRM}" == "1" ]]; then
  echo "$MSG_RUN_FINAL_CONFIRM_SKIPPED"
else
  printf "%s" "$MSG_RUN_FINAL_CONFIRM_PROMPT"
  read -r cont
  case "${cont:-Y}" in n|N|no|NO) echo "$MSG_RUN_FINAL_CANCELLED"; exit 0 ;; esac
fi

mkdir -p "$UPLOAD_LOG_DIR" "$UPLOAD_STATE_DIR"
rm -f "$UPLOAD_STATE_DIR/pubspec_updated_to.txt" || true

echo
echo "$MSG_RUN_STEP_FLUTTER_PUB_GET"
uploadtool_run_cmd flutter pub get

supports_no_pub=0
if uploadtool_run_cmd flutter build --help 2>&1 | grep -q -- "--no-pub"; then
  supports_no_pub=1
fi

supports_dart_define_from_file=0
if uploadtool_run_cmd flutter build --help 2>&1 | grep -q -- "--dart-define-from-file"; then
  supports_dart_define_from_file=1
fi
export UPLOADTOOL_SUPPORTS_DART_DEFINE_FROM_FILE="$supports_dart_define_from_file"

build_android() {
  uploadtool_build_android "$@"
}

build_ios() {
  uploadtool_build_ios "$@"
}

# Runs fastlane spaceauth interactively and stores FASTLANE_SESSION locally to avoid 2FA prompts mid-upload.
uploadtool_fastlane_ensure_session() {
  # Required only for iOS uploads and only when the wizard runs in an interactive terminal.
  if [[ "${UPLOAD_IOS:-0}" -ne 1 ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    # Skip authorization in CI or non-interactive shells.
    return 0
  fi
  # API key auth does not require a session.
  if [[ -n "${ASC_KEY_ID:-}" ]]; then
    return 0
  fi
  # FASTLANE_USER is required for spaceauth.
  if [[ -z "${FASTLANE_USER:-}" ]]; then
    return 0
  fi
  # Abort if fastlane root is not configured.
  if [[ -z "${UPLOADTOOL_FASTLANE_ROOT:-}" || ! -d "$UPLOADTOOL_FASTLANE_ROOT" ]]; then
    return 0
  fi

  echo
  echo "$MSG_RUN_SPACEAUTH_TITLE"
  printf "$MSG_RUN_SPACEAUTH_APPLE_ID\n" "${FASTLANE_USER}"
  echo "$MSG_RUN_SPACEAUTH_HINT_SESSION"
  echo "$MSG_RUN_SPACEAUTH_HINT_PASSWORD_ENV"
  echo

  local tmp_log
  tmp_log="$(mktemp)"
  local had_session="0"
  [[ -n "${FASTLANE_SESSION:-}" ]] && had_session="1"

  # Run spaceauth inside PTY (script) so fastlane can prompt for password/2FA when needed.
  # script -q syntax verified on macOS (BSD); GNU script may differ.
  _run_spaceauth() {
    export UPLOADTOOL_FASTLANE_ROOT FASTLANE_USER
    script -q "$tmp_log" bash -c 'cd "$UPLOADTOOL_FASTLANE_ROOT" && export BUNDLE_GEMFILE="$UPLOADTOOL_FASTLANE_ROOT/Gemfile" && bundle exec fastlane spaceauth -u "$FASTLANE_USER"'
  }

  _run_spaceauth
  local spaceauth_rc=$?

  # If the first attempt fails while a session existed, retry without it.
  if [[ "$spaceauth_rc" -ne 0 && "$had_session" == "1" ]]; then
    echo "$MSG_RUN_SPACEAUTH_SESSION_EXPIRED"
    unset FASTLANE_SESSION
    _run_spaceauth
    spaceauth_rc=$?
  fi

  if [[ "$spaceauth_rc" -ne 0 ]]; then
    printf "$MSG_RUN_ERR_SPACEAUTH_FAILED\n" "$spaceauth_rc" >&2
    rm -f "$tmp_log"
    return 1
  fi

  # Parse the exact export FASTLANE_SESSION line from spaceauth output.
  local env_line
  env_line="$(grep 'export FASTLANE_SESSION=' "$tmp_log" | tail -n 1 || true)"
  rm -f "$tmp_log"

  if [[ -z "$env_line" ]]; then
    echo "$MSG_RUN_ERR_SPACEAUTH_NO_SESSION_LINE" >&2
    echo "$MSG_RUN_SPACEAUTH_CONTINUE_WITHOUT_SAVE" >&2
    return 0
  fi

  # Remove leading spaces/export prefix; trim trailing commands.
  env_line="$(echo "$env_line" | sed -E 's/^[[:space:]]*export[[:space:]]+//')"
  env_line="${env_line%%;*}"

  if [[ "$env_line" != FASTLANE_SESSION=* ]]; then
    echo "$MSG_RUN_ERR_SPACEAUTH_UNEXPECTED_SESSION_FORMAT" >&2
    echo "       $env_line" >&2
    echo "$MSG_RUN_SPACEAUTH_CONTINUE_WITHOUT_SAVE" >&2
    return 0
  fi

  mkdir -p "$UPLOAD_CONFIG_DIR"
  printf '%s\n' "$env_line" >"$FASTLANE_SESSION_FILE"
  chmod 600 "$FASTLANE_SESSION_FILE" 2>/dev/null || true

  # Load the new session into current shell.
  eval "$env_line"
  echo "$MSG_RUN_SPACEAUTH_SESSION_SAVED"
  echo "      $FASTLANE_SESSION_FILE"
  return 0
}

echo
echo "$MSG_RUN_STEP_FASTLANE_PREPARE"
if [[ "${UPLOAD_IOS:-0}" -eq 1 || "${UPLOAD_ANDROID:-0}" -eq 1 ]]; then
  require_cmd bundle
  uploadtool_run_cmd_in_dir "$UPLOADTOOL_FASTLANE_ROOT" bundle install --path vendor/bundle
  # After installing fastlane dependencies, refresh spaceauth (when applicable) before background uploads.
  uploadtool_fastlane_ensure_session || exit 1
else
  echo "$MSG_RUN_STEP_FASTLANE_SKIPPED"
fi

UPLOAD_STATUS_FILES=()
UPLOAD_LABELS=()

update_pubspec_version() {
  uploadtool_update_pubspec_version "$@"
}

wait_for_all_uploads() {
  # Uploads are launched from background build workers, so their PID may not
  # be a child of this shell. We wait by polling their explicit exit-code file.
  uploadtool_wait_for_all_uploads
}

# Returns true if at least one upload succeeded (rc=0). Keeps pubspec in sync even on partial failures.
at_least_one_upload_succeeded() {
  uploadtool_at_least_one_upload_succeeded
}

run_for_env() {
  local env="$1"
  local build_number="$2"
  local async_upload="${3:-0}"

  # Notes in TestFlight require waiting for processing anyway, so in practice this will wait.
  uploadtool_run_for_env "$env" "$build_number" "$async_upload" "$changelog"
}

UPLOAD_OR_BUILD_FAILED=0

if [[ "$ENV_TARGETS" == "both" ]]; then
  async_upload_mode=1
  force_sequential_android_upload="${WIZARD_FORCE_SEQUENTIAL_ANDROID_UPLOAD:-1}"
  if [[ "$UPLOAD_ANDROID" -eq 1 && "$force_sequential_android_upload" != "0" ]]; then
    # Google Play Edits API can invalidate one edit when two uploads for the same app
    # happen in parallel ("This Edit has been deleted"), so serialize dev/prod uploads.
    async_upload_mode=0
  fi

  # Sequential dev/prod builds keep build/artifacts isolated.
  run_for_env "dev" "$DEV_BUILD_NUMBER" "$async_upload_mode" || exit 1
  run_for_env "prod" "$PROD_BUILD_NUMBER" "$async_upload_mode" || exit 1

  if [[ "$async_upload_mode" -eq 1 ]]; then
    if ! wait_for_all_uploads; then
      UPLOAD_OR_BUILD_FAILED=1
      echo
      echo "$MSG_RUN_ERR_UPLOADS_PARTIALLY_FAILED"
      [[ -f "$UPLOAD_LOG_DIR/dev_ios_upload.log" ]] && echo "   ---- iOS (dev) ----" && tail -n 80 "$UPLOAD_LOG_DIR/dev_ios_upload.log" || true
      [[ -f "$UPLOAD_LOG_DIR/dev_android_upload.log" ]] && echo "   ---- Android (dev) ----" && tail -n 80 "$UPLOAD_LOG_DIR/dev_android_upload.log" || true
      [[ -f "$UPLOAD_LOG_DIR/prod_ios_upload.log" ]] && echo "   ---- iOS (prod) ----" && tail -n 80 "$UPLOAD_LOG_DIR/prod_ios_upload.log" || true
      [[ -f "$UPLOAD_LOG_DIR/prod_android_upload.log" ]] && echo "   ---- Android (prod) ----" && tail -n 80 "$UPLOAD_LOG_DIR/prod_android_upload.log" || true
    fi
  fi
else
  if ! run_for_env "$ENV_TARGETS" "$DEV_BUILD_NUMBER"; then
    UPLOAD_OR_BUILD_FAILED=1
  fi
fi

# Update pubspec when at least one upload succeeds to avoid losing version bumps.
if [[ "$UPLOAD_IOS" -eq 1 || "$UPLOAD_ANDROID" -eq 1 ]]; then
  if at_least_one_upload_succeeded; then
    update_reason="$MSG_RUN_PUBSPEC_REASON_ALL_SUCCESS"
    [[ "$UPLOAD_OR_BUILD_FAILED" -eq 1 ]] && update_reason="$MSG_RUN_PUBSPEC_REASON_PARTIAL_SUCCESS"
    if [[ "$ENV_TARGETS" == "both" ]]; then
      update_pubspec_version "$PROD_BUILD_NUMBER" "$update_reason"
    else
      update_pubspec_version "$DEV_BUILD_NUMBER" "$update_reason"
    fi
  fi
fi

echo
if [[ "$UPLOAD_OR_BUILD_FAILED" -eq 1 ]]; then
  echo "$MSG_RUN_DONE_WITH_ERRORS"
  exit 1
fi
echo "$MSG_RUN_DONE_OK"

