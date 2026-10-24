import Foundation

/// The game files and field mappings selected when this app release was built.
public struct GameDataSnapshot: Codable, Sendable, Equatable {
  public let version: String
  public let patch: String
  public let schema: String

  public init(version: String, patch: String, schema: String) {
    self.version = version
    self.patch = patch
    self.schema = schema
  }
}

public enum GameDataIndexError: Error, LocalizedError, Sendable {
  case invalidBundle

  public var errorDescription: String? {
    "The bundled game-data index is missing or invalid. Reinstall this version of Aether Atlas."
  }
}

/// Pinned names and levels let every category be filtered and sorted before pagination.
public struct GameDataIndex: Decodable, Sendable {
  public let formatVersion: Int
  public let snapshot: GameDataSnapshot
  public struct Sheet: Decodable, Sendable {
    public let ids: [Int]
    public let levels: [Int]?
    public let names: [String: [String]]
    public let searchTerms: [String: [String]]?

    public init(
      ids: [Int], levels: [Int]?, names: [String: [String]], searchTerms: [String: [String]]? = nil
    ) {
      self.ids = ids
      self.levels = levels
      self.names = names
      self.searchTerms = searchTerms
    }
  }
  private let rows: [String: Sheet]

  public init(snapshot: GameDataSnapshot, rows: [String: Sheet], formatVersion: Int = 3) throws {
    self.formatVersion = formatVersion
    self.snapshot = snapshot
    self.rows = rows
    try validate()
  }

  public static func decode(_ data: Data) throws -> Self {
    guard data.count <= 32 * 1_024 * 1_024 else { throw GameDataIndexError.invalidBundle }
    let index = try JSONDecoder().decode(Self.self, from: data)
    try index.validate()
    return index
  }

  public static let bundled: Result<Self, GameDataIndexError> = {
    #if SWIFT_PACKAGE
      let bundle = Bundle.module
    #else
      let bundle = Bundle.main
    #endif
    do {
      guard let url = bundle.url(forResource: "GameDataIndex", withExtension: "json") else {
        throw GameDataIndexError.invalidBundle
      }
      return .success(try decode(Data(contentsOf: url)))
    } catch {
      return .failure(.invalidBundle)
    }
  }()

  private func validate() throws {
    guard formatVersion == 3,
      snapshot.version.range(of: #"^[a-f0-9]{16}$"#, options: .regularExpression) != nil,
      snapshot.schema.range(
        of: #"^exdschema@2:rev:[a-f0-9]{40}$"#, options: .regularExpression) != nil,
      snapshot.patch.range(of: #"^[0-9]+\.[0-9]+(x[0-9]+)?$"#, options: .regularExpression) != nil,
      Set(rows.keys) == Set(EntityKind.allCases.map(\.rawValue))
    else { throw GameDataIndexError.invalidBundle }
    let languages = Set(GameLanguage.allCases.map(\.rawValue))
    for (kind, sheet) in rows {
      let ids = sheet.ids
      guard !ids.isEmpty, ids.count <= 1_000_000,
        ids.allSatisfy({ $0 >= 0 && $0 <= Int(UInt32.max) }),
        zip(ids, ids.dropFirst()).allSatisfy({ $0 > $1 }),
        Set(sheet.names.keys) == languages,
        sheet.names.values.allSatisfy({ names in
          names.count == ids.count && names.allSatisfy { $0.utf8.count <= 4_096 }
        }),
        ids.indices.allSatisfy({ i in
          sheet.names.values.contains { $0[i].contains { !$0.isWhitespace } }
        })
      else { throw GameDataIndexError.invalidBundle }
      if kind == "Map" {
        guard sheet.levels == nil, let terms = sheet.searchTerms,
          Set(terms.keys) == languages,
          terms.values.allSatisfy({ values in
            values.count == ids.count && values.allSatisfy { $0.utf8.count <= 16_384 }
          })
        else { throw GameDataIndexError.invalidBundle }
      } else if kind == EntityKind.npc.rawValue {
        guard sheet.levels == nil else { throw GameDataIndexError.invalidBundle }
      } else {
        guard let levels = sheet.levels, levels.count == ids.count,
          levels.allSatisfy({ $0 >= 0 && $0 <= Int(UInt32.max) })
        else { throw GameDataIndexError.invalidBundle }
      }
    }
  }

  /// Names match literally, ignoring case, accents and character width in the game language.
  public func matchingIDs(
    kind: EntityKind, language: GameLanguage, sort: ResultSort, text: String = ""
  ) throws -> [Int] {
    guard let sheet = rows[kind.rawValue], let names = sheet.names[language.rawValue] else {
      return []
    }
    let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
      .precomposedStringWithCompatibilityMapping
    let locale = language.locale
    var offsets: [Int] = []
    for offset in sheet.ids.indices {
      if offset % 256 == 0 { try Task.checkCancellation() }
      let name = names[offset]
      guard name.contains(where: { !$0.isWhitespace }) else { continue }
      if query.isEmpty
        || (sheet.searchTerms?[language.rawValue]?[offset] ?? name)
          .precomposedStringWithCompatibilityMapping.range(
            of: query, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: locale) != nil
      {
        offsets.append(offset)
      }
    }
    switch sort {
    case .original: return offsets.map { sheet.ids[$0] }
    case .name:
      let keys = offsets.map { ResultSort.nameKey(names[$0]) }
      let positions = try offsets.indices.sorted { lhs, rhs in
        try Task.checkCancellation()
        let comparison = ResultSort.compare(keys[lhs], keys[rhs], locale: locale)
        return comparison == .orderedSame
          ? sheet.ids[offsets[lhs]] > sheet.ids[offsets[rhs]] : comparison == .orderedAscending
      }
      return positions.map { sheet.ids[offsets[$0]] }
    case .level:
      return try offsets.sorted { lhs, rhs in
        try Task.checkCancellation()
        let left = sheet.levels?[lhs] ?? -1
        let right = sheet.levels?[rhs] ?? -1
        return left == right ? sheet.ids[lhs] > sheet.ids[rhs] : left > right
      }.map { sheet.ids[$0] }
    }
  }

  /// `before` is exclusive. Gaps and an ID from an older release are both safe.
  public func page(kind: EntityKind, before: Int?, limit: Int = 50) -> [Int] {
    guard let ids = rows[kind.rawValue]?.ids, limit > 0 else { return [] }
    var lower = 0
    var upper = ids.count
    if let before {
      while lower < upper {
        let middle = lower + (upper - lower) / 2
        if ids[middle] >= before { lower = middle + 1 } else { upper = middle }
      }
    }
    return Array(ids[lower..<min(ids.count, lower + min(limit, ids.count))])
  }
}

/// A small, bounded cache avoids repeating full-category collation on every page.
actor GameIndexQueries {
  private struct Key: Hashable {
    let kind: EntityKind
    let language: GameLanguage
    let sort: ResultSort
    let text: String
  }
  private let index: GameDataIndex?
  private var cached: [Key: [Int]] = [:]
  private var recent: [Key] = []
  init(index: GameDataIndex?) { self.index = index }

  func ids(kind: EntityKind, language: GameLanguage, sort: ResultSort, text: String) throws -> [Int]
  {
    try Task.checkCancellation()
    let key = Key(kind: kind, language: language, sort: sort, text: text)
    if let value = cached[key] {
      recent.removeAll { $0 == key }
      recent.append(key)
      return value
    }
    let index = try index ?? GameDataIndex.bundled.get()
    let value = try index.matchingIDs(kind: kind, language: language, sort: sort, text: text)
    cached[key] = value
    recent.append(key)
    while recent.count > 12 { cached[recent.removeFirst()] = nil }
    return value
  }
}
