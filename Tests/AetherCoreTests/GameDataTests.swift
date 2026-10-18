import Foundation
import Testing

#if SWIFT_PACKAGE
  @testable import AetherCore
#else
  @testable import AetherAtlas
#endif

func testGameDataIndex(
  ids: [Int] = [1], names: [String: [String]]? = nil, levels: [Int]? = nil
) throws -> GameDataIndex {
  let localized =
    names
    ?? Dictionary(
      uniqueKeysWithValues: GameLanguage.allCases.map {
        ($0.rawValue, ids.map { "Potion name \($0)" })
      })
  var rows: [String: GameDataIndex.Sheet] = [:]
  for kind in EntityKind.allCases {
    rows[kind.rawValue] = GameDataIndex.Sheet(
      ids: ids, levels: kind == .npc ? nil : levels ?? ids.map { max(0, $0) }, names: localized)
  }
  return try GameDataIndex(
    snapshot: GameDataSnapshot(
      version: "0123456789abcdef", patch: "7.57",
      schema: "exdschema@2:rev:" + String(repeating: "a", count: 40)), rows: rows)
}

@Test func bundledIndexHasPinnedMetadataAndDescendingPagesForEveryCategory() throws {
  let index = try GameDataIndex.bundled.get()
  #expect(index.snapshot.patch != "latest")
  for kind in EntityKind.allCases {
    let first = index.page(kind: kind, before: nil)
    let second = index.page(kind: kind, before: first.last)
    #expect(first.count == 50)
    #expect(second.count == 50)
    #expect(zip(first + second, (first + second).dropFirst()).allSatisfy { $0 > $1 })
  }
}

@Test func indexHandlesGapsAndRejectsInvalidData() throws {
  let index = try testGameDataIndex(ids: [100, 50, 2, 0])
  #expect(index.page(kind: .item, before: nil, limit: 2) == [100, 50])
  #expect(index.page(kind: .item, before: 49, limit: 2) == [2, 0])
  #expect(index.page(kind: .item, before: 0).isEmpty)
  #expect(index.page(kind: .item, before: nil, limit: 0).isEmpty)
  for ids in [[1, 2], [2, 2], [-1], []] {
    #expect(throws: GameDataIndexError.self) { try testGameDataIndex(ids: ids) }
  }
  #expect(throws: (any Error).self) { try GameDataIndex.decode(Data("{}".utf8)) }
}

@Test(arguments: GameLanguage.allCases)
func allGameRequestsUseTheBundledDatasetAndSchema(language: GameLanguage) throws {
  let pin = try GameDataIndex.bundled.get().snapshot
  let requests: [APIRequest] = [
    .search(kind: .item, text: "Potion", language: language),
    .search(kind: .item, text: "", cursor: "next", language: language),
    .rows(kind: .recipe, ids: [9, 2], language: language),
    .detail(EntityID(kind: .action, row: 3), language: language),
    .recipes(item: 1, language: language),
    .recipes(item: 1, cursor: "next", language: language),
    try #require(APIRequest.questJournal(id: "test_00001", language: language)),
    .questGrowth(level: 50, language: language),
  ]
  for request in requests {
    let query = try #require(
      URLComponents(url: request.url(), resolvingAgainstBaseURL: false)?.queryItems)
    #expect(query.filter { $0.name == "version" }.map(\.value) == [pin.version])
    #expect(query.filter { $0.name == "schema" }.map(\.value) == [pin.schema])
    #expect(query.first { $0.name == "language" }?.value == language.rawValue)
  }
  let asset = try #require(
    URLComponents(url: APIRequest.asset(path: "icon.tex").url(), resolvingAgainstBaseURL: false)?
      .queryItems)
  #expect(asset.first { $0.name == "version" }?.value == pin.version)
  #expect(!asset.contains { $0.name == "schema" })
  let old = try APIRequest.detail(EntityID(kind: .item, row: 1)).pinned(
    to: testGameDataIndex().snapshot
  ).url()
  #expect(old != (try APIRequest.detail(EntityID(kind: .item, row: 1)).url()))
}

actor IndexBrowseTransport: HTTPTransport {
  var requests: [URLRequest] = []
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests.append(request)
    let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
    let ids = query.first { $0.name == "rows" }!.value!.split(separator: ",").map { Int($0)! }
    // Return ascending rows, an omitted ID, and a row unnamed in this localization.
    let rows = ids.sorted().filter { $0 != 119 }.map { id in
      SheetRow(rowID: id, fields: ["Name": .string(id == 118 ? "" : "Item \(id)")])
    }
    let data = try JSONSerialization.data(withJSONObject: [
      "rows": rows.map { ["row_id": $0.rowID, "fields": ["Name": $0["Name"].string!]] }
    ])
    return (
      data,
      HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    )
  }
}

@Test func indexedBrowseFillsPagesInDescendingOrderAndStopsWithoutAnAPIScan() async throws {
  let directory = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let transport = IndexBrowseTransport()
  let index = try testGameDataIndex(ids: Array((0...120).reversed()))
  let repository = LiveGameRepository(
    cache: ResponseCache(client: XIVAPIClient(transport: transport), directory: directory),
    index: index)
  let first = try await repository.browse(kind: .item, language: .german)
  #expect(first.entries.map(\.id.row) == [120] + Array((69...117).reversed()))
  #expect(first.after == 69)
  let second = try await repository.browse(kind: .item, after: first.after, language: .german)
  #expect(second.entries.map(\.id.row) == Array((19...68).reversed()))
  let last = try await repository.browse(kind: .item, after: second.after, language: .german)
  #expect(last.entries.map(\.id.row) == Array((0...18).reversed()))
  #expect(last.after == nil)
  let count = await transport.requests.count
  let exhausted = try await repository.browse(kind: .item, after: 0, language: .german)
  #expect(exhausted.entries.isEmpty)
  #expect(await transport.requests.count == count)
  for request in await transport.requests {
    let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
    #expect(query.first { $0.name == "version" }?.value == index.snapshot.version)
    #expect(query.first { $0.name == "schema" }?.value == index.snapshot.schema)
    #expect(query.first { $0.name == "language" }?.value == "de")
    #expect(!query.contains { $0.name == "after" })
  }
}

@Test func indexUsesLocalizedNamesNaturalCollationAndStableLevelTies() throws {
  let english = ["Zulu", "Éclair 10", "\u{e0bf} Éclair 2", ""]
  let names = [
    "en": english, "fr": english, "de": ["Aal", "Zebra", "Bär", "Leer"],
    "ja": ["ポーション１０", "ポーション２", "炎", ""],
  ]
  let index = try testGameDataIndex(ids: [100, 90, 80, 70], names: names, levels: [2, 1, 99, 5])
  #expect(try index.matchingIDs(kind: .item, language: .english, sort: .name) == [80, 90, 100])
  #expect(try index.matchingIDs(kind: .item, language: .german, sort: .name) == [100, 80, 70, 90])
  #expect(try index.matchingIDs(kind: .item, language: .english, sort: .level) == [80, 100, 90])
  #expect(
    try index.matchingIDs(kind: .item, language: .english, sort: .original, text: "ECLAIR") == [
      90, 80,
    ])
  #expect(
    try index.matchingIDs(kind: .item, language: .japanese, sort: .name, text: "ﾎﾟｰｼｮﾝ") == [
      90, 100,
    ])
  #expect(try index.matchingIDs(kind: .npc, language: .english, sort: .level) == [100, 90, 80])
  #expect(
    try index.matchingIDs(kind: .item, language: .english, sort: .name, text: "not found").isEmpty)
}

@Test func richerIndexRejectsMissingLanguagesAndMisalignedFields() throws {
  let snapshot = try testGameDataIndex().snapshot
  let goodNames = Dictionary(
    uniqueKeysWithValues: GameLanguage.allCases.map { ($0.rawValue, ["Name"]) })
  for sheet in [
    GameDataIndex.Sheet(ids: [1], levels: [], names: goodNames),
    GameDataIndex.Sheet(ids: [1], levels: [1], names: ["en": ["Name"]]),
    GameDataIndex.Sheet(ids: [1], levels: [1], names: goodNames.mapValues { _ in [""] }),
  ] {
    let rows = Dictionary(uniqueKeysWithValues: EntityKind.allCases.map { ($0.rawValue, sheet) })
    #expect(throws: GameDataIndexError.self) { try GameDataIndex(snapshot: snapshot, rows: rows) }
  }
}

@Test func indexedSearchAndBrowseSortBeforePaginationWithoutScanningTheAPI() async throws {
  let directory = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let ids = Array((0...120).reversed())
  let index = try testGameDataIndex(ids: ids, levels: ids.map { $0 == 1 ? 999 : $0 })
  let transport = IndexBrowseTransport()
  let repository = LiveGameRepository(
    cache: ResponseCache(client: XIVAPIClient(transport: transport), directory: directory),
    index: index)
  let alphabetical = try await repository.browse(kind: .item, sort: .name)
  #expect(alphabetical.entries.map(\.id.row) == Array(0...49))
  let level = try await repository.browse(kind: .item, sort: .level)
  #expect(level.entries.first?.id.row == 1)
  var cursor: String?
  var all: [Int] = []
  repeat {
    let page = try await repository.search(kind: .item, text: "POTION", cursor: cursor, sort: .name)
    all += page.entries.map(\.id.row)
    cursor = page.next
  } while cursor != nil
  #expect(all == Array(0...120).filter { $0 != 118 && $0 != 119 })
  #expect(Set(all).count == all.count)
  let count = await transport.requests.count
  #expect(try await repository.search(kind: .item, text: "missing").entries.isEmpty)
  #expect(await transport.requests.count == count)
  for request in await transport.requests {
    #expect(request.url?.path == "/api/sheet/Item")
    #expect(!request.url!.absoluteString.contains("after="))
  }
  await #expect(throws: APIError.self) {
    try await repository.search(kind: .item, text: "Potion", cursor: "old-api-cursor")
  }
}
