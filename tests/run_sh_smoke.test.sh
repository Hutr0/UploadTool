#!/usr/bin/env bash

TEST_DESCRIPTION="Smoke: полный прогон run.sh в фейковом репо с моками команд"

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPLOAD_TOOL_DIR="$(cd "${TEST_DIR}/.." && pwd)"

_failed=0
check() {
  if ! "$@"; then
    _failed=1
  fi
}

assert_file_exists() {
  local path="$1"
  local msg="${2:-}"
  if [[ ! -f "$path" ]]; then
    echo "Missing file: $path" >&2
    [[ -n "$msg" ]] && echo "$msg" >&2
    return 1
  fi
}

_tmp="$(mktemp -d)"

# Minimal fake repo in temp
cp -R "${UPLOAD_TOOL_DIR}" "${_tmp}/UploadTool"

# Provide embedded fastlane config (Gemfile) for bundle install step
mkdir -p "${_tmp}/UploadTool/fastlane"
printf "source 'https://rubygems.org'\n" > "${_tmp}/UploadTool/fastlane/Gemfile"

# В рабочем репо эти файлы могут существовать локально (они gitignored) и ломать тест,
# переопределяя переменные окружения. Для smoke-теста они не нужны.
rm -f "${_tmp}/UploadTool/config/wizard.env" || true
rm -f "${_tmp}/UploadTool/config/release.env" || true
rm -f "${_tmp}/UploadTool/config/env.json" || true

cat > "${_tmp}/pubspec.yaml" <<'YAML'
name: dummy
version: 1.2.3+1
YAML

cat > "${_tmp}/release.env" <<'ENV'
# empty on purpose for smoke test
ENV

# Stub external tools
stub_bin="${_tmp}/stub_bin"
mkdir -p "$stub_bin"

cat > "${stub_bin}/flutter" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "pub" && "${2:-}" == "get" ]]; then
  exit 0
fi

if [[ "${1:-}" == "build" && "${2:-}" == "--help" ]]; then
  echo "--no-pub"
  echo "--dart-define-from-file"
  exit 0
fi

if [[ "${1:-}" == "build" && "${2:-}" == "appbundle" ]]; then
  mkdir -p build/app/outputs/bundle/release
  printf 'dummy-aab' > build/app/outputs/bundle/release/app-release.aab
  exit 0
fi

if [[ "${1:-}" == "build" && "${2:-}" == "ipa" ]]; then
  mkdir -p build/ios/ipa
  printf 'dummy-ipa' > build/ios/ipa/app-release.ipa
  exit 0
fi

exit 0
SH
chmod +x "${stub_bin}/flutter"

cat > "${stub_bin}/bundle" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
# bundle install / bundle exec are no-ops in smoke test
exit 0
SH
chmod +x "${stub_bin}/bundle"

# Run wizard non-interactively (skip most prompts; provide empty inputs for remaining ones)
(
  export PATH="${stub_bin}:$PATH"
  export UPLOADTOOL_TODAY_YYYYMMDD="20260221"

  export UPLOADTOOL_SKIP_SAFE_PATH="1"

  export WIZARD_SKIP_TARGETS="1"
  export WIZARD_DEFAULT_TARGETS="both"

  export WIZARD_SKIP_ENV="1"
  export WIZARD_DEFAULT_ENV="dev"

  export WIZARD_SKIP_UPLOAD_PROMPTS="1"
  export WIZARD_DEFAULT_UPLOAD_IOS="0"
  export WIZARD_DEFAULT_UPLOAD_ANDROID="0"

  export WIZARD_SKIP_WAIT_IOS_PROMPT="1"
  export WIZARD_DEFAULT_WAIT_IOS="0"

  export WIZARD_SKIP_FINAL_CONFIRM="1"

  export UPLOADTOOL_FASTLANE_ROOT="${_tmp}/UploadTool/fastlane"

  cd "${_tmp}"
  printf '\n%.0s' {1..30} | bash "${_tmp}/UploadTool/run.sh" --env-file "${_tmp}/release.env"
)
rc=$?
if [[ "$rc" -ne 0 ]]; then
  echo "run.sh smoke failed rc=$rc" >&2
  _failed=1
else
  # Validate artifacts produced
  state_dir="${_tmp}/UploadTool/state/dev"
  assert_file_exists "${state_dir}/android_aab_path.txt" || _failed=1
  assert_file_exists "${state_dir}/ios_ipa_path.txt" || _failed=1
  aab_path="$(cat "${state_dir}/android_aab_path.txt" | tr -d '\r\n')"
  ipa_path="$(cat "${state_dir}/ios_ipa_path.txt" | tr -d '\r\n')"
  assert_file_exists "$aab_path" "AAB artifact должен существовать" || _failed=1
  assert_file_exists "$ipa_path" "IPA artifact должен существовать" || _failed=1
fi

rm -rf "${_tmp}"

return "${_failed}"
