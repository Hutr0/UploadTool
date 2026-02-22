#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

# На macOS /bin/sh часто является bash в POSIX-режиме: там отключены некоторые bash-фичи
# (например process substitution), и тест-раннер падает. Перезапускаемся в обычный bash.
if command -v shopt >/dev/null 2>&1; then
  if shopt -oq posix; then
    exec bash "$0" "$@"
  fi
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UPLOAD_TOOL_DIR="$SCRIPT_DIR"

TESTS_DIR="$UPLOAD_TOOL_DIR/tests"

fail() {
  echo "❌ $*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-}"
  if [[ "$expected" != "$actual" ]]; then
    echo "Expected: '$expected'" >&2
    echo "Actual:   '$actual'" >&2
    [[ -n "$msg" ]] && echo "$msg" >&2
    return 1
  fi
}

run_test_file() {
  local f="$1"
  local verbose="${UPLOADTOOL_TEST_VERBOSE:-}"
  if [[ "$verbose" == "1" ]]; then
    (
      # shellcheck disable=SC1090
      source "$f"
    )
    return $?
  fi

  local out_file
  out_file="$(mktemp)"
  if (
    # shellcheck disable=SC1090
    source "$f"
  ) >"$out_file" 2>&1; then
    rm -f "$out_file"
    return 0
  fi

  cat "$out_file" >&2
  rm -f "$out_file"
  return 1
}

print_help() {
  cat <<'EOF'
🧪 UploadTool — запуск тестов

Использование:
  ./UploadTool/test.sh                     # все тесты
  ./UploadTool/test.sh --unit              # только unit
  ./UploadTool/test.sh --integration       # только integration
  ./UploadTool/test.sh --smoke             # только smoke
  ./UploadTool/test.sh --regression        # только regression
  ./UploadTool/test.sh --pattern "*.test.sh" # произвольный glob по имени
  ./UploadTool/test.sh --list              # список найденных тестов

Опции:
  -v, --verbose     показывать вывод даже для прошедших тестов
  --fail-fast       остановиться на первом падении
  -h, --help        помощь

Примечание:
  Если запускать через `sh`, скрипт сам перезапустится в `bash`.

Интерактивный режим:
  ./UploadTool/test.sh
  (если не передавать аргументы, появится выбор типа тестирования)
EOF
}

test_suite_of_file() {
  local base
  base="$(basename "$1")"

  if [[ "$base" == *"_integration.test.sh" ]]; then
    echo "integration"
    return 0
  fi
  if [[ "$base" == *"smoke.test.sh" ]]; then
    echo "smoke"
    return 0
  fi
  if [[ "$base" == "config.test.sh" || "$base" == "config_validation.test.sh" ]]; then
    echo "regression"
    return 0
  fi
  echo "unit"
}

test_description_of_file() {
  local f="$1"
  local base
  base="$(basename "$f")"

  local desc
  desc="$(sed -nE 's/^TEST_DESCRIPTION="(.*)"$/\1/p' "$f" | head -n 1)"
  if [[ -z "$desc" ]]; then
    desc="$(sed -nE 's/^# *Описание: *(.*)$/\1/p' "$f" | head -n 1)"
  fi
  if [[ -n "$desc" ]]; then
    echo "$desc"
    return 0
  fi

  case "$base" in
    versioning.test.sh)
      echo "Версионирование: извлечение/инкремент build number, форматирование под env"
      ;;
    android_version_code.test.sh)
      echo "Android: вычисление versionCode из build number"
      ;;
    notes.test.sh)
      echo "Release notes: формирование текста описания релиза"
      ;;
    runner.test.sh)
      echo "Infra runner: мок внешних команд и трассировка"
      ;;
    time.test.sh)
      echo "Infra time: мок sleep/ожиданий"
      ;;
    env_json.test.sh)
      echo "env.json: запись CHOYS_ENV и сохранение остальных ключей"
      ;;
    config.test.sh)
      echo "Конфиги: выбор и загрузка release.env/wizard.env (регрессия)"
      ;;
    config_validation.test.sh)
      echo "Fail-fast: валидация required-полей для upload iOS/Android (регрессия)"
      ;;
    workflow_build_integration.test.sh)
      echo "Workflow: интеграционный тест сборки iOS/Android (flutter аргументы, артефакты)"
      ;;
    workflow_build_and_upload_integration.test.sh)
      echo "Workflow: интеграционный тест оркестрации build+upload (fastlane вызовы, статусы)"
      ;;
    workflow_wait_pubspec_integration.test.sh)
      echo "Workflow: ожидание загрузок + обновление pubspec версии (интеграция)"
      ;;
    workflow_run_for_env_integration.test.sh)
      echo "Workflow: run_for_env (подготовка ENV, build numbers, notes, оркестрация)"
      ;;
    run_sh_smoke.test.sh)
      echo "Smoke: полный прогон run.sh в фейковом репо с моками команд"
      ;;
    *)
      echo "(описание не задано)"
      ;;
  esac
}

collect_test_files() {
  local suite="$1"
  local pattern="$2"

  local find_pattern
  find_pattern="*.test.sh"
  [[ -n "$pattern" ]] && find_pattern="$pattern"

  local all=()
  while IFS= read -r f; do all+=("$f"); done < <(find "$TESTS_DIR" -type f -name "$find_pattern" | sort)

  local filtered=()
  local f
  for f in "${all[@]}"; do
    local s
    s="$(test_suite_of_file "$f")"
    if [[ "$suite" == "all" || "$s" == "$suite" ]]; then
      filtered+=("$f")
    fi
  done

  printf '%s\n' "${filtered[@]}"
}

prompt_yes_no() {
  local prompt="$1"
  local def="${2:-Y}"

  local def_l
  def_l="$(echo "$def" | tr '[:upper:]' '[:lower:]')"

  local ans
  read -r -p "$prompt (y/n) [$def_l]: " ans
  ans="${ans:-$def}"
  case "$ans" in
    y|Y|yes|YES) echo 1 ;;
    *) echo 0 ;;
  esac
}

run_wizard() {
  >&2 echo "🧙 Выбор режима тестирования:"
  >&2 echo "   1) Все тесты"
  >&2 echo "   2) Unit"
  >&2 echo "   3) Integration"
  >&2 echo "   4) Smoke"
  >&2 echo "   5) Regression"
  >&2 echo "   6) По шаблону (glob)"
  >&2 echo

  local choice
  read -r -p "Выбери режим [1]: " choice
  choice="${choice:-1}"

  local suite="all"
  local pattern=""

  case "$choice" in
    1) suite="all" ;;
    2) suite="unit" ;;
    3) suite="integration" ;;
    4) suite="smoke" ;;
    5) suite="regression" ;;
    6)
      suite="all"
      read -r -p "Введи glob (пример: *.test.sh): " pattern
      [[ -n "$pattern" ]] || fail "Пустой glob" 
      ;;
    *) fail "Неверный выбор: $choice" ;;
  esac

  local verbose
  verbose="$(prompt_yes_no "Показывать вывод успешных тестов?" "n")"
  local ff
  ff="$(prompt_yes_no "Остановиться на первом падении?" "n")"

  if [[ "$verbose" -eq 1 ]]; then
    export UPLOADTOOL_TEST_VERBOSE=1
  fi

  >&2 echo
  >&2 echo "📋 Выбрано:"
  >&2 echo "   📦 suite:   $suite"
  [[ -n "$pattern" ]] && >&2 echo "   🔎 pattern: $pattern"
  >&2 echo "   🧾 verbose: ${UPLOADTOOL_TEST_VERBOSE:-0}"
  >&2 echo "   🧨 fail-fast: $ff"
  >&2 echo

  local wizard_files=()
  while IFS= read -r f; do
    [[ -n "$f" ]] && wizard_files+=("$f")
  done < <(collect_test_files "$suite" "$pattern")

  if [[ "${#wizard_files[@]}" -eq 0 ]]; then
    fail "Тесты не найдены в $TESTS_DIR"
  fi

  >&2 echo "🗂️  Найденные тесты (${#wizard_files[@]}):"
  local i
  for i in "${!wizard_files[@]}"; do
    local tf="${wizard_files[$i]}"
    >&2 printf '   %2d) %s — %s\n' "$((i + 1))" "$(basename "$tf")" "$(test_description_of_file "$tf")"
  done
  >&2 echo

  local run_all
  run_all="$(prompt_yes_no "Запустить все найденные тесты?" "Y")"

  local selected_list_file=""
  if [[ "$run_all" -ne 1 ]]; then
    local sel
    read -r -p "Введи номера (пример: 1,3,5-7): " sel
    sel="${sel//[[:space:]]/}"
    [[ -n "$sel" ]] || fail "Пустой список"

    local selected=()
    local token
    IFS=',' read -r -a _tokens <<<"$sel"
    for token in "${_tokens[@]}"; do
      if [[ "$token" =~ ^[0-9]+$ ]]; then
        local n="$token"
        [[ "$n" -ge 1 && "$n" -le "${#wizard_files[@]}" ]] || fail "Неверный номер: $n"
        selected+=("${wizard_files[$((n - 1))]}")
      elif [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        local a="${BASH_REMATCH[1]}"
        local b="${BASH_REMATCH[2]}"
        [[ "$a" -ge 1 && "$b" -ge 1 && "$a" -le "${#wizard_files[@]}" && "$b" -le "${#wizard_files[@]}" ]] || fail "Неверный диапазон: $token"
        if [[ "$a" -gt "$b" ]]; then
          local tmp="$a"; a="$b"; b="$tmp"
        fi
        local n
        for ((n=a; n<=b; n++)); do
          selected+=("${wizard_files[$((n - 1))]}")
        done
      else
        fail "Неверный формат: $token"
      fi
    done

    selected_list_file="$(mktemp)"
    printf '%s\n' "${selected[@]}" >"$selected_list_file"
    >&2 echo "🎯 Выбрано тестов: ${#selected[@]}"
    >&2 echo
  fi

  # Возвращаем значения через stdout (4 строки)
  # 1) suite 2) pattern 3) fail-fast 4) optional file with selected tests
  printf '%s\n' "$suite" "$pattern" "$ff" "$selected_list_file"
}

main() {
  local suite="all"
  local pattern=""
  local list_only=0
  local fail_fast=0

  if [[ "$#" -eq 0 ]]; then
    if [[ -t 0 ]]; then
      local wizard_out
      wizard_out="$(run_wizard)"
      suite="$(echo "$wizard_out" | sed -n '1p')"
      pattern="$(echo "$wizard_out" | sed -n '2p')"
      fail_fast="$(echo "$wizard_out" | sed -n '3p')"
      local wizard_selected_file
      wizard_selected_file="$(echo "$wizard_out" | sed -n '4p')"
    fi
  fi

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -h|--help) print_help; return 0 ;;
      --list) list_only=1; shift ;;
      -v|--verbose) export UPLOADTOOL_TEST_VERBOSE=1; shift ;;
      --fail-fast) fail_fast=1; shift ;;
      --all) suite="all"; shift ;;
      --unit) suite="unit"; shift ;;
      --integration) suite="integration"; shift ;;
      --smoke) suite="smoke"; shift ;;
      --regression) suite="regression"; shift ;;
      --pattern)
        pattern="${2:-}"
        [[ -n "$pattern" ]] || fail "Не указан аргумент для --pattern"
        shift 2
        ;;
      --*) fail "Неизвестная опция: $1" ;;
      *)
        pattern="$1"
        shift
        ;;
    esac
  done

  local files=()
  if [[ -n "${wizard_selected_file:-}" && -f "${wizard_selected_file}" ]]; then
    trap 'rm -f "${wizard_selected_file}"' EXIT
    while IFS= read -r f; do
      [[ -n "$f" ]] && files+=("$f")
    done <"${wizard_selected_file}"
  else
    while IFS= read -r f; do
      [[ -n "$f" ]] && files+=("$f")
    done < <(collect_test_files "$suite" "$pattern")
  fi

  [[ "${#files[@]}" -gt 0 ]] || fail "Тесты не найдены в $TESTS_DIR"

  if [[ "$list_only" -eq 1 ]]; then
    local f
    for f in "${files[@]}"; do
      printf '%s\t%s\t%s\t%s\n' "$(test_suite_of_file "$f")" "$(basename "$f")" "$(test_description_of_file "$f")" "$f"
    done
    return 0
  fi

  local started
  started="$(date +%s)"

  echo "🧪 UploadTool: запуск тестов"
  echo "   📦 suite:   $suite"
  [[ -n "$pattern" ]] && echo "   🔎 pattern: $pattern"
  echo "   🧾 files:   ${#files[@]}"
  echo

  local passed=0
  local failed=0

  local f
  for f in "${files[@]}"; do
    local base
    base="$(basename "$f")"
    printf '➡️  %s — %s\n' "$base" "$(test_description_of_file "$f")"
    if run_test_file "$f"; then
      passed=$((passed + 1))
      printf '✅ %s\n\n' "$base"
    else
      failed=$((failed + 1))
      printf '❌ %s\n\n' "$base" >&2
      if [[ "$fail_fast" -eq 1 ]]; then
        break
      fi
    fi
  done

  local elapsed
  elapsed=$(( $(date +%s) - started ))

  echo "📊 Итог:"
  echo "   ✅ Passed: $passed"
  echo "   ❌ Failed: $failed"
  echo "   ⏱️  Time:   ${elapsed}s"

  if [[ "$failed" -eq 0 ]]; then
    echo "🎉 Все тесты прошли"
    return 0
  fi

  echo "💥 Есть упавшие тесты" >&2
  return 1
}

main "$@"
