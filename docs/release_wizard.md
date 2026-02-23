## Релиз‑мастер (UploadTool): iOS + Android

Это тот самый интерактивный мастер, который берёт тебя за руку и доводит до результата:

- **собирает** iOS (`.ipa`) и Android (`.aab`)
- по желанию **загружает** iOS в TestFlight и Android в Google Play
- умеет делать iOS+Android **параллельно** (чтобы не ждать лишнего)
- после успешной публикации обновляет версию в `pubspec.yaml` (`version: <name>+<number>`)

И да — теперь UploadTool можно держать как внутри проекта, так и отдельно (в другом репозитории).

### Точки входа

- `./run.sh` — запуск мастера из репозитория UploadTool
- `./run.sh ios|android|both` — запуск с предвыбранной платформой

Если UploadTool подключён как папка `./UploadTool` внутри Flutter‑проекта:

- `./UploadTool/run.sh` — запуск мастера напрямую
- `./UploadTool/run.sh ios|android|both` — запуск с предвыбранной платформой

Если UploadTool лежит **в другом месте**, запускай так:

```bash
bash /path/to/UploadTool/run.sh --project-root /path/to/flutter_project --config-dir /path/to/flutter_project/.uploadtool
```

### Где живут конфиги

Рекомендуемая схема для «бесшовного подключения» к разным проектам — хранить локальные конфиги рядом с Flutter‑проектом:

```text
<flutter_project>/
  .uploadtool/
    release.env
    wizard.env
    env.json
```

UploadTool выбирает конфиг‑директорию так:

- если передан `--config-dir` (или задан `UPLOADTOOL_CONFIG_DIR`) — берёт её
- иначе, если определён Flutter‑проект (найден `pubspec.yaml`) — использует `<project>/.uploadtool` (и создаёт директорию при необходимости)
- иначе — использует `config/` рядом с `run.sh`

Логи и state по умолчанию живут рядом с конфигами:

- `UPLOAD_LOG_DIR`: `<config-dir>/logs` (можно переопределить через `UPLOADTOOL_LOG_DIR`)
- `UPLOAD_STATE_DIR`: `<config-dir>/state` (можно переопределить через `UPLOADTOOL_STATE_DIR`)

Чтобы автоматически создать `.uploadtool/` и разложить туда шаблоны конфигов, можно использовать:

- `./run.sh init --project-root /path/to/flutter_project`

Если хочется запускать UploadTool без постоянной передачи `--project-root/--config-dir`, можно сохранить дефолты:

- `./run.sh init --project-root /path/to/flutter_project --save-defaults`

Формат файла дефолтов: `config/cli.env.example`.

### 1) Окружение приложения (dev/prod) — `env.json`

`env.json` — это dart‑defines, которые попадут в Flutter сборку через `--dart-define-from-file`.

Поддерживаемые ключи (пример для универсального использования):

- `APP_ENV`: `dev` или `prod`
- `BASE_URL`: опционально (если твоё приложение умеет его читать)

Важно: UploadTool **не навязывает** твоему приложению конкретные ключи. По умолчанию мастер пишет ключ `APP_ENV`.

Мастер перед сборкой **использует** `env.json` из директории конфигов (например, `.uploadtool/env.json`) как базу.

Перед каждой сборкой он создаёт пер‑окруженческий файл:

- `state/<env>/dart_defines.json`

Алгоритм такой:

- копируем текущий `env.json` в `state/<env>/dart_defines.json` (чтобы не потерять остальные ключи, например `BASE_URL`)
- затем обновляем в `state/<env>/dart_defines.json` ключ окружения (`APP_ENV`/`CHOYS_ENV`/или ключ из `UPLOADTOOL_ENV_JSON_ENV_KEY`) на `dev` или `prod`

Это сделано специально, чтобы при сценарии `dev + prod` две сборки не перетирали общий файл и не читали “не своё” окружение.

Минимальный пример (Flutter/Dart), как читать эти значения в приложении:

```dart
const appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'prod');
const baseUrl = String.fromEnvironment('BASE_URL', defaultValue: 'https://example.com');

bool get isProd => appEnv == 'prod';
```

Пример привязки поведения и отображения версии к окружению (минимально):

```dart
// Показывай бейдж окружения, включай/выключай фичи, меняй логирование и т.п.
final showDebugTools = appEnv != 'prod';

// Версию и build number обычно берут из pubspec через package_info_plus,
// а окружение — из dart-defines.
final aboutText = 'env=$appEnv';
```

Если тебе нужна совместимость с существующим проектом:

- если файл уже содержит `CHOYS_ENV` (и не содержит `APP_ENV`) — UploadTool продолжит обновлять именно `CHOYS_ENV`
- можно явно задать ключ через `UPLOADTOOL_ENV_JSON_ENV_KEY` (например, `UPLOADTOOL_ENV_JSON_ENV_KEY=MY_ENV`)

Если выбираешь `dev + prod`, мастер делает две публикации подряд:

- build number используется в формате `YYYYMMDD.N.X`, где `X`: `dev=0`, `prod=1`
- dev публикуется как `YYYYMMDD.N.0` (пример: `20260220.1.0`)
- prod — ядро `YYYYMMDD.N` на 1 больше + `.1` (пример: dev `20260220.1.0` → prod `20260220.2.1`)

### 1.1) State и retention артефактов сборки

После сборки UploadTool копирует артефакты в state:

- iOS: `state/<env>/artifacts/app-<env>-<BUILD_NUMBER>.ipa`
- Android: `state/<env>/artifacts/app-<env>-<BUILD_NUMBER>.aab`

Чтобы директория `state/` не разрасталась, включён retention:

- для каждого окружения (`dev`/`prod`) хранится только последние `3` `.ipa` и последние `3` `.aab`
- количество можно изменить переменной `UPLOADTOOL_STATE_ARTIFACTS_KEEP` (например, `UPLOADTOOL_STATE_ARTIFACTS_KEEP=5`)



### 2) Креды и настройки сборки/публикации — `release.env`

`release.env` — **единый источник правды** для сборки и публикации (iOS + Android).

По умолчанию UploadTool читает:

- `${UPLOAD_CONFIG_DIR}/release.env` (например, `.uploadtool/release.env`)

Пример со всеми опциями:

- `config/release.env.example`

### 3) Поведение мастера (опционально) — `wizard.env`

Файл опционален. Он позволяет:

- задать значения по умолчанию (targets/env/upload/wait)
- пропускать вопросы (удобно для CI или когда каждый релиз «по одному сценарию»)

Пример:

- `config/wizard.env.example`

### Запуск из IDE (VSCode/Android Studio)

Если запускаешь приложение не через мастер, а из IDE, и хочешь использовать то же окружение, добавь в аргументы Flutter:

- `--dart-define-from-file=PATH_TO_ENV_JSON`

Где `PATH_TO_ENV_JSON` — это файл `env.json` из твоей директории конфигов:

- если ты используешь рекомендованный вариант — это обычно `.uploadtool/env.json`
- если ты запускаешь UploadTool без определённого Flutter‑проекта (нет `pubspec.yaml`) — тогда используется `config/env.json` рядом с `run.sh`

Если хочешь 1:1 повторить поведение UploadTool для конкретного окружения — используй файл, который мастер подготовил для этого окружения:

- `<config-dir>/state/<env>/dart_defines.json`

### Fastlane (встроенный)

Fastlane‑конфигурация теперь живёт внутри UploadTool:

- `fastlane/Gemfile`
- `fastlane/fastlane/Fastfile`
- `fastlane/fastlane/Appfile`

По умолчанию мастер делает `bundle install` именно там. При необходимости можно переопределить:

- `UPLOADTOOL_FASTLANE_ROOT=/path/to/fastlane_root`

### Документация по платформам

- iOS TestFlight: `docs/testflight.md`
- Android Google Play: `docs/google_play.md`

