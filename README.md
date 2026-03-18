## UploadTool

A single module for building and uploading iOS/Android releases.

UploadTool is designed as an **autonomous** module:

- you can keep it directly inside a Flutter project
- or keep it in a separate repository and connect it to different projects

### Run

#### If UploadTool is inside the project

- From project root: `./Upload`
- Directly:
  - `./UploadTool/run.sh`
  - `./UploadTool/run.sh ios`
  - `./UploadTool/run.sh android`
  - `./UploadTool/run.sh both`

#### If UploadTool is in a separate directory / repository

Then you must explicitly pass the Flutter project root and (optionally) the config directory:

```bash
bash /path/to/UploadTool/run.sh --project-root /path/to/flutter_project --config-dir /path/to/flutter_project/.uploadtool
```

Short version (when you are already in the Flutter project root):

```bash
bash /path/to/UploadTool/run.sh --project-root . --config-dir ./.uploadtool
```

UploadTool will:

- detect the project root via `pubspec.yaml` (if `--project-root` is not provided)
- read configs from `--config-dir` / `UPLOADTOOL_CONFIG_DIR` (if provided)
- otherwise use `${PROJECT}/.uploadtool` (and create it when needed)
- if no Flutter project is detected — fall back to `config/` next to `run.sh`

### Quick start (project initialization)

To quickly and interactively configure UploadTool for a project (create `.uploadtool/`, copy templates, set base values and optionally save a project profile):

```bash
bash /path/to/UploadTool/init.sh
```

This wizard will:

- ask for the Flutter project path and config directory
- create `env.json`, `release.env`, `wizard.env` (without overwriting existing files unless forced)
- optionally create `cli.env` with default paths
- optionally save the project profile so you can later run via `--project <name>`

If you want the same but scripted (no interactive questions), use `run.sh init`:

```bash
bash /path/to/UploadTool/run.sh init \
  --project-root /path/to/flutter_project \
  --config-dir /path/to/flutter_project/.uploadtool \
  --save-defaults \
  --cli-env-file /path/to/flutter_project/.uploadtool/cli.env \
  --force
```

Main flags for `run.sh init`:

- `--project-root` — where `pubspec.yaml` is located
- `--config-dir` — where to create `env.json` / `release.env` / `wizard.env`
- `--cli-env-file` — explicit path to `cli.env` (defaults to `<config_dir>/cli.env`)
- `--save-defaults` / `--no-save-defaults` — whether to save `cli.env`
- `--force` / `--no-force` — whether to overwrite existing files

Recommended `cli.env` (project-local): `<flutter_project>/.uploadtool/cli.env`.

Legacy (global) variant: `~/.uploadtool/cli.env`.

Example format:

- `config/cli.env.example`

When `run.sh` starts, `cli.env` is resolved using this priority:

1. File passed via `--cli-env-file`
2. File from `UPLOADTOOL_CLI_ENV_FILE`
3. `<project>/.uploadtool/cli.env`
4. `~/.uploadtool/cli.env`

Through `cli.env` you can set:

```bash
UPLOADTOOL_CLI_PROJECT_ROOT="/path/to/flutter_project"
UPLOADTOOL_CLI_CONFIG_DIR="/path/to/flutter_project/.uploadtool"
UPLOADTOOL_CLI_FASTLANE_ROOT="/path/to/fastlane"
UPLOADTOOL_CLI_ENV_JSON_ENV_KEY="APP_ENV"
```

After `cli.env` is configured, you can simply run:

```bash
bash /path/to/UploadTool/run.sh
```

without passing `--project-root` / `--config-dir` each time.

### CLI parameters (`run.sh`)

Below are the main `run.sh` flags (besides the separate `init.sh` wizard).

- `--project-root /path/to/flutter_project`  
  Explicitly sets the Flutter project root (where `pubspec.yaml` is). If omitted, UploadTool will try:
  - the path from a profile (`--project <name>`)
  - a directory next to UploadTool that contains `pubspec.yaml`
  - the current directory if it contains `pubspec.yaml`

- `--config-dir /path/to/config_dir`  
  Explicitly sets the config directory (`env.json`, `release.env`, `wizard.env`, logs, state).  
  If omitted, UploadTool uses:
  - `UPLOADTOOL_CONFIG_DIR` / `UPLOADTOOL_CLI_CONFIG_DIR`, or
  - `<project_root>/.uploadtool` by default.

- `--env-file /path/to/release.env`  
  Explicitly chooses which `release.env` file to use (if there are multiple).

- `--env-json-env-key KEY` / `--env-key KEY`  
  Explicitly sets the environment key inside `env.json` (default is `APP_ENV`, fallback to `CHOYS_ENV`).  
  Equivalent to the `UPLOADTOOL_ENV_JSON_ENV_KEY` variable.

- `--fastlane-root /path/to/fastlane`  
  Overrides the fastlane directory.  
  Defaults to:
  - `UploadTool/fastlane` when it has a `Gemfile`
  - otherwise `ios/` inside the Flutter project (backwards‑compatible)

- `--project NAME`  
  Choose a saved project profile (created via `init.sh`).  
  The profile sets `project_root`, `config_dir`, `fastlane_root` and the `env.json` key.

- `--cli-env-file /path/to/cli.env`  
  Explicitly point to `cli.env` where defaults for `project_root`, `config_dir`, `fastlane_root` and the `env.json` key are stored.

### Multiple projects (profiles)

If one UploadTool instance is used for several apps, you can save projects into a registry (via `init.sh`) and select them at runtime:

```bash
bash /path/to/UploadTool/run.sh --project my_app
```

### Structure

- `run.sh` — interactive release wizard
- `config/` — examples and default configs (secrets are not committed)
- `docs/` — release documentation
- `logs/` — runtime logs (by default next to configs)
- `state/` — runtime state and copies of artifacts (by default next to configs)

### Configs (recommended layout)

To connect UploadTool seamlessly to different projects, keep configs **next to the project**, in a `.uploadtool/` folder (and add it to `.gitignore`):

```text
<flutter_project>/
  .uploadtool/
    release.env
    wizard.env
    env.json
```

Examples to copy from:

- `config/release.env.example`
- `config/wizard.env.example`
- `config/env.json.example`
- `config/i18n.env.example`

#### `env.json` (dart‑defines)

By default, UploadTool updates the `APP_ENV` key in `env.json` (`dev` / `prod`).

If your project already uses a different environment key:

- if the file contains `CHOYS_ENV` and not `APP_ENV` — UploadTool will keep updating `CHOYS_ENV`
- or you can explicitly set the key via `UPLOADTOOL_ENV_JSON_ENV_KEY`

### Fastlane

Fastlane configuration now lives **inside UploadTool**:

- `fastlane/Gemfile`
- `fastlane/fastlane/Fastfile`
- `fastlane/fastlane/Appfile`

By default, the fastlane root is:

1. `UploadTool/fastlane` when it has a `Gemfile`
2. otherwise `ios/` inside the Flutter project (backwards‑compatible)

`run.sh` will run `bundle install` in this fastlane root.

You can override fastlane root via:

- env `UPLOADTOOL_FASTLANE_ROOT=/path/to/ios_or_fastlane`
- flag `--fastlane-root /path/to/ios_or_fastlane`

At startup UploadTool prints the chosen fastlane path:

```text
Fastlane:/path/to/some/fastlane
```

### Localization (i18n)

UploadTool supports localized CLI messages (wizards in `run.sh` and `init.sh`):

- supported languages:
  - `en` — English (default)
  - `ru` — Russian
- language can be chosen via:
  - env var `UPLOADTOOL_LANG`, or
  - config file `<config_dir>/i18n.env` (see `config/i18n.env.example`)

Priority:

1. `UPLOADTOOL_LANG` environment variable
2. file from `UPLOADTOOL_I18N_ENV_FILE` (if provided)
3. `<config_dir>/i18n.env`
4. fallback to `en`

The actual messages are defined in:

- `lib/i18n/en.sh`
- `lib/i18n/ru.sh`

### Documentation

- Release wizard: `docs/release_wizard.md`
- Integration (submodule / separate repo): `docs/integration_guide.md`
- iOS / TestFlight: `docs/testflight.md`
- Android / Google Play: `docs/google_play.md`
