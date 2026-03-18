## Android → Google Play (Flutter + fastlane supply)

This repository includes a pipeline that **builds the Android `.aab`** and **uploads it to Google Play Console** (via fastlane supply).

You can also rely on the unified “Upload wizard” (`Upload` entry point) to run iOS and Android flows side-by-side.

### One-time Google setup

1) In Google Play Console:

- **Setup → API access**
- Link a Google Cloud project (if not already linked)

2) In Google Cloud Console:

- Create a **Service Account**
- Create and download the **JSON key**

3) Back in Play Console:

- Grant the service account access to the developer account / the specific app
- Assign permissions that allow uploading releases (e.g., Release manager / Upload)

### Local configuration

UploadTool relies on a **single** `release.env` file (already gitignored).

Recommended location:

- `<flutter_project>/.uploadtool/release.env`

Copy the template:

```bash
mkdir -p .uploadtool
cp /path/to/UploadTool/config/release.env.example .uploadtool/release.env
```

Alternative (creates `.uploadtool/` and populates templates automatically):

```bash
bash /path/to/UploadTool/run.sh init --project-root /path/to/flutter_project
```

If UploadTool is vendored as `./UploadTool` inside the Flutter project:

```bash
mkdir -p .uploadtool
cp UploadTool/config/release.env.example .uploadtool/release.env
```

Minimum Google Play configuration:

- `PLAY_JSON_KEY_PATH` (path to the service-account JSON key)
- `ANDROID_PACKAGE_NAME` (applicationId)
- `PLAY_TRACK` (typically `internal`)

### Running the wizard

Launch the wizard targeting Android:

```bash
./UploadTool/run.sh android
```

If you are inside the UploadTool repo itself:

```bash
./run.sh android
```

If UploadTool is stored elsewhere:

```bash
bash /path/to/UploadTool/run.sh --project-root /path/to/flutter_project --config-dir /path/to/flutter_project/.uploadtool android
```

To build only (skip upload), answer `n` to `Upload Android to Google Play?` inside the wizard.

### Choosing environment (dev/prod) via JSON

Environment is controlled by `env.json` in the config directory (e.g. `.uploadtool/env.json`).

- `APP_ENV`: `dev` or `prod`
- `BASE_URL`: optional (if your app uses it)

UploadTool updates `APP_ENV` by default. If your project uses another key, set:

- `UPLOADTOOL_ENV_JSON_ENV_KEY=...`

Need the template?

```bash
mkdir -p .uploadtool
cp /path/to/UploadTool/config/env.json.example .uploadtool/env.json
```

Wizard (`run.sh`) is the easiest way—it will ask for the environment and generate per-env `dart-defines` files.

Important: `flutter build` never consumes `.uploadtool/env.json` directly. Instead, UploadTool passes a per-environment file:

- `state/<env>/dart_defines.json`

Generation steps:

1. Copy the current `env.json` (to keep values like `BASE_URL`).
2. Update the environment key (`APP_ENV`/`CHOYS_ENV`/custom) inside the copy for the selected `dev`/`prod` value.

This protects the shared file when running `dev + prod` sequential builds.

If `dev + prod` is selected, the wizard performs two uploads in sequence:

- Build number format: `YYYYMMDD.N.X`, with `X = 0` for dev and `X = 1` for prod.
- Example: dev `20260220.1.0` → prod `20260220.2.1` (core increments, suffix switches to `.1`).

### State directory and artifacts retention

Each `.aab` is copied to:

- `state/<env>/artifacts/app-<env>-<BUILD_NUMBER>.aab`

Retention keeps storage under control:

- Only the last **3** `.aab` files per environment are stored (override with `UPLOADTOOL_STATE_ARTIFACTS_KEEP`).

Running from IDE? Pass:

- `--dart-define-from-file=.uploadtool/env.json`

To reproduce UploadTool’s behavior for a specific environment:

- `--dart-define-from-file=.uploadtool/state/<env>/dart_defines.json`

### Note about `versionCode`

Android `versionCode` must be an **integer**.

Project logic:

- If `ANDROID_BUILD_NUMBER` is provided — use it.
- Otherwise derive from `BUILD_NUMBER` (or from `pubspec.yaml`).
- Remove every non-digit character (e.g., `20260220.4` → `202602204`).

Important: when using the `YYYYMMDD.N.X` format, Android `versionCode` takes **only the core** `YYYYMMDD.N` (suffix `.X` is ignored) to guarantee it stays within the 32-bit range.

### Google Play release name

When uploading, fastlane/supply sets the **release name** in Play Console via `version_name`.

Default format:

- `"<BUILD_NAME> | <BUILD_NUMBER> | <dev/prod>"` (example: `3.8.3 | 20260220.2.1 | prod`)

Override manually if needed:

- `SUPPLY_VERSION_NAME="..."` (or `PLAY_RELEASE_NAME="..."`)

