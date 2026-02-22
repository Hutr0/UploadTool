#!/usr/bin/env bash

uploadtool_write_env_to_file() {
  local path="$1"
  local env="$2"
  python3 - <<'PY' "$path" "$env"
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
data["CHOYS_ENV"] = env
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
}
