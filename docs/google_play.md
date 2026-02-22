## Android → Google Play (Flutter + fastlane supply)

В репозитории есть готовый пайплайн, который **собирает Android `.aab`** и **загружает в Google Play Console** (через fastlane supply).

Также поддерживается единый “Upload wizard” (см. `Upload`), который может собрать/загрузить iOS и Android параллельно.

### Разовая настройка (Google)

1) В Google Play Console:

- **Setup → API access**
- Привяжи Google Cloud project (если ещё не привязан)

2) В Google Cloud Console:

- Создай **Service Account**
- Создай и скачай **JSON key**

3) Снова в Play Console:

- Дай service account доступ к аккаунту разработчика / конкретному приложению
- Выдай права, позволяющие загрузку релизов (например, release manager / upload)

### Локальная конфигурация

UploadTool использует **единый** `release.env` (он в `.gitignore`).

Рекомендуемый вариант:

- `<flutter_project>/.uploadtool/release.env`

Скопировать заготовку:

```bash
mkdir -p .uploadtool
cp UploadTool/config/release.env.example .uploadtool/release.env
```

Минимальный набор для Google Play:

- `PLAY_JSON_KEY_PATH` (путь до JSON ключа service account)
- `ANDROID_PACKAGE_NAME` (applicationId)
- `PLAY_TRACK` (рекомендуется `internal`)

### Запуск

Запустить wizard с Android-target:

```bash
./UploadTool/run.sh android
```

Если UploadTool лежит отдельно:

```bash
bash /path/to/UploadTool/run.sh --project-root /path/to/flutter_project --config-dir /path/to/flutter_project/.uploadtool android
```

Только сборка (без загрузки): в wizard выбери `Upload Android to Google Play? -> n`.

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

### Примечание про `versionCode`

Android `versionCode` должен быть **целым числом**.

В этом проекте логика такая:

- если задан `ANDROID_BUILD_NUMBER` — используем его
- иначе берём `BUILD_NUMBER` (или, если его нет, build-number из `pubspec.yaml`)
- и **удаляем все нецифровые символы** (пример: `20260220.4` → `202602204`)

Важно: если build number в формате `YYYYMMDD.N.X`, то для Android `versionCode` берётся **только ядро** `YYYYMMDD.N` (суффикс `.X` игнорируется), чтобы `versionCode` гарантированно оставался в диапазоне `int`.

### Имя релиза в Google Play (Release name)

При загрузке fastlane/supply выставляет **имя релиза** (в Play Console) через `version_name`.

По умолчанию оно формируется так:

- `"<BUILD_NAME> | <BUILD_NUMBER> | <dev/prod>"` (пример: `3.8.3 | 20260220.2.1 | prod`)

Если нужно переопределить вручную:

- `SUPPLY_VERSION_NAME="..."` (или `PLAY_RELEASE_NAME="..."`)

