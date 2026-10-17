import SwiftUI

struct EntityDetailView: View {
  @Bindable var workspace: Workspace
  @State private var refresh = 0
  private var model: DetailModel { workspace.detail }
  var body: some View {
    Group {
      if let current = workspace.navigation.current {
        if let detail = model.detail, detail.entity.id == current.id {
          content(detail)
        } else if let error = model.error {
          ContentUnavailableView {
            Label("Couldn’t open \(current.displayName)", systemImage: "exclamationmark.triangle")
          } description: {
            Text(error)
          } actions: {
            Button("Try Again") { refresh += 1 }
          }
        } else {
          ProgressView("Opening \(current.displayName)…").frame(
            maxWidth: .infinity, maxHeight: .infinity)
        }
      } else {
        ContentUnavailableView {
          Label("A world of details", systemImage: "book.closed")
        } description: {
          Text(
            "Search the archives or browse a category.\nSelect an entity to explore its story, stats, and connections."
          )
        }
      }
    }
    .navigationTitle(workspace.navigation.current?.displayName ?? "Aether Atlas")
    .toolbar {
      if let entity = model.detail?.entity, workspace.navigation.current?.id == entity.id {
        ToolbarItemGroup(placement: .primaryAction) {
          Button(
            workspace.library.isFavorite(entity.id) ? "Remove Favorite" : "Add Favorite",
            systemImage: workspace.library.isFavorite(entity.id) ? "star.fill" : "star"
          ) {
            Task { await workspace.library.toggle(entity) }
          }.help("Toggle favorite (⌘D)")
          Button("Refresh Details", systemImage: "arrow.clockwise") { refresh += 1 }
        }
      }
    }
    .task(id: LoadKey(id: workspace.navigation.current?.id, refresh: refresh)) {
      let id = workspace.navigation.current?.id
      await model.load(id, refresh: refresh > 0)
    }
    .onChange(of: model.detail?.entity) { _, entity in
      if let entity { Task { await workspace.library.record(entity) } }
    }
  }
  private func content(_ detail: EntityDetail) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 18) {
          HStack(spacing: 5) {
            Text("DATABASE")
            Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
            Text(detail.entity.id.kind.title.uppercased())
          }.font(.system(size: 10, weight: .semibold)).tracking(1.1).foregroundStyle(.secondary)
          HStack(alignment: .top, spacing: 16) {
            GameIcon(
              path: detail.entity.iconPath, kind: detail.entity.id.kind, icons: workspace.icons,
              size: 68)
            VStack(alignment: .leading, spacing: 6) {
              Text(detail.entity.displayName).font(
                .system(size: 28, weight: .semibold, design: .serif)
              ).textSelection(.enabled).accessibilityIdentifier("entityDetailName")
              Text(
                detail.entity.category.flatMap { $0.isEmpty ? nil : $0 }
                  ?? detail.entity.id.kind.singular
              ).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
          }
        }
        if detail.isStale {
          Label("Saved copy · couldn’t reach XIVAPI", systemImage: "wifi.slash").font(.caption)
            .foregroundStyle(.secondary)
        }
        switch detail.entity.id.kind {
        case .item: itemSections(detail)
        case .recipe: recipeSections(detail)
        case .action: actionSections(detail)
        case .quest: questSections(detail)
        case .npc: npcSections(detail)
        }
        Divider()
        DisclosureGroup("Source information") {
          VStack(alignment: .leading, spacing: 8) {
            MetadataRow(label: "Sheet / row", value: detail.entity.id.description)
            if let version = detail.version { MetadataRow(label: "Game version", value: version) }
            if let schema = detail.schema { MetadataRow(label: "Schema", value: schema) }
            if let url = try? APIRequest.detail(detail.entity.id).url() {
              Link("View source on XIVAPI", destination: url).font(.caption)
            }
          }.padding(.top, 10).textSelection(.enabled)
        }.font(.caption).foregroundStyle(.secondary)
        Text(
          "FINAL FANTASY XIV © SQUARE ENIX\nIndependent community tool · Data provided by XIVAPI"
        )
        .font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 8)
      }.padding(28).frame(maxWidth: 820, alignment: .leading).frame(
        maxWidth: .infinity, alignment: .leading)
    }.accessibilityIdentifier("entityDetail").id(detail.entity.id)
  }
  @ViewBuilder private func itemSections(_ detail: EntityDetail) -> some View {
    let row = detail.row
    HStack(spacing: 0) {
      Metric(label: "ITEM LEVEL", value: detail.entity.level.map(String.init) ?? "—")
      Metric(label: "REQUIRED LEVEL", value: row["LevelEquip"].integer.map(String.init) ?? "—")
      Metric(label: "STACK SIZE", value: row["StackSize"].integer?.formatted() ?? "—")
    }.padding(.vertical, 15).background(
      .quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    if !detail.description.isEmpty {
      GameDescriptionText(description: detail.description)
    }
    DetailSection("Item information") {
      if let jobs = row["ClassJobCategory"].referenceName, !jobs.isEmpty {
        MetadataRow(label: "Classes & jobs", value: jobs)
      }
      if let slots = equipmentSlots(row["EquipSlotCategory"]) {
        MetadataRow(label: "Equip slot", value: slots)
      }
      if let category = row["ItemSearchCategory"].referenceName, !category.isEmpty {
        MetadataRow(label: "Search category", value: category)
      }
      if let hq = row["CanBeHq"].boolean {
        MetadataRow(label: "High quality", value: hq ? "Available" : "Unavailable")
      }
      if let value = row["IsUntradable"].boolean {
        MetadataRow(label: "Trading", value: value ? "Untradable" : "Tradable")
      }
      if row["IsUnique"].boolean == true { MetadataRow(label: "Unique", value: "Yes") }
      if let slots = row["MateriaSlotCount"].integer, slots > 0 {
        MetadataRow(label: "Materia slots", value: String(slots))
      }
    }
    let stats = itemStats(row)
    if !stats.isEmpty {
      DetailSection("Attributes") {
        ForEach(stats, id: \.0) { name, value in MetadataRow(label: name, value: value) }
      }
    }
    DetailSection("Vendor values") {
      if let value = row["PriceMid"].integer {
        MetadataRow(label: "Base purchase value", value: "\(value.formatted()) gil")
      }
      if let value = row["PriceLow"].integer {
        MetadataRow(label: "Base sale value", value: "\(value.formatted()) gil")
      }
      Text(
        "Reference values from the item sheet. Individual shops and availability are not listed."
      ).font(.caption).foregroundStyle(.secondary)
    }
    DetailSection("Crafting recipes") {
      if model.recipesLoading && model.recipes.isEmpty { ProgressView().controlSize(.small) }
      ForEach(model.recipes) { recipe in
        entityLink(recipe, trailing: recipe.level.map { "Lv. \($0)" })
      }
      if let error = model.recipesError {
        Text(error).font(.caption).foregroundStyle(.secondary)
        Button("Retry Recipes") {
          Task {
            await model.loadRecipes(item: detail.entity.id.row, more: model.recipesNext != nil)
          }
        }
      } else if !model.recipesLoading && model.recipes.isEmpty {
        Text("No producing recipes found in the recipe sheet.").font(.callout).foregroundStyle(
          .secondary)
      }
      if model.recipesStale {
        Label("Cached recipes", systemImage: "wifi.slash").font(.caption).foregroundStyle(
          .secondary)
      }
      if model.recipesNext != nil {
        Button("More Recipes") {
          Task { await model.loadRecipes(item: detail.entity.id.row, more: true) }
        }.disabled(model.recipesLoading)
      }
    }
  }
  @ViewBuilder private func recipeSections(_ detail: EntityDetail) -> some View {
    let row = detail.row
    DetailSection("Crafting") {
      if let craft = row["CraftType"].referenceName {
        MetadataRow(label: "Discipline", value: craft)
      }
      if let level = detail.entity.level {
        MetadataRow(label: "Crafter level", value: String(level))
      }
      if let amount = row["AmountResult"].integer {
        MetadataRow(label: "Yield", value: String(amount))
      }
      if let value = row["CanHq"].boolean {
        MetadataRow(label: "High quality", value: value ? "Available" : "Unavailable")
      }
      forPositive(row, field: "RequiredCraftsmanship", label: "Craftsmanship required")
      forPositive(row, field: "RequiredControl", label: "Control required")
      if row["IsExpert"].boolean == true { MetadataRow(label: "Expert recipe", value: "Yes") }
    }
    if let output = linkedEntity(row["ItemResult"]) {
      DetailSection("Produces") {
        entityLink(output, trailing: row["AmountResult"].integer.map { "×\($0)" })
      }
    }
    DetailSection("Ingredients & crystals") {
      let ingredients = row["Ingredient"].array
      let amounts = row["AmountIngredient"].array
      ForEach(Array(ingredients.enumerated()), id: \.offset) { index, ingredient in
        if let entity = linkedEntity(ingredient), amounts.indices.contains(index),
          let count = amounts[index].integer, count > 0
        {
          entityLink(entity, trailing: "×\(count)")
        }
      }
    }
  }
  @ViewBuilder private func actionSections(_ detail: EntityDetail) -> some View {
    let row = detail.row
    if !detail.description.isEmpty {
      GameDescriptionText(description: detail.description)
    }
    DetailSection("Action information") {
      if let job = row["ClassJob"].referenceName, !job.isEmpty {
        MetadataRow(label: "Class / job", value: job.capitalized)
      }
      if let level = detail.entity.level {
        MetadataRow(label: "Required level", value: String(level))
      }
      if let cast = row["Cast100ms"].integer {
        MetadataRow(
          label: "Cast time",
          value: cast == 0 ? "Instant" : String(format: "%.1f s", Double(cast) / 10))
      }
      if let recast = row["Recast100ms"].integer {
        MetadataRow(label: "Recast time", value: String(format: "%.1f s", Double(recast) / 10))
      }
      if let range = row["Range"].integer {
        MetadataRow(label: "Range", value: range < 0 ? "Varies by weapon" : "\(range) yalms")
      }
    }
  }
  @ViewBuilder private func questSections(_ detail: EntityDetail) -> some View {
    let row = detail.row
    DetailSection("Quest information") {
      if let level = detail.entity.level {
        MetadataRow(label: "Required level", value: String(level))
      }
      if let expansion = row["Expansion"].referenceName {
        MetadataRow(label: "Expansion", value: expansion)
      }
      if let place = row["PlaceName"].referenceName { MetadataRow(label: "Location", value: place) }
    }
    if let issuer = linkedEntity(row["IssuerStart"]) {
      DetailSection("Quest issuer") { entityLink(issuer) }
    }
  }
  @ViewBuilder private func npcSections(_ detail: EntityDetail) -> some View {
    DetailSection("Resident information") {
      MetadataRow(label: "Name", value: detail.entity.displayName)
      if let title = detail.row["Title"].string, !title.isEmpty {
        MetadataRow(label: "Title", value: title)
      }
      Text(
        "Resident records identify named NPCs. Shop inventories and map locations are not included in this view."
      ).font(.caption).foregroundStyle(.secondary)
    }
  }
  private func entityLink(_ entity: EntitySummary, trailing: String? = nil) -> some View {
    Button {
      workspace.open(entity)
    } label: {
      HStack(spacing: 10) {
        GameIcon(path: entity.iconPath, kind: entity.id.kind, icons: workspace.icons, size: 30)
        VStack(alignment: .leading, spacing: 3) {
          Text(entity.displayName).foregroundStyle(.primary)
          if let category = entity.category, !category.isEmpty {
            Text(category).font(.caption).foregroundStyle(.secondary)
          }
        }
        Spacer()
        if let trailing {
          Text(trailing).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
      }.contentShape(Rectangle()).padding(.vertical, 5)
    }.buttonStyle(.plain).accessibilityLabel(
      "Open \(entity.displayName), \(entity.id.kind.singular)")
  }
  @ViewBuilder private func forPositive(_ row: SheetRow, field: String, label: String) -> some View
  {
    if let value = row[field].integer, value > 0 {
      MetadataRow(label: label, value: value.formatted())
    }
  }
  private func linkedEntity(_ value: FieldValue) -> EntitySummary? {
    guard let sheet = value["sheet"].string, let kind = EntityKind(rawValue: sheet),
      let row = value["row_id"].integer, row > 0
    else { return nil }
    return SheetRow(rowID: row, fields: value["fields"].object).summary(kind: kind)
  }
  private func equipmentSlots(_ value: FieldValue) -> String? {
    let slots = value["fields"].object.filter { ($0.value.integer ?? 0) > 0 }.map { key, _ in
      switch key {
      case "MainHand": "Main hand"
      case "OffHand": "Off hand"
      case "FingerL", "FingerR": "Finger"
      case "SoulCrystal": "Soul crystal"
      default: key
      }
    }
    return slots.isEmpty ? nil : Set(slots).sorted().joined(separator: ", ")
  }
  private func itemStats(_ row: SheetRow) -> [(String, String)] {
    var values: [(String, String)] = []
    for (key, name) in [
      ("DamagePhys", "Physical damage"), ("DamageMag", "Magic damage"), ("DefensePhys", "Defense"),
      ("DefenseMag", "Magic defense"),
    ] {
      if let n = row[key].integer, n > 0 { values.append((name, n.formatted())) }
    }
    let amounts = row["BaseParamValue"].array
    for (index, param) in row["BaseParam"].array.enumerated() {
      if let name = param.referenceName, !name.isEmpty, amounts.indices.contains(index),
        let n = amounts[index].integer, n != 0
      {
        values.append((name, n.formatted()))
      }
    }
    return values
  }
}
private struct LoadKey: Equatable {
  let id: EntityID?
  let refresh: Int
}
struct DetailSection<Content: View>: View {
  let title: String
  @ViewBuilder var content: Content
  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title).font(.headline)
      Divider()
      content
    }
  }
}
struct MetadataRow: View {
  let label: String
  let value: String
  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 16) {
      Text(label).foregroundStyle(.secondary).frame(minWidth: 130, alignment: .leading)
      Spacer(minLength: 0)
      Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
    }.font(.callout).accessibilityElement(children: .combine)
  }
}
private struct Metric: View {
  let label: String
  let value: String
  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(label).font(.system(size: 9, weight: .semibold)).tracking(0.8).foregroundStyle(
        .secondary)
      Text(value).font(.title2.weight(.medium).monospacedDigit())
    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).accessibilityElement(
      children: .combine)
  }
}
