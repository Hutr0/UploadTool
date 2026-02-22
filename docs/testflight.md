## iOS → TestFlight (Flutter + fastlane)

В репозитории есть готовый пайплайн, который **собирает iOS `.ipa`** и **загружает в TestFlight**.

Также поддерживается единый “Upload wizard” (см. `Upload`), который может собрать/загрузить iOS и Android параллельно.

### Быстрый старт (iOS)

#### 1) Подготовь конфиги

UploadTool читает настройки из **одного** файла: `release.env`.

Рекомендуемый вариант (удобно для подключения к разным проектам):

- `<flutter_project>/.uploadtool/release.env`

Скопировать заготовку:

```bash
mkdir -p .uploadtool
cp UploadTool/config/release.env.example .uploadtool/release.env
```

Если ты используешь UploadTool как «папку внутри проекта» и не хочешь заводить `.uploadtool`, можно по‑старому:

```bash
cp UploadTool/config/release.env.example UploadTool/config/release.env
```

#### 2) Выбери один способ авторизации

В `release.env` укажи **один** вариант:

- Вариант A (рекомендуется): App Store Connect API key
  - `ASC_KEY_ID`
  - `ASC_ISSUER_ID`
  - `ASC_KEY_PATH`
- Вариант B: Apple ID + app-specific password
  - `FASTLANE_USER`
  - `FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD`

Опционально (если несколько команд):

- `FASTLANE_TEAM_ID` / `FASTLANE_TEAM_NAME`

#### 3) Запусти мастер

Если UploadTool лежит в проекте:

```bash
./UploadTool/run.sh ios
```

Если UploadTool лежит отдельно:

```bash
bash /path/to/UploadTool/run.sh --project-root /path/to/flutter_project --config-dir /path/to/flutter_project/.uploadtool ios
```

Проверить только сборку `.ipa` (без загрузки): в wizard выбери `Upload iOS to TestFlight? -> n`.

### Выбор окружения (dev/prod) — через JSON

Окружение приложения задаётся через `env.json` в директории конфигов (например `.uploadtool/env.json`) и прокидывается в Flutter как dart-define:

- `CHOYS_ENV`: `dev` или `prod`
- `CHOYS_BASE_URL`: опционально (если задано — **перебивает** `CHOYS_ENV`)

Если файла ещё нет, можно создать из примера:

```bash
mkdir -p .uploadtool
cp UploadTool/config/env.json.example .uploadtool/env.json
```

Самый простой путь — запускать `Upload` / `UploadTool/run.sh`: мастер спросит окружение и сам обновит `env.json` в директории конфигов перед сборкой.

Если выбрано `dev + prod`, wizard выполнит две публикации подряд:

- build number используется в формате `YYYYMMDD.N.X`, где `X`: `dev=0`, `prod=1`
- dev (тестовая сборка) — например `20260220.1.0`
- prod (релизная сборка) — ядро `YYYYMMDD.N` на 1 больше + суффикс `.1` (пример: dev `20260220.1.0` → prod `20260220.2.1`)

Если собираешь/запускаешь из IDE — добавь в run конфиг Flutter аргумент:

- `--dart-define-from-file=.uploadtool/env.json`

### Авторизация в TestFlight

#### Вариант A: App Store Connect API key

В App Store Connect:

- **Users and Access → Integrations → Keys**
- Создай ключ и скачай `AuthKey_XXXXXX.p8`

В `release.env` укажи:

- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_KEY_PATH` (путь до скачанного `.p8`)

Важно: файл `.p8` **не хранится** в macOS Keychain.

#### Вариант B: Apple ID + app-specific password (без API key)

Сгенерируй app-specific password на `appleid.apple.com` и укажи в `release.env`:

- `FASTLANE_USER`
- `FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD`

Опционально (если несколько команд в App Store Connect):

- `FASTLANE_TEAM_ID`
- `FASTLANE_TEAM_NAME`

Также поддерживаются legacy-алиасы: `FASTLANE_ITC_TEAM_ID`, `FASTLANE_ITC_TEAM_NAME`.

### Что именно запускается

`UploadTool/run.sh ios`:

- загружает env‑переменные из `release.env` (по умолчанию из `--config-dir` / `.uploadtool` / `UploadTool/config`)
- делает `bundle install` в `UPLOADTOOL_FASTLANE_ROOT` (по умолчанию это `UploadTool/fastlane`)
- запускает lane `ios upload_testflight`

Fastlane‑логика:

- лежит в `UploadTool/fastlane/fastlane/Fastfile`
- выполняет `flutter pub get`
- выполняет `flutter build ipa --release` (если не задан `SKIP_FLUTTER_BUILD=1`)
- загружает `build/ios/ipa/*.ipa` в TestFlight

### Решение проблем

#### `error: exportArchive Copy failed` / проблемы с `rsync`

Если `flutter build ipa` падает с:

- `error: exportArchive Copy failed`
- и в `.xcdistributionlogs` есть что-то вроде:
  - `rsync: on remote machine: --extended-attributes: unknown option`

то обычно причина — **Homebrew rsync** “перехватывает” системный:

- Homebrew: `/opt/homebrew/bin/rsync` (3.x)
- System: `/usr/bin/rsync` (совместим с export pipeline Xcode)

В Xcode export pipeline может вызвать `/usr/bin/rsync`, но “server” rsync подтянуть через `PATH`. Если первым в `PATH` стоит Homebrew rsync — export ломается.

`UploadTool/run.sh` уже принудительно ставит системные пути первыми в `PATH`. Если делаешь вручную:

```bash
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
flutter build ipa --release
```

