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
- иначе попробует `${PROJECT}/.uploadtool`, и только потом — `UploadTool/config`

## Структура

- `run.sh` — интерактивный wizard
- `config/` — примеры и дефолтные конфиги (секреты не коммитим)
- `docs/` — документация по релизам
- `logs/` — runtime-логи wizard
- `state/` — runtime-state и копии артефактов

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

- `UploadTool/config/release.env.example`
- `UploadTool/config/wizard.env.example`
- `UploadTool/config/env.json.example`

## Fastlane

Fastlane‑настройки теперь живут **внутри UploadTool**:

- `UploadTool/fastlane/Gemfile`
- `UploadTool/fastlane/fastlane/Fastfile`
- `UploadTool/fastlane/fastlane/Appfile`

По умолчанию `run.sh` делает `bundle install` именно там. Для обратной совместимости можно переопределить:

- `UPLOADTOOL_FASTLANE_ROOT=/path/to/ios` (если хочется использовать старый `ios/Gemfile` и `ios/fastlane/*`)

## Документация

- Релиз‑мастер: `UploadTool/docs/release_wizard.md`
- iOS/TestFlight: `UploadTool/docs/testflight.md`
- Android/Google Play: `UploadTool/docs/google_play.md`
