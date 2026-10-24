import Foundation

public protocol GameRepository: Sendable {
  func search(
    kind: EntityKind, text: String, cursor: String?, language: GameLanguage, sort: ResultSort
  ) async throws
    -> EntityPage
  func browse(kind: EntityKind, after: Int?, language: GameLanguage, sort: ResultSort) async throws
    -> EntityPage
  func detail(_ id: EntityID, refresh: Bool, language: GameLanguage) async throws -> EntityDetail
  func recipes(item: Int, cursor: String?, language: GameLanguage) async throws -> EntityPage
}

extension GameRepository {
  public func search(kind: EntityKind, text: String, cursor: String?, language: GameLanguage)
    async throws -> EntityPage
  {
    try await search(kind: kind, text: text, cursor: cursor, language: language, sort: .original)
  }
  public func browse(kind: EntityKind, after: Int?, language: GameLanguage) async throws
    -> EntityPage
  {
    try await browse(kind: kind, after: after, language: language, sort: .original)
  }
}

public struct LiveGameRepository: GameRepository {
  public let cache: ResponseCache
  private let index: GameDataIndex?
  private let queries: GameIndexQueries
  public init(cache: ResponseCache, index: GameDataIndex? = nil) {
    self.cache = cache
    self.index = index
    queries = GameIndexQueries(index: index)
  }
  private var gameData: GameDataIndex {
    get throws { try index ?? GameDataIndex.bundled.get() }
  }
  private func pinned(_ request: APIRequest) throws -> APIRequest {
    request.pinned(to: try gameData.snapshot)
  }
  private func decoded<T: Decodable & Sendable>(
    _ type: T.Type, request: APIRequest, ttl: TimeInterval = 3_600, refresh: Bool = false
  ) async throws -> (T, Bool) {
    let request = try pinned(request)
    let resource = try await cache.resource(request, ttl: ttl, refresh: refresh)
    do { return (try XIVAPIClient.decode(type, from: resource.data), resource.isStale) } catch {
      try? await cache.invalidate(request)
      throw error
    }
  }
  public func search(
    kind: EntityKind, text: String, cursor: String? = nil, language: GameLanguage = .english,
    sort: ResultSort = .original
  ) async throws -> EntityPage {
    var before: Int?
    if let cursor {
      guard cursor.hasPrefix("index:"), let row = Int(cursor.dropFirst(6)), row >= 0 else {
        throw APIError.invalidResponse
      }
      before = row
    }
    let page = try await indexedPage(
      kind: kind, text: text, before: before, language: language, sort: sort)
    return EntityPage(
      entries: page.entries, next: page.after.map { "index:\($0)" }, isStale: page.isStale)
  }

  public func browse(
    kind: EntityKind, after: Int? = nil, language: GameLanguage = .english,
    sort: ResultSort = .original
  ) async throws -> EntityPage {
    try await indexedPage(kind: kind, text: "", before: after, language: language, sort: sort)
  }

  private func indexedPage(
    kind: EntityKind, text: String, before: Int?, language: GameLanguage, sort: ResultSort
  ) async throws -> EntityPage {
    if kind == .map {
      let page = try await LiveMapRepository(cache: cache, index: index).page(
        text: text, after: before, language: language, sort: sort, refresh: false)
      return EntityPage(entries: page.maps.map(\.summary), after: page.after, isStale: page.isStale)
    }
    let ids = try await queries.ids(kind: kind, language: language, sort: sort, text: text)
    var offset = 0
    if let before {
      if let previous = ids.firstIndex(of: before) {
        offset = previous + 1
      } else if sort == .original {
        offset = ids.firstIndex { $0 < before } ?? ids.count
      } else {
        throw APIError.invalidResponse
      }
    }
    var entries: [EntitySummary] = []
    var stale = false
    while offset < ids.count && entries.count < 50 {
      try Task.checkCancellation()
      let batch = Array(ids[offset..<min(ids.count, offset + 50 - entries.count)])
      let (envelope, cached) = try await decoded(
        BrowseEnvelope.self, request: .rows(kind: kind, ids: batch, language: language))
      let expected = Set(batch)
      var rows: [Int: SheetRow] = [:]
      for row in envelope.rows {
        guard expected.contains(row.rowID), rows.updateValue(row, forKey: row.rowID) == nil else {
          throw APIError.invalidResponse
        }
      }
      entries += batch.compactMap { rows[$0]?.summary(kind: kind) }.filter {
        !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
      stale = stale || cached
      offset += batch.count
    }
    return EntityPage(
      entries: entries, after: offset < ids.count ? ids[offset - 1] : nil, isStale: stale)
  }
  public func detail(_ id: EntityID, refresh: Bool = false, language: GameLanguage = .english)
    async throws -> EntityDetail
  {
    let (envelope, stale) = try await decoded(
      DetailEnvelope.self, request: .detail(id, language: language), refresh: refresh)
    guard envelope.rowID == id.row else { throw APIError.invalidResponse }
    if id.kind == .quest {
      async let journal = questJournal(envelope.row, refresh: refresh, language: language)
      async let experience = questExperience(envelope.row, refresh: refresh, language: language)
      let (text, xp) = try await (journal, experience)
      return EntityDetail(
        entity: envelope.row.summary(kind: .quest), row: envelope.row, schema: envelope.schema,
        version: envelope.version, isStale: stale || text.stale || xp.stale,
        questJournal: text.value, questExperience: xp.value,
        questContentError: text.failed || xp.failed
          ? "Some quest details couldn’t be loaded. Refresh to try again." : nil)
    }
    return EntityDetail(
      entity: envelope.row.summary(kind: id.kind), row: envelope.row, schema: envelope.schema,
      version: envelope.version, isStale: stale)
  }
  private func questJournal(_ row: SheetRow, refresh: Bool, language: GameLanguage) async throws
    -> (value: QuestJournal?, stale: Bool, failed: Bool)
  {
    guard let id = row["Id"].string,
      let request = APIRequest.questJournal(id: id, language: language)
    else { return (nil, false, true) }
    do {
      let (envelope, stale) = try await decoded(
        BrowseEnvelope.self, request: request, refresh: refresh)
      try Task.checkCancellation()
      return (QuestJournal(rows: envelope.rows), stale, false)
    } catch {
      try Task.checkCancellation()
      return (nil, false, true)
    }
  }
  private func questExperience(_ row: SheetRow, refresh: Bool, language: GameLanguage) async throws
    -> (value: Int?, stale: Bool, failed: Bool)
  {
    guard let factor = row["ExpFactor"].integer, factor >= 0 else { return (nil, false, true) }
    if factor == 0 { return (0, false, false) }
    guard let level = row.summary(kind: .quest).level, level > 0 else { return (nil, false, true) }
    do {
      let (growth, stale) = try await decoded(
        DetailEnvelope.self, request: .questGrowth(level: level, language: language),
        refresh: refresh)
      try Task.checkCancellation()
      let value = QuestPresentation.experience(factor: factor, growth: growth.row)
      return (value, stale, value == nil)
    } catch {
      try Task.checkCancellation()
      return (nil, false, true)
    }
  }
  public func recipes(item: Int, cursor: String? = nil, language: GameLanguage = .english)
    async throws -> EntityPage
  {
    let (envelope, stale) = try await decoded(
      SearchEnvelope.self, request: .recipes(item: item, cursor: cursor, language: language),
      ttl: 300)
    return EntityPage(
      entries: envelope.results.map { $0.summary(kind: .recipe) }, next: envelope.next,
      isStale: stale)
  }
}
