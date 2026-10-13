<p align="right"><a href="README.md">Русский</a> · <b>English</b></p>

<p align="center">
  <img src="web/public/woof-mascot.png" alt="WooF.Play" width="160">
</p>

<h1 align="center">WooF.Play</h1>

<p align="center"><b>A home cinema for kino.watch: a desktop web interface plus a native iPhone and iPad app.</b></p>

<p align="center">
  <a href="https://github.com/thefuckerguy/kinopub/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/thefuckerguy/kinopub?display_name=tag&style=flat-square"></a>
  <a href="https://github.com/thefuckerguy/kinopub/actions/workflows/ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/thefuckerguy/kinopub/ci.yml?branch=main&style=flat-square&label=tests"></a>
  <img alt="Go" src="https://img.shields.io/badge/Go-1.26-00ADD8?logo=go&logoColor=white&style=flat-square">
  <img alt="React" src="https://img.shields.io/badge/React-18-61DAFB?logo=react&logoColor=black&style=flat-square">
  <img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-iPhone%20%2B%20iPad-0A84FF?logo=swift&logoColor=white&style=flat-square">
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/License-MIT-7d47ff?style=flat-square"></a>
</p>

WooF.Play ships two clients in one repository:

- **Desktop app** — a single Go binary with an embedded React interface. It opens in your browser but runs entirely on your computer; Electron and a separate Node.js runtime are not required.
- **WooF.Play for iPhone/iPad** — a native SwiftUI client with online playback, offline downloads, internal storage, and external-drive support.

The web interface now shares the native app's visual language: deep navy surfaces, cyan/violet accents, and the WooF.Play mascot.

> This project is not a public streaming website and does not provide content. Catalog and playback require your own kino.watch account with an active subscription.

## Features

### Catalog and playback

- fresh, popular, and hot charts;
- full catalog search with genre, country, year, IMDb/Kinopoisk, AC3, and subtitle filters;
- collections, history, Watching, and a dedicated Subscriptions section;
- title details with plot, cast, ratings, seasons, episodes, voiceovers, and similar titles;
- built-in HLS player with resume and account progress sync;
- local manual watched/unwatched marks for a movie or episode.

### Lists and bookmarks

- **Watch later** — a local list in the current browser;
- **Personal viewing** — a private local list that is never sent to KinoPub;
- subscribe and unsubscribe from films and series;
- create and delete bookmark folders;
- add and remove titles from bookmark folders;
- quick actions on every catalog card and inside title details.

Only the Personal viewing list itself is local. Playing an item still updates the regular kino.watch history and resume position for your account.

### Downloads and offline library

- films, individual episodes, full seasons, and multi-season series;
- quality, voiceover, container, destination, proxy, and ffmpeg argument selection;
- retain the requested audio tracks and subtitles;
- title, episode, and track progress with speed and ETA;
- pause, resume, cancel, retry, and prioritize;
- a persistent queue that survives restarts and resumes unfinished work;
- one offline library for live jobs and completed files, with search, filters, sizes, and resolutions;
- open a file or reveal its folder; delete one episode or an entire title;
- a built-in Doctor that inspects and repairs library state.

### iPhone and iPad

The native app additionally provides:

- adaptive iPhone/iPad layouts and clean full-screen online/offline playback;
- background HLS downloads with quality, voiceover, and storage selection;
- `Files → On My iPhone/iPad → WooF.Play → Movies` internal storage;
- folder and USB-drive access through security-scoped bookmarks;
- compatibility with the desktop app's `.kinopub-state.json` metadata;
- moving a drive between the desktop and iPhone/iPad without losing the library;
- local resume recovery plus account progress sync;
- checking for and downloading newly available episodes;
- OAuth credentials stored in Keychain.

Apple signing, Developer Mode, IPA installation, and trusted-device management remain in Xcode and **WooF Installer for macOS**. These native operations are intentionally not duplicated in the browser UI.

## Quick start: desktop

Download the appropriate artifact from the [latest release](https://github.com/thefuckerguy/kinopub/releases/latest).

| Platform | Artifact |
| --- | --- |
| macOS Apple Silicon | `kinopub-gui-darwin-arm64` or `.dmg` |
| macOS Intel | `kinopub-gui-darwin-amd64` or `.dmg` |
| Windows x64 | `kinopub-gui-windows-amd64.exe` |
| Linux x64 | `kinopub-gui-linux-amd64` or AppImage |
| Linux ARM64 | `kinopub-gui-linux-arm64` |
| Android/Termux ARM64 | `kinopub-gui-android-arm64` |

On macOS/Linux:

```sh
chmod +x kinopub-gui-darwin-arm64
./kinopub-gui-darwin-arm64
```

On Windows, double-click the `.exe` or launch it from PowerShell:

```powershell
.\kinopub-gui-windows-amd64.exe
```

The app opens `http://127.0.0.1:8765`. Its server listens on loopback only and rejects requests originating from unrelated web pages.

### ffmpeg

The downloader needs `ffmpeg` and `ffprobe` to combine video, audio, and subtitles:

```sh
brew install ffmpeg          # macOS
sudo apt install ffmpeg      # Debian / Ubuntu
```

```powershell
winget install Gyan.FFmpeg   # Windows
```

If ffmpeg is missing, open **Settings → System → Install ffmpeg**. WooF.Play installs a private build without administrator rights or changes to the system `PATH`.

### First sign-in

1. Open **Profile → Sign in**.
2. Follow the kino.watch link shown in the app and enter the short device code.
3. Once confirmed, the catalog, player, subscriptions, and bookmarks become available automatically.

Desktop tokens are encrypted and machine-bound. Local pages — Library, Settings, Watch later, and Personal viewing — remain available without signing in.

> If kino.watch is unavailable on your network, enable a VPN or configure an HTTP/HTTPS/SOCKS5 proxy in WooF.Play settings.

### Updates

Release builds check [this repository's releases](https://github.com/thefuckerguy/kinopub/releases), select the artifact for the current platform, verify its SHA-256 from `checksums.txt`, and offer **Update & restart**. Source builds are marked `dev` and do not replace themselves automatically.

## Install on iPhone/iPad

### Xcode

1. Open [`ios/KinoPad.xcodeproj`](ios/KinoPad.xcodeproj) in Xcode.
2. Select the **KinoPad** scheme.
3. For a physical device, choose your Team under **Signing & Capabilities**.
4. Build and run the app.

See [`ios/README.md`](ios/README.md) and [`ios/TestFlight.md`](ios/TestFlight.md) for development IPA and TestFlight details.

### WooF Installer for macOS

[`macos/WooFInstaller`](macos/WooFInstaller) can fetch the current `main`, build, and install WooF.Play on your trusted iPhone/iPad over USB or Wi-Fi. It uses the supported Xcode and Apple workflows and does not bypass signing.

Personal development/ad hoc IPA files are intentionally excluded from public releases because a provisioning profile may expose registered device identifiers.

## Settings and data

| Data | Location |
| --- | --- |
| Desktop settings | `~/.config/kinopub/gui.json` |
| Encrypted desktop credentials | `~/.config/kinopub/credentials.enc` |
| Download queue | the app configuration directory |
| Per-title download state | `.kinopub-state.json` beside the files |
| Web Watch later / Personal viewing | current browser `localStorage` |
| iPhone/iPad OAuth credentials | Keychain |

Local browser lists store card metadata only — never tokens, playback URLs, or credentials.

## Build from source

Requirements: Go 1.26.3+, Node.js 20+, npm, and ffmpeg for actual downloads.

```sh
git clone https://github.com/thefuckerguy/kinopub.git
cd kinopub
cd web && npm ci && cd ..
make all
./kinopub-gui
```

For UI development with hot reload:

```sh
make dev
# http://localhost:5173
```

Checks:

```sh
cd web && npm test && npm run build
cd ..
go test ./... -count=1
go vet ./...
```

Native client:

```sh
cd ios
xcodebuild -project KinoPad.xcodeproj \
  -scheme KinoPad \
  -destination 'platform=iOS Simulator,name=iPhone 17e' \
  test
```

## Architecture

```text
React + TypeScript + Tailwind
            │ REST + SSE
            ▼
       local Go server
       internal/gui
        │         │
        │         └── official kino.watch API
        ▼
   queue and downloader
   HLS → ffmpeg → library
```

The React build lives in `web/dist` and is embedded through `go:embed`. Download progress arrives over SSE, commands use the local REST API, and the player receives HLS through signed one-use proxy URLs.

```text
cmd/kinopub-gui/          desktop entry point
internal/app/kinopub/     engine composition
internal/services/        API, HLS, downloader, scheduler, state
internal/gui/             local HTTP API, SSE, library, updater
web/                      WooF.Play React interface
ios/KinoPad/              native iPhone/iPad SwiftUI client
macos/WooFInstaller/      local iOS installation companion
```

## Security boundaries

- the desktop server binds to `127.0.0.1` by default;
- signed HLS URLs prevent the proxy from becoming an open proxy;
- OAuth tokens never enter local browser lists;
- the updater checks artifact size and SHA-256 before replacement;
- the project does not disable or bypass Apple signing, Developer Mode, or device trust;
- public releases do not contain personally signed IPA files.

## Releases

The current stable release is **v0.4.0**. A `v*` tag triggers GitHub Actions: the web UI is rebuilt, binaries for macOS, Windows, Linux, and Android/Termux are produced, `checksums.txt` is generated, and a GitHub Release is published.

## Credits

- Download-engine foundation: [niazlv/kinopub-downloader](https://github.com/niazlv/kinopub-downloader).
- WooF.Play interfaces, catalog/player integration, native client, and packaging are maintained in this repository.

## License

MIT — see [LICENSE](LICENSE).
