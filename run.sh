#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${BASH_VERSION:-}" ]]; then
  exec bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

UPLOAD_TOOL_DIR="$SCRIPT_DIR"
if [[ ! -d "$UPLOAD_TOOL_DIR/lib" ]]; then
  echo "❌ Не найдена папка lib рядом с run.sh: $UPLOAD_TOOL_DIR/lib" >&2
  exit 1
fi

# CLI overrides
PROJECT_ROOT_ARG=""
CONFIG_DIR_ARG=""
FASTLANE_ROOT_ARG=""
PROJECT_PROFILE_ARG=""
CLI_ENV_FILE="${UPLOADTOOL_CLI_ENV_FILE:-}"
ENV_FILE="${ENV_FILE:-}"

INIT_FORCE="${UPLOADTOOL_INIT_FORCE:-0}"
INIT_SAVE_DEFAULTS="${UPLOADTOOL_INIT_SAVE_DEFAULTS:-0}"

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
}

uploadtool_cli_init() {
  if [[ "${#@}" -ne 0 ]]; then
    echo "❌ Неизвестные аргументы для init: $*" >&2
    return 1
  fi

  local project_root
  project_root="${PROJECT_ROOT_ARG:-${UPLOADTOOL_PROJECT_ROOT:-${UPLOADTOOL_CLI_PROJECT_ROOT:-}}}"
  if [[ -z "$project_root" ]]; then
    if [[ -f "${PWD}/pubspec.yaml" ]]; then
      project_root="$PWD"
    else
      read -r -p "Путь к Flutter-проекту (где pubspec.yaml): " project_root
    fi
  fi
  if [[ -z "$project_root" ]]; then
    echo "❌ Не задан --project-root и не удалось определить проект." >&2
    return 1
  fi
  if [[ ! -d "$project_root" ]]; then
    echo "❌ Директория проекта не найдена: $project_root" >&2
    return 1
  fi
  project_root="$(cd "$project_root" && pwd)"
  if [[ ! -f "$project_root/pubspec.yaml" ]]; then
    echo "❌ Не найден pubspec.yaml в: $project_root" >&2
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
    echo "❌ Не найдена директория шаблонов: $src_dir" >&2
    return 1
  fi

  echo
  echo "🧰 UploadTool init"
  echo "   Project: $project_root"
  echo "   Config:  $config_dir"

  _copy_example() {
    local src="$1"
    local dst="$2"
    local label="$3"

    if [[ -f "$dst" && "${INIT_FORCE:-0}" != "1" ]]; then
      echo "   ✅ $label уже существует: $dst (пропущено)"
      return 0
    fi
    cp -f "$src" "$dst"
    echo "   ➕ $label: $dst"
  }

  _copy_example "$src_dir/env.json.example" "$config_dir/env.json" "env.json"
  _copy_example "$src_dir/release.env.example" "$config_dir/release.env" "release.env"
  _copy_example "$src_dir/wizard.env.example" "$config_dir/wizard.env" "wizard.env"

  if [[ "${INIT_SAVE_DEFAULTS:-0}" == "1" ]]; then
    local cli_file
    cli_file="$CLI_ENV_FILE"
    if [[ -z "$cli_file" ]]; then
      cli_file="$config_dir/cli.env"
    fi
    if [[ -z "$cli_file" ]]; then
      echo "❌ Не удалось определить путь для cli.env (нет HOME и не передан --cli-env-file / UPLOADTOOL_CLI_ENV_FILE)" >&2
      return 1
    fi

    uploadtool_write_cli_env_file "$cli_file" "$project_root" "$config_dir" "${FASTLANE_ROOT_ARG:-}" "${UPLOADTOOL_ENV_JSON_ENV_KEY:-}"
    echo "   💾 Сохранены дефолты CLI: $cli_file"
  fi

  echo
  echo "🎉 Готово. Дальше открой и заполни:"
  echo "   - $config_dir/release.env"
  echo
  echo "Запуск:"
  echo "   bash $UPLOAD_TOOL_DIR/run.sh --project-root $project_root --config-dir $config_dir"
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

# Если cli.env задан явно (флагом или env-переменной) — загрузим его сразу,
# чтобы он мог задать UPLOADTOOL_CLI_PROJECT_ROOT/UPLOADTOOL_CLI_CONFIG_DIR
# ещё до выбора проекта.
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
# Важно: не используем ROOT_DIR из внешней среды, чтобы случайно не подхватить
# «чужой» проект (ROOT_DIR — внутренняя переменная этого скрипта).
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
    echo "❌ Не удалось загрузить профиль проекта: $PROJECT_PROFILE_ARG" >&2
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
      echo "❌ Не удалось загрузить профиль проекта: $selected_profile" >&2
      exit 1
    fi
  fi
fi

if [[ -z "$PROJECT_ROOT" ]]; then
  PROJECT_ROOT="${UPLOADTOOL_CLI_PROJECT_ROOT:-}"
fi
if [[ -z "$PROJECT_ROOT" ]]; then
  echo "❌ Не удалось определить корень Flutter-проекта (где pubspec.yaml)." >&2
  echo "   Укажи через --project-root /path/to/flutter или ENV UPLOADTOOL_PROJECT_ROOT." >&2
  echo "   Или выбери сохранённый проект через --project <name> (см. init.sh)." >&2
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
    echo "❌ Не найдена зависимость: '$cmd'" >&2
    exit 1
  fi
}

require_cmd python3
require_cmd flutter

# Конфиги/логи/state должны относиться к конкретному Flutter-проекту.
# Поэтому дефолтная директория — <project>/.uploadtool.
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

# Если путь передан относительным, делаем его абсолютным относительно ROOT_DIR.
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
  # Если это дефолтная проектная директория — создаём автоматически.
  if [[ "$UPLOAD_CONFIG_DIR_DEFAULTED" == "1" && "$UPLOAD_CONFIG_DIR" == "$ROOT_DIR/.uploadtool" ]]; then
    mkdir -p "$UPLOAD_CONFIG_DIR"
  else
    echo "❌ Не найдена директория конфигов: $UPLOAD_CONFIG_DIR" >&2
    echo "   Создай её (например: mkdir -p .uploadtool) или передай корректный --config-dir." >&2
    exit 1
  fi
fi

# Приведём путь к каноническому абсолютному виду (без ../ и .), чтобы вывод
# был понятным, а сравнения путей работали корректно.
UPLOAD_CONFIG_DIR="$(cd "$UPLOAD_CONFIG_DIR" && pwd)"
export UPLOADTOOL_CONFIG_DIR="$UPLOAD_CONFIG_DIR"

# Файл для локального хранения FASTLANE_SESSION (пер-проект, не для git).
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

TARGET_ARG="${1:-}"
if [[ "$TARGET_ARG" == "ios" || "$TARGET_ARG" == "android" || "$TARGET_ARG" == "both" ]]; then
  shift
else
  TARGET_ARG=""
fi

# Единственный источник кредов и настроек сборки/публикации — release.env.
ENV_FILE="$(uploadtool_select_env_file "${ENV_FILE:-}" "$UPLOAD_CONFIG_DIR")"
uploadtool_load_env_file_if_present "$ENV_FILE"

# Настройки поведения мастера (значения по умолчанию и пропуск шагов). Опционально.
# См. config/wizard.env.example
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
echo "🚀 Release wizard"
echo "   Project: $ROOT_DIR"
echo "   Tool:    $UPLOAD_TOOL_DIR"
echo "   Config:  $UPLOAD_CONFIG_DIR"
echo "   Logs:    $UPLOAD_LOG_DIR"
echo "   State:   $UPLOAD_STATE_DIR"
echo "   Fastlane:$UPLOADTOOL_FASTLANE_ROOT"
echo "   Release: ${ENV_FILE:-<none>}"
echo "   Env key: ${UPLOADTOOL_ENV_JSON_ENV_KEY:-APP_ENV}"
[[ -f "$UPLOAD_CONFIG_DIR/wizard.env" ]] && echo "   Wizard:  $UPLOAD_CONFIG_DIR/wizard.env"
echo

targets="${RELEASE_TARGETS:-}"
if [[ -z "$targets" ]]; then
  targets="$TARGET_ARG"
fi

# Если есть сохранённый FASTLANE_SESSION — подхватим его до любых вызовов fastlane.
if [[ -f "$FASTLANE_SESSION_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$FASTLANE_SESSION_FILE"
fi

# Значение по умолчанию для «Куда собираем?» (1=ios, 2=android, 3=both)
wizard_default_targets="${WIZARD_DEFAULT_TARGETS:-both}"
default_t="3"
[[ "$wizard_default_targets" == "ios" ]] && default_t="1"
[[ "$wizard_default_targets" == "android" ]] && default_t="2"

if [[ -n "${WIZARD_SKIP_TARGETS:-}" && "${WIZARD_SKIP_TARGETS}" == "1" ]]; then
  targets="$wizard_default_targets"
  echo "📱 Куда собираем: $targets (из wizard.env, шаг пропущен)"
elif [[ -z "$targets" ]]; then
  echo "📱 Куда собираем?"
  echo "   1) iOS (TestFlight)"
  echo "   2) Android (Google Play)"
  echo "   3) Оба (по умолчанию)"
  read -r -p "   Выбор (1/2/3) [${default_t}]: " t
  t="${t:-$default_t}"
  case "$t" in
    1) targets="ios" ;;
    2) targets="android" ;;
    3) targets="both" ;;
    *) echo "   ❌ Неверный выбор: $t"; exit 1 ;;
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

# Значение по умолчанию для окружения (1=dev, 2=prod, 3=both)
wizard_default_env="${WIZARD_DEFAULT_ENV:-both}"
default_e="3"
[[ "$wizard_default_env" == "dev" ]] && default_e="1"
[[ "$wizard_default_env" == "prod" ]] && default_e="2"

if [[ -n "${WIZARD_SKIP_ENV:-}" && "${WIZARD_SKIP_ENV}" == "1" ]]; then
  ENV_TARGETS="$wizard_default_env"
  echo "🌍 Окружение: $ENV_TARGETS (из wizard.env, шаг пропущен)"
else
  echo "🌍 Окружение (env.json):"
  echo "   1) только dev  🧪"
  echo "   2) только prod 🏪"
  echo "   3) dev + prod  🎯  (по умолчанию)"
  read -r -p "   Выбор (1/2/3) [${default_e}]: " env_choice
  env_choice="${env_choice:-$default_e}"
  case "$env_choice" in
    1) ENV_TARGETS="dev" ;;
    2) ENV_TARGETS="prod" ;;
    3) ENV_TARGETS="both" ;;
    *) echo "   ❌ Неверный выбор: $env_choice"; exit 1 ;;
  esac
fi

echo
echo "📦 Версия сборки:"
read -r -p "   Build name (versionName) [${default_build_name:-from pubspec.yaml}]: " build_name
read -r -p "   Build number (YYYYMMDD.N[.X], X: dev=0, prod=1) [${default_build_number:-from pubspec.yaml}]: " build_number

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
  echo "   ❌ Не удалось определить build name. Введи его вручную."
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
  echo "   ❌ Не удалось определить build number. Используй YYYYMMDD.N или YYYYMMDD.N.X"
  exit 1
fi

DEV_BUILD_NUMBER=""
PROD_BUILD_NUMBER=""
if [[ "$ENV_TARGETS" == "both" ]]; then
  dev_core="$BASE_CORE_BUILD_NUMBER"
  prod_core="$(bump_core_build_number_one "$dev_core")"
  if [[ -z "$prod_core" ]]; then
    echo "   ❌ Build number '$BASE_CORE_BUILD_NUMBER' не подходит для dev+prod. Используй YYYYMMDD.N"
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
  *) echo "   ❌ Неверные targets: $targets"; exit 1 ;;
esac

echo
echo "☁️  Загрузка в сторы:"
UPLOAD_IOS=0
UPLOAD_ANDROID=0
wizard_upload_ios="${WIZARD_DEFAULT_UPLOAD_IOS:-1}"
wizard_upload_android="${WIZARD_DEFAULT_UPLOAD_ANDROID:-1}"
if [[ -n "${WIZARD_SKIP_UPLOAD_PROMPTS:-}" && "${WIZARD_SKIP_UPLOAD_PROMPTS}" == "1" ]]; then
  [[ "$BUILD_IOS" -eq 1 ]] && UPLOAD_IOS="$wizard_upload_ios"
  [[ "$BUILD_ANDROID" -eq 1 ]] && UPLOAD_ANDROID="$wizard_upload_android"
  echo "   iOS: $UPLOAD_IOS, Android: $UPLOAD_ANDROID (из wizard.env, шаг пропущен)"
else
  if [[ "$BUILD_IOS" -eq 1 ]]; then
    def_ios="Y"; [[ "$wizard_upload_ios" == "0" ]] && def_ios="n"
    read -r -p "   Загрузить iOS в TestFlight? (y/n) [$(echo "$def_ios" | tr '[:upper:]' '[:lower:]')]: " ans
    case "${ans:-$def_ios}" in n|N|no|NO) UPLOAD_IOS=0 ;; *) UPLOAD_IOS=1 ;; esac
  fi
  if [[ "$BUILD_ANDROID" -eq 1 ]]; then
    def_android="Y"; [[ "$wizard_upload_android" == "0" ]] && def_android="n"
    read -r -p "   Загрузить Android в Google Play? (y/n) [$(echo "$def_android" | tr '[:upper:]' '[:lower:]')]: " ans
    case "${ans:-$def_android}" in n|N|no|NO) UPLOAD_ANDROID=0 ;; *) UPLOAD_ANDROID=1 ;; esac
  fi
fi

uploadtool_validate_config "$UPLOAD_IOS" "$UPLOAD_ANDROID"

echo
echo "📝 Описание релиза (опционально):"
read -r -p "   Текст для TestFlight / Google Play: " changelog

echo
wizard_wait_ios="${WIZARD_DEFAULT_WAIT_IOS:-1}"
WAIT_IOS_CHOICE="0"
if [[ "$UPLOAD_IOS" -eq 1 ]]; then
  if [[ -n "${WIZARD_SKIP_WAIT_IOS_PROMPT:-}" && "${WIZARD_SKIP_WAIT_IOS_PROMPT}" == "1" ]]; then
    WAIT_IOS_CHOICE="$wizard_wait_ios"
    echo "   ⏳ Ждать обработку в TestFlight: $WAIT_IOS_CHOICE (из wizard.env, шаг пропущен)"
  else
    def_wait="Y"; [[ "$wizard_wait_ios" == "0" ]] && def_wait="n"
    read -r -p "⏳ Ждать обработку билда в TestFlight? (y/n) [$(echo "$def_wait" | tr '[:upper:]' '[:lower:]')]: " wait_choice
    case "${wait_choice:-$def_wait}" in n|N|no|NO) WAIT_IOS_CHOICE="0" ;; *) WAIT_IOS_CHOICE="1" ;; esac
  fi
fi

echo
echo "📋 Итог:"
echo "   targets:    $targets"
echo "   env:        $ENV_TARGETS"
echo "   build name: ${BUILD_NAME}"
if [[ "$ENV_TARGETS" == "both" ]]; then
  echo "   dev build:  ${DEV_BUILD_NUMBER}  🧪"
  echo "   prod build: ${PROD_BUILD_NUMBER}  🏪"
else
  echo "   build num:  ${DEV_BUILD_NUMBER}"
fi
build_notes_preview() {
  local env="$1"
  local header
  if [[ "$env" == "prod" ]]; then header="Релизная сборка"; else header="Тестовая сборка"; fi
  if [[ -n "${changelog// /}" ]]; then
    printf '%s\n\n%s\n' "$header" "$changelog"
  else
    printf '%s\n' "$header"
  fi
}

if [[ -n "${changelog// /}" ]]; then
  echo "   notes:"
  printf '%s\n' "$changelog" | sed 's/^/      /'
else
  echo "   notes: <пусто>"
fi

echo "   превью заметок:"
if [[ "$ENV_TARGETS" == "both" ]]; then
  echo "      [dev 🧪]"
  build_notes_preview "dev" | sed 's/^/        /'
  echo "      [prod 🏪]"
  build_notes_preview "prod" | sed 's/^/        /'
else
  echo "      [$ENV_TARGETS]"
  build_notes_preview "$ENV_TARGETS" | sed 's/^/        /'
fi
if [[ "$UPLOAD_IOS" -eq 1 && "$WAIT_IOS_CHOICE" == "1" ]]; then
  echo "   wait ios:   да"
else
  echo "   wait ios:   нет"
fi
echo "   iOS:        upload=$UPLOAD_IOS  📱"
echo "   Android:    upload=$UPLOAD_ANDROID  🤖"
if [[ "$ENV_TARGETS" == "both" ]]; then
  echo "   pubspec:    version: ${BUILD_NAME}+${PROD_BUILD_NUMBER} (после успешных загрузок)"
else
  echo "   pubspec:    version: ${BUILD_NAME}+${DEV_BUILD_NUMBER} (после успешной загрузки)"
fi
echo
if [[ -n "${WIZARD_SKIP_FINAL_CONFIRM:-}" && "${WIZARD_SKIP_FINAL_CONFIRM}" == "1" ]]; then
  echo "   ▶️  Запуск (подтверждение пропущено по wizard.env)"
else
  read -r -p "▶️  Поехали? (y/n) [y]: " cont
  case "${cont:-Y}" in n|N|no|NO) echo "   Отменено."; exit 0 ;; esac
fi

mkdir -p "$UPLOAD_LOG_DIR" "$UPLOAD_STATE_DIR"
rm -f "$UPLOAD_STATE_DIR/pubspec_updated_to.txt" || true

echo
echo "🔧 flutter pub get..."
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

# Запускает интерактивный fastlane spaceauth и сохраняет FASTLANE_SESSION
# в локальный файл, чтобы фоновые загрузки не просили код 2FA "в никуда".
uploadtool_fastlane_ensure_session() {
  # Нужна только для iOS-загрузок и только если мастер запущен в интерактивном терминале.
  if [[ "${UPLOAD_IOS:-0}" -ne 1 ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    # В CI или при неинтерактивном запуске не трогаем авторизацию.
    return 0
  fi
  # При авторизации по API-ключу App Store Connect сессия не нужна.
  if [[ -n "${ASC_KEY_ID:-}" ]]; then
    return 0
  fi
  # Нужен FASTLANE_USER, иначе fastlane spaceauth не имеет смысла.
  if [[ -z "${FASTLANE_USER:-}" ]]; then
    return 0
  fi
  # Если fastlane_root не определён — тоже выходим.
  if [[ -z "${UPLOADTOOL_FASTLANE_ROOT:-}" || ! -d "$UPLOADTOOL_FASTLANE_ROOT" ]]; then
    return 0
  fi

  echo
  echo "🔐 Проверка авторизации fastlane (spaceauth)..."
  echo "   Apple ID: ${FASTLANE_USER}"
  echo "   Если сессия ещё действует — запроса пароля не будет."
  echo "   (Пароль можно задать в release.env: FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD)"
  echo

  local tmp_log
  tmp_log="$(mktemp)"
  local had_session="0"
  [[ -n "${FASTLANE_SESSION:-}" ]] && had_session="1"

  # Запуск spaceauth в PTY (script), чтобы fastlane при необходимости мог запросить пароль/2FA.
  # Синтаксис script -q <file> <command> проверен на macOS (BSD script); на Linux (GNU script) может отличаться.
  _run_spaceauth() {
    export UPLOADTOOL_FASTLANE_ROOT FASTLANE_USER
    script -q "$tmp_log" bash -c 'cd "$UPLOADTOOL_FASTLANE_ROOT" && export BUNDLE_GEMFILE="$UPLOADTOOL_FASTLANE_ROOT/Gemfile" && bundle exec fastlane spaceauth -u "$FASTLANE_USER"'
  }

  _run_spaceauth
  local spaceauth_rc=$?

  # Если первая попытка с текущей сессией не удалась и сессия была — значит протухла, пробуем заново без неё.
  if [[ "$spaceauth_rc" -ne 0 && "$had_session" == "1" ]]; then
    echo "   Сессия протухла, повторный вход (введи пароль/2FA при запросе)..."
    unset FASTLANE_SESSION
    _run_spaceauth
    spaceauth_rc=$?
  fi

  if [[ "$spaceauth_rc" -ne 0 ]]; then
    echo "   ❌ spaceauth завершился с кодом $spaceauth_rc (проверь логин/пароль и 2FA)." >&2
    rm -f "$tmp_log"
    return 1
  fi

  # В выводе spaceauth ищем именно строку export FASTLANE_SESSION='...' (не "Pass the following via the...")
  local env_line
  env_line="$(grep 'export FASTLANE_SESSION=' "$tmp_log" | tail -n 1 || true)"
  rm -f "$tmp_log"

  if [[ -z "$env_line" ]]; then
    echo "   ⚠️  Не удалось найти export FASTLANE_SESSION в выводе fastlane spaceauth." >&2
    echo "       Продолжаем без автосохранения сессии." >&2
    return 0
  fi

  # Уберём ведущие пробелы и префикс export, отрежем хвост после точки с запятой.
  env_line="$(echo "$env_line" | sed -E 's/^[[:space:]]*export[[:space:]]+//')"
  env_line="${env_line%%;*}"

  if [[ "$env_line" != FASTLANE_SESSION=* ]]; then
    echo "   ⚠️  Строка с сессией имеет неожиданный формат:" >&2
    echo "       $env_line" >&2
    echo "       Продолжаем без автосохранения." >&2
    return 0
  fi

  mkdir -p "$UPLOAD_CONFIG_DIR"
  printf '%s\n' "$env_line" >"$FASTLANE_SESSION_FILE"
  chmod 600 "$FASTLANE_SESSION_FILE" 2>/dev/null || true

  # Подхватим новую сессию в текущем процессе.
  eval "$env_line"
  echo "   ✅ FASTLANE_SESSION обновлён и сохранён в:"
  echo "      $FASTLANE_SESSION_FILE"
  return 0
}

echo
echo "⚙️  Подготовка fastlane (bundle install)..."
if [[ "${UPLOAD_IOS:-0}" -eq 1 || "${UPLOAD_ANDROID:-0}" -eq 1 ]]; then
  require_cmd bundle
  uploadtool_run_cmd_in_dir "$UPLOADTOOL_FASTLANE_ROOT" bundle install --path vendor/bundle
  # После установки fastlane прогоняем интерактивный spaceauth (если актуально),
  # чтобы FASTLANE_SESSION был валиден ещё до фоновых загрузок.
  uploadtool_fastlane_ensure_session || exit 1
else
  echo "   Пропущено: загрузка в сторы выключена"
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

# Проверяет, что хотя бы одна загрузка из UPLOAD_STATUS_FILES успешна (rc=0).
# Нужно для обновления pubspec даже при частичном провале (чтобы не терять версию).
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
  # Сборки dev и prod по очереди (run_for_env вызываются последовательно), чтобы оба не
  # писали в один build/ — иначе артефакт dev может оказаться от prod. Загрузки ждать здесь
  # не обязательно: после сборок артефакты уже в state/dev и state/prod, все 4 загрузки
  # стартуют и в конце ждём их одной wait_for_all_uploads.
  run_for_env "dev" "$DEV_BUILD_NUMBER" 1 || exit 1
  run_for_env "prod" "$PROD_BUILD_NUMBER" 1 || exit 1
  if ! wait_for_all_uploads; then
    UPLOAD_OR_BUILD_FAILED=1
    echo
    echo "   ❌ Часть загрузок не удалась. Логи:"
    [[ -f "$UPLOAD_LOG_DIR/dev_ios_upload.log" ]] && echo "   ---- iOS (dev) ----" && tail -n 80 "$UPLOAD_LOG_DIR/dev_ios_upload.log" || true
    [[ -f "$UPLOAD_LOG_DIR/dev_android_upload.log" ]] && echo "   ---- Android (dev) ----" && tail -n 80 "$UPLOAD_LOG_DIR/dev_android_upload.log" || true
    [[ -f "$UPLOAD_LOG_DIR/prod_ios_upload.log" ]] && echo "   ---- iOS (prod) ----" && tail -n 80 "$UPLOAD_LOG_DIR/prod_ios_upload.log" || true
    [[ -f "$UPLOAD_LOG_DIR/prod_android_upload.log" ]] && echo "   ---- Android (prod) ----" && tail -n 80 "$UPLOAD_LOG_DIR/prod_android_upload.log" || true
  fi
else
  if ! run_for_env "$ENV_TARGETS" "$DEV_BUILD_NUMBER"; then
    UPLOAD_OR_BUILD_FAILED=1
  fi
fi

# Обновляем pubspec, если хотя бы одна загрузка прошла — чтобы не терять версию при падении одной из OS.
if [[ "$UPLOAD_IOS" -eq 1 || "$UPLOAD_ANDROID" -eq 1 ]]; then
  if at_least_one_upload_succeeded; then
    if [[ "$ENV_TARGETS" == "both" ]]; then
      update_pubspec_version "$PROD_BUILD_NUMBER" "$([[ "$UPLOAD_OR_BUILD_FAILED" -eq 1 ]] && echo "часть загрузок успешна" || echo "all uploads succeeded")"
    else
      update_pubspec_version "$DEV_BUILD_NUMBER" "$([[ "$UPLOAD_OR_BUILD_FAILED" -eq 1 ]] && echo "часть загрузок успешна" || echo "all uploads succeeded")"
    fi
  fi
fi

echo
if [[ "$UPLOAD_OR_BUILD_FAILED" -eq 1 ]]; then
  echo "⚠️  Завершено с ошибками (часть сборок/загрузок не удалась)."
  exit 1
fi
echo "🎉 Готово!"

