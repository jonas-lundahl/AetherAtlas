import Foundation

extension FieldValue {
  public var iconPath: String? {
    guard self["id"].integer != 0 else { return nil }
    return self["path_hr1"].string ?? self["path"].string
  }
}

public enum QuestPresentation {
  /// Journal genre icons identify the class/job even on its introductory unlock quest,
  /// where ClassJobRequired is zero. IDs are independent of the selected language.
  private static let genreJobs = [
    62301: 1, 62302: 2, 62303: 3, 62304: 4, 62305: 5, 62306: 6, 62307: 7,
    62308: 26, 62309: 29, 62310: 8, 62311: 9, 62312: 10, 62313: 11,
    62314: 12, 62315: 13, 62316: 14, 62317: 15, 62318: 16, 62319: 17, 62320: 18,
    62401: 19, 62402: 20, 62403: 21, 62404: 22, 62405: 23, 62406: 24,
    62407: 25, 62408: 27, 62409: 28, 62410: 30, 62411: 31, 62412: 32,
    62413: 33, 62414: 34, 62415: 35, 62416: 36, 62417: 37, 62418: 38,
    62419: 39, 62420: 40, 62421: 41, 62422: 42, 62423: 43,
  ]

  public static func thumbnailPath(for row: SheetRow) -> String {
    if let genreIcon = row["JournalGenre"]["fields"]["Icon"]["id"].integer,
      let job = genreJobs[genreIcon]
    {
      // Dictionary of Icons, set 9: silver class/job emblems.
      return iconPath(62_000 + job)
    }
    let available = row["EventIconType"]["fields"]["NpcIconAvailable"]
    // These fields name the start of a marker range. The base texture contains
    // developer text ("ANNOUNCE QUEST", etc.); offset 1 is available to begin.
    if let base = available["id"].integer, (71_200...71_340).contains(base), base % 20 == 0 {
      return iconPath(base + 1)
    }
    // Hidden announce-only events use a developer placeholder, not a quest marker.
    if available["id"].integer != 60_091, let path = available.iconPath { return path }
    return iconPath(71_221)
  }

  public static func iconPath(_ id: Int) -> String {
    String(format: "ui/icon/%06d/%06d_hr1.tex", id / 1_000 * 1_000, id)
  }

  /// XIVAPI's documented quest XP formula, evaluated at the quest's required level.
  public static func experience(factor: Int, growth: SheetRow) -> Int? {
    guard factor >= 0, let scaled = growth["ScaledQuestXP"].integer, scaled >= 0,
      let modifier = growth["QuestExpModifier"].integer, modifier >= 0
    else { return nil }
    let first = factor.multipliedReportingOverflow(by: scaled)
    let second = first.partialValue.multipliedReportingOverflow(by: modifier)
    guard !first.overflow, !second.overflow else { return nil }
    return second.partialValue / 100
  }
}

public struct QuestJournal: Sendable {
  public let description: GameDescription
  public let objectives: [GameDescription]

  public init(rows: [SheetRow]) {
    func text(_ row: SheetRow) -> GameDescription {
      GameDescription(
        plainText: row["unknown4"].string, html: row["unknown4@as(html)"].string)
    }
    // SEQ_01 is the first accepted journal entry, as displayed in the in-game journal.
    let accepted = rows.first { $0["unknown0"].string?.hasSuffix("_SEQ_01") == true }
    let offer = rows.first { $0["unknown0"].string?.hasSuffix("_SEQ_00") == true }
    description =
      accepted.map(text).flatMap { $0.isEmpty ? nil : $0 }
      ?? offer.map(text) ?? GameDescription(plainText: nil, html: nil)
    objectives = rows.sorted { $0.rowID < $1.rowID }.compactMap { row in
      guard let key = row["unknown0"].string,
        let marker = key.range(of: "_TODO_", options: .backwards),
        key[marker.upperBound...].count == 2,
        key[marker.upperBound...].allSatisfy(\.isNumber),
        // Battle dialogue can also contain TODO; only journal entries start at TEXT_…_TODO_.
        !key.contains("_QIB_")
      else { return nil }
      let value = text(row)
      return value.isEmpty ? nil : value
    }
  }
}
