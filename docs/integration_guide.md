## Интеграция UploadTool в новый Flutter‑проект

Ниже — два равноправных сценария подключения UploadTool:

- как папка `./UploadTool` внутри проекта (обычно через `git submodule`)
- как отдельный репозиторий в любом месте на диске

Во всех сценариях рекомендуется хранить конфиги рядом с проектом, в `.uploadtool/` (и добавить эту папку в `.gitignore`).

### 1) Быстрый старт через интерактивный `init.sh` (рекомендуется)

Основной способ настройки UploadTool — интерактивный wizard:

```bash
bash /path/to/UploadTool/init.sh
```

Он задаст вопросы (проект, директория конфигов, ключ окружения для `env.json`, базовые идентификаторы приложения) и создаст `.uploadtool/`.

### 2) Скриптовый режим через `run.sh init` (дополнительно)

`run.sh init` (или `run.sh setup`) создаёт директорию конфигов и копирует шаблоны:

- `env.json`
- `release.env`
- `wizard.env`

Пример для отдельного репозитория:

```bash
bash /path/to/UploadTool/run.sh init --project-root /path/to/flutter_project
```

Пример для случая, когда UploadTool лежит внутри проекта:

```bash
./UploadTool/run.sh init --project-root .
```

Флаги `init`:

- `--config-dir <path>`: куда создать конфиги (по умолчанию `<project>/.uploadtool`)
- `--force`: перезаписать существующие файлы (`env.json`, `release.env`, `wizard.env`)
- `--save-defaults`: сохранить дефолты CLI в `cli.env` (по умолчанию в `<config-dir>/cli.env`, см. ниже)

После `init` нужно открыть и заполнить:

- `<project>/.uploadtool/release.env`

### 3) (Опционально) сохранить дефолты CLI в `cli.env`

Чтобы не передавать каждый раз `--project-root` и `--config-dir`, можно сохранить дефолты:

```bash
bash /path/to/UploadTool/run.sh init --project-root /path/to/flutter_project --save-defaults
```

По умолчанию файл создаётся в:

- `<flutter_project>/.uploadtool/cli.env` (или в той директории, которую ты задал через `--config-dir`)

Legacy (глобальный) вариант:

- `~/.uploadtool/cli.env`

Переопределить путь можно:

- флагом `--cli-env-file /path/to/cli.env`
- переменной окружения `UPLOADTOOL_CLI_ENV_FILE=/path/to/cli.env`

Пример формата:

- `config/cli.env.example`

### Несколько проектов (profiles)

Если один UploadTool используется для нескольких приложений, можно сохранить проекты в реестр:

- `~/.uploadtool/projects/<name>.env`

И выбирать нужный проект при запуске:

```bash
bash /path/to/UploadTool/run.sh --project <name>
```

### 4) Сценарий A: UploadTool как `git submodule` (внутри проекта)

Рекомендуемая структура:

```text
<flutter_project>/
  UploadTool/          # git submodule
  .uploadtool/         # конфиги (gitignored)
```

Подключение:

```bash
git submodule add <repo_url> UploadTool
```

Инициализация (рекомендуется):

```bash
bash ./UploadTool/init.sh
```

Инициализация (скриптом, дополнительно):

```bash
./UploadTool/run.sh init --project-root .
```

Запуск мастера:

```bash
./UploadTool/run.sh
```

### 5) Сценарий B: UploadTool как отдельный репозиторий

Пример:

```text
~/Tools/UploadTool/     # отдельный репозиторий
~/Projects/MyApp/       # Flutter проект
```

Инициализация (рекомендуется):

```bash
bash ~/Tools/UploadTool/init.sh
```

Инициализация (скриптом, дополнительно):

```bash
bash ~/Tools/UploadTool/run.sh init --project-root ~/Projects/MyApp
```

Запуск мастера:

```bash
bash ~/Tools/UploadTool/run.sh --project-root ~/Projects/MyApp --config-dir ~/Projects/MyApp/.uploadtool
```

Или (если сохранены дефолты через `--save-defaults`):

```bash
bash ~/Tools/UploadTool/run.sh
```

### 6) Про `.uploadtool/` и gitignore

В `.uploadtool/` обычно лежит:

- `release.env` (секреты/ключи, не коммитить)
- `wizard.env` (опционально)
- `env.json` (dart-defines)
- `logs/` и `state/` (runtime‑артефакты)

По умолчанию логи и state создаются **рядом с конфигами**:

- `UPLOAD_LOG_DIR`: `<config-dir>/logs` (переопределяется через `UPLOADTOOL_LOG_DIR`)
- `UPLOAD_STATE_DIR`: `<config-dir>/state` (переопределяется через `UPLOADTOOL_STATE_DIR`)

Для сборок мастер создаёт per-env файл dart-defines:

- `<config-dir>/state/<env>/dart_defines.json`

Он формируется копированием `<config-dir>/env.json` + обновлением ключа окружения (`APP_ENV`/`CHOYS_ENV`/или ключ из `UPLOADTOOL_ENV_JSON_ENV_KEY`).

Артефакты сборок копируются в:

- `<config-dir>/state/<env>/artifacts/`

И автоматически чистятся (retention): хранится только последние `3` `.ipa` и последние `3` `.aab` на окружение. Количество можно изменить через `UPLOADTOOL_STATE_ARTIFACTS_KEEP`.

Рекомендуется добавить в `.gitignore` проекта:

```gitignore
.uploadtool/
```
