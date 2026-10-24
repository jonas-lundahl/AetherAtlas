#if DEBUG
  import Foundation

  struct UITestMapRepository: MapRepository {
    private let pagination = UITestPagination()
    static let artwork = Data(
      base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAEAAAAAkCAYAAAA5DDySAAAAoklEQVR4nOXG4WYCAACF0e/p7pMkmSSTZCbJJJMkM8kkmUwvue57fD8OhwzW/2Zk2IiRUSNGXhoxMm7EyKQRI9NGjLw2YmTWiJF5I0YWjRh5a8TIeyNGlo0YWTViZN2IkY9GjGwaMbJtxMhnI0Z2jRjZN2Lk0IiRYyNGvhox8t2IkVMjRs6NGPlpxMilESPXRozcGjHy24iReyNG/hox8mjEnkNVvy18j3IdAAAAAElFTkSuQmCC"
    )!
    private func maps(language: GameLanguage) -> [GameMap] {
      let names: [String]
      switch language {
      case .english: names = ["New Gridania", "Old Gridania"]
      case .german: names = ["Neu-Gridania", "Alt-Gridania"]
      case .french: names = ["Nouvelle Gridania", "Vieille Gridania"]
      case .japanese: names = ["グリダニア：新市街", "グリダニア：旧市街"]
      }
      let count = ProcessInfo.processInfo.environment["AETHER_UI_MAP_PAGINATION"] == "1" ? 121 : 2
      return (0..<count).map { offset in
        let name = count == 2 ? names[offset] : String(format: "Fixture Map %03d", offset + 2)
        return GameMap(
          row: SheetRow(
            rowID: offset + 2,
            fields: [
              "Id": .string("f1t\(offset + 1)/00"), "SizeFactor": .number(200),
              "MapMarkerRange": .number(Double(offset + 3)),
              "PlaceName": .object(["fields": .object(["Name": .string(name)])]),
              "PlaceNameRegion": .object([
                "fields": .object(["Name": .string("The Black Shroud")])
              ]),
              "TerritoryType": .object([
                "fields": .object([
                  "LoadingImage": .object([
                    "value": .number(1), "fields": .object(["FileName": .string("fixture")]),
                  ])
                ])
              ]),
            ]))!
      }
    }
    func page(text: String, after: Int?, language: GameLanguage, sort: ResultSort, refresh: Bool)
      async throws -> MapPage
    {
      if after != nil { try await pagination.loadNextPage() }
      let maps = maps(language: language).filter {
        text.isEmpty
          || "\($0.title) \($0.region) \($0.assetID) \($0.id)".localizedStandardContains(text)
      }.sorted {
        if sort == .original { return $0.id > $1.id }
        return ResultSort.compare($0.title, $1.title, locale: language.locale) == .orderedAscending
      }
      let start = after.flatMap { id in maps.firstIndex { $0.id == id }.map { $0 + 1 } } ?? 0
      let end = min(maps.count, start + 50)
      return MapPage(
        maps: Array(maps[start..<end]), after: end < maps.count ? maps[end - 1].id : nil,
        isStale: false)
    }
    func mapDetail(id: Int, language: GameLanguage, refresh: Bool) async throws -> MapRecord {
      guard let map = maps(language: language).first(where: { $0.id == id }) else {
        throw APIError.invalidResponse
      }
      return MapRecord(map: map, isStale: false)
    }
    func content(for map: GameMap, language: GameLanguage, refresh: Bool) async throws -> MapContent
    {
      let rows = [
        MapMarkerRow(
          rowID: map.markerRange, subrowID: 0,
          fields: [
            "X": .number(1024), "Y": .number(1024),
            "SubtextOrientation": .number(2),
            "Icon": .object(["id": .number(60442)]),
            "PlaceNameSubtext": .object(["fields": .object(["Name": .string("Fixture landmark")])]),
          ]),
        MapMarkerRow(
          rowID: map.markerRange, subrowID: 1,
          fields: [
            "X": .number(1300), "Y": .number(1100), "Icon": .object(["id": .number(1)]),
          ]),
      ]
      return MapContent(
        image: Self.artwork, markers: rows.compactMap(GameMapMarker.init(row:)),
        isStale: false, markerError: nil)
    }
  }

  struct UITestReleaseChecker: AppReleaseChecking {
    func latestRelease() async throws -> AppRelease {
      AppRelease(tag: "20991231.2359")!
    }
  }

  struct UITestIconTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      let path = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
        .queryItems?.first { $0.name == "path" }?.value
      if path == "ui/loadingimage/fixture_hr1.tex" || path == "ui/icon/060000/060442_hr1.tex" {
        return (
          UITestMapRepository.artwork,
          HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
      }
      throw URLError(.resourceUnavailable)
    }
  }

  /// Explicit Debug-only test seam. Release builds contain neither the fixtures nor this switch.
  struct UITestRepository: GameRepository {
    private let maps = UITestMapRepository()
    private let pagination = UITestPagination()
    private func potionName(_ language: GameLanguage) -> String {
      switch language {
      case .english: "Fixture Potion"
      case .german: "Fixture Heiltrank"
      case .french: "Fixture Potion française"
      case .japanese: "フィクスチャ・ポーション"
      }
    }
    private func waterName(_ language: GameLanguage) -> String {
      switch language {
      case .english: "Fixture Water"
      case .german: "Fixture Wasser"
      case .french: "Fixture Eau"
      case .japanese: "フィクスチャ・ウォーター"
      }
    }
    private func item(_ language: GameLanguage) -> EntitySummary {
      EntitySummary(
        id: EntityID(kind: .item, row: 1), name: potionName(language), category: "Test medicine",
        level: 1234)
    }
    private func entries(for kind: EntityKind, language: GameLanguage) -> [EntitySummary] {
      guard kind == .item else { return [entry(for: kind, language: language)] }
      return [
        item(language),
        EntitySummary(
          id: EntityID(kind: .item, row: 3), name: waterName(language), category: "Test reagent",
          level: 5),
      ]
    }
    private func recipe(_ language: GameLanguage) -> EntitySummary {
      EntitySummary(
        id: EntityID(kind: .recipe, row: 2), name: potionName(language), category: "Test alchemy",
        level: 12)
    }
    private var action: EntitySummary {
      EntitySummary(id: EntityID(kind: .action, row: 3), name: "Fixture Sprint", category: "System")
    }
    private var questName: String {
      ProcessInfo.processInfo.environment["AETHER_UI_SYMBOLS"] == "1"
        ? "\u{e0bf} Fixture Quest" : "Fixture Quest"
    }
    private var questRow: SheetRow {
      SheetRow(
        rowID: 4,
        fields: [
          "Name": .string(questName), "ClassJobLevel": .array([.number(10), .number(0)]),
          "GilReward": .number(2493),
          "JournalGenre": .object(["fields": .object(["Name": .string("Botanist Quests")])]),
          "Expansion": .object(["fields": .object(["Name": .string("A Realm Reborn")])]),
          "PlaceName": .object(["fields": .object(["Name": .string("Gridania")])]),
          "Reward": .array([reference(row: 1, name: "Fixture Potion")]),
          "ItemCountReward": .array([.number(1250)]),
          "IssuerStart": .object([
            "sheet": .string("ENpcResident"), "row_id": .number(5),
            "fields": .object(["Singular": .string("Fixture Guildmaster")]),
          ]),
        ])
    }
    private func entry(for kind: EntityKind, language: GameLanguage) -> EntitySummary {
      if kind == .quest {
        return EntitySummary(
          id: EntityID(kind: .quest, row: 4), name: questName, category: "Botanist Quests",
          level: 10)
      }
      return kind == .action ? action : kind == .recipe ? recipe(language) : item(language)
    }
    func search(
      kind: EntityKind, text: String, cursor: String?, language: GameLanguage, sort: ResultSort
    )
      async throws -> EntityPage
    {
      if kind == .map {
        let page = try await maps.page(
          text: text, after: cursor.flatMap(Int.init), language: language, sort: sort,
          refresh: false)
        return EntityPage(entries: page.maps.map(\.summary), next: page.after.map(String.init))
      }
      let entries = orderedEntries(kind: kind, language: language, sort: sort).filter {
        $0.name.range(
          of: text, options: [.caseInsensitive, .diacriticInsensitive], locale: language.locale)
          != nil
      }
      if cursor != nil { try await pagination.loadNextPage() }
      let page = page(entries, after: cursor.flatMap(Int.init))
      return EntityPage(entries: page.entries, next: page.after.map(String.init))
    }
    func browse(kind: EntityKind, after: Int?, language: GameLanguage, sort: ResultSort)
      async throws -> EntityPage
    {
      if kind == .map {
        let page = try await maps.page(
          text: "", after: after, language: language, sort: sort, refresh: false)
        return EntityPage(entries: page.maps.map(\.summary), after: page.after)
      }
      if after != nil { try await pagination.loadNextPage() }
      return page(orderedEntries(kind: kind, language: language, sort: sort), after: after)
    }
    private func orderedEntries(kind: EntityKind, language: GameLanguage, sort: ResultSort)
      -> [EntitySummary]
    {
      let all =
        ProcessInfo.processInfo.environment["AETHER_UI_SORTING"] == "1" && kind == .item
        ? sortingEntries(language) : entries(for: kind, language: language)
      return sort.ordered(all.sorted { $0.id.row > $1.id.row }, language: language)
    }
    private func sortingEntries(_ language: GameLanguage) -> [EntitySummary] {
      (1...61).map { id in
        let name =
          language == .german
          ? id == 61 ? "Aal im Muster" : id == 1 ? "Zebra im Muster" : "Muster \(id)"
          : String(format: "Fixture Item %03d", id)
        return EntitySummary(
          id: EntityID(kind: .item, row: id), name: name,
          category: "Test sorting", level: id == 2 ? 9_999 : id)
      }
    }
    private func page(_ entries: [EntitySummary], after: Int?) -> EntityPage {
      let start = after.flatMap { id in entries.firstIndex { $0.id.row == id }.map { $0 + 1 } } ?? 0
      let end = min(entries.count, start + 50)
      return EntityPage(
        entries: Array(entries[start..<end]),
        after: end < entries.count ? entries[end - 1].id.row : nil)
    }
    func recipes(item: Int, cursor: String?, language: GameLanguage) async throws -> EntityPage {
      EntityPage(entries: item == 1 ? [recipe(language)] : [])
    }
    func detail(_ id: EntityID, refresh: Bool, language: GameLanguage) async throws -> EntityDetail
    {
      if id.kind == .item, ProcessInfo.processInfo.environment["AETHER_UI_SORTING"] == "1",
        let entity = sortingEntries(language).first(where: { $0.id == id })
      {
        return EntityDetail(
          entity: entity, row: SheetRow(rowID: id.row, fields: ["Name": .string(entity.name)]),
          schema: "test", version: "test", isStale: false)
      }
      if id.kind == .quest {
        let journal = QuestJournal(rows: [
          SheetRow(
            rowID: 1,
            fields: [
              "unknown0": .string("TEXT_FIXTURE_SEQ_01"),
              "unknown4": .string("Learn the ways of the botanist from the guildmaster."),
            ]),
          SheetRow(
            rowID: 24,
            fields: [
              "unknown0": .string("TEXT_FIXTURE_TODO_00"),
              "unknown4": .string("Speak with the guildmaster."),
            ]),
        ])
        return EntityDetail(
          entity: entry(for: .quest, language: language), row: questRow, schema: "test",
          version: "test", isStale: false, questJournal: journal, questExperience: 224640)
      }
      if id.kind == .action {
        return EntityDetail(
          entity: action,
          row: SheetRow(
            rowID: id.row,
            fields: [
              "Name": .string("Fixture Sprint"), "Cast100ms": .number(25),
              "Recast100ms": .number(600), "Range": .number(25),
            ],
            transient: [
              "Description": .string("Increases movement speed.\nAdditional Effect: Grants Jog."),
              "Description@as(html)": .string(
                #"Increases movement speed.<br><span style="color:rgba(0,204,34,1);">Additional Effect:</span> Grants <span style="color:rgba(255,255,102,1);">Jog</span>."#
              ),
            ]), schema: "test", version: "test", isStale: false)
      }
      let fields: [String: FieldValue]
      if id.kind == .recipe {
        fields = [
          "ItemResult": reference(row: 1, name: potionName(language)),
          "Ingredient": .array([reference(row: 3, name: waterName(language))]),
          "AmountIngredient": .array([.number(1250)]), "AmountResult": .number(1000),
          "RequiredCraftsmanship": .number(1234), "RequiredControl": .number(2345),
        ]
      } else {
        fields = [
          "Name": .string(id.row == 1 ? potionName(language) : waterName(language)),
          "Description": .string("Deterministic UI test description."), "LevelEquip": .number(1),
          "StackSize": .number(9999), "PriceMid": .number(1_234_567),
          "PriceLow": .number(1234), "DamagePhys": .number(1234),
        ]
      }
      return EntityDetail(
        entity: EntitySummary(
          id: id,
          name: id.kind == .recipe || id.row == 1 ? potionName(language) : waterName(language)),
        row: SheetRow(rowID: id.row, fields: fields), schema: "test", version: "test",
        isStale: false)
    }
    private func reference(row: Int, name: String) -> FieldValue {
      .object([
        "sheet": .string("Item"), "row_id": .number(Double(row)),
        "fields": .object(["Name": .string(name)]),
      ])
    }
  }
  private actor UITestPagination {
    private var hasFailed = false

    func loadNextPage() async throws {
      try await Task.sleep(for: .milliseconds(250))
      if ProcessInfo.processInfo.environment["AETHER_UI_PAGINATION_FAILURE"] == "1", !hasFailed {
        hasFailed = true
        throw URLError(.notConnectedToInternet)
      }
    }
  }
#endif
