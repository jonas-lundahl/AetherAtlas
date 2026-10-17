import CryptoKit
import Foundation

public struct CachedResource: Sendable {
  public let data: Data
  public let isStale: Bool
}

/// Bounded, atomic disk cache with HTTP revalidation and reference-counted shared requests.
public actor ResponseCache {
  struct Entry: Codable, Sendable {
    let data: Data
    let saved: Date
    let expires: Date
    let etag: String?
    let cacheControl: String?
    let permitsStale: Bool
  }
  struct Flight {
    let id: UUID
    let task: Task<CachedResource, Error>
    var waiters: Set<UUID>
  }
  private let client: XIVAPIClient
  private let directory: URL
  private let diskLimit: Int
  private let now: @Sendable () -> Date
  private var memory: [String: Entry] = [:]
  private var recency: [String] = []
  private var flights: [String: Flight] = [:]
  public private(set) var diskError: String?
  public init(
    client: XIVAPIClient, directory: URL, diskLimit: Int = 128 * 1_024 * 1_024,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.client = client
    self.directory = directory
    self.diskLimit = diskLimit
    self.now = now
  }
  public func resource(_ request: APIRequest, ttl: TimeInterval = 3_600, refresh: Bool = false)
    async throws -> CachedResource
  {
    try Task.checkCancellation()
    let url = try request.url()
    let key = Self.key(url.absoluteString)
    let entry = read(key)
    if !refresh, let entry, entry.expires > now() {
      return CachedResource(data: entry.data, isStale: false)
    }
    let waiter = UUID()
    let flightID: UUID
    let task: Task<CachedResource, Error>
    if var flight = flights[key] {
      flight.waiters.insert(waiter)
      flights[key] = flight
      flightID = flight.id
      task = flight.task
    } else {
      flightID = UUID()
      task = Task {
        do {
          let payload = try await client.fetch(url: url, etag: entry?.etag)
          try Task.checkCancellation()
          let data: Data
          if payload.status == 304 {
            guard let entry else { throw APIError.invalidResponse }
            data = entry.data
          } else {
            data = payload.data
          }
          let cacheControl =
            payload.cacheControl ?? (payload.status == 304 ? entry?.cacheControl : nil)
          let control = cacheControl?.lowercased() ?? ""
          if control.contains("no-store") {
            remove(key)
          } else {
            let maxAge = control.split(separator: ",").compactMap { directive -> Double? in
              let s = directive.trimmingCharacters(in: .whitespaces)
              return s.hasPrefix("max-age=")
                ? Double(s.dropFirst(8).replacingOccurrences(of: "\"", with: "")) : nil
            }.first
            let lifetime = control.contains("no-cache") ? 0 : min(ttl, maxAge ?? ttl)
            let value = Entry(
              data: data, saved: now(), expires: now().addingTimeInterval(lifetime),
              etag: payload.etag ?? entry?.etag, cacheControl: cacheControl,
              permitsStale: !control.contains("must-revalidate") && !control.contains("no-cache"))
            write(value, key: key)
          }
          return CachedResource(data: data, isStale: false)
        } catch {
          try Task.checkCancellation()
          if case APIError.http(let code, _, _) = error, code == 404 || code == 410 { remove(key) }
          if let entry, entry.permitsStale, Self.allowsFallback(error) {
            return CachedResource(data: entry.data, isStale: true)
          }
          throw error
        }
      }
      flights[key] = Flight(id: flightID, task: task, waiters: [waiter])
    }
    return try await withTaskCancellationHandler {
      do {
        let result = try await task.value
        finish(key, flightID: flightID, waiter: waiter)
        try Task.checkCancellation()
        return result
      } catch {
        finish(key, flightID: flightID, waiter: waiter)
        throw error
      }
    } onCancel: {
      Task { await self.cancel(key, flightID: flightID, waiter: waiter) }
    }
  }
  public func invalidate(_ request: APIRequest) throws {
    remove(Self.key(try request.url().absoluteString))
  }
  private func finish(_ key: String, flightID: UUID, waiter: UUID) {
    guard var f = flights[key], f.id == flightID else { return }
    f.waiters.remove(waiter)
    if f.waiters.isEmpty { flights[key] = nil } else { flights[key] = f }
  }
  private func cancel(_ key: String, flightID: UUID, waiter: UUID) {
    guard var f = flights[key], f.id == flightID else { return }
    f.waiters.remove(waiter)
    if f.waiters.isEmpty {
      f.task.cancel()
      flights[key] = nil
    } else {
      flights[key] = f
    }
  }
  private static func allowsFallback(_ error: any Error) -> Bool {
    if let e = error as? URLError { return e.code != .cancelled }
    if case APIError.http(let code, _, _) = error { return code >= 500 || code == 429 }
    return false
  }
  private static func key(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
  private func file(_ key: String) -> URL {
    directory.appendingPathComponent(key).appendingPathExtension("json")
  }
  private func read(_ key: String) -> Entry? {
    if let value = memory[key] {
      touch(key)
      return value
    }
    guard let data = try? Data(contentsOf: file(key)),
      let value = try? JSONDecoder().decode(Entry.self, from: data)
    else { return nil }
    remember(value, key: key)
    return value
  }
  private func touch(_ key: String) {
    recency.removeAll { $0 == key }
    recency.append(key)
  }
  private func remember(_ value: Entry, key: String) {
    memory[key] = value
    touch(key)
    // Bound encoded in-memory resources to 16 MiB and 128 entries.
    while memory.count > 128 || memory.values.reduce(0, { $0 + $1.data.count }) > 16 * 1_024 * 1_024
    {
      guard let old = recency.first else { break }
      recency.removeFirst()
      memory[old] = nil
    }
  }
  private func write(_ value: Entry, key: String) {
    remember(value, key: key)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try JSONEncoder().encode(value).write(to: file(key), options: .atomic)
      try trimDisk()
    } catch { diskError = error.localizedDescription }
  }
  private func remove(_ key: String) {
    memory[key] = nil
    recency.removeAll { $0 == key }
    try? FileManager.default.removeItem(at: file(key))
  }
  private func trimDisk() throws {
    let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
    let files = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: Array(keys)
    )
    .filter { $0.pathExtension == "json" }
    .compactMap { url -> (URL, Int, Date)? in
      guard let v = try? url.resourceValues(forKeys: keys) else { return nil }
      return (url, v.fileSize ?? 0, v.contentModificationDate ?? .distantPast)
    }.sorted { $0.2 < $1.2 }
    var size = files.reduce(0) { $0 + $1.1 }
    for (url, bytes, _) in files where size > diskLimit {
      try FileManager.default.removeItem(at: url)
      size -= bytes
    }
  }
}
