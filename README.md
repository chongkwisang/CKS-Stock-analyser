# CKS Stock Analyser

Bursa Malaysia stock market analyser for Android phones and tablets, built with Flutter.

**Download the latest APK:**
https://github.com/chongkwisang/CKS-Stock-analyser/releases/latest/download/CKS-Stock-Analyser.apk

## Features
- **Market**: FBM KLCI chart, market breadth, sector performance and the KLCI's top gainers, losers and most active stocks
- **Watchlist**: sparklines and live % change; swipe to remove; drag to reorder. Tablets show a list and detail side by side
- **Search**: by name or 4-digit Bursa code, plus browse by sector
- **Stock detail**: candlestick or line chart (1D to MAX), MA20/50/200, Bollinger Bands, volume, RSI(14), MACD and a touch crosshair
- **Analyzer**: a technical score and signal breakdown. The rules live in `lib/services/analyzer.dart`, the place to change them
- **Adaptive layout**: bottom navigation on phones; a navigation rail and split panes on tablets. Light and dark themes
- **Claude AI assistant**: a floating button at the bottom-right opens an animated chat panel over any screen (tap again to minimise).
  - **Claude account (default, no API key):** the chat is a page on claude.ai (`claude_page/cks-ai.html`, published at https://claude.ai/artifact/Fw3oDijVjE9ZUPiE3dDQTZ) shown inside the app. You sign in to claude.ai once and it runs on your own Claude plan. The page reads live Bursa data from the app through a JavaScript bridge (`lib/ai/claude_web.dart`). In the chat you choose Fast / Balanced / Most capable, or a named model, plus thinking depth.
  - **API key (advanced):** a pay-as-you-go Claude Console key, with any model on the account, web search and fetch, and your own remote MCP servers.
  - Both modes share the 9 Bursa tools in `lib/ai/app_tools.dart`: search, quotes, price history, technical analysis, compare, market overview, read and update the watchlist, open charts.
- **In-app updates**: Settings → *Check for update* (and an automatic check on launch) downloads the newest release APK and installs it

Market data comes from Yahoo Finance's public endpoints (`XXXX.KL` symbols, `^KLSE` index) and may be delayed.

## How updates work
1. Push code to `main` (or a `ccr-*` branch).
2. GitHub Actions (`.github/workflows/release-apk.yml`) runs analyze and tests, then builds a signed APK. Each build is published as release `v1.0.<run number>`.
3. Installed apps check `releases/latest` and offer the update.

### Signing key (required for in-app updates)
Android only installs an update when it is signed with the **same key** as the installed app. The key is kept out of git; CI reads it from two repository secrets
(*Settings → Secrets and variables → Actions → New repository secret*):

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | base64 of the `.jks` keystore (alias `cks`) |
| `ANDROID_KEYSTORE_PASSWORD` | keystore/key password |

If they are missing, CI falls back to a temporary debug key (the release notes say so). Updates between debug-signed builds will not install.

## Develop
```bash
flutter pub get
flutter run            # device/emulator
flutter test
flutter build apk --release
```
For local release signing, create `android/key.properties`, which is git-ignored:
```
storeFile=/absolute/path/to/release.jks
storePassword=...
keyAlias=cks
keyPassword=...
```
