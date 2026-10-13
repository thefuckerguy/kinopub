<p align="right"><b>Русский</b> · <a href="README.en.md">English</a></p>

<p align="center">
  <img src="web/public/woof-mascot.png" alt="WooF.Play" width="160">
</p>

<h1 align="center">WooF.Play</h1>

<p align="center"><b>Домашний кинотеатр для kino.watch: веб-интерфейс на компьютере и нативное приложение для iPhone и iPad.</b></p>

<p align="center">
  <a href="https://github.com/thefuckerguy/kinopub/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/thefuckerguy/kinopub?display_name=tag&style=flat-square"></a>
  <a href="https://github.com/thefuckerguy/kinopub/actions/workflows/ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/thefuckerguy/kinopub/ci.yml?branch=main&style=flat-square&label=tests"></a>
  <img alt="Go" src="https://img.shields.io/badge/Go-1.26-00ADD8?logo=go&logoColor=white&style=flat-square">
  <img alt="React" src="https://img.shields.io/badge/React-18-61DAFB?logo=react&logoColor=black&style=flat-square">
  <img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-iPhone%20%2B%20iPad-0A84FF?logo=swift&logoColor=white&style=flat-square">
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/License-MIT-7d47ff?style=flat-square"></a>
</p>

WooF.Play объединяет два клиента в одном репозитории:

- **Настольное приложение** — один Go-бинарник со встроенным React-интерфейсом. Он открывается в браузере, но работает локально на вашем компьютере: Electron и отдельный Node.js во время работы не нужны.
- **WooF.Play для iPhone/iPad** — нативный SwiftUI-клиент с онлайн-просмотром, офлайн-загрузками, внутренним хранилищем и поддержкой внешних дисков.

Веб-интерфейс оформлен в том же стиле, что и приложение: тёмно-синий фон, cyan/violet-акценты и фирменный маскот WooF.Play.

> Проект не является публичным стриминговым сайтом и не предоставляет контент. Для каталога и воспроизведения нужен собственный аккаунт kino.watch с активной подпиской.

## Что умеет

### Каталог и просмотр

- новинки, популярное и горячее;
- полный каталог с поиском, жанрами, странами, годами, IMDb/Кинопоиск, AC3 и субтитрами;
- подборки, история, «Я смотрю» и отдельный раздел подписок;
- подробная карточка: описание, актёры, рейтинги, сезоны, серии, озвучки и похожие тайтлы;
- встроенный HLS-плеер с восстановлением позиции и синхронизацией прогресса с аккаунтом;
- ручные локальные отметки просмотренного для фильма или серии.

### Списки и закладки

- **Буду смотреть** — локальный список в текущем браузере;
- **Персональный просмотр** — локальный приватный список, который не отправляется в KinoPub;
- подписка и отписка от фильмов и сериалов;
- создание и удаление папок закладок;
- добавление и удаление тайтлов в папках закладок;
- быстрые действия доступны прямо на карточках и в подробном просмотре.

Локальность «Персонального просмотра» относится к самому списку. Если запустить видео, обычная история и позиция воспроизведения по-прежнему синхронизируются с аккаунтом kino.watch.

### Загрузки и офлайн-библиотека

- фильмы, отдельные серии, сезоны и многосезонные сериалы;
- выбор качества, озвучек, контейнера, папки вывода, прокси и аргументов ffmpeg;
- сохранение всех нужных аудиодорожек и субтитров;
- прогресс по тайтлу, серии и дорожке, скорость и оставшееся время;
- пауза, продолжение, отмена, повтор и приоритизация;
- очередь переживает перезапуск и продолжает незавершённую загрузку;
- единая офлайн-библиотека: активные задачи и готовые файлы, поиск, фильтры, размеры и разрешения;
- открытие файла или папки, удаление серии либо всего тайтла;
- встроенный Doctor для проверки и восстановления состояния библиотеки.

### iPhone и iPad

Нативное приложение дополнительно поддерживает:

- адаптивный интерфейс iPhone/iPad и полноэкранный онлайн- и офлайн-плеер;
- фоновые HLS-загрузки с выбором качества, озвучки и места хранения;
- внутреннюю папку `Файлы → На моём iPhone/iPad → WooF.Play → Movies`;
- подключённые папки и USB-диски через security-scoped bookmarks;
- чтение `.kinopub-state.json` от настольного приложения;
- перенос диска между компьютером и iPhone/iPad без потери библиотеки;
- локальное восстановление позиции и синхронизацию прогресса с аккаунтом;
- проверку новых серий и дозагрузку недостающих эпизодов;
- Keychain для OAuth-токенов.

Управление Apple-подписью, Developer Mode, установкой IPA и доверенными устройствами остаётся в Xcode и **WooF Installer для macOS**. Эти нативные операции намеренно не дублируются в веб-интерфейсе.

## Быстрый старт: компьютер

Скачайте готовый файл на странице [последнего релиза](https://github.com/thefuckerguy/kinopub/releases/latest).

| Платформа | Файл |
| --- | --- |
| macOS Apple Silicon | `kinopub-gui-darwin-arm64` или `.dmg` |
| macOS Intel | `kinopub-gui-darwin-amd64` или `.dmg` |
| Windows x64 | `kinopub-gui-windows-amd64.exe` |
| Linux x64 | `kinopub-gui-linux-amd64` или AppImage |
| Linux ARM64 | `kinopub-gui-linux-arm64` |
| Android/Termux ARM64 | `kinopub-gui-android-arm64` |

На macOS/Linux:

```sh
chmod +x kinopub-gui-darwin-arm64
./kinopub-gui-darwin-arm64
```

На Windows запустите `.exe` двойным щелчком или из PowerShell:

```powershell
.\kinopub-gui-windows-amd64.exe
```

Приложение откроет локальный адрес `http://127.0.0.1:8765`. Сервер слушает только loopback-интерфейс и отклоняет запросы с посторонних страниц.

### ffmpeg

Для сборки видео, аудио и субтитров нужен `ffmpeg` вместе с `ffprobe`:

```sh
brew install ffmpeg          # macOS
sudo apt install ffmpeg      # Debian / Ubuntu
```

```powershell
winget install Gyan.FFmpeg   # Windows
```

Если ffmpeg не найден, откройте **Настройки → Система → Установить ffmpeg**. Приложение скачает собственную сборку без прав администратора и не будет менять системный `PATH`.

### Первый вход

1. Откройте **Профиль → Войти**.
2. Перейдите по показанной ссылке kino.watch и введите короткий код устройства.
3. После подтверждения каталог, плеер, подписки и закладки станут доступны автоматически.

Токены на компьютере хранятся зашифрованными и привязаны к машине. Локальные страницы — библиотека, настройки, «Буду смотреть» и «Персональный просмотр» — не требуют входа.

> Если kino.watch недоступен в вашей сети, включите VPN или задайте HTTP/HTTPS/SOCKS5-прокси в настройках WooF.Play.

### Обновления

Релизная сборка проверяет [релизы этого репозитория](https://github.com/thefuckerguy/kinopub/releases), подбирает файл для текущей платформы, сверяет SHA-256 из `checksums.txt` и предлагает **Обновить и перезапустить**. Сборки из исходников помечены как `dev` и автоматически себя не заменяют.

## Установка на iPhone/iPad

### Xcode

1. Откройте [`ios/KinoPad.xcodeproj`](ios/KinoPad.xcodeproj) в Xcode.
2. Выберите схему **KinoPad**.
3. Для физического устройства укажите свою Team в **Signing & Capabilities**.
4. Соберите и запустите приложение.

Подробности, локальная development-IPA и TestFlight: [`ios/README.md`](ios/README.md) и [`ios/TestFlight.md`](ios/TestFlight.md).

### WooF Installer для macOS

[`macos/WooFInstaller`](macos/WooFInstaller) умеет получить актуальный `main`, собрать и установить WooF.Play на ваши доверенные iPhone/iPad по USB или Wi-Fi. Установщик использует штатные механизмы Xcode и Apple и не обходит подпись.

Подписанные development/ad hoc IPA намеренно не прикладываются к публичным релизам: provisioning profile может содержать идентификаторы зарегистрированных устройств.

## Настройки и данные

| Данные | Расположение |
| --- | --- |
| Настройки настольного приложения | `~/.config/kinopub/gui.json` |
| Зашифрованные данные входа | `~/.config/kinopub/credentials.enc` |
| Очередь загрузок | каталог конфигурации приложения |
| Состояние скачанного тайтла | `.kinopub-state.json` рядом с файлами |
| «Буду смотреть» / «Персональный просмотр» в web | `localStorage` текущего браузера |
| OAuth на iPhone/iPad | Keychain |

Локальные браузерные списки сохраняют только данные карточки — без токенов, URL видеопотока и учётных данных.

## Сборка из исходников

Требования: Go 1.26.3+, Node.js 20+, npm и ffmpeg для фактических загрузок.

```sh
git clone https://github.com/thefuckerguy/kinopub.git
cd kinopub
cd web && npm ci && cd ..
make all
./kinopub-gui
```

Для разработки интерфейса с hot reload:

```sh
make dev
# http://localhost:5173
```

Проверки:

```sh
cd web && npm test && npm run build
cd ..
go test ./... -count=1
go vet ./...
```

Нативный клиент:

```sh
cd ios
xcodebuild -project KinoPad.xcodeproj \
  -scheme KinoPad \
  -destination 'platform=iOS Simulator,name=iPhone 17e' \
  test
```

## Архитектура

```text
React + TypeScript + Tailwind
            │ REST + SSE
            ▼
      локальный Go-сервер
       internal/gui
        │         │
        │         └── официальный API kino.watch
        ▼
  очередь и загрузчик
  HLS → ffmpeg → библиотека
```

React-сборка лежит в `web/dist` и встраивается в бинарник через `go:embed`. Прогресс загрузок приходит по SSE, команды идут через локальный REST API, а HLS-поток плеера проксируется подписанными одноразовыми ссылками.

```text
cmd/kinopub-gui/          запуск настольного приложения
internal/app/kinopub/     движок и композиция сервисов
internal/services/        API, HLS, загрузчик, очередь, состояние
internal/gui/             локальный HTTP API, SSE, библиотека и updater
web/                      React-интерфейс WooF.Play
ios/KinoPad/              SwiftUI-клиент iPhone/iPad
macos/WooFInstaller/      локальная установка iOS-приложения
```

## Безопасность и границы

- настольный сервер по умолчанию доступен только на `127.0.0.1`;
- HLS-прокси использует подписанные ссылки и не работает как открытый прокси;
- OAuth-токены не попадают в браузерные локальные списки;
- updater сверяет размер и SHA-256 релизного файла перед заменой;
- приложение не отключает и не обходит Apple signing, Developer Mode или доверие устройства;
- публичные релизы не содержат персонально подписанных IPA.

## Релизы

Актуальная стабильная версия — **v0.4.0**. Тег `v*` запускает GitHub Actions: веб-интерфейс собирается заново, создаются бинарники для macOS, Windows, Linux и Android/Termux, формируется `checksums.txt`, после чего публикуется GitHub Release.

## Благодарности

- Основа движка загрузки: [niazlv/kinopub-downloader](https://github.com/niazlv/kinopub-downloader).
- Интерфейсы WooF.Play, интеграция каталога/плеера, нативный клиент и упаковка развиваются в этом репозитории.

## Лицензия

MIT — см. [LICENSE](LICENSE).
