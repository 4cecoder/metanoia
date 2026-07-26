# Metanoia Mobile

Kotlin/Compose Bible study app with gateway-proxied AI services (TTS, STT, interlinear, lexicon) and full offline Bible caching.

## Architecture

```
mobile/app/src/main/java/com/bytecats/metanoia/
├── bible/           Bible data layer (scraping, DB, analytics)
│   └── dao/         Domain-specific database access objects
├── gateway/         HTTP client for the Metanoia gateway server
├── models/          Data classes and constants
├── settings/        SharedPreferences wrapper
├── stt/             Speech-to-text manager
├── tts/             Text-to-speech manager and audio player
├── update/          Nightly update checker and APK installer
├── viewmodel/       MainViewModel (app-level state coordinator)
└── ui/
    ├── screens/     Full-screen Compose destinations
    │   └── settings/  Settings sub-screens (one per file)
    ├── components/  Reusable Compose components
    │   └── bible/   Bible-specific UI (verse items, grids, sheets)
    └── theme/       Material3 theme definition
```

## Build

```bash
cd mobile
./gradlew assembleDebug
```

Requires Android SDK with API 35 platform tools. The `debug.keystore` is pinned in the repo for CI build identity consistency — see `app/build.gradle.kts` for the rationale.

## Dependencies

Dependency versions are centralized in `gradle/libs.versions.toml`. To update a library version, edit the `[versions]` section — library and plugin references pick it up automatically.

## Gateway

The app connects to a Metanoia gateway server (default `192.168.122.2:8000`) for:
- Bible API (chapters, interlinear, lexicon, search)
- TTS (Kokoro neural, voice clone)
- STT (Whisper transcription)
- Nightly update checks (GitHub releases)

Configure in Settings > Gateway Connection, or set `useGatewayBible = false` to fall back to direct web scraping for Bible text.
