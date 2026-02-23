#!/usr/bin/env bash

uploadtool_write_env_to_file() {
  local path="$1"
  local env="$2"
  local env_key="${3:-${UPLOADTOOL_ENV_JSON_ENV_KEY:-}}"
  python3 - <<'PY' "$path" "$env" "${env_key}"
import json, sys, os
path = sys.argv[1]
env = sys.argv[2]
data = {}
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f) or {}
except Exception:
    data = {}
if not isinstance(data, dict):
    data = {}

env_key = os.environ.get("UPLOADTOOL_ENV_JSON_ENV_KEY", "").strip()

# Optional third arg can override key name without relying on env vars.
if len(sys.argv) >= 4 and sys.argv[3].strip() != "":
    env_key = sys.argv[3].strip()

if env_key == "":
    # Default for universal mode
    env_key = "APP_ENV"
    # Backward compatibility: if file already uses CHOYS_ENV and not APP_ENV, keep using it
    if "CHOYS_ENV" in data and "APP_ENV" not in data:
        env_key = "CHOYS_ENV"

data[env_key] = env
dir_name = os.path.dirname(path)
if dir_name:
    os.makedirs(dir_name, exist_ok=True)
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
}
