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
    private var action: EntitySummary {
      EntitySummary(id: EntityID(kind: .action, row: 3), name: "Fixture Sprint", category: "System")
    }
    private func entry(for kind: EntityKind) -> EntitySummary {
      kind == .action ? action : kind == .recipe ? recipe : item
    }
    func search(kind: EntityKind, text: String, cursor: String?) async throws -> EntityPage {
      EntityPage(
        entries: text.localizedCaseInsensitiveContains("fixture")
          ? [entry(for: kind)] : [])
    }
    func browse(kind: EntityKind, after: Int?) async throws -> EntityPage {
      EntityPage(entries: [entry(for: kind)])
    }
    func recipes(item: Int, cursor: String?) async throws -> EntityPage {
      EntityPage(entries: item == 1 ? [recipe] : [])
    }
    func detail(_ id: EntityID, refresh: Bool) async throws -> EntityDetail {
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
