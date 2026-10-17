#if DEBUG
  import Foundation

  /// Explicit Debug-only test seam. Release builds contain neither the fixtures nor this switch.
  struct UITestRepository: GameRepository {
    private var item: EntitySummary {
      EntitySummary(
        id: EntityID(kind: .item, row: 1), name: "Fixture Potion", category: "Test medicine",
        level: 10)
    }
    private var recipe: EntitySummary {
      EntitySummary(
        id: EntityID(kind: .recipe, row: 2), name: "Fixture Potion", category: "Test alchemy",
        level: 12)
    }
    func search(kind: EntityKind, text: String, cursor: String?) async throws -> EntityPage {
      EntityPage(
        entries: text.localizedCaseInsensitiveContains("fixture")
          ? [kind == .recipe ? recipe : item] : [])
    }
    func browse(kind: EntityKind, after: Int?) async throws -> EntityPage {
      EntityPage(entries: [kind == .recipe ? recipe : item])
    }
    func recipes(item: Int, cursor: String?) async throws -> EntityPage {
      EntityPage(entries: item == 1 ? [recipe] : [])
    }
    func detail(_ id: EntityID, refresh: Bool) async throws -> EntityDetail {
      let fields: [String: FieldValue]
      if id.kind == .recipe {
        fields = [
          "ItemResult": reference(row: 1, name: "Fixture Potion"),
          "Ingredient": .array([reference(row: 3, name: "Fixture Water")]),
          "AmountIngredient": .array([.number(2)]), "AmountResult": .number(1),
        ]
      } else {
        fields = [
          "Name": .string(id.row == 1 ? "Fixture Potion" : "Fixture Water"),
          "Description": .string("Deterministic UI test description."), "LevelEquip": .number(1),
          "StackSize": .number(99),
        ]
      }
      return EntityDetail(
        entity: EntitySummary(
          id: id, name: id.kind == .recipe || id.row == 1 ? "Fixture Potion" : "Fixture Water"),
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
