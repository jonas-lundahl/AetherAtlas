import Foundation

public protocol GameRepository: Sendable {
  func search(kind: EntityKind, text: String, cursor: String?) async throws -> EntityPage
  func browse(kind: EntityKind, after: Int?) async throws -> EntityPage
  func detail(_ id: EntityID, refresh: Bool) async throws -> EntityDetail
  func recipes(item: Int, cursor: String?) async throws -> EntityPage
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
  public func search(kind: EntityKind, text: String, cursor: String? = nil) async throws
    -> EntityPage
  {
    let envelope: SearchEnvelope
    let stale: Bool
    do {
      (envelope, stale) = try await decoded(
        SearchEnvelope.self, request: .search(kind: kind, text: text, cursor: cursor),
        ttl: cursor == nil ? 300 : 30)
    } catch {
      if cursor != nil, case APIError.http(400, _, _) = error {
        try? await cache.invalidate(.search(kind: kind, text: text))
      }
      throw error
    }
    return EntityPage(
      entries: envelope.results.map { $0.summary(kind: kind) }, next: envelope.next, isStale: stale)
  }
  public func browse(kind: EntityKind, after: Int? = nil) async throws -> EntityPage {
    let (envelope, stale) = try await decoded(
      BrowseEnvelope.self, request: .browse(kind: kind, after: after))
    return EntityPage(
      entries: envelope.rows.map { $0.summary(kind: kind) }.filter { !$0.name.isEmpty },
      after: envelope.rows.count == 50 ? envelope.rows.last?.rowID : nil, isStale: stale)
  }
  public func detail(_ id: EntityID, refresh: Bool = false) async throws -> EntityDetail {
    let (envelope, stale) = try await decoded(
      DetailEnvelope.self, request: .detail(id), refresh: refresh)
    guard envelope.rowID == id.row else { throw APIError.invalidResponse }
    return EntityDetail(
      entity: envelope.row.summary(kind: id.kind), row: envelope.row, schema: envelope.schema,
      version: envelope.version, isStale: stale)
  }
  public func recipes(item: Int, cursor: String? = nil) async throws -> EntityPage {
    let (envelope, stale) = try await decoded(
      SearchEnvelope.self, request: .recipes(item: item, cursor: cursor), ttl: 300)
    return EntityPage(
      entries: envelope.results.map { $0.summary(kind: .recipe) }, next: envelope.next,
      isStale: stale)
  }
}
