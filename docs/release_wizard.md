## Release wizard (UploadTool): iOS + Android

This is the interactive wizard that guides you from “nothing” to a shipped build:

- **builds** iOS (`.ipa`) and Android (`.aab`)
- optionally **uploads** iOS to TestFlight and Android to Google Play
- can build/upload iOS and Android **in parallel**
- after successful uploads, updates the version in `pubspec.yaml` (`version: <name>+<number>`)

UploadTool can live either inside the project or in a separate repository.

### Entry points

- `./run.sh` — run the wizard from the UploadTool repo
- `./run.sh ios|android|both` — run with pre‑selected platform

If UploadTool is connected as `./UploadTool` folder inside a Flutter project:

- `./UploadTool/run.sh` — run the wizard directly
- `./UploadTool/run.sh ios|android|both` — run with a pre‑selected platform

If UploadTool lives **elsewhere**, run:

```bash
bash /path/to/UploadTool/run.sh --project-root /path/to/flutter_project --config-dir /path/to/flutter_project/.uploadtool
```

### Where configs live

Recommended “seamless” layout — keep local configs next to the Flutter project:

```text
<flutter_project>/
  .uploadtool/
    release.env
    wizard.env
    env.json
```

UploadTool chooses the config directory as follows:

- if `--config-dir` (or `UPLOADTOOL_CONFIG_DIR`) is provided — use it
- else, if a Flutter project is detected (via `pubspec.yaml`) — use `<project>/.uploadtool` (and create it if needed)
- else — use `config/` next to `run.sh`

Logs and state by default live next to configs:

- `UPLOAD_LOG_DIR`: `<config-dir>/logs` (override via `UPLOADTOOL_LOG_DIR`)
- `UPLOAD_STATE_DIR`: `<config-dir>/state` (override via `UPLOADTOOL_STATE_DIR`)

To automatically create `.uploadtool/` and copy template configs, you can use:

- `./run.sh init --project-root /path/to/flutter_project`

If you want to run UploadTool without passing `--project-root/--config-dir` every time, you can save defaults:

- `./run.sh init --project-root /path/to/flutter_project --save-defaults`

The defaults file format is described in `config/cli.env.example`.

### 1) Application environment (dev/prod) — `env.json`

`env.json` is a JSON file with dart‑defines that are passed into Flutter builds via `--dart-define-from-file`.

Typical keys:

- `APP_ENV`: `dev` or `prod`
- `BASE_URL`: optional (if your app reads it)

Important: UploadTool **does not impose** a specific key set on your app. By default, the wizard writes `APP_ENV`.

Before each build, the wizard **uses** `env.json` from the config directory (for example `.uploadtool/env.json`) as a base.

For each environment it creates a per‑env file:

- `state/<env>/dart_defines.json`

Algorithm:

- copy current `env.json` into `state/<env>/dart_defines.json` (to keep all other keys such as `BASE_URL`)
- update the environment key in `state/<env>/dart_defines.json` (`APP_ENV` / `CHOYS_ENV` / custom key from `UPLOADTOOL_ENV_JSON_ENV_KEY`) to `dev` or `prod`

This is done specifically so that in the `dev + prod` scenario the two builds do not overwrite a shared file and do not read each other’s environment.

Minimal Flutter/Dart example of reading these values:

```dart
const appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'prod');
const baseUrl = String.fromEnvironment('BASE_URL', defaultValue: 'https://example.com');

bool get isProd => appEnv == 'prod';
```

Minimal behavior binding example:

```dart
// Show env badge, toggle features, logging, etc.
final showDebugTools = appEnv != 'prod';

// Version and build number usually come from pubspec via package_info_plus,
// while environment comes from dart-defines.
final aboutText = 'env=$appEnv';
```

If you need compatibility with an existing project:

- if the file already contains `CHOYS_ENV` (and not `APP_ENV`) — UploadTool will keep updating `CHOYS_ENV`
- you can explicitly set the key via `UPLOADTOOL_ENV_JSON_ENV_KEY` (for example `UPLOADTOOL_ENV_JSON_ENV_KEY=MY_ENV`)

If you select `dev + prod`, the wizard performs two consecutive releases:

- build number is in the form `YYYYMMDD.N.X`, where `X`: `dev=0`, `prod=1`
- dev is published as `YYYYMMDD.N.0` (e.g. `20260220.1.0`)
- prod uses core `YYYYMMDD.N` incremented by 1 and suffix `.1` (e.g. dev `20260220.1.0` → prod `20260220.2.1`)

### 1.1) State and artifacts retention

After building, UploadTool copies artifacts into state:

- iOS: `state/<env>/artifacts/app-<env>-<BUILD_NUMBER>.ipa`
- Android: `state/<env>/artifacts/app-<env>-<BUILD_NUMBER>.aab`

To avoid unbounded growth of `state/`, retention is enabled:

- for each environment (`dev` / `prod`) only the last `3` `.ipa` and last `3` `.aab` are kept
- you can change the number via `UPLOADTOOL_STATE_ARTIFACTS_KEEP` (for example `UPLOADTOOL_STATE_ARTIFACTS_KEEP=5`)

### 2) Build + publish configuration — `release.env`

`release.env` is the **single source of truth** for build and publish configuration (iOS + Android).

By default UploadTool reads:

- `${UPLOAD_CONFIG_DIR}/release.env` (for example `.uploadtool/release.env`)

The full example with all options is:

- `config/release.env.example`

### 3) Wizard behavior (optional) — `wizard.env`

This file is optional. It allows you to:

- set default values (targets/env/upload/wait)
- skip questions (handy for CI or when every release follows the same scenario)

Example:

- `config/wizard.env.example`

### Running from IDE (VSCode / Android Studio)

If you run the app from an IDE (not via the wizard) and want to use the same environment, add this Flutter argument:

- `--dart-define-from-file=PATH_TO_ENV_JSON`

Where `PATH_TO_ENV_JSON` is the `env.json` file from your config directory:

- if you use the recommended layout — usually `.uploadtool/env.json`
- if you run UploadTool without a detected Flutter project (`pubspec.yaml` absent) — `config/env.json` next to `run.sh` is used

To exactly reproduce UploadTool behavior for a specific environment, use the file the wizard prepared:

- `<config-dir>/state/<env>/dart_defines.json`

### Fastlane (embedded)

Fastlane configuration lives inside UploadTool:

- `fastlane/Gemfile`
- `fastlane/fastlane/Fastfile`
- `fastlane/fastlane/Appfile`

By default the wizard runs `bundle install` there. You can override via:

- `UPLOADTOOL_FASTLANE_ROOT=/path/to/fastlane_root`

### Platform‑specific docs

- iOS TestFlight: `docs/testflight.md`
- Android Google Play: `docs/google_play.md`

