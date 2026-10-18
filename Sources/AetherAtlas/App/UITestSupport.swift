#if DEBUG
  import Foundation

  struct UITestReleaseChecker: AppReleaseChecking {
    func latestRelease() async throws -> AppRelease {
      AppRelease(tag: "20991231.2359")!
    }
  }

  struct UITestIconTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      throw URLError(.resourceUnavailable)
    }
  }

  /// Explicit Debug-only test seam. Release builds contain neither the fixtures nor this switch.
  struct UITestRepository: GameRepository {
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
      let entries = orderedEntries(kind: kind, language: language, sort: sort).filter {
        $0.name.range(
          of: text, options: [.caseInsensitive, .diacriticInsensitive], locale: language.locale)
          != nil
      }
      let page = page(entries, after: cursor.flatMap(Int.init))
      return EntityPage(entries: page.entries, next: page.after.map(String.init))
    }
    func browse(kind: EntityKind, after: Int?, language: GameLanguage, sort: ResultSort)
      async throws -> EntityPage
    {
      page(orderedEntries(kind: kind, language: language, sort: sort), after: after)
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
#endif
