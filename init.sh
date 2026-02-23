#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${BASH_VERSION:-}" ]]; then
  exec bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UPLOAD_TOOL_DIR="$SCRIPT_DIR"

if [[ ! -d "$UPLOAD_TOOL_DIR/lib" ]]; then
  echo "❌ Не найдена папка lib рядом с init.sh: $UPLOAD_TOOL_DIR/lib" >&2
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

echo
echo "🧰 UploadTool — инициализация проекта (wizard)"
echo "✨ Сейчас я помогу быстро подготовить конфиги и базовые значения."
echo "🔐 Секреты (ASC/Google Play) я не спрашиваю — их нужно будет дописать в release.env вручную."
echo

def_project_root=""
project_candidate="$(cd "$UPLOAD_TOOL_DIR/.." && pwd)"
if [[ -f "${PWD}/pubspec.yaml" ]]; then
  def_project_root="$PWD"
elif [[ -f "$project_candidate/pubspec.yaml" ]]; then
  def_project_root="$project_candidate"
fi

project_root="$(prompt "📁 Путь к Flutter‑проекту (где pubspec.yaml)" "$def_project_root")"
project_root="$(expand_path "$project_root")"

if [[ -z "$project_root" ]]; then
  echo "❌ Путь к проекту не задан" >&2
  exit 1
fi
if [[ ! -d "$project_root" ]]; then
  echo "❌ Директория проекта не найдена: $project_root" >&2
  exit 1
fi
project_root="$(cd "$project_root" && pwd)"
if [[ ! -f "$project_root/pubspec.yaml" ]]; then
  echo "❌ Не найден pubspec.yaml в: $project_root" >&2
  exit 1
fi

def_config_dir=""
if [[ -d "$project_root/.uploadtool" ]]; then
  def_config_dir="$project_root/.uploadtool"
else
  def_config_dir="$project_root/.uploadtool"
fi
config_dir="$(prompt "⚙️  Директория конфигов (обычно .uploadtool рядом с проектом)" "$def_config_dir")"
config_dir="$(expand_path "$config_dir")"
if [[ -z "$config_dir" ]]; then
  echo "❌ Директория конфигов не задана" >&2
  exit 1
fi
if [[ "$config_dir" != /* ]]; then
  config_dir="$project_root/$config_dir"
fi
mkdir -p "$config_dir"
config_dir="$(cd "$config_dir" && pwd)"

force_overwrite="$(prompt_yes_no "♻️  Перезаписывать существующие env.json/release.env/wizard.env?" "n")"

save_defaults="$(prompt_yes_no "💾 Создать локальный cli.env (чтобы потом запускать без постоянных --project-root/--config-dir)?" "y")"
cli_env_file=""
if [[ "$save_defaults" -eq 1 ]]; then
  def_cli_env="$config_dir/cli.env"
  cli_env_file="$(prompt "📄 Путь к cli.env" "$def_cli_env")"
  cli_env_file="$(expand_path "$cli_env_file")"
  if [[ -z "$cli_env_file" ]]; then
    echo "❌ cli.env не задан" >&2
    exit 1
  fi
fi

profiles_dir="$(uploadtool_profiles_dir)"
save_profile="0"
if [[ -n "$profiles_dir" ]]; then
  save_profile="$(prompt_yes_no "📦 Сохранить проект в реестр (чтобы можно было выбирать его при запуске UploadTool)?" "y")"
else
  echo "ℹ️  Реестр проектов недоступен (нет HOME и не задан UPLOADTOOL_PROFILES_DIR) — пропускаю сохранение профиля."
fi
profile_name=""
set_default_profile="0"
overwrite_profile="0"
if [[ "$save_profile" -eq 1 ]]; then
  default_profile_name="$(basename "$project_root")"
  profile_name="$(prompt "🏷️  Имя проекта (profile)" "$default_profile_name")"
  profile_name="${profile_name:-$default_profile_name}"
  if uploadtool_profile_exists "$profile_name"; then
    overwrite_profile="$(prompt_yes_no "⚠️  Профиль '$profile_name' уже существует. Перезаписать?" "n")"
    if [[ "$overwrite_profile" -ne 1 ]]; then
      save_profile="0"
    fi
  fi

  if [[ "$save_profile" -eq 1 ]]; then
    set_default_profile="$(prompt_yes_no "⭐ Сделать '$profile_name' проектом по умолчанию?" "y")"
  fi
fi

def_fastlane_root="$UPLOAD_TOOL_DIR/fastlane"
if [[ ! -f "$def_fastlane_root/Gemfile" ]]; then
  def_fastlane_root="$project_root/ios"
fi
fastlane_root="$(prompt "🧩 Fastlane root (где Gemfile)" "$def_fastlane_root")"
fastlane_root="$(expand_path "$fastlane_root")"

env_key="$(prompt "🔑 Ключ окружения для env.json" "APP_ENV")"
env_key="${env_key:-APP_ENV}"

app_env="$(prompt "🌍 Окружение приложения (dev/prod)" "prod")"

base_url="$(prompt "🌐 BASE_URL (опционально, можно оставить пустым)" "")"

ios_app_id="$(prompt "🍎 iOS bundle id (IOS_APP_IDENTIFIER), опционально" "")"
android_pkg="$(prompt "🤖 Android applicationId (ANDROID_PACKAGE_NAME), опционально" "")"

echo
echo "📋 Итоговые значения:"
echo "   📁 Project:  $project_root"
echo "   ⚙️  Config:   $config_dir"
echo "   🧩 Fastlane: $fastlane_root"
echo "   🔑 env.json: $env_key=$app_env"
[[ -n "$base_url" ]] && echo "   🌐 env.json: BASE_URL=$base_url"
[[ -n "$ios_app_id" ]] && echo "   🍎 release.env: IOS_APP_IDENTIFIER=$ios_app_id"
[[ -n "$android_pkg" ]] && echo "   🤖 release.env: ANDROID_PACKAGE_NAME=$android_pkg"
if [[ "$save_defaults" -eq 1 ]]; then
  echo "   💾 cli.env: $cli_env_file"
fi
if [[ "$save_profile" -eq 1 ]]; then
  echo "   📦 profile: $profile_name"
  if [[ "$set_default_profile" -eq 1 ]]; then
    echo "   ⭐ default project: $profile_name"
  fi
fi

ok="$(prompt_yes_no "🚀 Продолжить инициализацию?" "y")"
if [[ "$ok" -ne 1 ]]; then
  echo "Остановлено." >&2
  exit 1
fi

echo
echo "🚀 Выполняю init..."

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
echo "✅ Готово"
echo "   - $config_dir/env.json"
echo "   - $config_dir/release.env"
echo "   - $config_dir/wizard.env"

if [[ "$save_defaults" -eq 1 ]]; then
  echo "   - $cli_env_file"
fi

if [[ "$save_profile" -eq 1 ]]; then
  profiles_dir="$(uploadtool_profiles_dir)"
  if [[ -n "$profiles_dir" ]]; then
    echo "   - $profiles_dir/$profile_name.env"
  fi
fi

echo
echo "Дальше:"
echo "1) 🔐 Заполни секреты в $config_dir/release.env"
echo "2) 🧙 Запусти мастер релиза:"
if [[ "$save_profile" -eq 1 ]]; then
  echo "   bash $UPLOAD_TOOL_DIR/run.sh --project $profile_name"
elif [[ "$save_defaults" -eq 1 ]]; then
  echo "   bash $UPLOAD_TOOL_DIR/run.sh --cli-env-file $cli_env_file"
else
  echo "   bash $UPLOAD_TOOL_DIR/run.sh --project-root $project_root --config-dir $config_dir"
fi
echo
