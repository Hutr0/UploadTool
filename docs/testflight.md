## iOS → TestFlight (Flutter + fastlane)

This repository ships with a ready-to-use pipeline that **builds the iOS `.ipa`** and **uploads it to TestFlight**.

You can run it either directly or through the unified “Upload wizard” (`Upload` entry point) that orchestrates iOS and Android builds in parallel.

### Quick start (iOS)

#### 1) Prepare the configs

UploadTool reads everything from **one** file: `release.env`.

Recommended location (works well when sharing UploadTool across multiple apps):

- `<flutter_project>/.uploadtool/release.env`

Copy the template:

```bash
mkdir -p .uploadtool
cp /path/to/UploadTool/config/release.env.example .uploadtool/release.env
```

Alternative (creates `.uploadtool/` and populates all templates automatically):

```bash
bash /path/to/UploadTool/run.sh init --project-root /path/to/flutter_project
```

If UploadTool lives inside the Flutter project (`./UploadTool`), you can also run:

```bash
mkdir -p .uploadtool
cp UploadTool/config/release.env.example .uploadtool/release.env
```

Legacy option (keep configs inside UploadTool itself):

```bash
cp UploadTool/config/release.env.example UploadTool/config/release.env
```

#### 2) Pick exactly one authentication method

Inside `release.env` provide **one** of the following:

- Option A (recommended): App Store Connect API key
  - `ASC_KEY_ID`
  - `ASC_ISSUER_ID`
  - `ASC_KEY_PATH`
- Option B: Apple ID + app-specific password
  - `FASTLANE_USER`
  - `FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD`

Optional (when you belong to multiple teams):

- `FASTLANE_TEAM_ID` / `FASTLANE_TEAM_NAME`

#### 3) Launch the wizard

If UploadTool is part of the Flutter project:

```bash
./UploadTool/run.sh ios
```

If UploadTool is stored elsewhere:

```bash
bash /path/to/UploadTool/run.sh --project-root /path/to/flutter_project --config-dir /path/to/flutter_project/.uploadtool ios
```

To only build the `.ipa` (without uploading), answer `n` to `Upload iOS to TestFlight?` inside the wizard.

### Choosing the environment (dev/prod) via JSON

The environment is controlled through `env.json` inside the config directory (for example `.uploadtool/env.json`).

- `APP_ENV`: `dev` or `prod`
- `BASE_URL`: optional (if your app reads it)

UploadTool updates `APP_ENV` by default. If your project already uses another key, set:

- `UPLOADTOOL_ENV_JSON_ENV_KEY=...`

Need a starting point? Copy the template:

```bash
mkdir -p .uploadtool
cp /path/to/UploadTool/config/env.json.example .uploadtool/env.json
```

The easiest way is to run the wizard (`run.sh`). It will ask for the environment and prepare per-env `dart-defines` files.

Important: `flutter build` never reads `.uploadtool/env.json` directly. Instead, UploadTool generates a per-environment file:

- `state/<env>/dart_defines.json`

Generation steps:

1. Copy the current `env.json` (to preserve every other key such as `BASE_URL`).
2. Update the environment key (`APP_ENV`/`CHOYS_ENV`/custom) inside the copy for the chosen `dev`/`prod` value.

This avoids race conditions when building `dev + prod` sequentially.

When you select `dev + prod`, the wizard performs two uploads back-to-back:

- Build number format: `YYYYMMDD.N.X`, where `X` is `0` for dev and `1` for prod.
- Example: dev `20260220.1.0` → prod `20260220.2.1` (core number increments, suffix flips to `.1`).

### State directory and artifact retention

Each `.ipa` is copied to:

- `state/<env>/artifacts/app-<env>-<BUILD_NUMBER>.ipa`

Retention keeps the directory under control:

- Only the last **3** `.ipa` files per environment are stored (`UPLOADTOOL_STATE_ARTIFACTS_KEEP` overrides the number).

When running from IDE, pass:

- `--dart-define-from-file=.uploadtool/env.json`

To mimic UploadTool exactly for a specific environment use:

- `--dart-define-from-file=.uploadtool/state/<env>/dart_defines.json`

### TestFlight authentication

#### Option A: App Store Connect API key

In App Store Connect:

- **Users and Access → Integrations → Keys**
- Create a key and download `AuthKey_XXXXXX.p8`

Populate `release.env` with:

- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_KEY_PATH` (path to the downloaded `.p8`)

Note: the `.p8` file is **not** stored in the macOS Keychain.

#### Option B: Apple ID + app-specific password (no API key)

Generate the password on `appleid.apple.com` and add to `release.env`:

- `FASTLANE_USER`
- `FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD`

Optional when multiple App Store Connect teams are involved:

- `FASTLANE_TEAM_ID`
- `FASTLANE_TEAM_NAME`

Legacy aliases are still supported: `FASTLANE_ITC_TEAM_ID`, `FASTLANE_ITC_TEAM_NAME`.

### What exactly runs

`run.sh ios` (or `./UploadTool/run.sh ios` when UploadTool is inside the project):

- loads env variables from `release.env` (from `--config-dir`, `.uploadtool`, or `config/` next to `run.sh`)
- executes `bundle install` inside `UPLOADTOOL_FASTLANE_ROOT` (defaults to `fastlane/` next to `run.sh`)
- triggers the `ios upload_testflight` lane

Fastlane logic:

- lives in `fastlane/fastlane/Fastfile`
- runs `flutter pub get`
- runs `flutter build ipa --release` (unless `SKIP_FLUTTER_BUILD=1` is set)
- uploads `build/ios/ipa/*.ipa` to TestFlight

### Troubleshooting

#### `error: exportArchive Copy failed` / `rsync` issues

If `flutter build ipa` crashes with:

- `error: exportArchive Copy failed`
- `.xcdistributionlogs` containing `rsync: on remote machine: --extended-attributes: unknown option`

The usual culprit is **Homebrew rsync** shadowing the system binary:

- Homebrew: `/opt/homebrew/bin/rsync` (3.x)
- System: `/usr/bin/rsync` (compatible with the Xcode export pipeline)

The Xcode export pipeline may start `/usr/bin/rsync` but pick the Homebrew daemon via `PATH`, which breaks the process.

The wizard (`run.sh`) already prepends system paths to `PATH`. If you run things manually, do the same:

```bash
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
flutter build ipa --release
```

