#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

# On macOS /bin/sh is often bash in POSIX mode (disabling features like process substitution).
# Relaunch under regular bash to ensure the runner works.
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
🧪 UploadTool — test runner

Usage:
  ./UploadTool/test.sh                     # all tests
  ./UploadTool/test.sh --unit              # unit only
  ./UploadTool/test.sh --integration       # integration only
  ./UploadTool/test.sh --smoke             # smoke only
  ./UploadTool/test.sh --regression        # regression only
  ./UploadTool/test.sh --pattern "*.test.sh" # arbitrary glob
  ./UploadTool/test.sh --list              # list discovered tests

Options:
  -v, --verbose     show output even on success
  --fail-fast       stop on first failure
  -h, --help        show help

Note:
  When invoked via `sh`, the script relaunches under `bash` automatically.

Interactive mode:
  ./UploadTool/test.sh
  (without arguments an interactive selector will appear)
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
    desc="$(sed -nE 's/^# *Description: *(.*)$/\1/p' "$f" | head -n 1)"
  fi
  if [[ -n "$desc" ]]; then
    echo "$desc"
    return 0
  fi

  case "$base" in
    versioning.test.sh)
      echo "Versioning: extract/increment build numbers and format env string"
      ;;
    android_version_code.test.sh)
      echo "Android: compute versionCode from build number"
      ;;
    notes.test.sh)
      echo "Release notes: build release description"
      ;;
    runner.test.sh)
      echo "Infra runner: mock external commands and tracing"
      ;;
    time.test.sh)
      echo "Infra time: mock sleep/await"
      ;;
    env_json.test.sh)
      echo "env.json: write APP_ENV and keep other keys"
      ;;
    config.test.sh)
      echo "Configs: select/load release.env & wizard.env"
      ;;
    config_validation.test.sh)
      echo "Fail-fast: validate required fields for iOS/Android upload"
      ;;
    workflow_build_integration.test.sh)
      echo "Workflow: integration test for iOS/Android builds"
      ;;
    workflow_build_and_upload_integration.test.sh)
      echo "Workflow: integration test for build+upload orchestration"
      ;;
    workflow_wait_pubspec_integration.test.sh)
      echo "Workflow: wait for uploads + pubspec update"
      ;;
    workflow_run_for_env_integration.test.sh)
      echo "Workflow: run_for_env (env prep, build numbers, notes, orchestration)"
      ;;
    run_sh_smoke.test.sh)
      echo "Smoke: full run.sh run with mocked commands"
      ;;
    *)
      echo "(no description)"
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
  >&2 echo "🧙 Select test mode:"
  >&2 echo "   1) All"
  >&2 echo "   2) Unit"
  >&2 echo "   3) Integration"
  >&2 echo "   4) Smoke"
  >&2 echo "   5) Regression"
  >&2 echo "   6) Custom glob"
  >&2 echo

  local choice
  read -r -p "Choice [1]: " choice
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
      read -r -p "Enter glob (e.g. *.test.sh): " pattern
      [[ -n "$pattern" ]] || fail "Empty glob" 
      ;;
    *) fail "Invalid choice: $choice" ;;
  esac

  local verbose
  verbose="$(prompt_yes_no "Show output for successful tests?" "n")"
  local ff
  ff="$(prompt_yes_no "Stop on first failure?" "n")"

  if [[ "$verbose" -eq 1 ]]; then
    export UPLOADTOOL_TEST_VERBOSE=1
  fi

  >&2 echo
  >&2 echo "📋 Selected:"
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
    fail "Tests not found in $TESTS_DIR"
  fi

  >&2 echo "🗂️  Discovered tests (${#wizard_files[@]}):"
  local i
  for i in "${!wizard_files[@]}"; do
    local tf="${wizard_files[$i]}"
    >&2 printf '   %2d) %s — %s\n' "$((i + 1))" "$(basename "$tf")" "$(test_description_of_file "$tf")"
  done
  >&2 echo

  local run_all
  run_all="$(prompt_yes_no "Run all discovered tests?" "Y")"

  local selected_list_file=""
  if [[ "$run_all" -ne 1 ]]; then
    local sel
    read -r -p "Enter indices (e.g. 1,3,5-7): " sel
    sel="${sel//[[:space:]]/}"
    [[ -n "$sel" ]] || fail "Empty selection"

    local selected=()
    local token
    IFS=',' read -r -a _tokens <<<"$sel"
    for token in "${_tokens[@]}"; do
      if [[ "$token" =~ ^[0-9]+$ ]]; then
        local n="$token"
        [[ "$n" -ge 1 && "$n" -le "${#wizard_files[@]}" ]] || fail "Invalid index: $n"
        selected+=("${wizard_files[$((n - 1))]}")
      elif [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        local a="${BASH_REMATCH[1]}"
        local b="${BASH_REMATCH[2]}"
        [[ "$a" -ge 1 && "$b" -ge 1 && "$a" -le "${#wizard_files[@]}" && "$b" -le "${#wizard_files[@]}" ]] || fail "Invalid range: $token"
        if [[ "$a" -gt "$b" ]]; then
          local tmp="$a"; a="$b"; b="$tmp"
        fi
        local n
        for ((n=a; n<=b; n++)); do
          selected+=("${wizard_files[$((n - 1))]}")
        done
      else
        fail "Invalid format: $token"
      fi
    done

    selected_list_file="$(mktemp)"
    printf '%s\n' "${selected[@]}" >"$selected_list_file"
    >&2 echo "🎯 Selected tests: ${#selected[@]}"
    >&2 echo
  fi

  # Return values via stdout (4 lines): suite, pattern, fail-fast, optional file with selected tests
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
        [[ -n "$pattern" ]] || fail "Missing argument for --pattern"
        shift 2
        ;;
      --*) fail "Unknown option: $1" ;;
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

  [[ "${#files[@]}" -gt 0 ]] || fail "Tests not found in $TESTS_DIR"

  if [[ "$list_only" -eq 1 ]]; then
    local f
    for f in "${files[@]}"; do
      printf '%s\t%s\t%s\t%s\n' "$(test_suite_of_file "$f")" "$(basename "$f")" "$(test_description_of_file "$f")" "$f"
    done
    return 0
  fi

  local started
  started="$(date +%s)"

  echo "🧪 UploadTool: running tests"
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

  echo "📊 Summary:"
  echo "   ✅ Passed: $passed"
  echo "   ❌ Failed: $failed"
  echo "   ⏱️  Time:   ${elapsed}s"

  if [[ "$failed" -eq 0 ]]; then
    echo "🎉 All tests passed"
    return 0
  fi

  echo "💥 Some tests failed" >&2
  return 1
}

main "$@"
