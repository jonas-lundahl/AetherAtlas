import Foundation
import Observation

public struct LibrarySnapshot: Codable, Sendable, Equatable {
  public var schemaVersion = 1
  public var favorites: [EntitySummary] = []
  public var history: [EntitySummary] = []
  public init() {}
}
public enum LibraryError: Error, LocalizedError {
  case unsupportedVersion(Int)
  public var errorDescription: String? {
    switch self {
    case .unsupportedVersion(let v):
      "Saved library version \(v) requires a newer Aether Atlas. Your file has been preserved."
    }
  }
}
public actor LibraryStore {
  private let file: URL
  private let historyLimit: Int
  private var snapshot: LibrarySnapshot?
  public init(file: URL, historyLimit: Int = 100) {
    self.file = file
    self.historyLimit = max(1, historyLimit)
  }
  public func load() throws -> LibrarySnapshot {
    if let snapshot { return snapshot }
    guard FileManager.default.fileExists(atPath: file.path) else {
      let empty = LibrarySnapshot()
      snapshot = empty
      return empty
    }
    let value = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: file))
    // Future migrations belong here. Never replace a corrupt or newer library with an empty one.
    guard value.schemaVersion == 1 else {
      throw LibraryError.unsupportedVersion(value.schemaVersion)
    }
    snapshot = value
    return value
  }
  public func toggleFavorite(_ entity: EntitySummary) throws -> LibrarySnapshot {
    var value = try load()
    if value.favorites.contains(where: { $0.id == entity.id }) {
      value.favorites.removeAll { $0.id == entity.id }
    } else {
      value.favorites.append(entity)
    }
    return try save(value)
  }
  public func record(_ entity: EntitySummary) throws -> LibrarySnapshot {
    var value = try load()
    value.history.removeAll { $0.id == entity.id }
    value.history.insert(entity, at: 0)
    value.history = Array(value.history.prefix(historyLimit))
    if let index = value.favorites.firstIndex(where: { $0.id == entity.id }) {
      value.favorites[index] = entity
    }
    return try save(value)
  }
  public func clearHistory() throws -> LibrarySnapshot {
    var value = try load()
    value.history = []
    return try save(value)
  }
  private func save(_ value: LibrarySnapshot) throws -> LibrarySnapshot {
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(value).write(to: file, options: .atomic)
    snapshot = value
    return value
  }
}

@MainActor @Observable public final class LibraryModel {
  public private(set) var snapshot = LibrarySnapshot()
  public var error: String?
  @ObservationIgnored private let store: LibraryStore
  public init(store: LibraryStore) { self.store = store }
  public func load() async {
    do { snapshot = try await store.load() } catch { self.error = error.localizedDescription }
  }
  public func isFavorite(_ id: EntityID) -> Bool { snapshot.favorites.contains { $0.id == id } }
  public func toggle(_ entity: EntitySummary) async {
    do { snapshot = try await store.toggleFavorite(entity) } catch {
      self.error = error.localizedDescription
    }
  }
  public func record(_ entity: EntitySummary) async {
    do { snapshot = try await store.record(entity) } catch {
      self.error = error.localizedDescription
    }
  }
  public func clearHistory() async {
    do { snapshot = try await store.clearHistory() } catch {
      self.error = error.localizedDescription
    }
  }
}
