# Aether Atlas

A native macOS encyclopedia for Final Fantasy XIV, powered by **XIVAPI v2**. Open the Xcode project and run the **AetherAtlas** scheme.

## Features

- Native three-pane SwiftUI window with resizable sidebar, results, and details; system light/dark appearance.
- Name search scoped by sidebar category: **Items, Recipes, Quests, NPCs, Actions**. The search field is always accessible; switch categories to apply the same name to another sheet.
- Flag button groups select **English (🇬🇧), Deutsch (🇩🇪), Français (🇫🇷), or 日本語 (🇯🇵)**; hover a flag to see its language name. **Default game language**, at the bottom of the sidebar, sets the language for searches and newly opened objects and is remembered across launches. **Object language**, above the details, changes only the current entity and its related recipes. Both groups contain exactly four flags. Object choices last for the session and follow their entity through back/forward navigation. App controls remain in English.
- Number formatting follows the selected game language: English/Japanese **1,234.5**, German **1.234,5**, French **1 234,5**. Results, saved-list counts, and favorites counts use the default language; object details and related recipes use the object's language. This covers levels, stats, prices, stacks, quantities, rewards, and action timings, which retain one decimal place. Source IDs, version strings, and numbers within game-provided descriptions retain their original form.
- 300 ms debounce, cancellation, response-order guards, and infinite scrolling. Results load the next page automatically near the bottom, with a loading indicator and a retry action if a page fails. A bundled index of IDs, localized names, and levels supports **highest ID first**, **Name**, and **Level (highest first)** across the full category or all matching name-search results before pages load. Name matching ignores case, accents, and character width; names sort naturally in the selected default game language. No startup API scan is needed. Favorites/history retain their saved original order and can also be sorted by name or level.
- The sidebar footer shows **Game data · Patch …**. Each app release uses the repository's selected game dataset and field schema until a newer app release is installed. Search, details, related recipes, quest journals/rewards, and artwork all use that same pinned dataset.
- Item descriptions, icons, item/equip levels, equipment slots, class/job restrictions, attributes, damage/defense, inventory flags, materia slots, stack size, and reference vendor values when supplied.
- Native selectable action/item descriptions retain XIVAPI’s colors, emphasis, and line breaks. Game highlight colors are preserved in dark appearance and adjusted for contrast on light surfaces; plain descriptions remain available as a fallback.
- FFXIV text symbols use an optional **34 KB Lodestone font**, downloaded in the background at startup when no valid saved copy exists. The font stays in Application Support across launches and app updates, without expiry or refresh requests. Failed/offline downloads leave browsing usable with normal fonts; another attempt occurs on the next launch. No font installation is required and no game font is bundled.
- Item → producing recipe → ingredient item navigation. Recipe discipline, level, yield, requirements, and crystals. Quest → named issuer navigation. Action descriptions and timings. NPC name/title details.
- Quests have a dedicated journal layout: level/title, artwork capped at 180 points high with its aspect ratio preserved, EXP/gil and item rewards, selectable description, and ordered objectives. Expansion, location, and issuer links follow below. Result thumbnails use the available-to-begin quest marker (MSQ, sidequest, blue unlock, etc.); class/job quests use the silver **set 9** emblems. Artwork, game EXP/gil icons, and quest/job icons load on demand from XIVAPI.
- Favorites and a deduplicated, most-recent-first history of the last 100 entities, saved across restarts. Names and summary metadata refresh when a saved entity is opened outside Recently Viewed. Selecting, navigating with keys, or reopening a row in Recently Viewed previews it without recording another visit, so history order stays unchanged. Opening an entity from another list or a related detail link records a visit normally.
- Bounded memory/disk response and icon caching, ETag revalidation, cancellation-safe shared downloads, and labeled stale responses during connection failures.
- Native result selection with clicks, ↑/↓ or W/S navigation while the results have focus, Return to reopen, context menus, accessible button labels, and selectable detail text. Scrolling keeps the current selection; clicking a visible row selects and opens it without moving the viewport. Loading more results and favorite/detail updates preserve the viewport and selection by entity identity. Empty results and empty saved lists fill the column, keeping the heading and count bar in place.
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

The workflow checks that the committed game-data index matches XIVAPI's latest dataset and schema, runs the core/native text tests, archives a universal **arm64 + x86_64** Release app, checks its version, architectures, minimum OS, signature, and bundled index, then publishes a [GitHub release](https://github.com/jonas-lundahl/AetherAtlas/releases) for the exact selected commit. GitHub never rebuilds the index. A stale index or an unavailable freshness check stops the release; update and commit the index locally before retrying. Assets are a versioned ZIP and a SHA-256 checksum. Release notes are generated by GitHub, with download and signing instructions prepended. Download the ZIP, unzip it, and move **AetherAtlas.app** into Applications. The repository and its releases are public; no GitHub account is required to download or check for updates.

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

# Index generator tests (offline)
python3 Scripts/test_update_game_data.py
```

Native list tests use 200 rows to check scroll preservation, selection identity through reordering/removal, keyboard boundaries, and exactly one activation per input. UI tests exercise mixed W/S/arrow navigation, scrolling then clicking far from the old selection, pagination without jumping, search-field typing, search, empty states, Escape, mouse selection across row contents and empty space, arrow-key navigation, reopening a selected result, selection in sorted favorites, history previews without reordering and normal visits from other lists, recipes, ingredients, back navigation, ⌘D, favorites after relaunch, native formatted action descriptions, quest journal reading order/reward navigation, and global/object language switching with default preference restoration. Number-formatting scenarios cover all four languages, a differing system locale, independent list/detail formatting, rewards, item values, crafting requirements, and decimal action timings. Test results are in `build/Logs/Test/*.xcresult`. See [verification notes](Docs/Verification.md) for observed results and limits.

Bundled-index coverage checks descending pagination across gaps, omitted and unnamed localized rows, exhaustion without an API scan, version/schema pins on all game request types, the visible sidebar patch, highest-ID-first browsing/search, localized natural ordering, and name/level sorting before pagination. Generator tests use injected responses to verify multilingual filtering, fixed pins, stale-index detection without scanning, and preserving existing files on invalid data.

Format sources with Xcode’s bundled tool:

```sh
xcrun swift-format format --in-place --recursive Sources Tests Package.swift
```

## Keyboard controls

| Action | Shortcut |
| --- | --- |
| Focus search | ⌘F |
| Select result | ↑ / ↓ or W / S in the focused results list |
| Open selected result | Return |
| Add/remove favorite | ⌘D |
| Back / forward | ⌘[ / ⌘] |
| Refresh results | ⌘R |
| Clear search / dismiss focus / close detail | Escape, according to current focus |

Clicking a result focuses the list, so ↑/↓ and W/S continue from that exact row. W/S remain ordinary text in the search field. Keyboard navigation reveals its selected row and stops at either end without wrapping. Clicking or pressing Return reopens the selected result after following a detail link. Changing category, query, language, or sort starts a new result context.

The Navigate menu and detail toolbar expose the same actions. Clear History appears in Recently Viewed. Result context menus include Open Details, Add/Remove Favorite, and Copy Name.

## Architecture

- `Sources/AetherCore/Domain`: stable sheet/row IDs, typed envelopes, flexible `FieldValue` only for variable sheet fields, summary mapping.
- `Sources/AetherCore/Networking`: HTTPS request construction, escaped query literals, URLSession transport, HTTP errors, cancellation and decoding.
- `Sources/AetherCore/Data`: replaceable repository protocol, actor-isolated cache, atomic versioned library persistence.
- `Sources/AetherCore/Features`: focused observable MainActor search/detail state and navigation history.
- `Sources/AetherAtlas/App`: app composition, menus, windows, Debug-only test seam.
- `Sources/AetherAtlas/Features`: sidebar/results, specialized entity sections, settings/attribution.
- `Sources/AetherAtlas/SharedUI`: icons, a bounded decoded-image cache, and the native results table. The table owns selection, input, and scrolling; SwiftUI supplies data snapshots and explicit open/favorite actions. Search state owns fetching and pagination only. Snapshot restoration never opens details or scrolls to a previous selection.
- `Tests`: deterministic core tests, captured v2 recipe/quest fixtures, and native UI tests.

Core files compile both as a Swift package and directly in the Xcode app target; conditional imports let the same tests run through either tool. No package binary or third-party dependency is embedded. `Scripts/generate_project.py` can regenerate the checked-in conventional Xcode project after source-file additions. `Design/AppIcon/aether-atlas-master.png` is the simplified open-book/aether icon master, created with the built-in image generator; its final prompt is saved beside it. `Scripts/MakeAppIcon.swift` resizes the master into every macOS icon slot without adding a frame, border, or corner mask. Regenerate sizes with `swift Scripts/MakeAppIcon.swift`. No game artwork is bundled.

## XIVAPI integration

Official sources: [welcome](https://v2.xivapi.com/docs/welcome/), [search](https://v2.xivapi.com/docs/guides/search/), [sheets](https://v2.xivapi.com/docs/guides/sheets/), [assets](https://v2.xivapi.com/docs/guides/assets/), [stability](https://v2.xivapi.com/docs/guides/pinning/), [OpenAPI](https://v2.xivapi.com/api/openapi.json).

The client uses `https://v2.xivapi.com/api`. Category browsing and literal name searches filter and sort the bundled localized index, then request `/sheet/{sheet}?rows=...` in batches of up to 50; details use `/sheet/{sheet}/{row}`. Original order is descending ID for browsing and name searches. Name sorting ignores private-use icon markers and uses numeric/case-insensitive collation in the selected default game language; equal names or levels use descending ID to keep pagination stable. Blank names in the selected language are excluded. Pages are reordered locally because API batch ordering is not assumed. Missing or unnamed localized rows are skipped while filling each 50-entry page. Recipes search `ItemResult=<item ID>` and read the verified `Ingredient[]` / `AmountIngredient[]` fields. NPC names use `Singular`; recipe name search uses `ItemResult.Name`. Icons use the returned game path through `/asset?path=...&format=png`.

All game-data requests, including cursor pages and related recipes, carry the selected `language` (`en`, `de`, `fr`, or `ja`). These are the four localizations [currently served by XIVAPI's global dataset](https://v2.xivapi.com/docs/guides/concepts/#editions--localisations). Search matches names in the global default language. Changing that default restarts search pagination and reloads an open object whose language has not been explicitly selected; an explicit object choice stays selected. Changing an object's language reloads its details and related recipes independently of search. Newly opened entities use the global default unless they already have a session choice. Cache keys include the language, and obsolete responses cannot replace the new language. Favorites and history keep stable sheet/row identities and the names last saved; opening an entry refreshes its summary in the object's selected language.

The public endpoints were verified without authentication; the OpenAPI schema declares no security scheme. Errors decode the documented `code`/`message` shape. HTTP 429 surfaces `Retry-After` without automatic polling. No numeric service-wide rate limit was found in the examined official docs. Field projection avoids unnecessary expanded relationships; identical requests share one task.

Descriptions request both `Description` and `Description@as(html)` (via `transient` for actions). A small Foundation parser converts the API’s inline HTML into sendable native text runs; SwiftUI renders those as an `AttributedString`, with text selection and the system body font. Supported formatting includes `rgb`/`rgba` and six-digit hex colors, line breaks, bold/italic/underline/strikethrough, nested spans, and XML/numeric entities. Unsupported or malformed fragments fall back to the accompanying plain text. Parsing is bounded in size/depth, rejects document/entity declarations, and never loads web resources. No phrase-specific highlighting is used. The changed field projection creates a new cache key, so an old plain-only response does not hide the upgrade.

Quest thumbnails use the available-to-begin image at `EventIconType.NpcIconAvailable.id + 1` for the standard marker ranges (the range base itself is a developer placeholder). Class/job journal genre icon IDs map to the corresponding `062000 + ClassJob` silver emblem, matching **set 9** in the [Dictionary of Icons](https://ffxiv.gamerescape.com/wiki/Dictionary_of_Icons). `Quest.Icon` is reserved for the wide journal banner. Quest text is fetched separately from `quest/{first three digits of Id suffix}/{Id}`, with the sheet-name slashes encoded as `%2F`. Live responses verified the raw `unknown0` text keys and `unknown4`/`unknown4@as(html)` values. The journal displays the initial accepted description (`SEQ_01`, falling back to `SEQ_00`) and the ordered `TODO_00`–`TODO_23` objectives, without later narrative/dialogue. EXP uses XIVAPI’s [documented formula](https://github.com/xivapi/ffxiv-datamining/blob/master/docs/QuestExpReward.md): `ExpFactor × ParamGrow.ScaledQuestXP × ParamGrow.QuestExpModifier / 100` at the required quest level. Numbers reflect the current dataset, so older screenshots may show pre-adjustment rewards. Journal/EXP requests share the existing localized cache, refresh, cancellation and stale-copy behavior; partial failures retain the base quest and show a retry notice.

Requests use the canonical dataset key and schema revision recorded in `Sources/AetherCore/Resources/GameDataIndex.json`. Assets pin the dataset only; sheet/search requests also pin the schema, including related-recipe cursor pages and auxiliary quest requests. Pins are part of cache URLs, so data from different snapshots cannot share a cache entry. Returned schema/version metadata remains visible in Source information. Missing or invalid bundled data produces a load error instead of falling back to `latest`. These pins stabilize game files and field mappings; they do not guarantee that XIVAPI's HTTP contract or service availability can never change.

## Updating bundled game data

The generated index is part of the repository and is copied unchanged into both Xcode app builds and the Swift package's resources. Ordinary builds work without an index scan or a connection to XIVAPI. To deliberately select newer game data, run this locally:

```sh
python3 Scripts/update_game_data.py
```

The script resolves the latest canonical dataset and schema, skips regeneration when the pins and index format are unchanged, otherwise scans the five sheets with fixed pins and atomically replaces `Sources/AetherCore/Resources/GameDataIndex.json`. Format version 2 stores parallel ID/level arrays and name arrays for English, German, French, and Japanese. Rows are included when named in at least one language. NPCs have no list-level field. The current patch 7.57x1 resource holds 146,884 rows in 15,275,191 UTF-8 JSON bytes. An older ID-only index is regenerated automatically by the updater. No descriptions or artwork are bundled. Review field mappings for the new schema, run the tests, and commit the generated JSON with any required code changes before releasing. The app never checks for or rebuilds game-data indexes at runtime.

`python3 Scripts/update_game_data.py --check` validates the repository file offline. `--check-latest` makes only metadata requests and fails if its dataset/schema pins are stale; it never scans or writes files. The release workflow uses that read-only freshness check. `Scripts/build_release.sh` retains its original two arguments and packages the repository snapshot after an offline validation.

## Persistence, cache, and privacy

Favorites/history use a version-1 Codable JSON document with atomic writes, keyed by entity kind + row ID. A failed write does not publish unsaved changes. Corrupt or newer-version documents are preserved and an error is shown; version migrations belong in `LibraryStore.load()`.

The game-language preference is stored separately in the app's local user defaults and falls back to English if unset or unsupported. Debug UI tests isolate both preferences and the saved library from real user data.

With App Sandbox, files live under the application container:

- `~/Library/Containers/dev.aetheratlas.mac/Data/Library/Application Support/AetherAtlas/library.json`
- `~/Library/Containers/dev.aetheratlas.mac/Data/Library/Caches/AetherAtlas/Responses-v1/`
- `~/Library/Containers/dev.aetheratlas.mac/Data/Library/Application Support/AetherAtlas/Fonts/FFXIV_Lodestone_SSF.ttf`

The cache uses SHA-256 URL keys; a default 1-hour TTL for details and indexed result batches, 5 minutes for recipe links, and 24 hours for icons. Server `max-age` can shorten these lifetimes; `no-store`, `no-cache`, and `must-revalidate` are respected. ETags are sent with `If-None-Match` on revalidation. Decode failures are evicted so retries can fetch corrected data. Name-search continuations are local row IDs scoped to the current query, language, and sort. Changing that context cancels old work and resets pagination. Collated ID lists are cached for at most 12 recent contexts.

Raw resources are capped at 16 MiB / 128 entries in memory and 128 MiB on disk (oldest written files evicted first). Decoded images have a separate 16 MiB / 256-entry NSCache. There is no background polling or bulk prefetch. Each shared request has consumer tracking; the download is canceled when its last consumer cancels. Cache writes are optional: disk failure preserves network browsing and in-memory caching, while the cache exposes a diagnostic for callers. Favorites/history failures are shown in the app.

On connection failures or temporary server errors, permitted cached responses can be shown with a saved-copy label. Unvisited data is unavailable offline; 404s and invalid responses do not silently return stale entities. This is a browsing cache, not an offline game-data pack.

No analytics, login, credentials, telemetry, or cloud persistence are included. Public game-data requests and requested assets are sent to XIVAPI. When no valid local symbol font exists, startup also requests the public `FFXIV_Lodestone_SSF.ttf` from `img.finalfantasyxiv.com`, without account information, search terms, or library data. A manual update check sends a request to GitHub for the latest release metadata; opening a release uses your browser. Update checks send no library, search history, or personal data.

## Attribution and scope

**FINAL FANTASY XIV © SQUARE ENIX.** Aether Atlas is an independent community tool and is not affiliated with or endorsed by Square Enix. Data and on-demand icons are provided by XIVAPI; its [asset documentation](https://v2.xivapi.com/docs/guides/assets/) encourages direct requests with caching/revalidation.

Square Enix retains rights to game text and assets. Consult the current [Materials Usage Policy](https://support.na.square-enix.com/rule.php?id=5382&policy=update&tag=authc) and the policy applicable to your region. The optional XIV AXIS symbol font is downloaded directly from Square Enix at runtime, never redistributed inside the app. Its original Type Project / Isao Suzuki copyright and AXIS trademark metadata remain in the saved file. API availability is not a grant of redistribution rights. The bundled index contains localized names and levels; descriptions, artwork, and game fonts are not bundled. This project does not claim permission for commercial distribution.

## Known limits and next work

- Search covers one category at a time. There is no aggregate cross-sheet search or advanced filter builder.
- Vendor prices are item-sheet reference values, not confirmed acquisition locations. Shops, gathering locations, and reverse NPC-to-quest lookup are not implemented. Quest journals show the initial description and static objectives; character progress, level-scaled bonuses, and later narrative stages are not tracked.
- NPC detail is intentionally limited to verified resident name/title fields; unnamed rows are skipped in browsing.
- History and favorites retain summary metadata for offline lists; full details still require a cached response.
- Exact macOS 26.0 execution, Intel execution, a full spoken VoiceOver audit, and distribution/notarization remain unverified. Native accessibility and keyboard workflows have automated/manual coverage.
- Multiple main windows share the current workspace state. Dedicated entity windows and session restoration remain future work.
- Disk eviction is oldest-write-first; no offline packs, crafting trees, item comparison, market data, or export are included.

The recommended next increments are richer verified acquisition data, item filters, and a full VoiceOver pass on macOS 26.0 hardware/VM before broad distribution.
