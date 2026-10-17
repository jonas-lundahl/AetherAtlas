import Foundation

public enum EntityKind: String, Codable, CaseIterable, Sendable, Identifiable {
  case item = "Item"
  case recipe = "Recipe"
  case quest = "Quest"
  case npc = "ENpcResident"
  case action = "Action"
  public var id: String { rawValue }
  public var title: String {
    switch self {
    case .item: "Items"
    case .recipe: "Recipes"
    case .quest: "Quests"
    case .npc: "NPCs"
    case .action: "Actions"
    }
  }
  public var singular: String {
    switch self {
    case .item: "Item"
    case .recipe: "Recipe"
    case .quest: "Quest"
    case .npc: "NPC"
    case .action: "Action"
    }
  }
  public var symbol: String {
    switch self {
    case .item: "shippingbox"
    case .recipe: "hammer"
    case .quest: "text.book.closed"
    case .npc: "person.2"
    case .action: "sparkles"
    }
  }
  public var nameField: String {
    self == .recipe ? "ItemResult.Name" : self == .npc ? "Singular" : "Name"
  }
  public var summaryFields: String {
    switch self {
    case .item: "Name,Icon,LevelItem@as(raw),LevelEquip,ItemUICategory.Name"
    case .recipe:
      "ItemResult.Name,ItemResult.Icon,CraftType.Name,RecipeLevelTable.ClassJobLevel,AmountResult"
    case .quest: "Name,Icon,ClassJobLevel,Expansion.Name,JournalGenre.Name"
    case .npc: "Singular,Title"
    case .action: "Name,Icon,ClassJobLevel,ClassJob.Name,ActionCategory.Name"
    }
  }
  public var detailFields: String {
    switch self {
    case .item:
      summaryFields
        + ",Description,ItemSearchCategory.Name,ClassJobCategory.Name,EquipSlotCategory,BaseParam[].Name,BaseParamValue,DamagePhys,DamageMag,DefensePhys,DefenseMag,StackSize,PriceMid,PriceLow,CanBeHq,IsUntradable,IsUnique,MateriaSlotCount"
    case .recipe:
      summaryFields
        + ",Ingredient[].Name,Ingredient[].Icon,AmountIngredient,CanHq,RequiredCraftsmanship,RequiredControl,IsExpert"
    case .quest: summaryFields + ",IssuerStart.Singular,PlaceName.Name"
    case .npc: summaryFields
    case .action: summaryFields + ",Cast100ms,Recast100ms,Range"
    }
  }
}

public struct EntityID: Hashable, Codable, Sendable, CustomStringConvertible {
  public let kind: EntityKind
  public let row: Int
  public init(kind: EntityKind, row: Int) {
    self.kind = kind
    self.row = row
  }
  public var description: String { "\(kind.rawValue):\(row)" }
}

/// Only sheet fields are dynamic; response envelopes and source identities remain typed.
public indirect enum FieldValue: Codable, Sendable, Equatable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case object([String: FieldValue])
  case array([FieldValue])
  case null
  public init(from decoder: any Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() {
      self = .null
    } else if let b = try? c.decode(Bool.self) {
      self = .bool(b)
    } else if let n = try? c.decode(Double.self) {
      self = .number(n)
    } else if let s = try? c.decode(String.self) {
      self = .string(s)
    } else if let a = try? c.decode([FieldValue].self) {
      self = .array(a)
    } else {
      self = .object(try c.decode([String: FieldValue].self))
    }
  }
  public func encode(to encoder: any Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .string(let v): try c.encode(v)
    case .number(let v): try c.encode(v)
    case .bool(let v): try c.encode(v)
    case .object(let v): try c.encode(v)
    case .array(let v): try c.encode(v)
    case .null: try c.encodeNil()
    }
  }
  public subscript(_ key: String) -> FieldValue {
    if case .object(let o) = self { o[key] ?? .null } else { .null }
  }
  public var string: String? { if case .string(let s) = self { s } else { nil } }
  public var integer: Int? {
    if case .number(let n) = self, n.isFinite, n >= Double(Int.min), n < Double(Int.max) {
      Int(n)
    } else {
      nil
    }
  }
  public var boolean: Bool? { if case .bool(let b) = self { b } else { nil } }
  public var array: [FieldValue] { if case .array(let a) = self { a } else { [] } }
  public var object: [String: FieldValue] { if case .object(let o) = self { o } else { [:] } }
  public var referenceName: String? {
    self["fields"]["Name"].string ?? self["fields"]["Singular"].string
  }
}

public struct SheetRow: Codable, Sendable {
  public let rowID: Int
  public let sheet: String?
  public let fields: [String: FieldValue]
  public let transient: [String: FieldValue]?
  enum CodingKeys: String, CodingKey {
    case rowID = "row_id"
    case sheet, fields, transient
  }
  public init(
    rowID: Int, sheet: String? = nil, fields: [String: FieldValue],
    transient: [String: FieldValue]? = nil
  ) {
    self.rowID = rowID
    self.sheet = sheet
    self.fields = fields
    self.transient = transient
  }
  public subscript(_ key: String) -> FieldValue { fields[key] ?? .null }
  public func summary(kind: EntityKind) -> EntitySummary {
    let result = self["ItemResult"]["fields"]
    let name =
      (kind == .recipe
        ? result["Name"].string : kind == .npc ? self["Singular"].string : self["Name"].string)
      ?? ""
    let icon = kind == .recipe ? result["Icon"] : self["Icon"]
    let category =
      switch kind {
      case .item: self["ItemUICategory"].referenceName
      case .recipe: self["CraftType"].referenceName
      case .quest: self["JournalGenre"].referenceName
      case .npc: self["Title"].string
      case .action: self["ActionCategory"].referenceName
      }
    let level =
      switch kind {
      case .item: self["LevelItem@as(raw)"].integer ?? self["LevelItem"]["value"].integer
      case .recipe: self["RecipeLevelTable"]["fields"]["ClassJobLevel"].integer
      case .quest: self["ClassJobLevel"].array.first?.integer
      case .npc: nil as Int?
      case .action: self["ClassJobLevel"].integer
      }
    return EntitySummary(
      id: EntityID(kind: kind, row: rowID), name: name, category: category,
      iconPath: icon["id"].integer == 0 ? nil : icon["path_hr1"].string ?? icon["path"].string,
      level: level)
  }
}

public struct EntitySummary: Identifiable, Codable, Sendable, Equatable {
  public let id: EntityID
  public var name: String
  public var category: String?
  public var iconPath: String?
  public var level: Int?
  public init(
    id: EntityID, name: String, category: String? = nil, iconPath: String? = nil, level: Int? = nil
  ) {
    self.id = id
    self.name = name
    self.category = category
    self.iconPath = iconPath
    self.level = level
  }
  public var displayName: String { name.isEmpty ? "\(id.kind.singular) #\(id.row)" : name }
}

public struct SearchEnvelope: Decodable, Sendable {
  public let next: String?
  public let results: [SheetRow]
  public let schema: String?
  public let version: String?
}
public struct BrowseEnvelope: Decodable, Sendable {
  public let rows: [SheetRow]
  public let schema: String?
  public let version: String?
}
public struct DetailEnvelope: Decodable, Sendable {
  public let rowID: Int
  public let fields: [String: FieldValue]
  public let transient: [String: FieldValue]?
  public let schema: String?
  public let version: String?
  enum CodingKeys: String, CodingKey {
    case rowID = "row_id"
    case fields, transient, schema, version
  }
  public var row: SheetRow { SheetRow(rowID: rowID, fields: fields, transient: transient) }
}
public struct EntityPage: Sendable {
  public var entries: [EntitySummary]
  public var next: String?
  public var after: Int?
  public var isStale: Bool
  public init(
    entries: [EntitySummary], next: String? = nil, after: Int? = nil, isStale: Bool = false
  ) {
    self.entries = entries
    self.next = next
    self.after = after
    self.isStale = isStale
  }
}
public struct EntityDetail: Sendable {
  public let entity: EntitySummary
  public let row: SheetRow
  public let schema: String?
  public let version: String?
  public let isStale: Bool
}
