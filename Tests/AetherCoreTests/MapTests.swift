import Foundation
import Testing

#if SWIFT_PACKAGE
  @testable import AetherCore
#else
  import AppKit
  @testable import AetherAtlas
#endif

private func mapFixture() throws -> GameMap {
  let page = try XIVAPIClient.decode(BrowseEnvelope.self, from: fixture("maps"))
  return try #require(page.rows.compactMap(GameMap.init(row:)).first { $0.id == 2 })
}

private func markerFixture() throws -> [GameMapMarker] {
  struct Page: Decodable { let rows: [MapMarkerRow] }
  return try JSONDecoder().decode(Page.self, from: fixture("map-markers")).rows
    .filter { $0.rowID == 3 }.compactMap(GameMapMarker.init(row:))
}

@Test func mapCursorCoordinatesUseTheGameScaleAndTruncateToOneDecimal() throws {
  let map = try mapFixture()
  #expect(map.sizeFactor == 200)
  let aetheryte = try #require(try markerFixture().first { $0.name == "Gridania Aetheryte Plaza" })
  let location = try #require(
    GameMapCoordinates(
      normalizedX: aetheryte.x, normalizedY: aetheryte.y, sizeFactor: map.sizeFactor))
  #expect(location.x == 11.9)
  #expect(location.y == 11.8)
  let whole = try #require(
    GameMapCoordinates(normalizedX: 1100.0 / 2048, normalizedY: 1079.0 / 2048, sizeFactor: 200))
  #expect(whole.formatted() == "X: 12.0  Y: 11.7")
  let field = try #require(
    GameMapCoordinates(normalizedX: 1100.0 / 2048, normalizedY: 1079.0 / 2048, sizeFactor: 100))
  #expect(field.x == 23.0)
  #expect(field.y == 22.5)
  #expect(!whole.formatted().contains("Z"))
  for scale in [nil, 0, -1, 65_536] as [Int?] {
    #expect(GameMapCoordinates(normalizedX: 0.5, normalizedY: 0.5, sizeFactor: scale) == nil)
  }
  for point in [-0.01, 1.01, Double.nan, Double.infinity] {
    #expect(GameMapCoordinates(normalizedX: point, normalizedY: 0.5, sizeFactor: 100) == nil)
    #expect(GameMapCoordinates(normalizedX: 0.5, normalizedY: point, sizeFactor: 100) == nil)
  }
}

@Test func mapFixturesPreserveFloorsAndTerritoryLoadingArtwork() throws {
  let map = try mapFixture()
  #expect(map.assetID == "f1t1/00")
  #expect(map.title == "New Gridania")
  #expect(map.region == "The Black Shroud")
  #expect(map.markerRange == 3)
  #expect(map.loadingImagePath == "ui/loadingimage/-nowloading_base_hr1.tex")
  #expect(GameMap(row: SheetRow(rowID: 0, fields: [:])) == nil)
  var row = try XIVAPIClient.decode(BrowseEnvelope.self, from: fixture("maps")).rows[2].fields
  row["PlaceNameSub"] = .object(["fields": .object(["Name": .string("Upper floor")])])
  row["TerritoryType"] = .null
  let floor = try #require(GameMap(row: SheetRow(rowID: 9, fields: row)))
  #expect(floor.title == "New Gridania · Upper floor")
  #expect(floor.loadingImagePath == nil)
}

@Test func mapMarkerSubrowsUseCanvasCoordinatesAndExcludeEmptyEntries() throws {
  let markers = try markerFixture()
  #expect(markers.count == 37)
  #expect(Set(markers.map(\.id)).count == 37)
  let roost = try #require(markers.first)
  #expect(roost.id == "3:0")
  #expect(roost.name == "The Roost")
  #expect(roost.x == 1078.0 / 2048)
  #expect(roost.y == 1222.0 / 2048)
  #expect(roost.iconPath == "ui/icon/060000/060436_hr1.tex")
  #expect(roost.labelPlacement == .right)
  #expect(markers[1].labelPlacement == .below)
  #expect(markers.first { $0.id == "3:3" }?.labelPlacement == .left)
  #expect(markers.first { $0.id == "3:14" }?.labelPlacement == .above)
  #expect(markers.first { $0.id == "3:29" }?.isMapLink == true)
  #expect(markers.first { $0.id == "3:11" }?.iconPath == nil)
  #expect(!markers.contains { $0.id == "3:19" || $0.id == "3:21" })
  #expect(markers[1].name == "Carline Canopy\n(Adventurers' Guild)")
  #expect(!markers.contains { $0.id == "3:37" })
  #expect(
    GameMapMarker(
      row: MapMarkerRow(
        rowID: 3, subrowID: 0,
        fields: ["X": .number(-1), "Y": .number(1), "Icon": .object(["id": .number(1)])])) == nil)
}

@Test func mapRequestsPinDataAndRejectUnsafeAssetPaths() throws {
  let map = try mapFixture()
  for request in [
    APIRequest.mapRows(ids: [499, 3], language: .japanese),
    .mapDetail(id: 2, language: .japanese),
    .mapMarkers(after: "2:65535", language: .japanese),
    try #require(APIRequest.mapAsset(map.assetID)),
  ] {
    let url = try request.url()
    let parameters = try #require(
      URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(parameters.contains { $0.name == "version" && $0.value == "0874aee069e1e7c4" })
    if url.path.contains("/sheet/") {
      #expect(parameters.contains { $0.name == "language" && $0.value == "ja" })
      #expect(parameters.contains { $0.name == "schema" })
    } else {
      #expect(url.path == "/api/asset/map/f1t1/00")
      #expect(!parameters.contains { $0.name == "schema" })
    }
  }
  for invalid in ["../00", "f1t1/0", "f1t1/00?version=latest", "f1t1/00/extra", ""] {
    #expect(APIRequest.mapAsset(invalid) == nil)
  }
}

@Test func mapLayersRevealDetailAtZoomThresholds() throws {
  let markers = try markerFixture()
  let named = try #require(markers.first { $0.isNamed })
  let other = try #require(markers.first { !$0.isNamed })
  var layers = MapLayers()
  #expect(layers.shows(named, zoom: 1))
  #expect(!layers.shows(other, zoom: 1.74))
  #expect(layers.shows(other, zoom: 1.75))
  #expect(!layers.showsLabel(named, zoom: 2.49))
  #expect(layers.showsLabel(named, zoom: 2.5))
  layers.landmarks = false
  layers.otherIcons = false
  layers.labels = false
  #expect(!layers.shows(named, zoom: 5))
  #expect(!layers.shows(other, zoom: 5))
  #expect(!layers.showsLabel(named, zoom: 5))
}

@Test func mapThumbnailsUseTeleportCityEmblemsAndAetheryteFallback() throws {
  let maps = try XIVAPIClient.decode(BrowseEnvelope.self, from: fixture("maps"))
  let towns = try XIVAPIClient.decode(BrowseEnvelope.self, from: fixture("map-town-icons"))
  var icons: [Int: String] = [:]
  for town in towns.rows where (town["Icon"]["id"].integer ?? 0) > 0 {
    icons[town.rowID] = town["Icon"].iconPath
  }
  let gridania = try #require(GameMap(row: maps.rows[2], teleportIcons: icons))
  #expect(gridania.thumbnailPath == "ui/icon/060000/060882_hr1.tex")
  let shroud = try #require(GameMap(row: maps.rows[4], teleportIcons: icons))
  #expect(shroud.thumbnailPath == GameMap.fallbackThumbnailPath)
  let missing = try #require(GameMap(row: maps.rows[2], teleportIcons: [:]))
  #expect(missing.thumbnailPath == GameMap.fallbackThumbnailPath)
}

private actor MapFixtureTransport: HTTPTransport {
  let catalog: Data
  let markers: Data
  var urls: [URL] = []
  let failMarkers: Bool
  let paginated: Bool
  let paginateMarkers: Bool
  init(failMarkers: Bool = false, paginated: Bool = false, paginateMarkers: Bool = false) throws {
    catalog = try fixture("maps")
    markers = try fixture("map-markers")
    self.failMarkers = failMarkers
    self.paginated = paginated
    self.paginateMarkers = paginateMarkers
  }
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let url = request.url!
    urls.append(url)
    let data: Data
    if url.path.hasSuffix("/MapMarker") {
      if failMarkers { throw URLError(.notConnectedToInternet) }
      if paginateMarkers {
        struct Row: Encodable {
          let rowID: Int
          let subrowID: Int
          let fields: [String: FieldValue]
          enum CodingKeys: String, CodingKey {
            case rowID = "row_id"
            case subrowID = "subrow_id"
            case fields
          }
        }
        struct Page: Encodable { let rows: [Row] }
        let after = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first {
          $0.name == "after"
        }?.value
        let range = after == "2:65535" ? 0..<100 : 100..<101
        data = try JSONEncoder().encode(
          Page(
            rows: range.map {
              Row(
                rowID: 3, subrowID: $0,
                fields: [
                  "X": .number(1024), "Y": .number(1024), "Icon": .object(["id": .number(1)]),
                ])
            }))
      } else {
        data = markers
      }
    } else if url.path.hasSuffix("/Town") {
      data = try fixture("map-town-icons")
    } else if url.path.hasSuffix("/Map") {
      let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
      let ids = query.first { $0.name == "rows" }!.value!.split(separator: ",").map { Int($0)! }
      struct Page: Encodable { let rows: [SheetRow] }
      let fixture = try XIVAPIClient.decode(BrowseEnvelope.self, from: catalog).rows
      let rows: [SheetRow]
      if paginated {
        rows = ids.sorted().filter { $0 != 119 && $0 != 118 }.map { id in
          var fields = fixture[2].fields
          fields["PlaceName"] = .object(["fields": .object(["Name": .string("Map \(id)")])])
          return SheetRow(rowID: id, fields: fields)
        }
      } else {
        rows = fixture.filter { ids.contains($0.rowID) }
      }
      data = try JSONEncoder().encode(Page(rows: rows))
    } else {
      data = Data("map image".utf8)
    }
    return (
      data,
      HTTPURLResponse(
        url: url, statusCode: 200, httpVersion: nil,
        headerFields: ["Cache-Control": "max-age=86400"])!
    )
  }
}

private func mapTestIndex(maps: [GameMap]) throws -> GameDataIndex {
  let maps = maps.sorted { $0.id > $1.id }
  let names = Dictionary(
    uniqueKeysWithValues: GameLanguage.allCases.map { ($0.rawValue, maps.map(\.title)) })
  let terms = Dictionary(
    uniqueKeysWithValues: GameLanguage.allCases.map {
      ($0.rawValue, maps.map { "\($0.title) \($0.region) \($0.assetID) \($0.id)" })
    })
  var rows = Dictionary(
    uniqueKeysWithValues: EntityKind.allCases.map {
      (
        $0.rawValue,
        GameDataIndex.Sheet(
          ids: [1], levels: $0 == .npc ? nil : [1], names: names.mapValues { _ in ["Name"] })
      )
    })
  rows["Map"] = GameDataIndex.Sheet(
    ids: maps.map(\.id), levels: nil, names: names, searchTerms: terms)
  return try GameDataIndex(snapshot: GameDataIndex.bundled.get().snapshot, rows: rows)
}

@Test func mapRepositorySortsAndFiltersBeforeLoadingFiftyRowPagesWithoutScanning() async throws {
  let transport = try MapFixtureTransport(paginated: true)
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let source = try XIVAPIClient.decode(BrowseEnvelope.self, from: fixture("maps")).rows[2]
  let maps = (0...120).map { id in
    var fields = source.fields
    fields["PlaceName"] = .object(["fields": .object(["Name": .string("Map \(id)")])])
    return GameMap(row: SheetRow(rowID: id, fields: fields))!
  }
  let repository = LiveMapRepository(
    cache: ResponseCache(client: XIVAPIClient(transport: transport), directory: directory),
    index: try mapTestIndex(maps: maps))
  let first = try await repository.page(
    text: "", after: nil, language: .english, sort: .original, refresh: false)
  #expect(first.maps.count == 50)
  #expect(first.maps.map(\.id) == [120] + Array((69...117).reversed()))
  #expect(first.maps.first?.thumbnailPath == "ui/icon/060000/060882_hr1.tex")
  #expect(first.after == 69)
  let second = try await repository.page(
    text: "", after: first.after, language: .english, sort: .original, refresh: false)
  #expect(second.maps.map(\.id) == Array((19...68).reversed()))
  let last = try await repository.page(
    text: "", after: second.after, language: .english, sort: .original, refresh: false)
  #expect(last.maps.map(\.id) == Array((0...18).reversed()))
  #expect(last.after == nil)
  let alphabetical = try await repository.page(
    text: "", after: nil, language: .english, sort: .name, refresh: false)
  #expect(alphabetical.maps.map(\.id) == Array(0...49))
  let search = try await repository.page(
    text: "MAP 11", after: nil, language: .english, sort: .name, refresh: false)
  #expect(search.maps.map(\.id) == [11] + Array(110...117))
  let requestCount = await transport.urls.count
  #expect(
    try await repository.page(
      text: "no-match", after: nil, language: .english, sort: .original, refresh: false
    ).maps.isEmpty)
  #expect(
    try await repository.page(
      text: "", after: 0, language: .english, sort: .original, refresh: false
    )
    .maps.isEmpty)
  #expect(await transport.urls.count == requestCount)
  for url in await transport.urls where url.path.hasSuffix("/Map") {
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
    #expect(!query.contains { $0.name == "after" })
    #expect(query.first { $0.name == "limit" }?.value == "50")
    #expect(query.first { $0.name == "rows" }!.value!.split(separator: ",").count <= 50)
  }
  let content = try await repository.content(for: mapFixture(), language: .english, refresh: false)
  #expect(content.markers.count == 37)
  #expect(content.markerError == nil)
  #expect(content.image == Data("map image".utf8))
}

@Test func mapArtworkRemainsAvailableWhenOverlayRequestFails() async throws {
  let transport = try MapFixtureTransport(failMarkers: true)
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let repository = LiveMapRepository(
    cache: ResponseCache(client: XIVAPIClient(transport: transport), directory: directory))
  let content = try await repository.content(for: mapFixture(), language: .english, refresh: false)
  #expect(content.image == Data("map image".utf8))
  #expect(content.markers.isEmpty)
  #expect(content.markerError != nil)
}

@Test func mapMarkerPaginationPreservesSubrowContinuation() async throws {
  let transport = try MapFixtureTransport(paginateMarkers: true)
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let repository = LiveMapRepository(
    cache: ResponseCache(client: XIVAPIClient(transport: transport), directory: directory))
  let content = try await repository.content(for: mapFixture(), language: .english, refresh: false)
  #expect(content.markerError == nil)
  #expect(content.markers.count == 101)
  #expect(content.markers.last?.id == "3:100")
  #expect(await transport.urls.contains { $0.absoluteString.contains("after=3:99") })
}

private actor MapModelRepository: MapRepository {
  var fail = false
  var failPageOnce: Bool
  let delayPages: Bool
  let metadataStale: Bool
  let maps: [GameMap]
  var requested: [Int] = []
  var pageRequests: [Int?] = []
  func setFailure(_ value: Bool) { fail = value }
  init(
    large: Bool = false, failPageOnce: Bool = false, delayPages: Bool = false,
    metadataStale: Bool = false
  ) throws {
    let rows = try XIVAPIClient.decode(BrowseEnvelope.self, from: fixture("maps")).rows
    if large {
      maps = (1...121).map { id in
        var fields = rows[2].fields
        fields["PlaceName"] = .object(["fields": .object(["Name": .string("Map \(id)")])])
        return GameMap(row: SheetRow(rowID: id, fields: fields))!
      }
    } else {
      maps = rows.compactMap(GameMap.init(row:))
    }
    self.failPageOnce = failPageOnce
    self.delayPages = delayPages
    self.metadataStale = metadataStale
  }
  func page(text: String, after: Int?, language: GameLanguage, sort: ResultSort, refresh: Bool)
    async throws -> MapPage
  {
    pageRequests.append(after)
    if after != nil {
      if delayPages { try? await Task.sleep(for: .milliseconds(150)) }
      if failPageOnce {
        failPageOnce = false
        throw URLError(.notConnectedToInternet)
      }
    }
    let ids = try mapTestIndex(maps: maps).matchingIDs(
      kind: .map, language: language, sort: sort, text: text)
    let start = after.flatMap { ids.firstIndex(of: $0).map { $0 + 1 } } ?? 0
    let end = min(ids.count, start + 50)
    return MapPage(
      maps: ids[start..<end].compactMap { id in maps.first { $0.id == id } },
      after: end < ids.count ? ids[end - 1] : nil, isStale: after != nil)
  }
  func mapDetail(id: Int, language: GameLanguage, refresh: Bool) async throws -> MapRecord {
    guard let map = maps.first(where: { $0.id == id }) else { throw APIError.invalidResponse }
    return MapRecord(map: map, isStale: metadataStale)
  }
  func content(for map: GameMap, language: GameLanguage, refresh: Bool) async throws -> MapContent {
    requested.append(map.id)
    try? await Task.sleep(for: .milliseconds(map.id == 2 ? 100 : 30))
    if fail { throw URLError(.notConnectedToInternet) }
    return MapContent(
      image: Data("\(map.id)-\(language.rawValue)".utf8), markers: [], isStale: false,
      markerError: nil)
  }
}

private struct MapSearchRepository: GameRepository {
  let maps: MapModelRepository
  func browse(kind: EntityKind, after: Int?, language: GameLanguage, sort: ResultSort) async throws
    -> EntityPage
  {
    let page = try await maps.page(
      text: "", after: after, language: language, sort: sort, refresh: false)
    return EntityPage(entries: page.maps.map(\.summary), after: page.after, isStale: page.isStale)
  }
  func search(
    kind: EntityKind, text: String, cursor: String?, language: GameLanguage, sort: ResultSort
  ) async throws -> EntityPage {
    let page = try await maps.page(
      text: text, after: cursor.flatMap(Int.init), language: language, sort: sort, refresh: false)
    return EntityPage(
      entries: page.maps.map(\.summary), next: page.after.map(String.init), isStale: page.isStale)
  }
  func detail(_ id: EntityID, refresh: Bool, language: GameLanguage) async throws -> EntityDetail {
    throw APIError.invalidResponse
  }
  func recipes(item: Int, cursor: String?, language: GameLanguage) async throws -> EntityPage {
    EntityPage(entries: [])
  }
}

@Test @MainActor func mapDetailRejectsObsoleteContentAndSupportsLanguageRefreshAndRetry()
  async throws
{
  let repository = try MapModelRepository(metadataStale: true)
  let model = MapDetailModel(repository: repository)
  let old = Task { await model.load(2, language: .english) }
  try await eventually { await repository.requested.contains(2) }
  await model.load(3, language: .english)
  await old.value
  #expect(model.map?.id == 3)
  #expect(model.content?.image == Data("3-en".utf8))
  #expect(model.content?.isStale == true)
  let localized = Task { await model.load(3, language: .german) }
  try await eventually { model.isLoading }
  #expect(model.content?.image == Data("3-en".utf8))
  await localized.value
  #expect(model.content?.image == Data("3-de".utf8))
  await repository.setFailure(true)
  await model.load(3, language: .german, refresh: true)
  #expect(model.error != nil)
  await repository.setFailure(false)
  await model.load(3, language: .german, refresh: true)
  #expect(model.error == nil)
  #expect(model.content?.image == Data("3-de".utf8))
}

@Test @MainActor func mapsUseTheSharedSearchModelForSortPagingRetryAndExhaustion() async throws {
  let repository = try MapModelRepository(large: true, failPageOnce: true)
  let model = SearchModel(repository: MapSearchRepository(maps: repository), debounce: .zero)
  model.kind = .map
  model.start()
  try await eventually { !model.isLoading }
  #expect(model.entries.map(\.id.row) == Array((72...121).reversed()))
  await model.loadMore()
  #expect(model.error != nil)
  #expect(model.entries.count == 50)
  #expect(model.after == 72)
  await model.loadMore()
  #expect(model.entries.count == 100)
  #expect(model.error == nil)
  #expect(model.isStale)
  await model.loadMore()
  #expect(model.entries.map(\.id.row) == Array((1...121).reversed()))
  #expect(!model.canLoadMore)
  await model.loadMore()
  #expect(await repository.pageRequests == [nil, 72, 72, 22])
  model.sort = .name
  try await eventually { !model.isLoading }
  #expect(model.entries.map(\.id.row) == Array(1...50))
  model.query = "MAP 11"
  try await eventually { !model.isLoading }
  #expect(model.entries.map(\.id.row) == [11] + Array(110...119))
}

@Test @MainActor func mapSearchRejectsAnObsoleteContinuation() async throws {
  let repository = try MapModelRepository(large: true, delayPages: true)
  let model = SearchModel(repository: MapSearchRepository(maps: repository), debounce: .zero)
  model.kind = .map
  model.start()
  try await eventually { !model.isLoading }
  let pending = Task { await model.loadMore() }
  try await eventually { await repository.pageRequests.count == 2 }
  model.query = "MAP 1"
  try await eventually { !model.isLoading }
  let matches = model.entries
  #expect(matches.count == 33)
  #expect(!model.canLoadMore)
  await pending.value
  #expect(model.entries == matches)
  #expect(!model.isLoadingMore)
  #expect(model.error == nil)
}

@Test func bundledMapIndexIncludesLocalizedPlacesFloorsRegionsAndAssetIDs() throws {
  let index = try GameDataIndex.bundled.get()
  let ids = try index.matchingIDs(kind: .map, language: .english, sort: .original)
  #expect(ids.count == 1_247)
  #expect(zip(ids, ids.dropFirst()).allSatisfy { $0 > $1 })
  #expect(
    try index.matchingIDs(kind: .map, language: .english, sort: .original, text: "f1t1/00") == [2])
  #expect(
    try index.matchingIDs(kind: .map, language: .english, sort: .original, text: "The Black Shroud")
      .contains(2))
  #expect(
    try index.matchingIDs(kind: .map, language: .german, sort: .name, text: "Neu-Gridania") == [2])
}

#if !SWIFT_PACKAGE
  @Suite(.serialized) @MainActor struct MapCanvasTests {
    @Test func pointerConversionFollowsZoomPanAndRejectsTheMargin() throws {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.borderless],
        backing: .buffered, defer: false)
      let scroll = MapScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
      window.contentView = scroll
      let icons = IconStore(
        responses: ResponseCache(
          client: XIVAPIClient(transport: StubTransport()),
          directory: FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)))
      scroll.apply(
        image: NSImage(size: NSSize(width: 2048, height: 2048)), mapID: 2, markers: [],
        icons: icons, layers: MapLayers(), sizeFactor: 200)
      scroll.layoutSubtreeIfNeeded()
      let source = NSPoint(x: 1100, y: 1079)
      let target = scroll.mapDocument.convert(source, to: nil)
      #expect(scroll.coordinates(at: target)?.formatted() == "X: 12.0  Y: 11.7")
      // Fit leaves horizontal letterboxing outside the actual square texture.
      let margin = scroll.contentView.convert(
        NSPoint(x: scroll.contentView.bounds.minX + 1, y: scroll.contentView.bounds.midY), to: nil)
      #expect(scroll.coordinates(at: margin) == nil)
      scroll.zoom(by: 3)
      scroll.layoutSubtreeIfNeeded()
      let zoomed = scroll.mapDocument.convert(source, to: nil)
      #expect(scroll.coordinates(at: zoomed)?.formatted() == "X: 12.0  Y: 11.7")
      let before = scroll.coordinates(at: zoomed)
      var origin = scroll.contentView.bounds.origin
      origin.x += 100
      scroll.contentView.scroll(to: origin)
      scroll.reflectScrolledClipView(scroll.contentView)
      #expect(scroll.coordinates(at: zoomed)?.x == (before!.x + 1))
      #expect(window.makeFirstResponder(scroll.mapDocument))
      #expect(window.firstResponder === scroll.mapDocument)
      let originBeforeKey = scroll.contentView.bounds.origin
      let right = try #require(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero,
          modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
          characters: "\u{f703}", charactersIgnoringModifiers: "\u{f703}", isARepeat: false,
          keyCode: 124))
      scroll.mapDocument.keyDown(with: right)
      #expect(scroll.contentView.bounds.origin.x > originBeforeKey.x)
      scroll.tracksPointer = false
      #expect(scroll.coordinates(at: zoomed) == nil)
    }

    @Test func nativeViewportFitsZoomsAndKeepsMarkerHitTargetsAtScreenSize() throws {
      let scroll = MapScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      let icons = IconStore(
        responses: ResponseCache(
          client: XIVAPIClient(transport: StubTransport()), directory: directory))
      let markers = try markerFixture()
      scroll.apply(
        image: NSImage(size: NSSize(width: 2048, height: 2048)), mapID: 2,
        markers: markers, icons: icons, layers: MapLayers())
      scroll.layoutSubtreeIfNeeded()
      #expect(abs(scroll.magnification - scroll.fitScale) < 0.001)
      let marker = try #require(scroll.mapDocument.subviews.compactMap { $0 as? NSButton }.first)
      #expect(abs(marker.frame.width * scroll.magnification - 28) < 0.01)
      scroll.zoom(by: 3)
      scroll.layoutSubtreeIfNeeded()
      #expect(abs(scroll.magnification / scroll.fitScale - 3) < 0.01)
      #expect(abs(marker.frame.width * scroll.magnification - 28) < 0.01)
      let captions = scroll.mapDocument.subviews.compactMap { $0 as? NSTextField }.filter {
        !$0.isHidden
      }
      #expect(!captions.isEmpty)
      let gameLabel = try #require(captions.first)
      #expect(!gameLabel.drawsBackground)
      #expect(gameLabel.maximumNumberOfLines == 0)
      #expect(gameLabel.lineBreakMode == .byWordWrapping)
      #expect(
        gameLabel.attributedStringValue.attribute(.strokeWidth, at: 0, effectiveRange: nil) as? Int
          == 8)
      for (index, caption) in captions.enumerated() {
        #expect(!captions.dropFirst(index + 1).contains { $0.frame.intersects(caption.frame) })
      }
      let before = scroll.contentView.bounds.origin
      let event = try #require(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero,
          modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
          characters: "\u{f702}", charactersIgnoringModifiers: "\u{f702}", isARepeat: false,
          keyCode: 123))
      scroll.keyDown(with: event)
      #expect(scroll.contentView.bounds.origin.x < before.x)
      #expect(
        scroll.mapDocument.subviews.compactMap { $0 as? NSButton }.filter { !$0.isHidden }.count
          == markers.count)
      var hidden = MapLayers()
      hidden.landmarks = false
      hidden.otherIcons = false
      scroll.apply(
        image: NSImage(size: NSSize(width: 2048, height: 2048)), mapID: 2,
        markers: markers, icons: icons, layers: hidden)
      #expect(scroll.mapDocument.subviews.allSatisfy { $0.isHidden })
      scroll.fit()
      #expect(abs(scroll.magnification - scroll.fitScale) < 0.001)
    }

    @Test func labelsUseSourceAnchorsAndPreserveMultilineNamesWithoutFakePins() throws {
      let icons = IconStore(
        responses: ResponseCache(
          client: XIVAPIClient(transport: StubTransport()),
          directory: FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)))
      let markers = try markerFixture()
      for marker in markers.filter({ $0.isNamed }) {
        let button = MapMarkerButton(marker: marker, icons: icons)
        button.frame = NSRect(x: 100, y: 100, width: 28, height: 28)
        button.updateLabel(visible: true, scale: 1, selected: false)
        #expect(button.caption.stringValue == marker.name)
        #expect(!button.caption.stringValue.contains("…"))
        if marker.iconPath == nil {
          #expect(button.image == nil)
          #expect(abs(button.caption.frame.midX - 114) < 0.01)
          #expect(abs(button.caption.frame.midY - 114) < 0.01)
        } else {
          switch marker.labelPlacement {
          case .left: #expect(button.caption.frame.maxX < button.frame.minX)
          case .right: #expect(button.caption.frame.minX > button.frame.maxX)
          case .above: #expect(button.caption.frame.maxY < button.frame.minY)
          case .below: #expect(button.caption.frame.minY > button.frame.maxY)
          case .hidden: break
          }
        }
        if marker.id == "3:1" {
          #expect(button.caption.stringValue.contains("\n"))
          #expect(button.caption.frame.height > 30)
          #expect(button.caption.frame.width < 160)
        }
        if marker.id == "3:0" || marker.id == "3:16" {
          let bitmap = try #require(
            button.caption.bitmapImageRepForCachingDisplay(in: button.caption.bounds))
          button.caption.cacheDisplay(in: button.caption.bounds, to: bitmap)
          var readableFill = false
          for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
              guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                pixel.alphaComponent > 0.7
              else { continue }
              if marker.isMapLink {
                readableFill =
                  readableFill
                  || (pixel.redComponent < 0.65 && pixel.greenComponent > 0.75
                    && pixel.blueComponent > 0.8)
              } else {
                readableFill =
                  readableFill
                  || (pixel.redComponent > 0.8 && pixel.greenComponent > 0.8
                    && pixel.blueComponent > 0.8)
              }
            }
          }
          #expect(readableFill)
        }
        button.cancel()
      }
    }

    @Test func nativeMarkerDrawsArtworkAndLeavesTextOnlyLocationsUnpainted() throws {
      let icons = IconStore(
        responses: ResponseCache(
          client: XIVAPIClient(transport: StubTransport()),
          directory: FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)))
      let markers = try markerFixture()
      let artwork = try #require(NSImage(data: UITestMapRepository.artwork))
      for hasIcon in [true, false] {
        let marker = try #require(markers.first { ($0.iconPath != nil) == hasIcon })
        let button = MapMarkerButton(marker: marker, icons: icons)
        button.frame = NSRect(x: 0, y: 0, width: 28, height: 28)
        button.image = artwork
        let bitmap = try #require(button.bitmapImageRepForCachingDisplay(in: button.bounds))
        button.cacheDisplay(in: button.bounds, to: bitmap)
        let center = try #require(
          bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(
            .deviceRGB))
        if hasIcon {
          #expect(center.alphaComponent > 0.99)
          #expect(center.blueComponent > 0.4)
        } else {
          #expect(center.alphaComponent == 0)
        }
        button.cancel()
      }
    }

    @Test func mapsShareObjectNavigationLanguagesFavoritesAndHistory() async throws {
      let workspace = Workspace()
      workspace.search.cancel()
      workspace.language = .english
      let map = try mapFixture().summary
      workspace.section = .category(.map)
      workspace.openResult(map)
      await workspace.mapDetail.load(map.id.row, language: .english)
      let loaded = try #require(workspace.loadedEntity)
      #expect(loaded.id == map.id)
      await workspace.recordLoadedEntity(loaded)
      #expect(workspace.library.snapshot.history.first?.id == map.id)
      #expect(workspace.canToggleFavorite)
      workspace.toggleCurrentFavorite()
      try await eventually { workspace.library.isFavorite(map.id) }
      workspace.objectLanguageOverride = .japanese
      workspace.language = .german
      #expect(workspace.objectLanguage == .japanese)
      workspace.open(EntitySummary(id: EntityID(kind: .item, row: 1), name: "Item"))
      #expect(workspace.objectLanguage == .german)
      workspace.goBack()
      #expect(workspace.navigation.current?.id == map.id)
      #expect(workspace.objectLanguage == .japanese)
      #expect(workspace.canGoForward)
      workspace.toggleCurrentFavorite()
      try await eventually { !workspace.library.isFavorite(map.id) }
      workspace.search.cancel()
    }
  }
#endif
