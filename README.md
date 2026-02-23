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

Чтобы быстро и интерактивно настроить UploadTool для проекта (создать `.uploadtool/`, разложить шаблоны, проставить базовые значения):

```bash
bash /path/to/UploadTool/init.sh
```

Если хочется сделать то же самое скриптом (без опросника) — есть дополнительная команда `run.sh init`:

```bash
bash /path/to/UploadTool/run.sh init --project-root /path/to/flutter_project --save-defaults
```

 Рекомендуемый `cli.env` (локально для проекта): `<flutter_project>/.uploadtool/cli.env`.

 Legacy (глобальный) вариант: `~/.uploadtool/cli.env`.

 Пример формата:

- `config/cli.env.example`

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

По умолчанию `run.sh` делает `bundle install` именно там. Для обратной совместимости можно переопределить:

- `UPLOADTOOL_FASTLANE_ROOT=/path/to/ios` (если хочется использовать старый `ios/Gemfile` и `ios/fastlane/*`)

## Документация

- Релиз‑мастер: `docs/release_wizard.md`
- Интеграция (submodule/отдельный repo): `docs/integration_guide.md`
- iOS/TestFlight: `docs/testflight.md`
- Android/Google Play: `docs/google_play.md`
