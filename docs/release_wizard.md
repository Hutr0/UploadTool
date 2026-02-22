## Релиз‑мастер (UploadTool): iOS + Android

Это тот самый интерактивный мастер, который берёт тебя за руку и доводит до результата:

- **собирает** iOS (`.ipa`) и Android (`.aab`)
- по желанию **загружает** iOS в TestFlight и Android в Google Play
- умеет делать iOS+Android **параллельно** (чтобы не ждать лишнего)
- после успешной публикации обновляет версию в `pubspec.yaml` (`version: <name>+<number>`)

И да — теперь UploadTool можно держать как внутри проекта, так и отдельно (в другом репозитории).

### Точки входа

- `./Upload` — «как в этом проекте принято» (обёртка над UploadTool)
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
- иначе, если есть `${PROJECT}/.uploadtool` — берёт её
- иначе — использует `UploadTool/config`

### 1) Окружение приложения (dev/prod) — `env.json`

`env.json` — это dart‑defines, которые попадут в Flutter сборку через `--dart-define-from-file`.

Поддерживаемые ключи:

- `CHOYS_ENV`: `dev` или `prod`
- `CHOYS_BASE_URL`: опционально. Если задан (не пустой) — **перебивает** `CHOYS_ENV`.

Приоритет (как в приложении, так и в iOS ShareExtension):

1) `CHOYS_BASE_URL` / `config.baseUrl`
2) `CHOYS_ENV` / `config.env`
3) если ничего не задано — **prod**

Мастер перед сборкой **сам обновляет** `env.json` в директории конфигов (например, `.uploadtool/env.json`).

Если выбираешь `dev + prod`, мастер делает две публикации подряд:

- build number используется в формате `YYYYMMDD.N.X`, где `X`: `dev=0`, `prod=1`
- dev публикуется как `YYYYMMDD.N.0` (пример: `20260220.1.0`)
- prod — ядро `YYYYMMDD.N` на 1 больше + `.1` (пример: dev `20260220.1.0` → prod `20260220.2.1`)

Важно про iOS ShareExtension: он берёт baseUrl из App Group (значения `config.env` / `config.baseUrl`), которые приложение записывает при старте. Поэтому после смены окружения рекомендуется **один раз запустить приложение**, чтобы extension точно подхватил актуальный baseUrl.

### 2) Креды и настройки сборки/публикации — `release.env`

`release.env` — **единый источник правды** для сборки и публикации (iOS + Android).

По умолчанию UploadTool читает:

- `${UPLOAD_CONFIG_DIR}/release.env` (например, `.uploadtool/release.env`)

Пример со всеми опциями:

- `UploadTool/config/release.env.example`

### 3) Поведение мастера (опционально) — `wizard.env`

Файл опционален. Он позволяет:

- задать значения по умолчанию (targets/env/upload/wait)
- пропускать вопросы (удобно для CI или когда каждый релиз «по одному сценарию»)

Пример:

- `UploadTool/config/wizard.env.example`

### Запуск из IDE (VSCode/Android Studio)

Если запускаешь приложение не через мастер, а из IDE, и хочешь использовать то же окружение, добавь в аргументы Flutter:

- `--dart-define-from-file=PATH_TO_ENV_JSON`

Где `PATH_TO_ENV_JSON` — это файл `env.json` из твоей директории конфигов:

- если ты используешь рекомендованный вариант — это обычно `.uploadtool/env.json`
- если ты используешь дефолт (когда UploadTool лежит внутри проекта) — это может быть `UploadTool/config/env.json`

### Fastlane (встроенный)

Fastlane‑конфигурация теперь живёт внутри UploadTool:

- `UploadTool/fastlane/Gemfile`
- `UploadTool/fastlane/fastlane/Fastfile`
- `UploadTool/fastlane/fastlane/Appfile`

По умолчанию мастер делает `bundle install` именно там. При необходимости можно переопределить:

- `UPLOADTOOL_FASTLANE_ROOT=/path/to/fastlane_root`

### Документация по платформам

- iOS TestFlight: `UploadTool/docs/testflight.md`
- Android Google Play: `UploadTool/docs/google_play.md`

