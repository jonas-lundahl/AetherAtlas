import Foundation
import Testing

#if SWIFT_PACKAGE
  @testable import AetherCore
#else
  import AppKit
  @testable import AetherAtlas
#endif

actor FeatureRepository: GameRepository {
  var searches: [String] = []
  var browses = 0
  var fails = false
  var searchLanguages: [GameLanguage] = []
  var browseLanguages: [GameLanguage] = []
  var recipeLanguages: [GameLanguage] = []
  func setFailure(_ value: Bool) { fails = value }
  func search(kind: EntityKind, text: String, cursor: String?, language: GameLanguage) async throws
    -> EntityPage
  {
    searches.append(text)
    searchLanguages.append(language)
    if text == "old" { try? await Task.sleep(for: .milliseconds(150)) }
    if fails { throw URLError(.notConnectedToInternet) }
    return EntityPage(
      entries: [EntitySummary(id: EntityID(kind: kind, row: cursor == nil ? 1 : 2), name: text)],
      next: cursor == nil ? "page2" : nil)
  }
  func browse(kind: EntityKind, after: Int?, language: GameLanguage) async throws -> EntityPage {
    browses += 1
    browseLanguages.append(language)
    return EntityPage(entries: [EntitySummary(id: EntityID(kind: kind, row: 10), name: "Browse")])
  }
  func detail(_ id: EntityID, refresh: Bool, language: GameLanguage) async throws -> EntityDetail {
    EntityDetail(
      entity: EntitySummary(id: id, name: "Detail"), row: SheetRow(rowID: id.row, fields: [:]),
      schema: nil, version: nil, isStale: false)
  }
  func recipes(item: Int, cursor: String?, language: GameLanguage) async throws -> EntityPage {
    recipeLanguages.append(language)
    return EntityPage(entries: [])
  }
}
@MainActor func eventually(_ check: () async -> Bool) async throws {
  let deadline = ContinuousClock.now + .seconds(3)
  while !(await check()) {
    if ContinuousClock.now > deadline {
      Issue.record("Condition did not become true")
      return
    }
    try await Task.sleep(for: .milliseconds(5))
  }
}
@Test @MainActor func searchDebouncesAndHandlesEmptyQuery() async throws {
  let repository = FeatureRepository()
  let search = SearchModel(repository: repository, debounce: .milliseconds(40))
  search.query = "p"
  search.query = "po"
  search.query = "potion"
  try await eventually { !search.isLoading }
  #expect(await repository.searches == ["potion"])
  search.clear()
  try await eventually { !search.isLoading }
  #expect(await repository.browses == 1)
  #expect(search.entries.first?.name == "Browse")
  search.cancel()
}
@Test @MainActor func obsoleteSearchCannotReplaceNewResults() async throws {
  let repository = FeatureRepository()
  let search = SearchModel(repository: repository, debounce: .zero)
  search.query = "old"
  try await eventually { await repository.searches.contains("old") }
  search.query = "new"
  try await eventually { !search.isLoading }
  #expect(search.entries.first?.name == "new")
  #expect(search.error == nil)
}
@Test @MainActor func searchFailureRetryPaginationAndSelection() async throws {
  let repository = FeatureRepository()
  let search = SearchModel(repository: repository, debounce: .zero)
  await repository.setFailure(true)
  search.query = "potion"
  try await eventually { !search.isLoading }
  #expect(search.error != nil)
  await repository.setFailure(false)
  search.retry()
  try await eventually { !search.isLoading }
  #expect(search.error == nil)
  search.selection = search.entries.first?.id
  #expect(search.selection?.row == 1)
  await search.loadMore()
  #expect(search.entries.count == 2)
  #expect(!search.canLoadMore)
  search.kind = .recipe
  try await eventually { !search.isLoading }
  #expect(search.entries.first?.id.kind == .recipe)
}
@Test @MainActor func navigationBackForwardBranchesAndSearchContext() {
  let navigation = EntityNavigation()
  let search = SearchModel(repository: FeatureRepository())
  let item = EntitySummary(id: EntityID(kind: .item, row: 4551), name: "Potion")
  let recipe = EntitySummary(id: EntityID(kind: .recipe, row: 1118), name: "Potion recipe")
  search.query = "potion"
  navigation.open(item)
  navigation.open(recipe)
  navigation.back()
  #expect(navigation.current == item)
  #expect(search.query == "potion")
  navigation.back()
  #expect(navigation.current == nil)
  #expect(navigation.canForward)
  navigation.forward()
  #expect(navigation.current == item)
  navigation.open(item)
  #expect(navigation.path.count == 2)
  navigation.open(EntitySummary(id: EntityID(kind: .item, row: 2), name: "Shard"))
  #expect(!navigation.canForward)
  search.cancel()
}
@Test @MainActor func languageChangeRestartsSearchAndPaginationWithoutLosingQuery() async throws {
  let repository = FeatureRepository()
  let search = SearchModel(repository: repository, debounce: .zero)
  search.query = "potion"
  try await eventually { !search.isLoading }
  await search.loadMore()
  #expect(search.entries.count == 2)
  search.selection = search.entries.first?.id
  search.language = .french
  #expect(search.entries.isEmpty)
  #expect(search.selection == nil)
  #expect(!search.canLoadMore)
  #expect(search.query == "potion")
  try await eventually { !search.isLoading }
  #expect(search.entries.count == 1)
  await search.loadMore()
  #expect(await repository.searchLanguages == [.english, .english, .french, .french])
  search.clear()
  try await eventually { !search.isLoading }
  search.language = .japanese
  try await eventually { !search.isLoading }
  #expect(await repository.browseLanguages == [.french, .japanese])
}
@Test @MainActor func detailsAndRelatedRequests() async {
  let detail = DetailModel(repository: FeatureRepository())
  await detail.load(EntityID(kind: .item, row: 4551))
  #expect(detail.detail?.entity.id.row == 4551)
  #expect(!detail.isLoading)
  #expect(detail.recipesError == nil)
  await detail.load(nil)
  #expect(detail.detail == nil)
}
private final class FixtureBundle {}
func fixture(_ name: String) throws -> Data {
  #if SWIFT_PACKAGE
    let bundle = Bundle.module
  #else
    let bundle = Bundle(for: FixtureBundle.self)
  #endif
  return try Data(
    contentsOf: #require(
      bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")))
}
@Test func verifiedRecipeAndQuestFixturesDecode() throws {
  let recipe = try XIVAPIClient.decode(DetailEnvelope.self, from: fixture("recipe"))
  #expect(recipe.row.summary(kind: .recipe).name == "Potion")
  #expect(recipe.row["Ingredient"].array.count == 8)
  #expect(recipe.row["Ingredient"].array[0]["row_id"].integer == 5487)
  #expect(recipe.row["AmountIngredient"].array[0].integer == 1)
  let quests = try XIVAPIClient.decode(SearchEnvelope.self, from: fixture("quest-search"))
  #expect(quests.results.first?.summary(kind: .quest).level == 51)
  #expect(quests.results.first?["IssuerStart"]["sheet"].string == "ENpcResident")
}

actor UncooperativeRepository: GameRepository {
  var continuation: CheckedContinuation<EntityPage, Never>?
  var started: Bool { continuation != nil }
  func search(kind: EntityKind, text: String, cursor: String?, language: GameLanguage) async throws
    -> EntityPage
  {
    if text == "old", language == .english {
      return await withCheckedContinuation { continuation = $0 }
    }
    return EntityPage(entries: [
      EntitySummary(
        id: EntityID(kind: kind, row: 2), name: language == .english ? text : language.rawValue)
    ])
  }
  func finishOld() {
    continuation?.resume(
      returning: EntityPage(entries: [EntitySummary(id: EntityID(kind: .item, row: 1), name: "old")]
      ))
    continuation = nil
  }
  func browse(kind: EntityKind, after: Int?, language: GameLanguage) async throws -> EntityPage {
    EntityPage(entries: [])
  }
  func detail(_ id: EntityID, refresh: Bool, language: GameLanguage) async throws -> EntityDetail {
    throw APIError.invalidResponse
  }
  func recipes(item: Int, cursor: String?, language: GameLanguage) async throws -> EntityPage {
    EntityPage(entries: [])
  }
}
@Test @MainActor func outOfOrderNonCooperativeResponseIsIgnored() async throws {
  let repository = UncooperativeRepository()
  let search = SearchModel(repository: repository, debounce: .zero)
  search.query = "old"
  try await eventually { await repository.started }
  search.query = "new"
  try await eventually { !search.isLoading }
  await repository.finishOld()
  // Give the already-resumed obsolete continuation a turn on the main actor.
  try await Task.sleep(for: .milliseconds(10))
  #expect(search.entries.first?.name == "new")
}
@Test @MainActor func obsoleteLanguageSearchCannotReplaceNewResults() async throws {
  let repository = UncooperativeRepository()
  let search = SearchModel(repository: repository, debounce: .zero)
  search.query = "old"
  try await eventually { await repository.started }
  search.language = .japanese
  try await eventually { !search.isLoading }
  await repository.finishOld()
  try await Task.sleep(for: .milliseconds(10))
  #expect(search.entries.first?.name == "ja")
}

actor SuspendedDetailRepository: GameRepository {
  var continuation: CheckedContinuation<EntityDetail, Never>?
  var started: Bool { continuation != nil }
  var recipeLanguages: [GameLanguage] = []
  func search(kind: EntityKind, text: String, cursor: String?, language: GameLanguage) async throws
    -> EntityPage
  { EntityPage(entries: []) }
  func browse(kind: EntityKind, after: Int?, language: GameLanguage) async throws -> EntityPage {
    EntityPage(entries: [])
  }
  func detail(_ id: EntityID, refresh: Bool, language: GameLanguage) async throws -> EntityDetail {
    if language == .english {
      return await withCheckedContinuation { continuation = $0 }
    }
    return result(id, name: language.rawValue)
  }
  func finishOld(_ id: EntityID) {
    continuation?.resume(returning: result(id, name: "en"))
    continuation = nil
  }
  private func result(_ id: EntityID, name: String) -> EntityDetail {
    EntityDetail(
      entity: EntitySummary(id: id, name: name), row: SheetRow(rowID: id.row, fields: [:]),
      schema: nil, version: nil, isStale: false)
  }
  func recipes(item: Int, cursor: String?, language: GameLanguage) async throws -> EntityPage {
    recipeLanguages.append(language)
    return EntityPage(
      entries: [
        EntitySummary(
          id: EntityID(kind: .recipe, row: cursor == nil ? 1 : 2), name: language.rawValue)
      ], next: cursor == nil ? "more" : nil)
  }
}

@Test @MainActor func languageChangeRejectsObsoleteDetailsAndLocalizesRelatedPages() async throws {
  let repository = SuspendedDetailRepository()
  let detail = DetailModel(repository: repository)
  let id = EntityID(kind: .item, row: 4551)
  let old = Task { await detail.load(id) }
  try await eventually { await repository.started }
  detail.language = .german
  #expect(detail.detail == nil)
  #expect(detail.recipes.isEmpty)
  await detail.load(id)
  await detail.loadRecipes(item: id.row, more: true)
  await repository.finishOld(id)
  await old.value
  #expect(detail.detail?.entity.name == "de")
  #expect(detail.recipes.map(\.name) == ["de", "de"])
  #expect(await repository.recipeLanguages == [.german, .german])
}

#if !SWIFT_PACKAGE
  @Test @MainActor func flagLanguageControlProvidesNativeTooltips() {
    let control = GameLanguageControl()
    #expect(control.segmentCount == 4)
    #expect(control.trackingMode == .selectOne)
    for (index, language) in GameLanguage.allCases.enumerated() {
      #expect(control.label(forSegment: index) == language.flag)
      #expect(control.toolTip(forSegment: index) == language.title)
    }
  }

  @Test @MainActor func objectLanguagesOverrideTheDefaultByStableEntityIdentity() {
    let workspace = Workspace()
    let item = EntitySummary(id: EntityID(kind: .item, row: 1), name: "Item")
    let recipe = EntitySummary(id: EntityID(kind: .recipe, row: 2), name: "Recipe")
    workspace.language = .english
    workspace.open(item)
    #expect(workspace.objectLanguage == .english)
    workspace.objectLanguageOverride = .japanese
    workspace.language = .german
    #expect(workspace.search.language == .german)
    #expect(workspace.objectLanguage == .japanese)
    #expect(workspace.detail.language == .japanese)
    workspace.open(recipe)
    #expect(workspace.objectLanguageOverride == nil)
    #expect(workspace.objectLanguage == .german)
    workspace.navigation.back()
    #expect(workspace.objectLanguage == .japanese)
    workspace.objectLanguageOverride = nil
    #expect(workspace.objectLanguage == .german)
    #expect(workspace.detail.language == .german)
    workspace.search.cancel()
  }
#endif
