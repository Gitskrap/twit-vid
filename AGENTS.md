# Twit Vid — repository instructions

## Project overview

**Twit Vid** (GitHub repository `Gitskrap/twit-vid`) is the Flutter Android application branded **Twitter vidéo**. It is an independent fork of [XFlow](https://github.com/Alchemist-Aloha/xflow) focused on public X/Twitter videos, local viewing preferences, and Google Cast.

- Android application ID: **`fr.twittervideo.client`**. Preserve this ID for in-place APK updates.
- Flutter package name: **`xflow`**, retained for import compatibility (`package:xflow/...`). Do not casually rename it.
- Android namespace: **`com.alchemistaloha.xflow`**, also retained to avoid breaking the native app.
- Flutter entrypoint: `lib/main.dart`.
- User-facing README: `README.md`; historical changelog: `TWITTER-VIDEO.md`.
- No affiliation with X Corp.

## Current app behavior

- The Videos tab presents videos longer than 15 seconds and recommends content from *local likes*, meaningfully watched videos, locally followed accounts, and favorite hashtags.
- Likes/dislikes are **local-only**, never POSTed to X. Displayed public like counts come from X's metadata.
- Dislikes exclude clips and related topics. Blacklisted hashtags override favorable signals.
- Search and hashtag pages can use X, public fallback, and cached media; these sources are not always available.
- Video playback starts muted; full-screen mode follows the feed rather than individual videos.
- Google Cast uses a LAN relay for MP4 streaming. Autoplay-next is implemented but receiver compatibility can vary.

## Source map

| Area | Purpose |
| --- | --- |
| `lib/core/` | X/public clients, models, caching and SQLite migrations |
| `lib/features/feed/` | Vertical feed, personalized discovery, hashtags, reactions |
| `lib/features/search/` | Video keyword and hashtag searches |
| `lib/features/player/` | media_kit player pool, seek bar, volume and fullscreen |
| `lib/features/cast/` | Chromecast integration and LAN video proxy |
| `lib/features/subscriptions/` | Local account following |
| `lib/features/settings/` | User preferences |
| `test/` | Flutter tests, with FFI tests for local SQLite |
| `android/` | Android platform configuration and permanent signing setup |

## Environment and commands

- Flutter SDK **3.44+** (GitHub Actions currently uses **3.47.6**).
- Dart SDK **3.12+**, JDK 17, Android SDK.

```bash
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter run
```

Local signed release build (requires configured private Android signing key):

```bash
flutter build apk --release --target-platform android-arm64
```

Never commit `android/key.properties`, Android keystore files, or authentication secrets.

## Publishing and versioning

- **Canonical Android CI / Release workflow:** [`.github/workflows/twitter-video-android.yml`](.github/workflows/twitter-video-android.yml).
- Every signed APK release must publish a matching SHA-256 checksum file as a GitHub Release asset for the in-app updater. The checksum filename is the APK filename followed by `.sha256`.
- Keep the update API endpoint at `Gitskrap/twit-vid` and do not embed any GitHub token in the Android app.
- New releases must increment both version and build number in `pubspec.yaml`, plus the workflow's build/release version and filename.
- The workflow signs releases using GitHub secrets `ANDROID_KEYSTORE_BASE64` and `ANDROID_SIGNING_PASSWORD`. The key must remain stable for updates over the existing app.
- GitHub Releases and build artifacts are published in **`Gitskrap/twit-vid`**, not the old `Gitskrap/X-vid` address.
- `.github/workflows/release.yml` is legacy automation, not the primary release procedure. The obsolete one-time v0.16.0 APK publishing workflow was removed to avoid accidentally republishing an old release.
- A documentation-only change does **not** require a new Android version. Use a docs-only commit with `[skip ci]` to avoid rebuilding/replacing assets of an already published version; never use this marker for application or CI changes.

## Home video feed stability contract

- Keep the active `PageView` prefix stable during background refreshes and load-more operations; append vetted unseen videos instead of inserting/reordering currently displayed pages.
- Only a real change in normalized local creator handles should invalidate the home feed. The subscriptions tab refreshes counters, sort order, search text, and loading flags often.
- Persist discovered/recommended videos before presenting them; mark the viewed video record on first display so it is filtered on next start.
- Enforce the strictly greater-than-15-seconds rule, local dislikes and hashtag blacklist on every home feed ingress.
- Deduplicate by tweet ID, media key and stable URL (without ephemeral query) where possible. Use short cooldowns when a cursor or topic is exhausted rather than repeatedly requesting page one.
- Keep diagnostics strictly content-blind: only fixed enum events, relative time and bucketed counts. Never export video identifiers or hashes.

## Anonymous diagnostic privacy contract

- `lib/features/diagnostics/privacy_diagnostics.dart` is the **only** source for user-shareable diagnostics.
- The export receives only a closed `DiagnosticEvent` enum and optional **bucketed** result counts. Do not add dynamic strings, hashes, tweet IDs, account identifiers, subscriptions, hashtags, URLs, arbitrary HTTP errors, raw stack traces, or absolute timestamps.
- Diagnostic recording is automatic, local, and rolling (5 minutes, 4,000 events). Private SharedPreferences storage retains recent entries across restarts. Internal timestamps are never exported. Only the export is user-initiated.
- **Never serialize `AppLogger.logs`** or `debugPrint` output into an exported diagnostic report. Raw logs may contain private media or account data.
- Android 10+ writes JSON directly to public Downloads using MediaStore; older Android uses app-specific external Downloads. Delete only exported entries after confirmed write; preserve new entries and failed exports. No chooser, no auto-send.

## Coding constraints

- Use Riverpod 3 APIs that exist in `flutter_riverpod: ^3.3.1`; do not assume `StateProvider` is supported.
- Preserve local user data across SQLite upgrades; add non-destructive migrations and tests for schema changes.
- Reactions stay local; do not revive X like/unlike mutation endpoints.
- Treat X/public APIs as unreliable. Keep fallback paths, visible error handling, cursor separation, and deduplication.
- Keep the long-video rule scoped to the main Videos tab, except where explicitly required elsewhere.
- Ensure UI changes work during Cast sessions and when no X account is connected.
- Do not overwrite or disable the permanent Android release signature.

## Validation and documentation

- Add focused tests under `test/` for code changes; use `sqflite_common_ffi` for SQLite.
- Run `flutter analyze`, `flutter test`, and validate Android APK builds for release changes.
- Update `README.md`, `CHANGELOG.md`, `TWITTER-VIDEO.md`, relevant technical documentation, `KNOWN_ISSUES.md` and release notes with each version. Do not mark a release as published before checking CI and both assets.
- Keep public repository branding **Twit Vid** and Android branding **Twitter vidéo** distinct from internal package identifiers.
- Project license: MIT; preserve credits and notices for XFlow/Squawker.


## Mandatory handover workflow (reference v0.33.0)

1. Read this file, [ARCHITECTURE.md](ARCHITECTURE.md), [KNOWN_ISSUES.md](KNOWN_ISSUES.md), [CHANGELOG.md](CHANGELOG.md), and the relevant subsystem document ([recommendations](RECOMMENDATIONS.md), [Cast](CAST.md), [diagnostics](DIAGNOSTICS.md), [release](RELEASE.md)).
2. Inspect the current branch, latest release, workflow result and source code; documentation can lag. Never assume a reported bug is solved just because code was committed.
3. The maintainer collects feedback in batches. Do not change code, commit, build or publish before explicit GO when a batch is pending. On GO, preserve existing local user data and previously agreed behavior. Prefer a branch and review; if direct master integration is necessary, disclose it.
4. Add targeted regression tests. Validate analyze, the test list in the canonical CI, Android build and actual release assets. Hardware and live service tests remain separate; document what was not tested.
5. Increment the semantic version/build consistently (pubspec, workflow and diagnostic report version) for code releases. Keep the stable package ID/signature. Never republish an existing version merely for documentation.
6. Record the user-visible changes, technical decisions, limitations, regression tests and exact CI/release evidence. For unresolved problems, update KNOWN_ISSUES with reproduction and next checks. Never include the user's raw logs, credentials or identifiers in a public commit.
7. Report the exact stage: code integrated, CI queued/running, tests successful/failed, APK and SHA-256 present, or hardware validation outstanding. No claim of background work.

Additional invariants:
- Chromecast is the playback source of truth during Cast. Remote controls must not seek or play the local media_kit player. Ignore stale FINISHED events during LOAD or from another media session.
- Preserve queue prefix and diversity; recommendation percentages are not hard quotas. Prefer topic relevance and fresh distinct creators without bypassing feedback and blacklist.
- The J’aime tab is local metadata, not offline video storage; never prune liked metadata solely because it is old.
- Diagnostics export must atomically distinguish saved events from events arriving during the write; keep journal on failed export. No absolute timestamps, identifiers or free-form errors in exported JSON.
