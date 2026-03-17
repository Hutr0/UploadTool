# UploadTool

Единый модуль для сборки и загрузки релизов iOS/Android.

UploadTool задуман как **автономный** модуль:

- его можно держать прямо внутри Flutter‑проекта, как сейчас
- или вынести в отдельный репозиторий и подключать к разным проектам

## Запуск

### Если UploadTool лежит внутри проекта

- Из корня проекта: `./Upload`
- Напрямую:
  - `./UploadTool/run.sh`
  - `./UploadTool/run.sh ios`
  - `./UploadTool/run.sh android`
  - `./UploadTool/run.sh both`

### Если UploadTool лежит отдельно (в другом месте/репозитории)

Тогда надо явно указать корень Flutter‑проекта и (желательно) папку с конфигами:

```bash
bash /path/to/UploadTool/run.sh --project-root /path/to/flutter_project --config-dir /path/to/flutter_project/.uploadtool
```

Короткая версия (если ты уже находишься в корне Flutter‑проекта):

```bash
bash /path/to/UploadTool/run.sh --project-root . --config-dir ./.uploadtool
```

UploadTool сам:

- найдёт корень проекта по `pubspec.yaml` (если не задан `--project-root`)
- возьмёт конфиги из `--config-dir` / `UPLOADTOOL_CONFIG_DIR` (если задано)
- иначе использует `${PROJECT}/.uploadtool` (и создаст директорию при необходимости)
- если Flutter‑проект не определён — использует `config/` рядом с `run.sh`

## Быстрый старт (инициализация проекта)

Чтобы быстро и интерактивно настроить UploadTool для проекта (создать `.uploadtool/`, разложить шаблоны, проставить базовые значения и, при желании, сохранить профиль проекта):

```bash
bash /path/to/UploadTool/init.sh
```

Этот wizard:

- спрашивает путь к Flutter‑проекту и директории конфигов
- создаёт `env.json`, `release.env`, `wizard.env` (с возможностью не перезаписывать существующие файлы)
- по желанию создаёт `cli.env` с дефолтными путями
- по желанию сохраняет проект в реестр (profile), чтобы потом запускать через `--project <name>`

Если хочется сделать то же самое скриптом (без опросника) — есть команда `run.sh init`:

```bash
bash /path/to/UploadTool/run.sh init \
  --project-root /path/to/flutter_project \
  --config-dir /path/to/flutter_project/.uploadtool \
  --save-defaults \
  --cli-env-file /path/to/flutter_project/.uploadtool/cli.env \
  --force
```

Основные флаги для `run.sh init`:

- `--project-root` — где лежит `pubspec.yaml`
- `--config-dir` — куда складывать `env.json` / `release.env` / `wizard.env`
- `--cli-env-file` — явный путь к `cli.env` (по умолчанию `<config_dir>/cli.env`)
- `--save-defaults` / `--no-save-defaults` — сохранять ли `cli.env`
- `--force` / `--no-force` — перезаписывать ли уже существующие файлы

Рекомендуемый `cli.env` (локально для проекта): `<flutter_project>/.uploadtool/cli.env`.

Legacy (глобальный) вариант: `~/.uploadtool/cli.env`.

Пример формата:

- `config/cli.env.example`

При запуске `run.sh` используется следующий приоритет для `cli.env`:

1. Файл, переданный через `--cli-env-file`
2. Файл из `UPLOADTOOL_CLI_ENV_FILE`
3. `<project>/.uploadtool/cli.env`
4. `~/.uploadtool/cli.env`

Через `cli.env` можно задать:

```bash
UPLOADTOOL_CLI_PROJECT_ROOT="/path/to/flutter_project"
UPLOADTOOL_CLI_CONFIG_DIR="/path/to/flutter_project/.uploadtool"
UPLOADTOOL_CLI_FASTLANE_ROOT="/path/to/fastlane"
UPLOADTOOL_CLI_ENV_JSON_ENV_KEY="APP_ENV"
```

После настройки `cli.env` достаточно вызывать:

```bash
bash /path/to/UploadTool/run.sh
```

без постоянного прокидывания `--project-root` / `--config-dir`.

## Параметры CLI

Ниже перечислены основные флаги `run.sh` (кроме отдельного `init.sh`‑wizard).

- `--project-root /path/to/flutter_project`  
  Явно задаёт корень Flutter‑проекта (где `pubspec.yaml`). Если не указан, UploadTool попробует:
  - взять путь из профиля (`--project <name>`)
  - или папку рядом с UploadTool, в которой есть `pubspec.yaml`
  - или текущую директорию, если в ней есть `pubspec.yaml`.

- `--config-dir /path/to/config_dir`  
  Явно задаёт директорию конфигов (`env.json`, `release.env`, `wizard.env`, логи и state).  
  Если не указан, используется:
  - `UPLOADTOOL_CONFIG_DIR` / `UPLOADTOOL_CLI_CONFIG_DIR`, либо
  - `<project_root>/.uploadtool` по умолчанию.

- `--env-file /path/to/release.env`  
  Явно указывает, какой `release.env` использовать (если файлов несколько).

- `--env-json-env-key KEY` / `--env-key KEY`  
  Явно задаёт ключ окружения в `env.json` (по умолчанию `APP_ENV`, fallback на `CHOYS_ENV`).  
  Эквивалентно переменной `UPLOADTOOL_ENV_JSON_ENV_KEY`.

- `--fastlane-root /path/to/fastlane`  
  Переопределяет директорию fastlane.  
  По умолчанию:
  - `UploadTool/fastlane`, если там есть `Gemfile`
  - иначе `ios/` внутри Flutter‑проекта (обратная совместимость со старыми проектами).

- `--project NAME`  
  Выбрать сохранённый профиль проекта (создаётся через `init.sh`).  
  Профиль задаёт `project_root`, `config_dir`, `fastlane_root` и ключ для `env.json`.

- `--cli-env-file /path/to/cli.env`  
  Явно указать файл `cli.env`, откуда брать дефолты для `project_root`, `config_dir`, `fastlane_root` и ключа `env.json`.

## Несколько проектов (profiles)

Если один UploadTool используется для нескольких приложений, можно сохранить проекты в реестр (через `init.sh`) и выбирать при запуске:

```bash
bash /path/to/UploadTool/run.sh --project my_app
```

## Структура

- `run.sh` — интерактивный wizard
- `config/` — примеры и дефолтные конфиги (секреты не коммитим)
- `docs/` — документация по релизам
- `logs/` — runtime-логи wizard (по умолчанию рядом с конфигами)
- `state/` — runtime-state и копии артефактов (по умолчанию рядом с конфигами)

## Конфиги (рекомендуемый вариант)

Чтобы подключать UploadTool к разным проектам бесшовно, удобно держать конфиги **рядом с проектом**, в папке `.uploadtool/` (и добавить её в `.gitignore`):

```text
<flutter_project>/
  .uploadtool/
    release.env
    wizard.env
    env.json
```

Примеры для копирования:

- `config/release.env.example`
- `config/wizard.env.example`
- `config/env.json.example`

### env.json (dart-defines)

По умолчанию UploadTool обновляет в `env.json` ключ `APP_ENV` (`dev`/`prod`).

Если в проекте уже используется другой ключ окружения:

- если файл содержит `CHOYS_ENV` (и не содержит `APP_ENV`) — UploadTool продолжит обновлять `CHOYS_ENV`
- или можно явно указать ключ через `UPLOADTOOL_ENV_JSON_ENV_KEY`

## Fastlane

Fastlane‑настройки теперь живут **внутри UploadTool**:

- `fastlane/Gemfile`
- `fastlane/fastlane/Fastfile`
- `fastlane/fastlane/Appfile`

По умолчанию корнем fastlane считается:

1. `UploadTool/fastlane`, если там есть `Gemfile`
2. иначе `ios/` внутри Flutter‑проекта (обратная совместимость со старыми проектами)

По этому пути `run.sh` делает `bundle install`.

При необходимости можно явно задать fastlane‑root:

- через переменную `UPLOADTOOL_FASTLANE_ROOT=/path/to/ios_or_fastlane`
- или через флаг `--fastlane-root /path/to/ios_or_fastlane`

Во время запуска UploadTool показывает выбранный путь:

```text
Fastlane:/path/to/some/fastlane
```

## Документация

- Релиз‑мастер: `docs/release_wizard.md`
- Интеграция (submodule/отдельный repo): `docs/integration_guide.md`
- iOS/TestFlight: `docs/testflight.md`
- Android/Google Play: `docs/google_play.md`
