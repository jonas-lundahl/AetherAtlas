# Implementation and verification record

Verified 17 October 2026 on macOS 26.6.2 / Apple Silicon using Xcode 27.1 (27A9275), Swift 6.4, and macOS SDK 27.0. Deployment target: 26.0. No prerelease tools or external packages were installed.

## Stage 1 — Environment and API research

The workspace contained no project or source files. `sw_vers`, `xcodebuild -version`, `xcrun swift --version`, `xcodebuild -showsdks`, and `xcode-select -p` confirmed the environment. Apple’s published Xcode compatibility table matched the selected stable release and host. Context7 and the official XIVAPI guide/OpenAPI specification were inspected.

Public live requests verified Item name search, detail row 4551 (Potion), Recipe row 1118, NPC Singular search (Tataru), Quest search (Homesick), and Action row 119 (Stone). The Recipe field is **Ingredient**, not ItemIngredient. Quest ClassJobLevel is an array. LevelItem can be returned as a raw scalar using `@as(raw)`. Search responses include `sheet`, `row_id`, `fields`, and an optional `next` cursor. No authentication is needed for these public requests.

Files established: project layout, `Package.swift`, `Sources/AetherCore/Domain`, and `Networking`. No existing work required migration. Next: foundation build.

## Stages 2–3 — Foundation and complete item workflow

Created the conventional `AetherAtlas.xcodeproj`, shared schemes, app composition, repository, actor cache, search/navigation models, SwiftUI browser, and detail components. Swift 6 complete concurrency checking is enabled. The initial Debug build succeeded after fixing a URLComponents exclusivity diagnostic.

The initial 21 deterministic tests passed both through SwiftPM and `xcodebuild test`. The running app was inspected through native accessibility and a screenshot. Live search **Potion** showed real names, medicine categories, item levels, and game icons. Selecting Potion showed its description, levels, stack size, inventory flags, vendor reference values, and its producing recipe. The interface remained usable while results loaded.

Files: `Sources/AetherAtlas/App`, `Features/BrowserView.swift`, `Features/EntityDetailView.swift`, `SharedUI/GameIcon.swift`, the core networking/data/state files, and `Tests/AetherCoreTests`. Next: relationships and persistence.

## Stages 4–6 — Relationships, saved library, and categories

Implemented item → recipe → ingredient navigation and quest → NPC issuer links using returned source identities. Native live interaction opened **Potion → Alchemy recipe → Distilled Water**, then ⌘[ twice returned to Potion with the **Potion** query and results intact. Live browsing also displayed Action data and descriptions.

Added atomic versioned library persistence, favorites, bounded deduplicated history, context menus, pagination, and loaded-result sorting. Exposed Items, Recipes, Quests, NPCs, and Actions with fields verified against v2 responses. Captured recipe and quest JSON in `Tests/AetherCoreTests/Fixtures`; these files are test resources only.

Files: `LibraryStore.swift`, `DetailModel.swift`, entity mapping/request projections, reusable sections/links, and data/feature tests. No shops or gathering relationships were fabricated. Next: UI verification and final polish.

## Stage 7 — Native interaction and cache review

Added ⌘F, ⌘D, ⌘R, back/forward commands, Escape, Return, result selection, accessible action names and stable test IDs. A selected result can be reopened after following related links. Added settings/attribution, the original procedural book/compass app icon, and a bounded decoded-image cache.

Cache review added HTTP directive handling, 304 metadata inheritance, invalid-response eviction, deleted-resource invalidation, and independent cancellation of shared consumers. The expanded **26 core tests** pass through SwiftPM, including mocked URLSession loading, a noncooperative late response, persistence failures, newer schema rejection, cache expiration/limits, offline fallback, and no-store/no-cache/must-revalidate behavior.

The focused **2 UI tests passed** through Xcode: search/empty/Escape and item/detail/recipe/ingredient/back/⌘D plus favorite persistence across app relaunch. UI tests use an isolated Debug repository and temporary library, excluded from Release. Early UI selector failures were corrected with stable accessibility identifiers.

Files: `SharedUI/IconStore.swift`, `App/UITestSupport.swift`, `Tests/AetherAtlasUITests`, icon assets/generator, and the browser/cache refinements. Next: final Release build, test rerun, and launch check.

## Stage 8 — Final verification

Final test/build results are recorded below after the last source changes. No claim is made for running on exact macOS 26.0 or Intel hardware; the target and binary metadata are checked separately from runtime verification on 26.6.2.

- **Xcode core suite:** 26 tests passed after the cache/image changes. Result bundle: `build/Logs/Test/Test-AetherAtlas-2026.10.17_09-57-20-+0200.xcresult`.
- **Xcode UI suite:** 2 tests passed after the final UI/image changes. Result bundle: `build/Logs/Test/Test-AetherAtlas-UI-2026.10.17_09-58-29-+0200.xcresult`.
- **Release archive:** `xcodebuild archive` succeeded, producing `build/AetherAtlas.xcarchive`. Both arm64 and x86_64 Mach-O load commands declare `minos 26.0`, SDK 27.0. `LSMinimumSystemVersion` is 26.0.
- **Signing:** `codesign --verify --deep --strict` passed. Entitlements contain App Sandbox and outgoing network access. Signing is local/ad-hoc, not a notarized distribution signature.
- **Release isolation:** the archived executable contains neither the UI fixture names nor the Debug test-mode switch.
- **Release runtime:** the archived app launched on macOS 26.6.2. A new live **Angel Brush** search returned the real weapon/icon and displayed item level 690, required level 99, PCT/main-hand equipment data, materia slots, and attributes. Potion/X-Potion selection then verified ↑/↓ and Return through native controls. The app was left open on Potion.
- **Formatting:** bundled `swift-format lint --strict` passed for all Swift sources, tests, manifest, and icon generator. No Swift compile or concurrency diagnostics remain. Xcode emits its standard informational App Intents metadata warning because this app defines no App Intents.

Remaining limits: exact macOS 26.0 and Intel runtime tests, a complete spoken VoiceOver audit, detailed acquisition/shop/gathering data, and distribution signing/notarization. The next step for wider distribution is a 26.0 compatibility/VoiceOver pass and verified acquisition data; see README for the narrower current scope.

## Icon refinement — 17 October 2026

Replaced the closed-book icon with a simplified open book in three-quarter view, emitting broad cyan aether ribbons against a quiet full-bleed navy background. The user requested reduced detail for small sizes and no painted border or frame. The chosen master was produced using the built-in image generator and saved at `Design/AppIcon/aether-atlas-master.png`; the exact final prompt is in `Design/AppIcon/prompt.txt`.

`Scripts/MakeAppIcon.swift` now mechanically resizes that master instead of drawing the old bordered design. All 10 macOS asset slots were checked against their required pixel dimensions; 32 px and 128 px outputs were visually inspected. The Release archive rebuilt successfully with the new icon, and signing validation passed. Application behavior was unchanged, so the existing functional tests were not rerun for this artwork-only update. The existing running browsing session was preserved; the new bundle icon is available on relaunch.

## Native game text formatting — 17 October 2026

Added formatted descriptions for actions and items using the documented `Description@as(html)` projection alongside the original plain text. `GameDescription` converts the API fragment into native sendable text runs before presentation. `GameDescriptionText` maps color and emphasis into selectable SwiftUI attributed text. No WebView, remote resource loading, or hardcoded effect-label detection is used. Unsupported/malformed fragments retain the plain description. Bright game colors are preserved in dark appearance and darkened by hue-preserving scaling on light surfaces.

- **Xcode:** 36 core/native-attributed-text tests passed, including Sprint's captured API response, exact highlight colors, nested style restoration, entity/line-break handling, plain fallback, request projection, and light-appearance color mapping.
- **SwiftPM:** 34 core tests passed, including the final bounded-parser and unsupported-markup cases. The two SwiftUI-specific tests run only in Xcode.
- **Native UI:** all 3 tests passed, including opening a formatted action description and verifying its accessible, markup-free text. Result bundles: `Test-AetherAtlas-2026.10.17_10-47-34-+0200.xcresult` and `Test-AetherAtlas-UI-2026.10.17_10-48-39-+0200.xcresult`, under `build/Logs/Test/`.
- **Release:** universal Release archive rebuilt successfully; code-signature validation and Swift formatting checks passed. The sharing ZIP was regenerated and every bundled file compared with the archived application.
- **Live verification:** opened Sprint from the real API in the rebuilt Release app. The screenshot visibly shows green Duration / Additional Effect / Jog Effect labels, yellow Jog, and the original line breaks. The app was left open on that action.

Files: new domain/parser and shared SwiftUI text component; action/item request projections and detail mapping/views; captured Sprint fixture and parser/native-attribute/UI tests; Xcode source registration; README. Formatting coverage is the documented inline subset; unfamiliar future markup falls back to plain text.

## Manual update checking — 17 October 2026

Added **Check for Updates…** after About in the application menu and in Settings. A single native Software Update window checks the public GitHub latest-release endpoint only when opened or retried. Numeric component comparison supports timestamp tags and the original `1.0` development version. New releases open the canonical GitHub release URL in the browser for manual installation. The app does not install or replace itself, persist credentials, or poll in the background.

The user selected public visibility for `jonas-lundahl/AetherAtlas` so release checks and downloads can work without GitHub authentication. Request failures, missing releases, unsupported tags, and rate limits are distinct from an up-to-date result. Cancellation and generation checks prevent a closed or superseded request from publishing a stale result. Release URLs are constructed from the fixed repository and validated numeric tag rather than accepting an arbitrary URL from the response.

- **Xcode:** 45 core/native text tests passed, including version comparison, public request headers, release validation, HTTP failures, offline state, cancellation, and response ordering. Result: `build/Logs/Test/Test-AetherAtlas-2026.10.17_11-17-53-+0200.xcresult`.
- **SwiftPM:** 43 core tests passed with complete strict concurrency checking.
- **Native UI:** the three existing browsing tests passed. The new focused update-menu test passed after correcting its menu selector; it verifies opening Software Update, the available version, download action, and Check Again. Fixtures keep these tests independent of GitHub and never open a browser. The update fixture is excluded from Release.
- **Formatting:** Swift formatting and whitespace checks passed for the changed sources.

Signing and notarization are unchanged: downloaded updates use ad-hoc signing and may require macOS approval. Installation is manual, and Intel runtime behavior remains unverified.

## Global and per-object game languages — 17 October 2026

Added compact, native flag groups for English (🇬🇧), German (🇩🇪), French (🇫🇷), and Japanese (🇯🇵), the localizations available in XIVAPI's global dataset. The sidebar saves the global default across launches; an object's group records a session choice for that stable entity identity. An explicit object choice survives back/forward navigation and global default changes. Each group has exactly four flags, sizes to its contents, and provides native per-segment tooltips with language names. There is no separate default option in the object group.

Search/browse requests and their pagination use the global default. Details, related recipe pages, and source links use the effective object language. Language-specific URLs separate cached responses; changing language resets the applicable state and generation guards reject obsolete responses. Existing favorites/history identities and versioned persistence are preserved. Debug UI launches isolate language preferences as well as library files.

- **Xcode:** 52 core/native tests passed, including every request type and language, localized cache separation, search pagination reset, obsolete language responses, related recipe languages, object override/default behavior, and native flag tooltip metadata. Result: `build/Logs/Test/Test-AetherAtlas-2026.10.17_11-52-25-+0200.xcresult`.
- **SwiftPM:** 48 tests passed with complete strict concurrency checking. Compiler/package caches were redirected to temporary directories for the workspace sandbox.
- **Native UI:** the four existing browsing/description/update tests passed in the full run. Both new language tests passed in a focused rerun after correcting string assertions for native numeric selection values. The tests cover all four languages, exactly four options, compact widths, global preference restoration, localized recipe/ingredient navigation, independent object choices, and back navigation. Results: `Test-AetherAtlas-UI-2026.10.17_11-53-13-+0200.xcresult` (existing tests) and `Test-AetherAtlas-UI-2026.10.17_11-54-56-+0200.xcresult` (language tests), under `build/Logs/Test/`.
- **Live inspection:** verified compact groups in the running Debug app's dark appearance and native accessibility tree. Selecting Japanese for **Fire Shard** loaded **ファイアシャード**, its Japanese description, and Japanese category while the global selection and results remained English. The accessibility tree exposes native radio buttons and each language name as its help text.
- **Formatting:** strict Swift formatting and `git diff --check` passed. The generated Xcode project includes the shared native language control.

App controls remain in English. Object language choices last only for the current session; saved summary names refresh when their entity is opened. Exact macOS 26.0, Intel runtime behavior, and a full spoken VoiceOver audit remain unverified.

## Quest journal layout and icons — 18 October 2026

Added a dedicated native quest journal card following the in-game reading order: level/title and emblem, banner, rewards, description, and objectives. Supplemental category, required level, expansion, location, linked **Quest issuer**, and source metadata follow below the card. The card ends after its objectives, without a redundant quest-giver signature. Fixed and optional item rewards support navigation, with “Choose one” and HQ labels where supplied. The warm card surface adapts to system appearance.

The gold border follows the actual card edge, with clipped contents, a contained divider, and a centered 52-point emblem on its top edge. The body has equal 36-point horizontal margins; 18-point heading icons sit centered within the left margin, outside the content column. Banner artwork shares the content bounds, retains its aspect ratio, and is capped at 180 points high, including its loading placeholder. Header padding is 22 points above and 12 below; the 44-point level circle uses a single line with identical font, size, and weight for “Lv.” and its value, allowing three-digit levels to extend slightly beyond the circle. Reward-bar vertical padding is 8 points. Object-panel content starts with 12 points of top padding.

Quest thumbnails use available-to-begin markers or the corresponding class/job's silver set 9 emblem; banner artwork is reserved for the journal. Live XIVAPI responses verified the quest, reward, event-icon, journal-genre, localized text-sheet, and ParamGrow projections. Standard `NpcIconAvailable` values are marker range bases; offset **+1** gives the available-to-begin image: MSQ **71201**, regular quest **71221**, and blue unlock **71341**. Class/job emblems use **62000 + ClassJob**, including introductory quests with no required job. The actual game EXP (**65001**) and gil (**65002**) icons were fetched and visually checked; gil's icon was also confirmed through Item row 1. All artwork uses the existing on-demand XIVAPI cache, without bundled game images.

Quest journals request the first 48 localized text rows, selecting `SEQ_01` with `SEQ_00` fallback and numbered journal TODO entries while excluding later narrative and battle dialogue. EXP uses the required level's ParamGrow values: `ExpFactor × ScaledQuestXP × QuestExpModifier / 100`, with overflow checks. Journal text uses native selectable game-description formatting. Auxiliary text/EXP failures retain the usable base quest with a refresh notice; cancellation, language isolation, and stale-response handling remain active. Captured responses are test-only fixtures, and Debug UI tests use an isolated icon transport without contacting XIVAPI.

- **SwiftPM:** all 54 tests passed with complete strict concurrency checking after the final core changes. Coverage includes class/job/MSQ/blue/regular icons, encoded sheet paths and all languages, journal text/objective selection, EXP and overflow, and partial auxiliary-request failures.
- **Xcode:** all 58 core/native tests passed after the final core changes. Result: `build/Logs/Test/Test-AetherAtlas-2026.10.18_10-20-56-+0200.xcresult`.
- **Native UI:** the focused quest test passed against the final card layout, covering reading order, item-reward navigation, and back navigation. Result: `build/Logs/Test/Test-AetherAtlas-UI-2026.10.18_11-00-48-+0200.xcresult`. The six existing UI scenarios passed in an earlier broader run during this pass; the full seven-test suite was not rerun together on the final layout.
- **Live inspection:** checked **Weapons of a Feather**, **Way of the Archer**, and **Dawntrail** during this pass, including class/job emblems, available quest markers, actual EXP/gil icons, rewards, and the single-line **Lv. 100** typography. Final inspection of **Way of the Archer** confirmed centered margin icons, shared banner/text/reward bounds, compact header and level badge, and a card ending after its objectives with issuer navigation below. The Debug app was left open on that quest in dark appearance.
- **Formatting and project:** strict Swift formatting and `git diff --check` passed. The generated Xcode project registers the new domain, view, and test files; existing scheme settings were preserved.

Verified as a Debug build on macOS 26.6.2 / Apple Silicon with Xcode 27.1 and Swift 6.4; no new release/archive was produced. Quest progress and player-specific reward bonuses are not modeled. Exact macOS 26.0, Intel runtime behavior, a live light-appearance inspection, and a full spoken VoiceOver audit remain unverified.
