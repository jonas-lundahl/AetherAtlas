#if DEBUG
  import Foundation

  struct UITestReleaseChecker: AppReleaseChecking {
    func latestRelease() async throws -> AppRelease {
      AppRelease(tag: "20991231.2359")!
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
        level: 10)
    }
    private func recipe(_ language: GameLanguage) -> EntitySummary {
      EntitySummary(
        id: EntityID(kind: .recipe, row: 2), name: potionName(language), category: "Test alchemy",
        level: 12)
    }
    private var action: EntitySummary {
      EntitySummary(id: EntityID(kind: .action, row: 3), name: "Fixture Sprint", category: "System")
    }
    private func entry(for kind: EntityKind, language: GameLanguage) -> EntitySummary {
      kind == .action ? action : kind == .recipe ? recipe(language) : item(language)
    }
    func search(kind: EntityKind, text: String, cursor: String?, language: GameLanguage)
      async throws -> EntityPage
    {
      EntityPage(
        entries: text.localizedCaseInsensitiveContains("fixture")
          || entry(for: kind, language: language).name.localizedCaseInsensitiveContains(text)
          ? [entry(for: kind, language: language)] : [])
    }
    func browse(kind: EntityKind, after: Int?, language: GameLanguage) async throws -> EntityPage {
      EntityPage(entries: [entry(for: kind, language: language)])
    }
    func recipes(item: Int, cursor: String?, language: GameLanguage) async throws -> EntityPage {
      EntityPage(entries: item == 1 ? [recipe(language)] : [])
    }
    func detail(_ id: EntityID, refresh: Bool, language: GameLanguage) async throws -> EntityDetail
    {
      if id.kind == .action {
        return EntityDetail(
          entity: action,
          row: SheetRow(
            rowID: id.row, fields: ["Name": .string("Fixture Sprint")],
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
          "AmountIngredient": .array([.number(2)]), "AmountResult": .number(1),
        ]
      } else {
        fields = [
          "Name": .string(id.row == 1 ? potionName(language) : waterName(language)),
          "Description": .string("Deterministic UI test description."), "LevelEquip": .number(1),
          "StackSize": .number(99),
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
