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
ENV_FILE="${ENV_FILE:-}"
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
    *)
      break
      ;;
  esac
done

# Flutter project root (ROOT_DIR)
PROJECT_ROOT="${PROJECT_ROOT_ARG:-${UPLOADTOOL_PROJECT_ROOT:-${ROOT_DIR:-}}}"
if [[ -z "$PROJECT_ROOT" ]]; then
  default_candidate="$(cd "$UPLOAD_TOOL_DIR/.." && pwd)"
  if [[ -f "$default_candidate/pubspec.yaml" ]]; then
    PROJECT_ROOT="$default_candidate"
  elif [[ -f "${PWD}/pubspec.yaml" ]]; then
    PROJECT_ROOT="$PWD"
  fi
fi
if [[ -z "$PROJECT_ROOT" ]]; then
  echo "❌ Не удалось определить корень Flutter-проекта (где pubspec.yaml)." >&2
  echo "   Укажи через --project-root /path/to/flutter или ENV UPLOADTOOL_PROJECT_ROOT." >&2
  exit 1
fi

ROOT_DIR="$(cd "$PROJECT_ROOT" && pwd)"
export ROOT_DIR
export UPLOADTOOL_PROJECT_ROOT="$ROOT_DIR"
cd "$ROOT_DIR"

if [[ "${UPLOADTOOL_SKIP_SAFE_PATH:-}" != "1" ]]; then
  export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
fi

# Конфиги могут жить рядом с проектом (например <project>/.uploadtool),
# а сам UploadTool может быть клонирован куда угодно.
UPLOAD_CONFIG_DIR="${CONFIG_DIR_ARG:-${UPLOADTOOL_CONFIG_DIR:-}}"
if [[ -z "$UPLOAD_CONFIG_DIR" ]]; then
  if [[ -d "$ROOT_DIR/.uploadtool" ]]; then
    UPLOAD_CONFIG_DIR="$ROOT_DIR/.uploadtool"
  else
    UPLOAD_CONFIG_DIR="$UPLOAD_TOOL_DIR/config"
  fi
fi
export UPLOADTOOL_CONFIG_DIR="$UPLOAD_CONFIG_DIR"

UPLOAD_LOG_DIR="${UPLOADTOOL_LOG_DIR:-$UPLOAD_TOOL_DIR/logs}"
UPLOAD_STATE_DIR="${UPLOADTOOL_STATE_DIR:-$UPLOAD_TOOL_DIR/state}"

default_fastlane_root="$UPLOAD_TOOL_DIR/fastlane"
if [[ ! -f "$default_fastlane_root/Gemfile" ]]; then
  default_fastlane_root="$ROOT_DIR/ios"
fi
UPLOADTOOL_FASTLANE_ROOT="${UPLOADTOOL_FASTLANE_ROOT:-$default_fastlane_root}"
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

# Единственный источник кредов и настроек сборки/публикации — release.env (или .env.release).
ENV_FILE="$(uploadtool_select_env_file "${ENV_FILE:-}" "$UPLOAD_CONFIG_DIR" "$ROOT_DIR")"
uploadtool_load_env_file_if_present "$ENV_FILE"

# Настройки поведения мастера (значения по умолчанию и пропуск шагов). Опционально.
# См. UploadTool/config/wizard.env.example
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
echo "   Release: ${ENV_FILE:-<none>}"
[[ -f "$UPLOAD_CONFIG_DIR/wizard.env" ]] && echo "   Wizard:  $UPLOAD_CONFIG_DIR/wizard.env"
echo

targets="${RELEASE_TARGETS:-}"
if [[ -z "$targets" ]]; then
  targets="$TARGET_ARG"
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
if [[ -f "$ENV_JSON" ]]; then
  CURRENT_ENV="$(python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p,"r",encoding="utf-8")); print(d.get("CHOYS_ENV",""))' "$ENV_JSON" 2>/dev/null || true)"
fi
if [[ "$CURRENT_ENV" != "dev" && "$CURRENT_ENV" != "prod" ]]; then
  CURRENT_ENV="prod"
fi

write_env_json() {
  local env="$1"
  write_env_to_file "$ENV_JSON" "$env"
}

# Write CHOYS_ENV (and any other keys from current ENV_JSON) to a given path.
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
  echo "   1) только dev  🧪  (https://choys.dnadev.ru)"
  echo "   2) только prod 🏪  (https://my.choys.app)"
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

echo
echo "⚙️  Подготовка fastlane (bundle install)..."
uploadtool_run_cmd_in_dir "$UPLOADTOOL_FASTLANE_ROOT" bundle install --path vendor/bundle

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

