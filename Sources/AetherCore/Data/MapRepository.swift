import Foundation

public protocol MapRepository: Sendable {
  func page(text: String, after: Int?, language: GameLanguage, sort: ResultSort, refresh: Bool)
    async throws -> MapPage
  func mapDetail(id: Int, language: GameLanguage, refresh: Bool) async throws -> MapRecord
  func content(for map: GameMap, language: GameLanguage, refresh: Bool) async throws -> MapContent
}

extension APIRequest {
  private static let mapFields = EntityKind.map.summaryFields
  static func mapDetail(id: Int, language: GameLanguage) -> Self {
    Self(
      path: "sheet/Map/\(id)",
      parameters: [
        .init(name: "fields", value: mapFields), .init(name: "language", value: language.rawValue),
      ])
  }
  static func mapTownIcons(language: GameLanguage) -> Self {
    Self(
      path: "sheet/Town",
      parameters: [
        .init(name: "fields", value: "Icon"), .init(name: "limit", value: "100"),
        .init(name: "language", value: language.rawValue),
      ])
  }
  public static func mapRows(ids: [Int], language: GameLanguage) -> Self {
    Self(
      path: "sheet/Map",
      parameters: [
        .init(name: "fields", value: mapFields),
        .init(name: "rows", value: ids.map(String.init).joined(separator: ",")),
        .init(name: "language", value: language.rawValue), .init(name: "limit", value: "50"),
      ])
  }

  public static func mapAsset(_ id: String) -> Self? {
    guard GameMap.isValidAssetID(id) else { return nil }
    return Self(path: "asset/map/\(id)", parameters: [.init(name: "format", value: "png")])
  }

  static func mapMarkers(after: String, language: GameLanguage) -> Self {
    Self(
      path: "sheet/MapMarker",
      parameters: [
        .init(name: "fields", value: "X,Y,Icon,PlaceNameSubtext.Name,SubtextOrientation,DataType"),
        .init(name: "language", value: language.rawValue), .init(name: "limit", value: "100"),
        .init(name: "after", value: after),
      ])
  }
}

public struct LiveMapRepository: MapRepository {
  private let cache: ResponseCache
  private let index: GameDataIndex?
  private let queries: GameIndexQueries
  public init(cache: ResponseCache, index: GameDataIndex? = nil) {
    self.cache = cache
    self.index = index
    queries = GameIndexQueries(index: index)
  }

  private func decoded<T: Decodable & Sendable>(_ type: T.Type, request: APIRequest, refresh: Bool)
    async throws -> (T, Bool)
  {
    let request = try request.pinned(to: (index ?? GameDataIndex.bundled.get()).snapshot)
    let resource = try await cache.resource(request, ttl: 86_400, refresh: refresh)
    do { return (try XIVAPIClient.decode(type, from: resource.data), resource.isStale) } catch {
      try? await cache.invalidate(request)
      throw error
    }
  }

  public func page(
    text: String, after: Int?, language: GameLanguage, sort: ResultSort, refresh: Bool
  )
    async throws -> MapPage
  {
    let ids = try await queries.ids(kind: .map, language: language, sort: sort, text: text)
    var offset = 0
    if let after {
      guard let previous = ids.firstIndex(of: after) else { throw APIError.invalidResponse }
      offset = previous + 1
    }
    guard offset < ids.count else { return MapPage(maps: [], isStale: false) }
    var maps: [GameMap] = []
    var stale = false
    let (teleportIcons, cachedIcons) = try await townIcons(language: language, refresh: refresh)
    stale = cachedIcons
    while offset < ids.count && maps.count < 50 {
      try Task.checkCancellation()
      let batch = Array(ids[offset..<min(ids.count, offset + 50 - maps.count)])
      let (page, cached) = try await decoded(
        BrowseEnvelope.self,
        request: .mapRows(ids: batch, language: language), refresh: refresh)
      let expected = Set(batch)
      var rows: [Int: SheetRow] = [:]
      for row in page.rows {
        guard expected.contains(row.rowID), rows.updateValue(row, forKey: row.rowID) == nil else {
          throw APIError.invalidResponse
        }
      }
      maps += batch.compactMap { id in
        rows[id].flatMap { GameMap(row: $0, teleportIcons: teleportIcons) }
      }
      stale = stale || cached
      offset += batch.count
    }
    return MapPage(maps: maps, after: offset < ids.count ? ids[offset - 1] : nil, isStale: stale)
  }

  private func townIcons(language: GameLanguage, refresh: Bool) async throws -> (
    [Int: String], Bool
  ) {
    do {
      let (towns, stale) = try await decoded(
        BrowseEnvelope.self, request: .mapTownIcons(language: language), refresh: refresh)
      var icons: [Int: String] = [:]
      for town in towns.rows where (town["Icon"]["id"].integer ?? 0) > 0 {
        icons[town.rowID] = town["Icon"].iconPath
      }
      return (icons, stale)
    } catch {
      try Task.checkCancellation()
      return ([:], false)
    }
  }

  public func mapDetail(id: Int, language: GameLanguage, refresh: Bool) async throws -> MapRecord {
    async let emblems = townIcons(language: language, refresh: refresh)
    let (row, stale) = try await decoded(
      DetailEnvelope.self, request: .mapDetail(id: id, language: language), refresh: refresh)
    let (icons, cachedIcons) = try await emblems
    guard row.rowID == id, let map = GameMap(row: row.row, teleportIcons: icons) else {
      throw APIError.invalidResponse
    }
    return MapRecord(map: map, isStale: stale || cachedIcons)
  }

  private func markers(for map: GameMap, language: GameLanguage, refresh: Bool)
    async throws -> (markers: [GameMapMarker], stale: Bool)
  {
    guard map.markerRange > 0 else { return ([], false) }
    // A bare `rows=range` returns only subrow zero. Start just before the group,
    // then follow subrow pagination until the next group, preserving subrow identity.
    var after = "\(map.markerRange - 1):65535"
    var previousSubrow = -1
    var result: [GameMapMarker] = []
    var stale = false
    struct Page: Decodable, Sendable { let rows: [MapMarkerRow] }
    for _ in 0..<64 {
      try Task.checkCancellation()
      let (page, cached) = try await decoded(
        Page.self,
        request: .mapMarkers(after: after, language: language), refresh: refresh)
      stale = stale || cached
      for row in page.rows {
        guard row.rowID >= map.markerRange else { throw APIError.invalidResponse }
        if row.rowID > map.markerRange { return (result, stale) }
        guard row.subrowID > previousSubrow, row.subrowID <= 65535 else {
          throw APIError.invalidResponse
        }
        previousSubrow = row.subrowID
        if let marker = GameMapMarker(row: row) { result.append(marker) }
      }
      if page.rows.count < 100 { return (result, stale) }
      after = "\(map.markerRange):\(previousSubrow)"
    }
    throw APIError.invalidResponse
  }

  public func content(for map: GameMap, language: GameLanguage, refresh: Bool) async throws
    -> MapContent
  {
    guard let request = APIRequest.mapAsset(map.assetID) else { throw APIError.invalidURL }
    async let artwork = cache.resource(request, ttl: 86_400, refresh: refresh)
    var markers: [GameMapMarker] = []
    var stale = false
    var markerError: String?
    do {
      let overlay = try await self.markers(for: map, language: language, refresh: refresh)
      markers = overlay.markers
      stale = overlay.stale
    } catch {
      try Task.checkCancellation()
      markerError = "Map markers couldn’t be loaded. Refresh to try again."
    }
    let image = try await artwork
    try Task.checkCancellation()
    return MapContent(
      image: image.data, markers: markers, isStale: stale || image.isStale,
      markerError: markerError)
  }
}
