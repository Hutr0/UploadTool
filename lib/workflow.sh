#!/usr/bin/env bash

uploadtool_cleanup_state_artifacts() {
  local artifacts_dir="$1"
  local tag="$2"
  local keep="${UPLOADTOOL_STATE_ARTIFACTS_KEEP:-3}"

  if [[ -z "$keep" ]]; then
    keep="3"
  fi
  if [[ ! "$keep" =~ ^[0-9]+$ ]]; then
    return 0
  fi
  if (( keep < 1 )); then
    return 0
  fi
  if [[ ! -d "$artifacts_dir" ]]; then
    return 0
  fi

  python3 - <<'PY' "$artifacts_dir" "$tag" "$keep"
import glob, os, sys

artifacts_dir = sys.argv[1]
tag = sys.argv[2]
keep = int(sys.argv[3])

for ext in ("ipa", "aab"):
    pattern = os.path.join(artifacts_dir, f"app-{tag}-*.{ext}")
    files = glob.glob(pattern)
    files.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    for p in files[keep:]:
        try:
            os.remove(p)
        except Exception:
            pass
PY
}

uploadtool_build_android() {
  local tag="$1"
  local state_dir="$2"
  local log="$UPLOAD_LOG_DIR/${tag}_android.log"
  printf "$MSG_WORKFLOW_ANDROID_BUILD_START\n" "$tag" "$log"
  local cmd=(flutter build appbundle --release --build-number "$ANDROID_BUILD_NUMBER")
  if [[ "${supports_no_pub:-0}" -eq 1 ]]; then cmd+=(--no-pub); fi
  local env_file="${state_dir}/dart_defines.json"
  if [[ -f "$env_file" ]]; then
    if [[ "${UPLOADTOOL_SUPPORTS_DART_DEFINE_FROM_FILE:-1}" == "1" ]]; then
      cmd+=(--dart-define-from-file="$env_file")
    else
      _dart_def_tmp="$(mktemp)"
      python3 - <<'PY' "$env_file" > "$_dart_def_tmp"
import json, sys
d = json.load(open(sys.argv[1], "r", encoding="utf-8"))
for k, v in d.items():
    print(f"{k}={v}")
PY
      while IFS= read -r kv; do
        [[ -z "$kv" ]] && continue
        cmd+=("--dart-define=$kv")
      done < "$_dart_def_tmp"
      rm -f "$_dart_def_tmp"
    fi
  else
    printf "$MSG_WORKFLOW_ANDROID_ENV_FILE_MISSING\n" "$env_file" "$tag" >&2
    return 1
  fi
  if [[ -n "${BUILD_NAME:-}" ]]; then cmd+=(--build-name "$BUILD_NAME"); fi
  {
    echo "$MSG_WORKFLOW_BUILD_ENV_HEADER"
    printf "$MSG_WORKFLOW_ENV_FILE_POINTER\n" "${UPLOADTOOL_ENV_JSON_ENV_KEY:-APP_ENV}" "$tag" "$env_file"
    printf "$MSG_WORKFLOW_ENV_FILE_CONTENTS\n" "$(tr -d '\n' < "$env_file" 2>/dev/null || true)"
    echo "$MSG_WORKFLOW_FLUTTER_BUILD_HEADER"
    uploadtool_run_cmd "${cmd[@]}"
  } >"$log" 2>&1
  local aab
  aab="$(ls -t build/app/outputs/bundle/release/*.aab 2>/dev/null | head -n 1 || true)"
  if [[ -z "$aab" ]]; then
    echo "[Android] No AAB found at build/app/outputs/bundle/release/*.aab" >>"$log"
    return 1
  fi
  local artifacts_dir="${state_dir}/artifacts"
  mkdir -p "$artifacts_dir"
  local aab_copy="${artifacts_dir}/app-${tag}-${BUILD_NUMBER}.aab"
  cp -f "$aab" "$aab_copy"
  uploadtool_cleanup_state_artifacts "$artifacts_dir" "$tag"
  echo "$aab_copy" > "${state_dir}/android_aab_path.txt"
  printf "$MSG_WORKFLOW_ANDROID_BUILD_DONE\n" "$tag" "$aab_copy"
}

uploadtool_build_ios() {
  local tag="$1"
  local state_dir="$2"
  local log="$UPLOAD_LOG_DIR/${tag}_ios.log"
  printf "$MSG_WORKFLOW_IOS_BUILD_START\n" "$tag" "$log"
  local cmd=(flutter build ipa --release)
  if [[ "${supports_no_pub:-0}" -eq 1 ]]; then cmd+=(--no-pub); fi
  local env_file="${state_dir}/dart_defines.json"
  if [[ -f "$env_file" ]]; then
    if [[ "${UPLOADTOOL_SUPPORTS_DART_DEFINE_FROM_FILE:-1}" == "1" ]]; then
      cmd+=(--dart-define-from-file="$env_file")
    else
      _dart_def_tmp="$(mktemp)"
      python3 - <<'PY' "$env_file" > "$_dart_def_tmp"
import json, sys
d = json.load(open(sys.argv[1], "r", encoding="utf-8"))
for k, v in d.items():
    print(f"{k}={v}")
PY
      while IFS= read -r kv; do
        [[ -z "$kv" ]] && continue
        cmd+=("--dart-define=$kv")
      done < "$_dart_def_tmp"
      rm -f "$_dart_def_tmp"
    fi
  else
    printf "$MSG_WORKFLOW_IOS_ENV_FILE_MISSING\n" "$env_file" "$tag" >&2
    return 1
  fi
  if [[ -n "${BUILD_NAME:-}" ]]; then cmd+=(--build-name "$BUILD_NAME"); fi
  if [[ -n "${BUILD_NUMBER:-}" ]]; then cmd+=(--build-number "$BUILD_NUMBER"); fi
  {
    echo "$MSG_WORKFLOW_BUILD_ENV_HEADER"
    printf "$MSG_WORKFLOW_ENV_FILE_POINTER\n" "${UPLOADTOOL_ENV_JSON_ENV_KEY:-APP_ENV}" "$tag" "$env_file"
    printf "$MSG_WORKFLOW_ENV_FILE_CONTENTS\n" "$(tr -d '\n' < "$env_file" 2>/dev/null || true)"
    echo "$MSG_WORKFLOW_FLUTTER_BUILD_HEADER"
    uploadtool_run_cmd "${cmd[@]}"
  } >"$log" 2>&1
  local ipa
  ipa="$(ls -t build/ios/ipa/*.ipa 2>/dev/null | head -n 1 || true)"
  if [[ -z "$ipa" ]]; then
    echo "[iOS] No IPA found at build/ios/ipa/*.ipa" >>"$log"
    return 1
  fi
  local artifacts_dir="${state_dir}/artifacts"
  mkdir -p "$artifacts_dir"
  local ipa_copy="${artifacts_dir}/app-${tag}-${BUILD_NUMBER}.ipa"
  cp -f "$ipa" "$ipa_copy"
  uploadtool_cleanup_state_artifacts "$artifacts_dir" "$tag"
  echo "$ipa_copy" > "${state_dir}/ios_ipa_path.txt"
  printf "$MSG_WORKFLOW_IOS_BUILD_DONE\n" "$tag" "$ipa_copy"
}

uploadtool_wait_for_all_uploads() {
  local fail=0
  local i
  for ((i=0; i<${#UPLOAD_STATUS_FILES[@]}; i++)); do
    local status_file="${UPLOAD_STATUS_FILES[$i]}"
    local label="${UPLOAD_LABELS[$i]}"

    while [[ ! -f "$status_file" ]]; do
      uploadtool_sleep 2
    done

    local rc
    rc="$(tr -d '[:space:]' < "$status_file" 2>/dev/null || echo "1")"
    if [[ "$rc" != "0" ]]; then
      printf "$MSG_WORKFLOW_UPLOAD_STATUS_ERROR\n" "$label" "$rc"
      fail=1
    fi
  done

  if [[ "$fail" -ne 0 ]]; then
    return 1
  fi
  return 0
}

uploadtool_run_for_env() {
  local env="$1"
  local build_number="$2"
  local async_upload="${3:-0}"
  local changelog="${4:-}"

  local tag="$env"
  local state_dir="$UPLOAD_STATE_DIR/$tag"

  echo
  if [[ "$env" == "prod" ]]; then
    echo "$MSG_WORKFLOW_ENV_HEADER_PROD"
  else
    echo "$MSG_WORKFLOW_ENV_HEADER_DEV"
  fi

  unset TESTFLIGHT_CHANGELOG PLAY_RELEASE_NOTES
  export WAIT_FOR_BUILD_PROCESSING="$WAIT_IOS_CHOICE"

  export BUILD_TYPE="$env"
  export BUILD_NUMBER="$build_number"

  mkdir -p "$state_dir"
  local dart_defines_path="${state_dir}/dart_defines.json"
  if [[ -n "${UPLOADTOOL_CONFIG_DIR:-}" && -f "${UPLOADTOOL_CONFIG_DIR}/env.json" ]]; then
    cp -f "${UPLOADTOOL_CONFIG_DIR}/env.json" "$dart_defines_path"
  fi
  uploadtool_write_env_to_file "$dart_defines_path" "$env" "${UPLOADTOOL_ENV_JSON_ENV_KEY:-}"
  printf "$MSG_WORKFLOW_ENV_FILE_POINTER\n" "${UPLOADTOOL_ENV_JSON_ENV_KEY:-APP_ENV}" "$env" "${state_dir}/dart_defines.json"
  if [[ -f "${state_dir}/dart_defines.json" ]]; then
    printf "$MSG_WORKFLOW_ENV_FILE_CONTENTS\n" "$(tr -d '\n' < "${state_dir}/dart_defines.json" 2>/dev/null || true)"
  fi

  if [[ "${BUILD_ANDROID:-0}" -eq 1 ]]; then
    if [[ "${ENV_TARGETS:-}" == "both" ]]; then
      export ANDROID_BUILD_NUMBER="$(uploadtool_compute_android_version_code "$build_number")"
    else
      local candidate="${ANDROID_BUILD_NUMBER:-$build_number}"
      export ANDROID_BUILD_NUMBER="$(uploadtool_compute_android_version_code "$candidate")"
    fi

    if [[ ! "${ANDROID_BUILD_NUMBER:-}" =~ ^[0-9]+$ ]]; then
      printf "$MSG_RUN_ERR_ANDROID_BUILD_NUMBER_NAN\n" "${ANDROID_BUILD_NUMBER:-}"
      return 1
    fi
    local android_build_number_dec=$((10#$ANDROID_BUILD_NUMBER))
    if (( android_build_number_dec <= 0 || android_build_number_dec >= 2147483647 )); then
      printf "$MSG_RUN_ERR_ANDROID_BUILD_NUMBER_RANGE\n" "${ANDROID_BUILD_NUMBER}"
      return 1
    fi
  fi

  if [[ "${UPLOAD_IOS:-0}" -eq 1 || "${UPLOAD_ANDROID:-0}" -eq 1 ]]; then
    local notes
    notes="$(uploadtool_build_release_notes "$env" "$changelog")"
    export TESTFLIGHT_CHANGELOG="$notes"
    export PLAY_RELEASE_NOTES="$notes"
  fi

  mkdir -p "$state_dir"

  uploadtool_build_and_upload_for_env "$tag" "$state_dir" "$async_upload"
}

uploadtool_at_least_one_upload_succeeded() {
  local f
  for f in "${UPLOAD_STATUS_FILES[@]:-}"; do
    [[ -z "$f" ]] && continue
    [[ -f "$f" ]] || continue
    [[ "$(tr -d '[:space:]' < "$f" 2>/dev/null)" == "0" ]] && return 0
  done
  return 1
}

uploadtool_update_pubspec_version() {
  local build_number="$1"
  local reason="$2"
  local ver="${BUILD_NAME}+${build_number}"
  local marker="$UPLOAD_STATE_DIR/pubspec_updated_to.txt"

  echo
  echo "✏️  pubspec.yaml → ${ver} (${reason})"

  python3 - <<'PY' "$ROOT_DIR/pubspec.yaml" "$ver"
import re, sys
path = sys.argv[1]
ver = sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
    lines = f.readlines()
out = []
done = False
for line in lines:
    if not done and re.match(r"^version:\s*", line):
        out.append(f"version: {ver}\n")
        done = True
    else:
        out.append(line)
with open(path, "w", encoding="utf-8") as f:
    f.writelines(out)
PY

  printf '%s\n' "$ver ($reason)" >"$marker"
}

uploadtool_build_and_upload_for_env() {
  local tag="$1"
  local state_dir="$2"
  local async_upload="${3:-0}"

  local build_pids=()
  local fastlane_root="${UPLOADTOOL_FASTLANE_ROOT:-$ROOT_DIR/ios}"
  local ios_status_file="${state_dir}/upload_ios_exit_code.txt"
  local android_status_file="${state_dir}/upload_android_exit_code.txt"
  rm -f "$ios_status_file" "$android_status_file"

  if [[ "${BUILD_ANDROID:-0}" -eq 1 ]]; then
    (
      uploadtool_build_android "$tag" "$state_dir" || exit 1
      if [[ "${UPLOAD_ANDROID:-0}" -eq 1 ]]; then
        aab_path="$(cat "${state_dir}/android_aab_path.txt")"
        printf "$MSG_WORKFLOW_ANDROID_UPLOAD_START\n" "$tag" "$aab_path"
        (
          cd "$fastlane_root"
          set +e
          SKIP_FLUTTER_BUILD=1 BUNDLE_GEMFILE="$PWD/Gemfile" uploadtool_run_cmd bundle exec fastlane android upload_play aab:"$aab_path"
          rc=$?
          printf '%s\n' "$rc" > "$android_status_file"
          exit $rc
        ) >"$UPLOAD_LOG_DIR/${tag}_android_upload.log" 2>&1 &
      fi
    ) &
    build_pids+=($!)
  fi

  if [[ "${BUILD_IOS:-0}" -eq 1 ]]; then
    (
      uploadtool_build_ios "$tag" "$state_dir" || exit 1
      if [[ "${UPLOAD_IOS:-0}" -eq 1 ]]; then
        ipa_path="$(cat "${state_dir}/ios_ipa_path.txt")"
        printf "$MSG_WORKFLOW_IOS_UPLOAD_START\n" "$tag" "$ipa_path"
        (
          cd "$fastlane_root"
          set +e
          SKIP_FLUTTER_BUILD=1 BUNDLE_GEMFILE="$PWD/Gemfile" uploadtool_run_cmd bundle exec fastlane ios upload_testflight ipa:"$ipa_path"
          rc=$?
          printf '%s\n' "$rc" > "$ios_status_file"
          exit $rc
        ) >"$UPLOAD_LOG_DIR/${tag}_ios_upload.log" 2>&1 &
      fi
    ) &
    build_pids+=($!)
  fi

  local fail=0
  for pid in "${build_pids[@]}"; do
    if ! wait "$pid"; then fail=1; fi
  done

  if [[ "$fail" -ne 0 ]]; then
    echo
    printf "$MSG_WORKFLOW_BUILD_FAILED\n" "$tag"
    [[ -f "$UPLOAD_LOG_DIR/${tag}_ios.log" ]] && printf "$MSG_WORKFLOW_LOG_SECTION_TAIL\n" "iOS" "$tag" "60" && tail -n 60 "$UPLOAD_LOG_DIR/${tag}_ios.log" || true
    [[ -f "$UPLOAD_LOG_DIR/${tag}_android.log" ]] && printf "$MSG_WORKFLOW_LOG_SECTION_TAIL\n" "Android" "$tag" "60" && tail -n 60 "$UPLOAD_LOG_DIR/${tag}_android.log" || true
    return 1
  fi

  if [[ "${UPLOAD_ANDROID:-0}" -eq 1 ]]; then
    UPLOAD_STATUS_FILES+=("$android_status_file")
    UPLOAD_LABELS+=("${tag}:android")
  fi
  if [[ "${UPLOAD_IOS:-0}" -eq 1 ]]; then
    UPLOAD_STATUS_FILES+=("$ios_status_file")
    UPLOAD_LABELS+=("${tag}:ios")
  fi

  if [[ "$async_upload" -eq 1 ]]; then
    return 0
  fi

  if ! uploadtool_wait_for_all_uploads; then
    echo
    echo "$MSG_WORKFLOW_UPLOAD_FAILED"
    [[ -f "$UPLOAD_LOG_DIR/${tag}_ios_upload.log" ]] && printf "$MSG_WORKFLOW_UPLOAD_SECTION_HEADER\n" "iOS" "$tag" && tail -n 80 "$UPLOAD_LOG_DIR/${tag}_ios_upload.log" || true
    [[ -f "$UPLOAD_LOG_DIR/${tag}_android_upload.log" ]] && printf "$MSG_WORKFLOW_UPLOAD_SECTION_HEADER\n" "Android" "$tag" && tail -n 80 "$UPLOAD_LOG_DIR/${tag}_android_upload.log" || true
    return 1
  fi

  return 0
}
