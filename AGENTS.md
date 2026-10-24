# Repository instructions

These instructions apply throughout this repository. Start with `README.md` for setup and architecture, and `Docs/Verification.md` for observed test results and known limits.

## Project

Aether Atlas is a native macOS SwiftUI encyclopedia for Final Fantasy XIV using XIVAPI v2. Keep the interface native, accessible, keyboard navigable, and usable in light and dark appearance.

- Target macOS 26.0, Swift 6, and complete strict concurrency checking. `Package.swift` requires Swift tools 6.4. The release workflow pins Xcode 27.1 / 27A9275; coordinate toolchain changes across the manifest, project generator, workflow, and documentation.
- Prefer Apple frameworks; the project currently has no third-party dependencies.
- `Sources/AetherCore/` contains domain models, networking, persistence/cache actors, and observable feature state. It compiles both as a Swift package and directly into the app target.
- `Sources/AetherAtlas/` contains app composition, SwiftUI views, menus, and shared UI.
- `Tests/AetherCoreTests/` uses Swift Testing and fixtures; `Tests/AetherAtlasUITests/` uses XCTest.

## Database pages and shared behavior

Database categories are one browser with specialized detail content. New categories must integrate with this shared structure; a pilot is not an exception to the established behavior.

- Register the sheet in `EntityKind` with its title, symbol, verified field projections, and meaningful sort options. Use stable `EntityID` / `EntitySummary` values for all list, navigation, favorites, and history entries. Extend the pinned multilingual index and its generator/validation when adding a category.
- `BrowserView` owns the sidebar, search field, result heading/subtitle, sort menu, loaded-count footer, loading/empty/error states, and keyboard focus/Escape behavior. Reuse this host rather than creating a separate category list/header or an extra reload button. The existing Find and Refresh Results commands apply to the active category.
- `SearchModel` owns the 300 ms search debounce, cancellation, response-order guards, initial load, continuations, retry, and stale-result state. Sort/filter the full bundled index before fetching batches of up to **50** records. Default to highest ID first; name sorting uses the default game language. Do not fetch an entire sheet at runtime to sort or search it.
- `ResultsList` / `ResultsTableView` own native row selection, mouse and W/S/arrow/Return input, context menus, and viewport restoration by entity identity. `ResultRow` / `GameIcon` provide the row presentation and on-demand artwork. `ResultsScrollView` loads the next page within five rows of the loaded end and checks again after resizing/snapshot changes. Pagination must preserve selection/scrolling, show a footer spinner, pause on errors, and offer Retry Loading More without discarding rows or shifting the table.
- `EntityDetailView` owns the common detail shell: `ObjectLanguageHeader`, loading/retry states, title-bar Favorite and Refresh Details actions, and the request/record lifecycle. Specialized views such as `QuestJournalView` and `MapDetailView` supply the actual detail content. Specialized models may load content/assets that require different APIs, but must not replace the shared shell, category search state, navigation, or library state.
- `Workspace.navigation` is the current-object authority across all categories and saved lists. Use `openResult` / `open` for explicit activation, and preserve Back/Forward, ⌘D, toolbar actions, and context-menu actions for every category. Resolve actions against the current matching loaded object, never a stale detail from another category. Do not add category-specific command-availability branches to `AetherAtlasApp.swift`.
- Use the existing `LibraryModel` / `LibraryStore` and atomic, versioned persistence for favorites and recent history. Opening a loaded object records a visit and refreshes saved summary metadata; Recently Viewed previews must preserve history order. Saved map or other specialized records must reopen with their proper detail content, including after relaunch.
- `GameLanguagePicker` / `ObjectLanguageHeader` and Workspace's per-object overrides are shared. Default language controls searches/list ordering/counts; Object language controls only the current object's content and numbers. Explicit object choices last for the session by stable identity and survive Back/Forward/default-language changes. Keep app controls in English and use `GameLanguage` formatting for displayed numbers. Map cursor X/Y coordinates follow the game's convention instead: always US decimal points, exactly one fractional digit, and no Z, regardless of object language.
- Route all data and artwork through the pinned request builders and existing bounded response/icon caches. Preserve HTTP cache/cancellation semantics, stale labels, readable fallback images/text, accessible control names, and native light/dark appearance. Keep implementation details out of user-facing flows.

When a category is added or changed, verify the complete shared workflow as applicable: 50-row initial load, full-index sorting/search before pagination, automatic continuation and retry, keyboard/mouse selection without scroll jumps, independent object language, title-bar Favorite/Refresh, ⌘D and Back/Forward, saved-list reopening after relaunch, and history previews without reordering. Document the final workflow and actual verification results; do not silently leave common features out of a pilot.

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
