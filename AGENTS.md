# Repository instructions

These instructions apply throughout this repository. Start with `README.md` for setup and architecture, and `Docs/Verification.md` for observed test results and known limits.

## Project

Aether Atlas is a native macOS SwiftUI encyclopedia for Final Fantasy XIV using XIVAPI v2. Keep the interface native, accessible, keyboard navigable, and usable in light and dark appearance.

- Target macOS 26.0, Swift 6, and complete strict concurrency checking. `Package.swift` requires Swift tools 6.4. The release workflow pins Xcode 27.1 / 27A9275; coordinate toolchain changes across the manifest, project generator, workflow, and documentation.
- Prefer Apple frameworks; the project currently has no third-party dependencies.
- `Sources/AetherCore/` contains domain models, networking, persistence/cache actors, and observable feature state. It compiles both as a Swift package and directly into the app target.
- `Sources/AetherAtlas/` contains app composition, SwiftUI views, menus, and shared UI.
- `Tests/AetherCoreTests/` uses Swift Testing and fixtures; `Tests/AetherAtlasUITests/` uses XCTest.

## Project files and formatting

- After adding, moving, or removing Swift source/test files, run `python3 Scripts/generate_project.py` and commit the resulting Xcode project changes. Make build-setting changes in that generator so regeneration preserves them.
- Format changed Swift files with `xcrun swift-format format --in-place <files>` and check them with `xcrun swift-format lint --strict <files>`.
- Keep generated builds, archives, ZIPs, `.build/`, user-specific Xcode settings, and local credentials out of Git.
- The icon master is `Design/AppIcon/aether-atlas-master.png`. Regenerate sizes with `swift Scripts/MakeAppIcon.swift`. Preserve the simple open-book/aether design; do not paint borders, frames, or rounded corner masks into it.

## Build and verification

Run commands from the repository root. These Xcode destinations assume an Apple Silicon development Mac.

```sh
# Debug app
xcodebuild -project AetherAtlas.xcodeproj -scheme AetherAtlas \
  -configuration Debug -derivedDataPath build \
  -destination 'platform=macOS,arch=arm64' build CODE_SIGN_IDENTITY=-

# Core and native text tests through Xcode
xcodebuild -project AetherAtlas.xcodeproj -scheme AetherAtlas \
  -configuration Debug -derivedDataPath build \
  -destination 'platform=macOS,arch=arm64' test CODE_SIGN_IDENTITY=-

# Native UI tests
xcodebuild -project AetherAtlas.xcodeproj -scheme AetherAtlas-UI \
  -configuration Debug -derivedDataPath build \
  -destination 'platform=macOS,arch=arm64' test CODE_SIGN_IDENTITY=-

# Reusable core package
swift test -Xswiftc -strict-concurrency=complete
```

- For core behavior changes, check both SwiftPM and Xcode: platform-specific native text tests run only in Xcode. For UI changes, run the relevant native UI tests and inspect the affected interface.
- Keep tests deterministic with injected transports/repositories or captured fixtures. Tests must not depend on live XIVAPI or GitHub availability. Keep UI fixture behavior under `#if DEBUG` and isolated from the real saved library.
- Preserve cancellation and response-order guards. Keep UI state on the main actor and shared mutable data actor isolated; address concurrency diagnostics rather than suppressing them.
- Run `git diff --check` before finishing. Documentation-only changes do not require app builds or test runs.
- Update `README.md` for changed user workflows and `Docs/Verification.md` for material verification results. Report checks actually run and distinguish binary metadata checks from runtime testing; exact macOS 26.0 and Intel runtime support have not been verified.
- While iterating on uncommitted code, rewrite the current pass's entry in `Docs/Verification.md` from scratch to describe the final implementation, checks actually run, and remaining limits. Keep one cohesive record instead of appending follow-up notes for each iteration; remove superseded settings, abandoned approaches, and transient troubleshooting. Preserve previously committed verification records, and start a new entry once the preceding pass has been committed.

## Data and behavior

- Verify XIVAPI field projections against the official guides/OpenAPI or real responses before adding mappings. Do not invent relationships or present item reference vendor values as confirmed acquisition sources.
- Preserve native selectable game-description formatting, appearance contrast, bounded parsing, and plain-text fallback. Do not introduce a WebView or hardcode effect-label highlighting.
- Preserve atomic, versioned favorites/history persistence and existing data on failures or unsupported versions. Keep cache bounds, HTTP cache directives, shared-request cancellation, and stale-response labels intact.
- Update checks are manual and anonymous against the public `jonas-lundahl/AetherAtlas` releases API. Compare versions numerically, including timestamp tags; network failures and rate limits must not be reported as “up to date.” Downloads open the canonical release page for manual installation.
- Keep saved library/search data out of update requests and logs. Do not embed GitHub credentials, analytics, or game assets. Preserve Square Enix and XIVAPI attribution.

## Releases

- Use `.github/workflows/release.yml` for requested releases. It is manually triggered with `workflow_dispatch`; documentation-only changes do not need a release.
- Preserve version format `YYYYMMDD.HHmm` using `Europe/Stockholm` time, with the workflow run number as the separate app build number. Do not overwrite an existing timestamp tag.
- `Scripts/build_release.sh` creates the universal arm64 + x86_64 app ZIP and SHA-256 checksum, and checks version, minimum OS, architectures, signature, and archive integrity. The workflow publishes the selected commit with generated GitHub release notes.
- Builds use ad-hoc signing and are not notarized. Do not describe them as Developer ID signed or notarized; downloaded copies may need **Privacy & Security → Open Anyway**.

## Current documentation

Use Context7 MCP for library, framework, SDK, API, CLI, or cloud-service documentation when the task needs it, even for familiar tools. Resolve the library ID first, choose the closest authoritative match (and requested version when available), then query with the full question scoped to one concept. Prefer this over general web search for library documentation. Use primary official sources when Context7 does not cover the topic, and state any documentation-access limitation.

Context7 is not needed for ordinary refactoring, scripts written from scratch, business-logic debugging, code review, or general programming concepts that do not depend on external API details.
