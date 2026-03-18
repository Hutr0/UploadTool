#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${BASH_VERSION:-}" ]]; then
  exec bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UPLOAD_TOOL_DIR="$SCRIPT_DIR"

if [[ ! -d "$UPLOAD_TOOL_DIR/lib" ]]; then
  echo "❌ Could not find lib directory next to init.sh: $UPLOAD_TOOL_DIR/lib" >&2
  exit 1
fi

prompt() {
  local text="$1"
  local def="${2:-}"

  local ans
  if [[ -n "$def" ]]; then
    read -r -p "$text [$def]: " ans
    ans="${ans:-$def}"
  else
    read -r -p "$text: " ans
  fi
  printf '%s' "$ans"
}

prompt_yes_no() {
  local text="$1"
  local def="${2:-y}"

  local def_l
  def_l="$(echo "$def" | tr '[:upper:]' '[:lower:]')"

  local ans
  read -r -p "$text (y/n) [$def_l]: " ans
  ans="${ans:-$def_l}"

  case "$ans" in
    y|Y|yes|YES) echo 1 ;;
    *) echo 0 ;;
  esac
}

expand_path() {
  local p="$1"
  if [[ -n "${HOME:-}" && "$p" == ~/* ]]; then
    echo "$HOME/${p#~/}"
    return 0
  fi
  echo "$p"
}

set_json_key() {
  local path="$1"
  local key="$2"
  local value="$3"

  python3 - <<'PY' "$path" "$key" "$value"
import json, sys, os
path = sys.argv[1]
key = sys.argv[2]
value = sys.argv[3]

data = {}
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f) or {}
except Exception:
    data = {}
if not isinstance(data, dict):
    data = {}

data[key] = value

dir_name = os.path.dirname(path)
if dir_name:
    os.makedirs(dir_name, exist_ok=True)

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
}

set_dotenv_var() {
  local path="$1"
  local key="$2"
  local value="$3"

  python3 - <<'PY' "$path" "$key" "$value"
import re, sys
path = sys.argv[1]
key = sys.argv[2]
value = sys.argv[3]

try:
    with open(path, "r", encoding="utf-8") as f:
        lines = f.readlines()
except Exception:
    lines = []

escaped = value.replace('"', '\\"')
new_line = f'{key}="{escaped}"\n'

pattern = re.compile(r"^\s*#?\s*" + re.escape(key) + r"\s*=.*$")
found = False
out = []
for line in lines:
    if pattern.match(line):
        out.append(new_line)
        found = True
    else:
        out.append(line)

if not found:
    if out and not out[-1].endswith("\n"):
        out[-1] = out[-1] + "\n"
    if out and out[-1].strip() != "":
        out.append("\n")
    out.append(new_line)

with open(path, "w", encoding="utf-8") as f:
    f.writelines(out)
PY
}

source "$UPLOAD_TOOL_DIR/lib/env_json.sh"
source "$UPLOAD_TOOL_DIR/lib/profiles.sh"
source "$UPLOAD_TOOL_DIR/lib/i18n.sh"
uploadtool_i18n_init

echo
echo "$MSG_INIT_TITLE"
echo "$MSG_INIT_SUBTITLE_SETUP"
echo "$MSG_INIT_SUBTITLE_SECRETS"
echo

def_project_root=""
project_candidate="$(cd "$UPLOAD_TOOL_DIR/.." && pwd)"
if [[ -f "${PWD}/pubspec.yaml" ]]; then
  def_project_root="$PWD"
elif [[ -f "$project_candidate/pubspec.yaml" ]]; then
  def_project_root="$project_candidate"
fi

project_root="$(prompt "$MSG_INIT_PROMPT_PROJECT_ROOT" "$def_project_root")"
project_root="$(expand_path "$project_root")"

if [[ -z "$project_root" ]]; then
  echo "$MSG_INIT_ERR_PROJECT_PATH_EMPTY" >&2
  exit 1
fi
if [[ ! -d "$project_root" ]]; then
  printf "$MSG_INIT_ERR_PROJECT_DIR_NOT_FOUND\n" "$project_root" >&2
  exit 1
fi
project_root="$(cd "$project_root" && pwd)"
if [[ ! -f "$project_root/pubspec.yaml" ]]; then
  printf "$MSG_INIT_ERR_PUBSPEC_NOT_FOUND\n" "$project_root" >&2
  exit 1
fi

def_config_dir=""
if [[ -d "$project_root/.uploadtool" ]]; then
  def_config_dir="$project_root/.uploadtool"
else
  def_config_dir="$project_root/.uploadtool"
fi
config_dir="$(prompt "$MSG_INIT_PROMPT_CONFIG_DIR" "$def_config_dir")"
config_dir="$(expand_path "$config_dir")"
if [[ -z "$config_dir" ]]; then
  echo "$MSG_INIT_ERR_CONFIG_DIR_EMPTY" >&2
  exit 1
fi
if [[ "$config_dir" != /* ]]; then
  config_dir="$project_root/$config_dir"
fi
mkdir -p "$config_dir"
config_dir="$(cd "$config_dir" && pwd)"

force_overwrite="$(prompt_yes_no "$MSG_INIT_PROMPT_FORCE_OVERWRITE" "n")"

save_defaults="$(prompt_yes_no "$MSG_INIT_PROMPT_SAVE_DEFAULTS" "y")"
cli_env_file=""
if [[ "$save_defaults" -eq 1 ]]; then
  def_cli_env="$config_dir/cli.env"
  cli_env_file="$(prompt "$MSG_INIT_PROMPT_CLI_ENV_PATH" "$def_cli_env")"
  cli_env_file="$(expand_path "$cli_env_file")"
  if [[ -z "$cli_env_file" ]]; then
    echo "$MSG_INIT_ERR_CLI_ENV_EMPTY" >&2
    exit 1
  fi
fi

profiles_dir="$(uploadtool_profiles_dir)"
save_profile="0"
if [[ -n "$profiles_dir" ]]; then
  save_profile="$(prompt_yes_no "$MSG_INIT_PROMPT_SAVE_PROFILE" "y")"
else
  echo "$MSG_INIT_INFO_PROFILES_UNAVAILABLE"
fi
profile_name=""
set_default_profile="0"
overwrite_profile="0"
if [[ "$save_profile" -eq 1 ]]; then
  default_profile_name="$(basename "$project_root")"
  profile_name="$(prompt "$MSG_INIT_PROMPT_PROFILE_NAME" "$default_profile_name")"
  profile_name="${profile_name:-$default_profile_name}"
  if uploadtool_profile_exists "$profile_name"; then
    overwrite_profile="$(prompt_yes_no "$(printf "$MSG_INIT_PROMPT_PROFILE_OVERWRITE" "$profile_name")" "n")"
    if [[ "$overwrite_profile" -ne 1 ]]; then
      save_profile="0"
    fi
  fi

  if [[ "$save_profile" -eq 1 ]]; then
    set_default_profile="$(prompt_yes_no "$(printf "$MSG_INIT_PROMPT_SET_DEFAULT_PROFILE" "$profile_name")" "y")"
  fi
fi

def_fastlane_root="$UPLOAD_TOOL_DIR/fastlane"
if [[ ! -f "$def_fastlane_root/Gemfile" ]]; then
  def_fastlane_root="$project_root/ios"
fi
fastlane_root="$(prompt "$MSG_INIT_PROMPT_FASTLANE_ROOT" "$def_fastlane_root")"
fastlane_root="$(expand_path "$fastlane_root")"

env_key="$(prompt "$MSG_INIT_PROMPT_ENV_KEY" "APP_ENV")"
env_key="${env_key:-APP_ENV}"

app_env="$(prompt "$MSG_INIT_PROMPT_APP_ENV" "prod")"

base_url="$(prompt "$MSG_INIT_PROMPT_BASE_URL" "")"

ios_app_id="$(prompt "$MSG_INIT_PROMPT_IOS_APP_ID" "")"
android_pkg="$(prompt "$MSG_INIT_PROMPT_ANDROID_PKG" "")"

echo
echo "$MSG_INIT_SUMMARY_TITLE"
printf "$MSG_INIT_SUMMARY_PROJECT\n" "$project_root"
printf "$MSG_INIT_SUMMARY_CONFIG\n" "$config_dir"
printf "$MSG_INIT_SUMMARY_FASTLANE\n" "$fastlane_root"
printf "$MSG_INIT_SUMMARY_ENV_KEY\n" "$env_key" "$app_env"
[[ -n "$base_url" ]] && printf "$MSG_INIT_SUMMARY_BASE_URL\n" "$base_url"
[[ -n "$ios_app_id" ]] && printf "$MSG_INIT_SUMMARY_IOS_APP_ID\n" "$ios_app_id"
[[ -n "$android_pkg" ]] && printf "$MSG_INIT_SUMMARY_ANDROID_PKG\n" "$android_pkg"
if [[ "$save_defaults" -eq 1 ]]; then
  printf "$MSG_INIT_SUMMARY_CLI_ENV\n" "$cli_env_file"
fi
if [[ "$save_profile" -eq 1 ]]; then
  printf "$MSG_INIT_SUMMARY_PROFILE\n" "$profile_name"
  if [[ "$set_default_profile" -eq 1 ]]; then
    printf "$MSG_INIT_SUMMARY_DEFAULT_PROFILE\n" "$profile_name"
  fi
fi

ok="$(prompt_yes_no "$MSG_INIT_PROMPT_CONFIRM_INIT" "y")"
if [[ "$ok" -ne 1 ]]; then
  echo "$MSG_INIT_ABORTED" >&2
  exit 1
fi

echo
echo "$MSG_INIT_RUNNING"

args=("init" "--project-root" "$project_root" "--config-dir" "$config_dir" "--fastlane-root" "$fastlane_root" "--env-key" "$env_key")
if [[ "$force_overwrite" -eq 1 ]]; then
  args+=("--force")
else
  args+=("--no-force")
fi
if [[ "$save_defaults" -eq 1 ]]; then
  args+=("--save-defaults" "--cli-env-file" "$cli_env_file")
else
  args+=("--no-save-defaults")
fi

bash "$UPLOAD_TOOL_DIR/run.sh" "${args[@]}"

if [[ "$save_profile" -eq 1 ]]; then
  uploadtool_save_profile "$profile_name" "$project_root" "$config_dir" "$fastlane_root" "$env_key"
  if [[ "$set_default_profile" -eq 1 ]]; then
    uploadtool_set_default_profile "$profile_name"
  fi
fi

env_json_path="$config_dir/env.json"
release_env_path="$config_dir/release.env"

uploadtool_write_env_to_file "$env_json_path" "$app_env" "$env_key"
if [[ -n "$base_url" ]]; then
  set_json_key "$env_json_path" "BASE_URL" "$base_url"
fi

if [[ -n "$ios_app_id" ]]; then
  set_dotenv_var "$release_env_path" "IOS_APP_IDENTIFIER" "$ios_app_id"
fi
if [[ -n "$android_pkg" ]]; then
  set_dotenv_var "$release_env_path" "ANDROID_PACKAGE_NAME" "$android_pkg"
fi

echo
echo "$MSG_INIT_DONE_TITLE"
echo "$MSG_INIT_DONE_FILES_HEADER"
printf "$MSG_INIT_DONE_ENV_JSON\n" "$config_dir"
printf "$MSG_INIT_DONE_RELEASE_ENV\n" "$config_dir"
printf "$MSG_INIT_DONE_WIZARD_ENV\n" "$config_dir"

if [[ "$save_defaults" -eq 1 ]]; then
  printf "$MSG_INIT_DONE_CLI_ENV\n" "$cli_env_file"
fi

if [[ "$save_profile" -eq 1 ]]; then
  profiles_dir="$(uploadtool_profiles_dir)"
  if [[ -n "$profiles_dir" ]]; then
    printf "$MSG_INIT_DONE_PROFILE_FILE\n" "$profiles_dir" "$profile_name"
  fi
fi

echo
echo "$MSG_INIT_NEXT_STEPS_TITLE"
printf "$MSG_INIT_NEXT_FILL_SECRETS\n" "$config_dir"
echo "2) 🧙"
if [[ "$save_profile" -eq 1 ]]; then
  printf "$MSG_INIT_NEXT_RUN_WIZARD_FROM_PROFILE\n" "$UPLOAD_TOOL_DIR" "$profile_name"
elif [[ "$save_defaults" -eq 1 ]]; then
  printf "$MSG_INIT_NEXT_RUN_WIZARD_FROM_CLI_ENV\n" "$UPLOAD_TOOL_DIR" "$cli_env_file"
else
  printf "$MSG_INIT_NEXT_RUN_WIZARD_FROM_PATHS\n" "$UPLOAD_TOOL_DIR" "$project_root" "$config_dir"
fi
echo
