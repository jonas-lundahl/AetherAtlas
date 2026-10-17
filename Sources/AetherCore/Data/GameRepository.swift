import Foundation

public protocol GameRepository: Sendable {
  func search(kind: EntityKind, text: String, cursor: String?, language: GameLanguage) async throws
    -> EntityPage
  func browse(kind: EntityKind, after: Int?, language: GameLanguage) async throws -> EntityPage
  func detail(_ id: EntityID, refresh: Bool, language: GameLanguage) async throws -> EntityDetail
  func recipes(item: Int, cursor: String?, language: GameLanguage) async throws -> EntityPage
}

public struct LiveGameRepository: GameRepository {
  public let cache: ResponseCache
  public init(cache: ResponseCache) { self.cache = cache }
  private func decoded<T: Decodable & Sendable>(
    _ type: T.Type, request: APIRequest, ttl: TimeInterval = 3_600, refresh: Bool = false
  ) async throws -> (T, Bool) {
    let resource = try await cache.resource(request, ttl: ttl, refresh: refresh)
    do { return (try XIVAPIClient.decode(type, from: resource.data), resource.isStale) } catch {
      try? await cache.invalidate(request)
      throw error
    }
  }
  public func search(
    kind: EntityKind, text: String, cursor: String? = nil, language: GameLanguage = .english
  ) async throws
    -> EntityPage
  {
    let envelope: SearchEnvelope
    let stale: Bool
    do {
      (envelope, stale) = try await decoded(
        SearchEnvelope.self,
        request: .search(kind: kind, text: text, cursor: cursor, language: language),
        ttl: cursor == nil ? 300 : 30)
    } catch {
      if cursor != nil, case APIError.http(400, _, _) = error {
        try? await cache.invalidate(.search(kind: kind, text: text, language: language))
      }
      throw error
    }
    return EntityPage(
      entries: envelope.results.map { $0.summary(kind: kind) }, next: envelope.next, isStale: stale)
  }
  public func browse(kind: EntityKind, after: Int? = nil, language: GameLanguage = .english)
    async throws -> EntityPage
  {
    let (envelope, stale) = try await decoded(
      BrowseEnvelope.self, request: .browse(kind: kind, after: after, language: language))
    return EntityPage(
      entries: envelope.rows.map { $0.summary(kind: kind) }.filter { !$0.name.isEmpty },
      after: envelope.rows.count == 50 ? envelope.rows.last?.rowID : nil, isStale: stale)
  }
  public func detail(_ id: EntityID, refresh: Bool = false, language: GameLanguage = .english)
    async throws -> EntityDetail
  {
    let (envelope, stale) = try await decoded(
      DetailEnvelope.self, request: .detail(id, language: language), refresh: refresh)
    guard envelope.rowID == id.row else { throw APIError.invalidResponse }
    return EntityDetail(
      entity: envelope.row.summary(kind: id.kind), row: envelope.row, schema: envelope.schema,
      version: envelope.version, isStale: stale)
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
