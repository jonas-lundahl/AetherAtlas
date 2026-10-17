import Foundation
import Synchronization
import Testing

#if SWIFT_PACKAGE
  @testable import AetherCore
#else
  @testable import AetherAtlas
#endif

func temporaryDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(
    "AetherAtlasTests-\(UUID())")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}
final class TestClock: Sendable {
  let date = Mutex(Date(timeIntervalSince1970: 1_000))
  func now() -> Date { date.withLock { $0 } }
  func advance(_ seconds: Double) { date.withLock { $0 = $0.addingTimeInterval(seconds) } }
}

@Test func cacheHitDiskReloadExpirationAndOfflineFallback() async throws {
  let directory = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let clock = TestClock()
  let transport = StubTransport("data", headers: ["ETag": "abc"])
  let client = XIVAPIClient(transport: transport)
  let cache = ResponseCache(client: client, directory: directory, now: { clock.now() })
  let request = APIRequest.detail(EntityID(kind: .item, row: 1))
  _ = try await cache.resource(request, ttl: 10)
  _ = try await cache.resource(request, ttl: 10)
  #expect(await transport.count == 1)
  let reloaded = ResponseCache(client: client, directory: directory, now: { clock.now() })
  #expect(try await reloaded.resource(request).data == Data("data".utf8))
  #expect(await transport.count == 1)
  clock.advance(11)
  await transport.setFailure(URLError(.notConnectedToInternet))
  let stale = try await reloaded.resource(request)
  #expect(stale.isStale)
  #expect(stale.data == Data("data".utf8))
  #expect(await transport.count == 2)
  let last = await transport.requests.last
  #expect(last?.value(forHTTPHeaderField: "If-None-Match") == "abc")
}
@Test func cacheCoalescesConcurrentRequests() async throws {
  let directory = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let transport = StubTransport("same", delay: .milliseconds(80))
  let cache = ResponseCache(client: XIVAPIClient(transport: transport), directory: directory)
  let request = APIRequest(path: "same")
  async let first = cache.resource(request)
  async let second = cache.resource(request)
  let (a, b) = try await (first, second)
  #expect(a.data == b.data)
  #expect(await transport.count == 1)
}
@Test func cacheCancellationDoesNotCancelOtherConsumer() async throws {
  let directory = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let transport = StubTransport("shared", delay: .milliseconds(100))
  let cache = ResponseCache(client: XIVAPIClient(transport: transport), directory: directory)
  let request = APIRequest(path: "shared")
  let first = Task { try await cache.resource(request) }
  try await Task.sleep(for: .milliseconds(10))
  let second = Task { try await cache.resource(request) }
  try await Task.sleep(for: .milliseconds(20))
  first.cancel()
  #expect(try await second.value.data == Data("shared".utf8))
  do {
    _ = try await first.value
    Issue.record("Expected cancelled consumer")
  } catch { #expect(error is CancellationError) }
  #expect(await transport.count == 1)
}
@Test func cacheRevalidates304AndHonorsNoStore() async throws {
  let directory = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let initial = ResponseCache(
    client: XIVAPIClient(transport: StubTransport("body", headers: ["ETag": "v1"])),
    directory: directory)
  let request = APIRequest(path: "etag")
  _ = try await initial.resource(request, ttl: 0)
  let revalidation = StubTransport("", status: 304)
  let cache = ResponseCache(client: XIVAPIClient(transport: revalidation), directory: directory)
  let resource = try await cache.resource(request)
  #expect(resource.data == Data("body".utf8))
  #expect(!resource.isStale)
  #expect(await revalidation.requests.first?.value(forHTTPHeaderField: "If-None-Match") == "v1")
  let transport = StubTransport("private", headers: ["Cache-Control": "no-store"])
  let noStore = ResponseCache(client: XIVAPIClient(transport: transport), directory: directory)
  _ = try await noStore.resource(APIRequest(path: "no-store"))
  _ = try await noStore.resource(APIRequest(path: "no-store"))
  #expect(await transport.count == 2)
}
@Test func diskLimitAndCacheWriteFailures() async throws {
  let directory = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let cache = ResponseCache(
    client: XIVAPIClient(transport: StubTransport(String(repeating: "x", count: 100))),
    directory: directory, diskLimit: 1)
  _ = try await cache.resource(APIRequest(path: "large"))
  #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
  let file = directory.appendingPathComponent("file")
  try Data().write(to: file)
  let failing = ResponseCache(
    client: XIVAPIClient(transport: StubTransport("works")), directory: file)
  #expect(try await failing.resource(APIRequest(path: "test")).data == Data("works".utf8))
  #expect(await failing.diskError != nil)
}
@Test func http404DoesNotReturnStaleEntity() async throws {
  let directory = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let request = APIRequest(path: "deleted")
  let first = ResponseCache(
    client: XIVAPIClient(transport: StubTransport("old")), directory: directory)
  _ = try await first.resource(request, ttl: 0)
  let second = ResponseCache(
    client: XIVAPIClient(transport: StubTransport(status: 404)), directory: directory)
  await #expect(throws: APIError.self) { try await second.resource(request) }
}
@Test func favoritesHistoryAndReload() async throws {
  let directory = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let file = directory.appendingPathComponent("library.json")
  let store = LibraryStore(file: directory.appendingPathComponent("library.json"), historyLimit: 2)
  let a = EntitySummary(id: EntityID(kind: .item, row: 1), name: "A")
  let b = EntitySummary(id: EntityID(kind: .recipe, row: 1), name: "B")
  let c = EntitySummary(id: EntityID(kind: .item, row: 2), name: "C")
  _ = try await store.toggleFavorite(a)
  _ = try await store.record(a)
  _ = try await store.record(b)
  _ = try await store.record(a)
  #expect(try await store.load().history.map(\.id) == [a.id, b.id])
  _ = try await store.record(c)
  let reload = LibraryStore(file: file)
  #expect(try await reload.load().favorites == [a])
  #expect(try await reload.load().history.map(\.id) == [c.id, a.id])
  #expect(try await reload.toggleFavorite(a).favorites.isEmpty)
  #expect(try await reload.clearHistory().history.isEmpty)
}
@Test func libraryRefreshesSavedMetadataAndPreservesCorruptFiles() async throws {
  let directory = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let file = directory.appendingPathComponent("library.json")
  let store = LibraryStore(file: directory.appendingPathComponent("library.json"))
  let old = EntitySummary(id: EntityID(kind: .item, row: 1), name: "Old")
  _ = try await store.toggleFavorite(old)
  let changed = EntitySummary(id: old.id, name: "Changed")
  #expect(try await store.record(changed).favorites.first?.name == "Changed")
  try Data("corrupt".utf8).write(to: file)
  let corrupt = LibraryStore(file: file)
  await #expect(throws: (any Error).self) { try await corrupt.toggleFavorite(old) }
  #expect(try String(contentsOf: file, encoding: .utf8) == "corrupt")
}
@Test func libraryWriteFailureDoesNotPublishUnsavedChanges() async throws {
  let directory = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let file = directory.appendingPathComponent("blocked")
  try Data().write(to: file)
  let store = LibraryStore(file: file.appendingPathComponent("library.json"))
  let entity = EntitySummary(id: EntityID(kind: .item, row: 1), name: "A")
  await #expect(throws: (any Error).self) { try await store.toggleFavorite(entity) }
  #expect(try await store.load().favorites.isEmpty)
}

@Test(arguments: ["no-cache", "max-age=0, must-revalidate"])
func strictCacheDirectivesPreventOfflineReuse(control: String) async throws {
  let directory = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let transport = StubTransport("body", headers: ["Cache-Control": control])
  let cache = ResponseCache(client: XIVAPIClient(transport: transport), directory: directory)
  _ = try await cache.resource(APIRequest(path: "strict"))
  await transport.setFailure(URLError(.notConnectedToInternet))
  await #expect(throws: URLError.self) { try await cache.resource(APIRequest(path: "strict")) }
}
@Test func malformedResponseIsEvictedForRetry() async throws {
  let directory = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let transport = StubTransport("invalid")
  let repository = LiveGameRepository(
    cache: ResponseCache(client: XIVAPIClient(transport: transport), directory: directory))
  await #expect(throws: APIError.self) { try await repository.search(kind: .item, text: "a") }
  await #expect(throws: APIError.self) { try await repository.search(kind: .item, text: "a") }
  #expect(await transport.count == 2)
}
@Test func repositoryKeepsLocalizedCacheEntriesSeparate() async throws {
  let directory = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let transport = StubTransport(
    #"{"results":[],"rows":[],"row_id":4551,"fields":{"Name":"Potion"}}"#)
  let repository = LiveGameRepository(
    cache: ResponseCache(client: XIVAPIClient(transport: transport), directory: directory))
  for language in GameLanguage.allCases {
    for _ in 0..<2 {
      _ = try await repository.search(kind: .item, text: "potion", language: language)
      _ = try await repository.browse(kind: .item, language: language)
      _ = try await repository.detail(EntityID(kind: .item, row: 4551), language: language)
      _ = try await repository.recipes(item: 4551, language: language)
    }
  }
  let requests = await transport.requests
  #expect(requests.count == 16)
  for language in GameLanguage.allCases {
    #expect(
      requests.filter {
        URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems?
          .contains { $0.name == "language" && $0.value == language.rawValue } == true
      }.count == 4)
  }
}
@Test func unsupportedLibrarySchemaPreservesData() async throws {
  let directory = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let file = directory.appendingPathComponent("future.json")
  let data = Data(#"{"schemaVersion":99,"favorites":[],"history":[]}"#.utf8)
  try data.write(to: file)
  let store = LibraryStore(file: file)
  await #expect(throws: LibraryError.self) { try await store.load() }
  #expect(try Data(contentsOf: file) == data)
}
