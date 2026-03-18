## Integrating UploadTool into a new Flutter project

There are two equivalent ways to connect UploadTool to a project:

- as an `./UploadTool` folder inside the Flutter project (usually via `git submodule`)
- as a separate repository anywhere on disk

In all scenarios it is recommended to keep configs next to the project in `.uploadtool/` (and add that folder to `.gitignore`).

### 1) Quick start via interactive `init.sh` (recommended)

The primary setup path is the interactive wizard:

```bash
bash /path/to/UploadTool/init.sh
```

It will ask questions (project path, config directory, `env.json` key, base app identifiers) and create `.uploadtool/`.

### 2) Scripted mode via `run.sh init` (optional)

`run.sh init` (or `run.sh setup`) creates the config directory and copies templates:

- `env.json`
- `release.env`
- `wizard.env`

Example for a standalone repository:

```bash
bash /path/to/UploadTool/run.sh init --project-root /path/to/flutter_project
```

Example when UploadTool is inside the project:

```bash
./UploadTool/run.sh init --project-root .
```

`init` flags:

- `--config-dir <path>`: where to create configs (defaults to `<project>/.uploadtool`)
- `--force`: overwrite existing files (`env.json`, `release.env`, `wizard.env`)
- `--save-defaults`: save CLI defaults into `cli.env` (defaults to `<config-dir>/cli.env`, see below)

After `init` you must open and fill:

- `<project>/.uploadtool/release.env`

### 3) (Optional) save CLI defaults into `cli.env`

To avoid passing `--project-root` and `--config-dir` every time, you can save defaults:

```bash
bash /path/to/UploadTool/run.sh init --project-root /path/to/flutter_project --save-defaults
```

By default the file is created at:

- `<flutter_project>/.uploadtool/cli.env` (or at the directory you chose via `--config-dir`)

Legacy (global) variant:

- `~/.uploadtool/cli.env`

You can override the path via:

- flag `--cli-env-file /path/to/cli.env`
- env `UPLOADTOOL_CLI_ENV_FILE=/path/to/cli.env`

Example format:

- `config/cli.env.example`

### Multiple projects (profiles)

If one UploadTool instance is used for multiple apps, you can save projects into a registry:

- `~/.uploadtool/projects/<name>.env`

and choose the desired project when running:

```bash
bash /path/to/UploadTool/run.sh --project <name>
```

### 4) Scenario A: UploadTool as a `git submodule` (inside the project)

Recommended structure:

```text
<flutter_project>/
  UploadTool/          # git submodule
  .uploadtool/         # configs (gitignored)
```

Add submodule:

```bash
git submodule add <repo_url> UploadTool
```

Initialization (recommended):

```bash
bash ./UploadTool/init.sh
```

Initialization (scripted, optional):

```bash
./UploadTool/run.sh init --project-root .
```

Running the wizard:

```bash
./UploadTool/run.sh
```

### 5) Scenario B: UploadTool as a separate repository

Example:

```text
~/Tools/UploadTool/     # separate repository
~/Projects/MyApp/       # Flutter project
```

Initialization (recommended):

```bash
bash ~/Tools/UploadTool/init.sh
```

Initialization (scripted, optional):

```bash
bash ~/Tools/UploadTool/run.sh init --project-root ~/Projects/MyApp
```

Running the wizard:

```bash
bash ~/Tools/UploadTool/run.sh --project-root ~/Projects/MyApp --config-dir ~/Projects/MyApp/.uploadtool
```

Or (if defaults were saved via `--save-defaults`):

```bash
bash ~/Tools/UploadTool/run.sh
```

### 6) About `.uploadtool/` and gitignore

Typically `.uploadtool/` contains:

- `release.env` (secrets/keys, should not be committed)
- `wizard.env` (optional)
- `env.json` (dart‑defines)
- `logs/` and `state/` (runtime artifacts)

By default logs and state are created **next to configs**:

- `UPLOAD_LOG_DIR`: `<config-dir>/logs` (override via `UPLOADTOOL_LOG_DIR`)
- `UPLOAD_STATE_DIR`: `<config-dir>/state` (override via `UPLOADTOOL_STATE_DIR`)

For builds the wizard creates a per‑env dart‑defines file:

- `<config-dir>/state/<env>/dart_defines.json`

It is formed by copying `<config-dir>/env.json` and then updating the environment key (`APP_ENV` / `CHOYS_ENV` / key from `UPLOADTOOL_ENV_JSON_ENV_KEY`).

Artifacts are copied to:

- `<config-dir>/state/<env>/artifacts/`

And are automatically cleaned up (retention): only the last `3` `.ipa` and last `3` `.aab` per environment are kept. You can change this via `UPLOADTOOL_STATE_ARTIFACTS_KEEP`.

Recommended `.gitignore` entry:

```gitignore
.uploadtool/
```
