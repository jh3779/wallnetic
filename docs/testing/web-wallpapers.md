# Web wallpapers — validation record

Date: 2026-10-29. Native macOS fork based on v1.4.2/main.

## Delivered behavior

The Web tab adds HTTPS and local index.html backgrounds plus an offline Orbit scene. WKWebView windows sit below desktop icons, ignore mouse clicks and keyboard input, and receive normalized mouse-position events at up to 30 Hz. One JavaScript request may be in flight per display. Unchanged pointer positions are skipped.

A web background replaces the video renderer and disables existing video auto-switch schedules. Choosing a video tears down WebKit. Pause/lock/power handling unloads web documents (including timers); resume reloads them. Manual pause and the existing automatic-resume setting are respected, including when a web source is chosen during an existing power pause. Optional restore at launch takes priority over video restore.

Browsing data is ephemeral. Address validation requires HTTPS without credentials. Navigation stays on the supplied origin or inside the selected local folder; popup windows, camera/microphone requests and script dialogs are declined. Local folder bookmarks are scoped read-only and balanced on failure. These are containment measures, not an assertion that arbitrary websites are safe.

## RED → GREEN evidence

1. Commit 213f1c8 defines source-validation and pointer-coordinate contracts. Build fails because WebWallpaperSource and WebWallpaperPointer are absent. Evidence: web-red.log.
2. Native WKWebView integration tests verify document loading, relative local image assets, synthesized pointer events, click-through windows, full page teardown while paused, manual pause persistence, display rebuild, restore opt-in, failed-source replacement and web-process recovery. Initial full suite: 196 passing tests.
3. Added power-release and retry tests; RED build reports missing updatePowerCondition. Implemented the power-condition channel and load-error retry state. Full suite: 198 passing tests.
4. Manual import showed the same video twice: the library directory watcher can publish the copied file before import resumes. A regression test defines idempotent registration, fails without registerImportedWallpaper, and passes after preserving the already-published record and identity.
5. Final build-for-testing and Release build succeeded. Final test run: **199 tests, 0 failures**.

## Coverage and isolation

New source/pointer and WebKit engine logic: **253/279 executable lines (90.7%)** under Xcode coverage. SwiftUI layout is checked manually; this is not a claim of 80% coverage across the entire pre-existing app.

Tests run from a separate copied product under bundle identifier com.jh3779.wallnetic.audit, with the widget identifier changed to match. Deep-link registration is removed from this test host and it is signed ad hoc. Original build products and installed app are preserved. UserDefaults tests therefore do not run against the user's Wallnetic preference domain. New integration tests use unique suite names and temporary HTML folders and remove their own test data.

## Build and test environment

Xcode 27.1, macOS, Apple Silicon test destination. Release binary contains arm64 and x86_64 slices. Build uses CODE_SIGN_IDENTITY=-, CODE_SIGN_ENTITLEMENTS=, ENABLE_APP_SANDBOX=NO and DEBUG_INFORMATION_FORMAT=dwarf, matching the existing directly distributed app's non-sandboxed local build. This is a local development artifact, not an Apple-notarized distribution.

The project file explicitly includes new files; project.yml's recursive sources also include them. `git diff --check` passes. Final packaged app passes codesign --verify --deep --strict.

## Manual verification

- Launch local output app, leaving /Applications/Wallnetic.app unchanged.
- Import the generated HEVC MP4; UI reports 3456×2234, 0:30, 79.7 MB.
- Final launch shows one library item and Playing; Web tab exposes Orbit, website input, folder import, pointer preference and restore preference.
- WKWebView loading and pointer-event delivery are exercised in the native test host.

## Limits

This does not implement Steam Workshop, Wallpaper Engine .pkg/scene files, a scene editor, or audio-reactive rendering. Only pointer movement is forwarded; native clicks and CSS :hover are not simulated. Websites that require login, user gestures, cross-origin top-level redirects or special browser permissions may not work. Resume reloads page state. Web sources apply to all screens; simultaneous per-screen mixed video/web selection is not provided. Coordinate transforms and display rebuild are tested, but physical multi-monitor hot-plug, long-duration energy use and a full macOS sleep/wake cycle have not been manually exercised. The widget retains its existing video-oriented model.
