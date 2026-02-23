#!/usr/bin/env bash

TEST_DESCRIPTION="Smoke: init.sh wizard (создание .uploadtool + базовое заполнение env.json/release.env + cli.env)"

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPLOAD_TOOL_DIR="$(cd "${TEST_DIR}/.." && pwd)"

_failed=0

assert_file_exists() {
  local path="$1"
  local msg="${2:-}"
  if [[ ! -f "$path" ]]; then
    echo "Missing file: $path" >&2
    [[ -n "$msg" ]] && echo "$msg" >&2
    return 1
  fi
}

assert_dir_exists() {
  local path="$1"
  local msg="${2:-}"
  if [[ ! -d "$path" ]]; then
    echo "Missing dir: $path" >&2
    [[ -n "$msg" ]] && echo "$msg" >&2
    return 1
  fi
}

_tmp="$(mktemp -d)"

# Copy tool into temp to avoid relying on local working tree state
cp -R "${UPLOAD_TOOL_DIR}" "${_tmp}/UploadTool"

# Fake Flutter project
project_dir="${_tmp}/project"
mkdir -p "$project_dir"
cat > "${project_dir}/pubspec.yaml" <<'YAML'
name: dummy
version: 1.2.3+1
YAML

export HOME="${_tmp}/home"
mkdir -p "$HOME"

# Run init.sh wizard with predefined answers
(
  cd "${_tmp}/UploadTool"

  printf '%s\n' \
    "$project_dir" \
    "" \
    "n" \
    "y" \
    "" \
    "y" \
    "" \
    "y" \
    "" \
    "" \
    "dev" \
    "" \
    "com.example.app" \
    "com.example.app" \
    "y" \
  | bash "${_tmp}/UploadTool/init.sh"
) || _failed=1

assert_dir_exists "${project_dir}/.uploadtool" ".uploadtool должен быть создан" || _failed=1
assert_file_exists "${project_dir}/.uploadtool/env.json" "env.json должен быть создан" || _failed=1
assert_file_exists "${project_dir}/.uploadtool/release.env" "release.env должен быть создан" || _failed=1
assert_file_exists "${project_dir}/.uploadtool/wizard.env" "wizard.env должен быть создан" || _failed=1

# env.json should contain APP_ENV=dev
if ! grep -q '"APP_ENV"[[:space:]]*:[[:space:]]*"dev"' "${project_dir}/.uploadtool/env.json"; then
  echo "APP_ENV=dev not set in env.json" >&2
  _failed=1
fi

# release.env should contain app identifiers
if ! grep -q '^IOS_APP_IDENTIFIER="com\.example\.app"' "${project_dir}/.uploadtool/release.env"; then
  echo "IOS_APP_IDENTIFIER not set in release.env" >&2
  _failed=1
fi
if ! grep -q '^ANDROID_PACKAGE_NAME="com\.example\.app"' "${project_dir}/.uploadtool/release.env"; then
  echo "ANDROID_PACKAGE_NAME not set in release.env" >&2
  _failed=1
fi

# cli.env should be created under project config dir
cli_env_path="${project_dir}/.uploadtool/cli.env"
assert_file_exists "$cli_env_path" "cli.env должен быть создан" || _failed=1

if ! grep -q "^UPLOADTOOL_CLI_PROJECT_ROOT=\"${project_dir}\"$" "$cli_env_path"; then
  echo "UPLOADTOOL_CLI_PROJECT_ROOT not saved in cli.env" >&2
  _failed=1
fi

# profile should be created under HOME registry
profile_path="${HOME}/.uploadtool/projects/project.env"
assert_file_exists "$profile_path" "profile должен быть создан" || _failed=1

default_profile_file="${HOME}/.uploadtool/default_project"
assert_file_exists "$default_profile_file" "default_project должен быть создан" || _failed=1
if ! grep -q '^project$' "$default_profile_file"; then
  echo "default_project should be 'project'" >&2
  _failed=1
fi

rm -rf "${_tmp}"

return "${_failed}"
