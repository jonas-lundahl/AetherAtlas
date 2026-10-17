# Aether Atlas

A native macOS encyclopedia for Final Fantasy XIV, powered by **XIVAPI v2**. Open the Xcode project and run the **AetherAtlas** scheme.

## Features

- Native three-pane SwiftUI window with resizable sidebar, results, and details; system light/dark appearance.
- Name search scoped by sidebar category: **Items, Recipes, Quests, NPCs, Actions**. The search field is always accessible; switch categories to apply the same name to another sheet.
- Flag button groups select **English (🇬🇧), Deutsch (🇩🇪), Français (🇫🇷), or 日本語 (🇯🇵)**; hover a flag to see its language name. **Default game language**, at the bottom of the sidebar, sets the language for searches and newly opened objects and is remembered across launches. **Object language**, above the details, changes only the current entity and its related recipes. Both groups contain exactly four flags. Object choices last for the session and follow their entity through back/forward navigation. App controls remain in English.
- 300 ms debounce, cancellation, response-order guards, relevance order, and cursor pagination. Empty search browses the selected sheet in row order. Sort the **loaded** results by name or level.
- Item descriptions, icons, item/equip levels, equipment slots, class/job restrictions, attributes, damage/defense, inventory flags, materia slots, stack size, and reference vendor values when supplied.
- Native selectable action/item descriptions retain XIVAPI’s colors, emphasis, and line breaks. Game highlight colors are preserved in dark appearance and adjusted for contrast on light surfaces; plain descriptions remain available as a fallback.
- Item → producing recipe → ingredient item navigation. Recipe discipline, level, yield, requirements, and crystals. Quest → named issuer navigation. Action descriptions and timings. NPC name/title details.
- Favorites and a deduplicated, most-recent-first history of the last 100 entities, saved across restarts. Names and summary metadata refresh when a saved entity is opened.
- Bounded memory/disk response and icon caching, ETag revalidation, cancellation-safe shared downloads, and labeled stale responses during connection failures.
- Native result selection, arrow-key navigation, Return to open, context menus, accessible button labels, and selectable detail text.
- **Aether Atlas → Check for Updates…** compares the installed version with the latest published GitHub release. A new version opens its release page for manual download and installation. The same command is available in Settings.

## Verified development environment

Verified **17 October 2026**, using the selected `/Applications/Xcode.app` toolchain:

| Component | Actual value |
| --- | --- |
| Host | macOS 26.6.2, build 25G83 |
| Machine | Apple Silicon, arm64 |
| Xcode | 27.1, build 27A9275 |
| Swift | Apple Swift 6.4, swiftlang-6.4.0.34.1 |
| SDK | macOS 27.0 |
| Deployment target | **macOS 26.0** |
| Language / concurrency | Swift 6, complete strict concurrency checking |

[Apple’s Xcode requirements](https://developer.apple.com/xcode/system-requirements) list Xcode 27.1 as stable, requiring macOS 26.6 or later; 27.2 is beta. The installed compiler/SDK were retained. The app was built and launched on **26.6.2**; the exact 26.0 point release and Intel hardware have not been run-tested. Release builds include arm64 and x86_64. The SDK version does not raise the deployment target.

No external packages, accounts, keys, backend, or toolchain installation are required. `Package.swift` exposes the reusable core and its tests through SwiftPM; there are no dependencies to resolve, so `Package.resolved` is not generated.

## Build and launch

```sh
git clone https://github.com/jonas-lundahl/AetherAtlas.git
cd AetherAtlas
open AetherAtlas.xcodeproj
```

Choose the **AetherAtlas** scheme and **My Mac**, then Run (⌘R). The project uses local ad-hoc signing by default and enables App Sandbox with outgoing network access.

Command line:

```sh
xcodebuild -project AetherAtlas.xcodeproj -scheme AetherAtlas \
  -configuration Debug -derivedDataPath build \
  -destination 'platform=macOS,arch=arm64' build CODE_SIGN_IDENTITY=-
open build/Build/Products/Debug/AetherAtlas.app
```

Release and archive:

```sh
xcodebuild -project AetherAtlas.xcodeproj -scheme AetherAtlas \
  -configuration Release -derivedDataPath build build CODE_SIGN_IDENTITY=-
xcodebuild -project AetherAtlas.xcodeproj -scheme AetherAtlas \
  -configuration Release -archivePath build/AetherAtlas.xcarchive archive CODE_SIGN_IDENTITY=-
```

Distribution signing and notarization require your own Apple Developer identity and have not been configured. Builds use ad-hoc signing; downloaded copies may need approval in macOS Privacy & Security.

## Release from GitHub

Open [Actions → Release macOS app](https://github.com/jonas-lundahl/AetherAtlas/actions/workflows/release.yml), click **Run workflow**, select **main** (or the branch to release), and click **Run workflow** again. No version input or repository secrets are required. The workflow runs only when manually requested.

Each run chooses the current **Europe/Stockholm** time at the beginning of the job, formatted as `YYYYMMDD.HHmm`, for example `20261017.1055`. This becomes the release tag, title version, app marketing version, and ZIP filename. The workflow run number supplies the separate app build number. An existing timestamp tag causes the run to stop; run again in a later minute instead of overwriting a release.

The workflow runs the core/native text tests, archives a universal **arm64 + x86_64** Release app, checks its version, architectures, minimum OS, and signature, then publishes a [GitHub release](https://github.com/jonas-lundahl/AetherAtlas/releases) for the exact selected commit. Assets are a versioned ZIP and a SHA-256 checksum. Release notes are generated by GitHub, with download and signing instructions prepended. Download the ZIP, unzip it, and move **AetherAtlas.app** into Applications. The repository and its releases are public; no GitHub account is required to download or check for updates.

Update checking runs only when you open **Check for Updates…** or click **Check Again**. It uses GitHub's public latest-release API, compares numeric version components (including timestamp tags), and reports connection failures or rate limits separately from “up to date.” There is no background polling or automatic installation. To install, quit Aether Atlas and replace the app in Applications with the unzipped download; favorites and history stay in the app's separate data container. Builds are still ad-hoc signed, so macOS may require **Privacy & Security → Open Anyway** for a newly downloaded version.

CI uses GitHub's [`xcode-27` runner image](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md), currently a preview image, with **Xcode 27.1 / 27A9275** explicitly selected and verified. That toolchain is the stable build used locally. If GitHub retires it or changes the image, update the workflow's toolchain selection and verification together. The app still targets macOS 26.0. CI does not perform interactive UI tests, notarization, or an Intel runtime test.

To reproduce the packaging step locally with the selected Xcode toolchain:

```sh
bash Scripts/build_release.sh "$(TZ=Europe/Stockholm date '+%Y%m%d.%H%M')" 1
```

The result is saved under `build/Distribution/`. To verify a downloaded ZIP, run `shasum -a 256 -c AetherAtlas-<version>-macOS-universal.zip.sha256` from the directory containing both assets.

## Tests

All automated tests use injected transports/repositories, mocked URL loading, or captured fixtures. They do not require XIVAPI. Debug test-host launches use an isolated test repository and temporary library; Release excludes that test seam entirely.

```sh
# Core suite through Xcode (Swift Testing)
xcodebuild -project AetherAtlas.xcodeproj -scheme AetherAtlas \
  -derivedDataPath build -destination 'platform=macOS,arch=arm64' test CODE_SIGN_IDENTITY=-

# Focused native UI suite (XCTest)
xcodebuild -project AetherAtlas.xcodeproj -scheme AetherAtlas-UI \
  -derivedDataPath build -destination 'platform=macOS,arch=arm64' test CODE_SIGN_IDENTITY=-

# Core suite through SwiftPM
swift test -Xswiftc -strict-concurrency=complete
```

UI tests exercise search, empty states, Escape, selection, recipes, ingredients, back navigation, ⌘D, favorites after relaunch, native formatted action descriptions, and global/object language switching with default preference restoration. Test results are in `build/Logs/Test/*.xcresult`. See [verification notes](Docs/Verification.md) for observed results and limits.

Format sources with Xcode’s bundled tool:

```sh
xcrun swift-format format --in-place --recursive Sources Tests Package.swift
```

## Keyboard controls

| Action | Shortcut |
| --- | --- |
| Focus search | ⌘F |
| Select result | ↑ / ↓ in results list |
| Open selected result | Return |
| Add/remove favorite | ⌘D |
| Back / forward | ⌘[ / ⌘] |
| Refresh results | ⌘R |
| Clear search / dismiss focus / close detail | Escape, according to current focus |

The Navigate menu and detail toolbar expose the same actions. Clear History appears in Recently Viewed. Result context menus include Open Details, Add/Remove Favorite, and Copy Name.

## Architecture

- `Sources/AetherCore/Domain`: stable sheet/row IDs, typed envelopes, flexible `FieldValue` only for variable sheet fields, summary mapping.
- `Sources/AetherCore/Networking`: HTTPS request construction, escaped query literals, URLSession transport, HTTP errors, cancellation and decoding.
- `Sources/AetherCore/Data`: replaceable repository protocol, actor-isolated cache, atomic versioned library persistence.
- `Sources/AetherCore/Features`: focused observable MainActor search/detail state and navigation history.
- `Sources/AetherAtlas/App`: app composition, menus, windows, Debug-only test seam.
- `Sources/AetherAtlas/Features`: sidebar/results, specialized entity sections, settings/attribution.
- `Sources/AetherAtlas/SharedUI`: icons and a bounded decoded-image cache.
- `Tests`: deterministic core tests, captured v2 recipe/quest fixtures, and native UI tests.

Core files compile both as a Swift package and directly in the Xcode app target; conditional imports let the same tests run through either tool. No package binary or third-party dependency is embedded. `Scripts/generate_project.py` can regenerate the checked-in conventional Xcode project after source-file additions. `Design/AppIcon/aether-atlas-master.png` is the simplified open-book/aether icon master, created with the built-in image generator; its final prompt is saved beside it. `Scripts/MakeAppIcon.swift` resizes the master into every macOS icon slot without adding a frame, border, or corner mask. Regenerate sizes with `swift Scripts/MakeAppIcon.swift`. No game artwork is bundled.

## XIVAPI integration

Official sources: [welcome](https://v2.xivapi.com/docs/welcome/), [search](https://v2.xivapi.com/docs/guides/search/), [sheets](https://v2.xivapi.com/docs/guides/sheets/), [assets](https://v2.xivapi.com/docs/guides/assets/), [stability](https://v2.xivapi.com/docs/guides/pinning/), [OpenAPI](https://v2.xivapi.com/api/openapi.json).

The client uses `https://v2.xivapi.com/api`. Search uses `/search?sheets=Item&query=Name~"Potion"` with explicit fields and a limit of 50; subsequent pages send `cursor`. Browsing uses `/sheet/{sheet}` with `after`; details use `/sheet/{sheet}/{row}`. Recipes search `ItemResult=<item ID>` and read the verified `Ingredient[]` / `AmountIngredient[]` fields. NPC names use `Singular`; recipe name search uses `ItemResult.Name`. Icons use the returned game path through `/asset?path=...&format=png`.

All game-data requests, including cursor pages and related recipes, carry the selected `language` (`en`, `de`, `fr`, or `ja`). These are the four localizations [currently served by XIVAPI's global dataset](https://v2.xivapi.com/docs/guides/concepts/#editions--localisations). Search matches names in the global default language. Changing that default restarts search pagination and reloads an open object whose language has not been explicitly selected; an explicit object choice stays selected. Changing an object's language reloads its details and related recipes independently of search. Newly opened entities use the global default unless they already have a session choice. Cache keys include the language, and obsolete responses cannot replace the new language. Favorites and history keep stable sheet/row identities and the names last saved; opening an entry refreshes its summary in the object's selected language.

The public endpoints were verified without authentication; the OpenAPI schema declares no security scheme. Errors decode the documented `code`/`message` shape. HTTP 429 surfaces `Retry-After` without automatic polling. No numeric service-wide rate limit was found in the examined official docs. Field projection avoids unnecessary expanded relationships; identical requests share one task. Search and sheet ordering follow the API; name/level sorting is local to loaded rows.

Descriptions request both `Description` and `Description@as(html)` (via `transient` for actions). A small Foundation parser converts the API’s inline HTML into sendable native text runs; SwiftUI renders those as an `AttributedString`, with text selection and the system body font. Supported formatting includes `rgb`/`rgba` and six-digit hex colors, line breaks, bold/italic/underline/strikethrough, nested spans, and XML/numeric entities. Unsupported or malformed fragments fall back to the accompanying plain text. Parsing is bounded in size/depth, rejects document/entity declarations, and never loads web resources. No phrase-specific highlighting is used. The changed field projection creates a new cache key, so an old plain-only response does not hide the upgrade.

Requests use the latest available game/schema data, preserve returned schema/version metadata, and expose it in Source information. A canonical schema pin is deliberately not hardcoded across future game patches. A future release should reverify field mappings after game/schema changes; the API supports pinning if a fixed dataset is desired.

## Persistence, cache, and privacy

Favorites/history use a version-1 Codable JSON document with atomic writes, keyed by entity kind + row ID. A failed write does not publish unsaved changes. Corrupt or newer-version documents are preserved and an error is shown; version migrations belong in `LibraryStore.load()`.

The game-language preference is stored separately in the app's local user defaults and falls back to English if unset or unsupported. Debug UI tests isolate both preferences and the saved library from real user data.

With App Sandbox, files live under the application container:

- `~/Library/Containers/dev.aetheratlas.mac/Data/Library/Application Support/AetherAtlas/library.json`
- `~/Library/Containers/dev.aetheratlas.mac/Data/Library/Caches/AetherAtlas/Responses-v1/`

The cache uses SHA-256 URL keys; a default 1-hour TTL for details/browsing, 5 minutes for initial searches/recipe links, 30 seconds for cursor pages, and 24 hours for icons. Server `max-age` can shorten these lifetimes; `no-store`, `no-cache`, and `must-revalidate` are respected. ETags are sent with `If-None-Match` on revalidation. Decode failures are evicted so retries can fetch corrected data. Expired cursor errors invalidate the first page before a new search.

Raw resources are capped at 16 MiB / 128 entries in memory and 128 MiB on disk (oldest written files evicted first). Decoded images have a separate 16 MiB / 256-entry NSCache. There is no background polling or bulk prefetch. Each shared request has consumer tracking; the download is canceled when its last consumer cancels. Cache writes are optional: disk failure preserves network browsing and in-memory caching, while the cache exposes a diagnostic for callers. Favorites/history failures are shown in the app.

On connection failures or temporary server errors, permitted cached responses can be shown with a saved-copy label. Unvisited data is unavailable offline; 404s and invalid responses do not silently return stale entities. This is a browsing cache, not an offline game-data pack.

No analytics, login, credentials, telemetry, or cloud persistence are included. Public game-data requests and requested assets are sent to XIVAPI. A manual update check sends a request to GitHub for the latest release metadata; opening a release uses your browser. Update checks send no library, search history, or personal data.

## Attribution and scope

**FINAL FANTASY XIV © SQUARE ENIX.** Aether Atlas is an independent community tool and is not affiliated with or endorsed by Square Enix. Data and on-demand icons are provided by XIVAPI; its [asset documentation](https://v2.xivapi.com/docs/guides/assets/) encourages direct requests with caching/revalidation.

Square Enix retains rights to game text and assets. Consult the current [Materials Usage Policy](https://support.na.square-enix.com/rule.php?id=5382&policy=update&tag=authc) and the policy applicable to your region. API availability is not a grant of redistribution rights. This project does not bundle game assets or claim permission for commercial distribution.

## Known limits and next work

- Search covers one category at a time. There is no aggregate cross-sheet search or advanced filter builder.
- Vendor prices are item-sheet reference values, not confirmed acquisition locations. Shops, gathering locations, quest journal narratives, and reverse NPC-to-quest lookup are not implemented.
- NPC detail is intentionally limited to verified resident name/title fields; unnamed rows are skipped in browsing.
- History and favorites retain summary metadata for offline lists; full details still require a cached response.
- Exact macOS 26.0 execution, Intel execution, a full spoken VoiceOver audit, and distribution/notarization remain unverified. Native accessibility and keyboard workflows have automated/manual coverage.
- Multiple main windows share the current workspace state. Dedicated entity windows and session restoration remain future work.
- Disk eviction is oldest-write-first; no offline packs, crafting trees, item comparison, market data, or export are included.

The recommended next increments are richer verified acquisition data, item filters, and a full VoiceOver pass on macOS 26.0 hardware/VM before broad distribution.
