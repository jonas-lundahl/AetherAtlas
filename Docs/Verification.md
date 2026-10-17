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
