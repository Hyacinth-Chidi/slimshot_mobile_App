# SlimShotAI

SlimShotAI is a local-first Flutter app for compressing, converting, saving, and sharing photos and videos. It is designed around fast media optimization, privacy-friendly metadata removal, and simple output flows for everyday sharing.

## Current Features

- Video compression with FFmpeg presets
- Basic video editing with trim and mute export
- Image compression with quality presets
- Image format conversion to JPG, PNG, and WebP
- Image metadata stripping
- Before/after image preview
- Video preview and playback on result screens
- Save to gallery and share actions
- Onboarding and update-check flow
- Android share-intent support for incoming media

## Tech Stack

- Flutter and Dart
- Riverpod for feature state
- GoRouter for navigation
- FFmpeg Kit for video analysis and compression
- Pro Video Editor for Android/iOS video editing exports
- Flutter Image Compress for image compression and conversion
- Gal for gallery writes
- Share Plus for sharing exported files
- Google Mobile Ads for interstitial ads

## Project Structure

```text
lib/
  core/
    models/       Shared data models
    services/     App-level services such as ads, updates, saving, and picking
    theme/        App colors and Material theme
    utils/        File and toast helpers
    widgets/      Shared UI widgets
  features/
    compression/  Compression providers, presets, and services
    convert/      Image conversion state and logic
    privacy/      Metadata-stripping state and logic
    sharing/      Android/iOS share-intent handling
    video_editor/ Video editing export services
  screens/        App screens and feature flows
```

## Setup

Install Flutter, then fetch dependencies:

```bash
flutter pub get
```

Run the app:

```bash
flutter run
```

Run static analysis:

```bash
flutter analyze
```

Run tests:

```bash
flutter test
```

## Build Notes

Android release signing expects `android/key.properties` to exist for release builds. Debug builds do not need release signing credentials.

The app uses media, storage, internet, share-intent, and ad-related platform permissions. Check platform configuration before release builds.

The video editor roadmap targets Android phones, Android tablets, iPhone, and iPad. Desktop platforms are not part of the planned editor support.

## Upgrade Plans

See:

- `upgrade.md` for the product roadmap
- `implementation.md` for the phased implementation plan
- `editor.md` for the dedicated video editor roadmap
