# Aether Atlas

A native macOS encyclopedia for Final Fantasy XIV, powered by **XIVAPI v2**. Open the Xcode project and run the **AetherAtlas** scheme.

## Features

- Native three-pane SwiftUI window with resizable sidebar, results, and details; system light/dark appearance.
- Name search scoped by sidebar category: **Items, Recipes, Quests, NPCs, Actions**. The search field is always accessible; switch categories to apply the same name to another sheet.
- 300 ms debounce, cancellation, response-order guards, relevance order, and cursor pagination. Empty search browses the selected sheet in row order. Sort the **loaded** results by name or level.
- Item descriptions, icons, item/equip levels, equipment slots, class/job restrictions, attributes, damage/defense, inventory flags, materia slots, stack size, and reference vendor values when supplied.
- Item → producing recipe → ingredient item navigation. Recipe discipline, level, yield, requirements, and crystals. Quest → named issuer navigation. Action descriptions and timings. NPC name/title details.
- Favorites and a deduplicated, most-recent-first history of the last 100 entities, saved across restarts. Names and summary metadata refresh when a saved entity is opened.
- Bounded memory/disk response and icon caching, ETag revalidation, cancellation-safe shared downloads, and labeled stale responses during connection failures.
- Native result selection, arrow-key navigation, Return to open, context menus, accessible button labels, and selectable detail text.

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

Distribution signing and notarization require your own Apple Developer identity and have not been configured. The built app is intended for local development.

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

UI tests exercise search, empty states, Escape, selection, recipes, ingredients, back navigation, ⌘D, and favorites after relaunch. Test results are in `build/Logs/Test/*.xcresult`. See [verification notes](Docs/Verification.md) for observed results and limits.

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

The public endpoints were verified without authentication; the OpenAPI schema declares no security scheme. Errors decode the documented `code`/`message` shape. HTTP 429 surfaces `Retry-After` without automatic polling. No numeric service-wide rate limit was found in the examined official docs. Field projection avoids unnecessary expanded relationships; identical requests share one task. Search and sheet ordering follow the API; name/level sorting is local to loaded rows.

Requests use the latest available game/schema data, preserve returned schema/version metadata, and expose it in Source information. A canonical schema pin is deliberately not hardcoded across future game patches. A future release should reverify field mappings after game/schema changes; the API supports pinning if a fixed dataset is desired.

## Persistence, cache, and privacy

Favorites/history use a version-1 Codable JSON document with atomic writes, keyed by entity kind + row ID. A failed write does not publish unsaved changes. Corrupt or newer-version documents are preserved and an error is shown; version migrations belong in `LibraryStore.load()`.

With App Sandbox, files live under the application container:

- `~/Library/Containers/dev.aetheratlas.mac/Data/Library/Application Support/AetherAtlas/library.json`
- `~/Library/Containers/dev.aetheratlas.mac/Data/Library/Caches/AetherAtlas/Responses-v1/`

The cache uses SHA-256 URL keys; a default 1-hour TTL for details/browsing, 5 minutes for initial searches/recipe links, 30 seconds for cursor pages, and 24 hours for icons. Server `max-age` can shorten these lifetimes; `no-store`, `no-cache`, and `must-revalidate` are respected. ETags are sent with `If-None-Match` on revalidation. Decode failures are evicted so retries can fetch corrected data. Expired cursor errors invalidate the first page before a new search.

Raw resources are capped at 16 MiB / 128 entries in memory and 128 MiB on disk (oldest written files evicted first). Decoded images have a separate 16 MiB / 256-entry NSCache. There is no background polling or bulk prefetch. Each shared request has consumer tracking; the download is canceled when its last consumer cancels. Cache writes are optional: disk failure preserves network browsing and in-memory caching, while the cache exposes a diagnostic for callers. Favorites/history failures are shown in the app.

On connection failures or temporary server errors, permitted cached responses can be shown with a saved-copy label. Unvisited data is unavailable offline; 404s and invalid responses do not silently return stale entities. This is a browsing cache, not an offline game-data pack.

No analytics, login, credentials, telemetry, or cloud persistence are included. Only public game-data requests and requested assets are sent to XIVAPI.

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
