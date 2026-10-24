import Foundation

public struct GameMap: Identifiable, Sendable, Equatable {
  public let id: Int
  public let assetID: String
  public let name: String
  public let region: String
  public let floor: String
  public let markerRange: Int
  public let sizeFactor: Int?
  public let loadingImagePath: String?
  public let thumbnailPath: String
  public var summary: EntitySummary {
    EntitySummary(
      id: EntityID(kind: .map, row: id), name: title,
      category: region.isEmpty || region == "???" ? assetID : region, iconPath: thumbnailPath)
  }
  public static let fallbackThumbnailPath = "ui/icon/060000/060453_hr1.tex"
  public var title: String { floor.isEmpty ? name : "\(name) · \(floor)" }

  public init?(row: SheetRow) {
    self.init(row: row, teleportIcons: [:])
  }

  public init?(row: SheetRow, teleportIcons: [Int: String]) {
    guard let asset = row["Id"].string, Self.isValidAssetID(asset),
      let name = row["PlaceName"].referenceName, !name.isEmpty
    else { return nil }
    id = row.rowID
    assetID = asset
    self.name = name
    region = row["PlaceNameRegion"].referenceName ?? ""
    floor = row["PlaceNameSub"].referenceName ?? ""
    markerRange = max(0, row["MapMarkerRange"].integer ?? 0)
    sizeFactor = row["SizeFactor"].integer.flatMap { (1...65_535).contains($0) ? $0 : nil }
    // Town rows share identifiers with city aetheryte networks; absent emblems
    // use the same crystal as the Teleport menu.
    let group = row["TerritoryType"]["fields"]["Aetheryte"]["fields"]["AethernetGroup"].integer ?? 0
    thumbnailPath = teleportIcons[group] ?? Self.fallbackThumbnailPath
    let loading = row["TerritoryType"]["fields"]["LoadingImage"]
    if (loading["value"].integer ?? 0) > 0,
      let file = loading["fields"]["FileName"].string, file.utf8.count <= 100,
      file.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    {
      loadingImagePath = "ui/loadingimage/\(file)_hr1.tex"
    } else {
      loadingImagePath = nil
    }
  }

  public static func isValidAssetID(_ id: String) -> Bool {
    id.utf8.count <= 80
      && id.range(of: #"^[A-Za-z0-9]+/[0-9]{2}$"#, options: .regularExpression) != nil
  }
}

public struct GameMapCoordinates: Sendable, Equatable {
  public let x: Double
  public let y: Double

  public init?(normalizedX: Double, normalizedY: Double, sizeFactor: Int?) {
    guard let sizeFactor, (1...65_535).contains(sizeFactor),
      normalizedX.isFinite, normalizedY.isFinite,
      (0...1).contains(normalizedX), (0...1).contains(normalizedY)
    else { return nil }
    // Texture pixels already include the map's world offset. Use the game's
    // pixel / SizeFactor * 2 + 1 conversion, then truncate to a tenth.
    // https://github.com/xivapi/ffxiv-datamining/blob/master/docs/MapCoordinates.md
    func coordinate(_ value: Double) -> Double {
      ((value * 4096 / Double(sizeFactor) + 1) * 10).rounded(.towardZero) / 10
    }
    x = coordinate(normalizedX)
    y = coordinate(normalizedY)
  }

  public func formatted() -> String {
    let style = FloatingPointFormatStyle<Double>.number.locale(Locale(identifier: "en_US"))
      .precision(.fractionLength(1)).grouping(.never)
    return "X: \(x.formatted(style))  Y: \(y.formatted(style))"
  }
}

public struct GameMapMarker: Identifiable, Sendable, Equatable {
  public enum LabelPlacement: Int, Sendable {
    case hidden = 0
    case left = 1
    case right = 2
    case below = 3
    case above = 4
  }
  public let id: String
  public let name: String
  public let iconPath: String?
  public let labelPlacement: LabelPlacement
  public let isMapLink: Bool
  /// Normalized coordinates in the game's 2048 × 2048 map canvas, top-left origin.
  public let x: Double
  public let y: Double
  public var isNamed: Bool { !name.isEmpty }
  public var title: String { isNamed ? name.replacingOccurrences(of: "\n", with: " ") : "Map icon" }

  init?(row: MapMarkerRow) {
    let fields = row.fields
    let name = fields["PlaceNameSubtext"]?.referenceName ?? ""
    let icon = fields["Icon"] ?? .null
    let placement = LabelPlacement(rawValue: fields["SubtextOrientation"]?.integer ?? 2) ?? .hidden
    guard let x = fields["X"]?.integer, let y = fields["Y"]?.integer,
      (0...2048).contains(x), (0...2048).contains(y),
      (!name.isEmpty && placement != .hidden) || (icon["id"].integer ?? 0) > 0
    else { return nil }
    id = "\(row.rowID):\(row.subrowID)"
    self.name = name
    labelPlacement = placement
    isMapLink = fields["DataType"]?.integer == 1
    iconPath = (icon["id"].integer ?? 0) > 0 ? icon.iconPath : nil
    self.x = Double(x) / 2048
    self.y = Double(y) / 2048
  }
}

struct MapMarkerRow: Decodable, Sendable {
  let rowID: Int
  let subrowID: Int
  let fields: [String: FieldValue]
  enum CodingKeys: String, CodingKey {
    case rowID = "row_id"
    case subrowID = "subrow_id"
    case fields
  }
}

public struct MapPage: Sendable {
  public let maps: [GameMap]
  public let after: Int?
  public let isStale: Bool
  public init(maps: [GameMap], after: Int? = nil, isStale: Bool) {
    self.maps = maps
    self.after = after
    self.isStale = isStale
  }
}

public struct MapRecord: Sendable {
  public let map: GameMap
  public let isStale: Bool
}

public struct MapContent: Sendable {
  public let image: Data
  public let markers: [GameMapMarker]
  public let isStale: Bool
  public let markerError: String?
}

public struct MapLayers: Sendable, Equatable {
  public var landmarks = true
  public var otherIcons = true
  public var labels = true
  public init() {}
  public func shows(_ marker: GameMapMarker, zoom: Double) -> Bool {
    marker.isNamed ? landmarks && (marker.iconPath != nil || labels) : otherIcons && zoom >= 1.75
  }
  public func showsLabel(_ marker: GameMapMarker, zoom: Double) -> Bool {
    labels && marker.isNamed && marker.labelPlacement != .hidden
      && (marker.iconPath == nil || zoom >= 2.5)
  }
}
