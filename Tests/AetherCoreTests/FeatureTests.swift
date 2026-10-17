import Foundation
import Testing

#if SWIFT_PACKAGE
  @testable import AetherCore
#else
  @testable import AetherAtlas
#endif

actor FeatureRepository: GameRepository {
  var searches: [String] = []
  var browses = 0
  var fails = false
  func setFailure(_ value: Bool) { fails = value }
  func search(kind: EntityKind, text: String, cursor: String?) async throws -> EntityPage {
    searches.append(text)
    if text == "old" { try? await Task.sleep(for: .milliseconds(150)) }
    if fails { throw URLError(.notConnectedToInternet) }
    return EntityPage(
      entries: [EntitySummary(id: EntityID(kind: kind, row: cursor == nil ? 1 : 2), name: text)],
      next: cursor == nil ? "page2" : nil)
  }
  func browse(kind: EntityKind, after: Int?) async throws -> EntityPage {
    browses += 1
    return EntityPage(entries: [EntitySummary(id: EntityID(kind: kind, row: 10), name: "Browse")])
  }
  func detail(_ id: EntityID, refresh: Bool) async throws -> EntityDetail {
    EntityDetail(
      entity: EntitySummary(id: id, name: "Detail"), row: SheetRow(rowID: id.row, fields: [:]),
      schema: nil, version: nil, isStale: false)
  }
  func recipes(item: Int, cursor: String?) async throws -> EntityPage { EntityPage(entries: []) }
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
  func search(kind: EntityKind, text: String, cursor: String?) async throws -> EntityPage {
    if text == "old" { return await withCheckedContinuation { continuation = $0 } }
    return EntityPage(entries: [EntitySummary(id: EntityID(kind: kind, row: 2), name: text)])
  }
  func finishOld() {
    continuation?.resume(
      returning: EntityPage(entries: [EntitySummary(id: EntityID(kind: .item, row: 1), name: "old")]
      ))
    continuation = nil
  }
  func browse(kind: EntityKind, after: Int?) async throws -> EntityPage { EntityPage(entries: []) }
  func detail(_ id: EntityID, refresh: Bool) async throws -> EntityDetail {
    throw APIError.invalidResponse
  }
  func recipes(item: Int, cursor: String?) async throws -> EntityPage { EntityPage(entries: []) }
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
