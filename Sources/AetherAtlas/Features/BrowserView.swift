import SwiftUI

struct BrowserView: View {
  @Bindable var workspace: Workspace
  @FocusState private var searchFocused: Bool
  @FocusState private var resultsFocused: Bool
  @State private var savedSelection: EntityID?
  @State private var sort: ResultSort = .relevance
  var body: some View {
    @Bindable var search = workspace.search
    NavigationSplitView {
      sidebar
        .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 260)
    } content: {
      results
        .navigationSplitViewColumnWidth(min: 300, ideal: 390, max: 620)
    } detail: {
      EntityDetailView(workspace: workspace)
        .navigationSplitViewColumnWidth(min: 380, ideal: 600)
    }
    .navigationSplitViewStyle(.balanced)
    .searchable(text: $search.query, prompt: "Search \(search.kind.title.lowercased())")
    .searchFocused($searchFocused)
    .toolbar {
      ToolbarItemGroup(placement: .navigation) {
        Button("Back", systemImage: "chevron.left") { workspace.navigation.back() }.disabled(
          !workspace.navigation.canBack)
        Button("Forward", systemImage: "chevron.right") { workspace.navigation.forward() }.disabled(
          !workspace.navigation.canForward)
      }
    }
    .onChange(of: workspace.searchFocus) { searchFocused = true }
    .onChange(of: workspace.section) { _, section in
      savedSelection = nil
      if case .category(let kind) = section { search.kind = kind }
    }
    .onChange(of: search.query) {
      if case .category = workspace.section {} else { workspace.section = .category(search.kind) }
    }
    .onExitCommand {
      if !search.query.isEmpty {
        search.clear()
      } else if searchFocused {
        searchFocused = false
      } else {
        workspace.navigation.close()
        search.selection = nil
        savedSelection = nil
      }
    }
    .task {
      await workspace.library.load()
      search.start()
    }
    .alert(
      "Couldn’t save your library",
      isPresented: Binding(
        get: { workspace.library.error != nil }, set: { if !$0 { workspace.library.error = nil } })
    ) {
      Button("OK") { workspace.library.error = nil }
    } message: {
      Text(workspace.library.error ?? "")
    }
  }
  private var sidebar: some View {
    List(selection: $workspace.section) {
      Section {
        ForEach(EntityKind.allCases) { kind in
          Label(kind.title, systemImage: kind.symbol).tag(BrowserSection.category(kind))
            .accessibilityIdentifier("category-\(kind.rawValue)")
        }
      } header: {
        Text("Game Database")
      }
      Section("Your Library") {
        Label {
          HStack {
            Text("Favorites")
            Spacer()
            Text(workspace.language.formatNumber(workspace.library.snapshot.favorites.count))
              .foregroundStyle(
                .tertiary)
          }
        } icon: {
          Image(systemName: "star")
        }.tag(BrowserSection.favorites).accessibilityIdentifier("sidebar-favorites")
        Label("Recently Viewed", systemImage: "clock").tag(BrowserSection.history)
          .accessibilityIdentifier("sidebar-history")
      }
    }
    .listStyle(.sidebar)
    .navigationTitle("Aether Atlas")
    .safeAreaInset(edge: .bottom) {
      VStack(alignment: .leading, spacing: 5) {
        Text("Default game language").font(.caption).foregroundStyle(.secondary)
        GameLanguagePicker(
          label: "Default game language", selection: $workspace.language,
          identifier: "gameLanguagePicker"
        )
        .fixedSize()
        .padding(.bottom, 10)
        Label("XIVAPI v2", systemImage: "network").font(.caption.weight(.medium))
        Text("An Eorzean field guide").font(.caption2).foregroundStyle(.tertiary)
      }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
    }
  }
  private var savedEntries: [EntitySummary] {
    workspace.section == .favorites
      ? workspace.library.snapshot.favorites : workspace.library.snapshot.history
  }
  private var isSaved: Bool { if case .category = workspace.section { false } else { true } }
  private var resultSelection: Binding<EntityID?> {
    Binding(
      get: { isSaved ? savedSelection : workspace.search.selection },
      set: { id in
        if isSaved {
          savedSelection = id
        } else {
          workspace.search.selection = id
        }
        if let entity = displayedEntries.first(where: { $0.id == id }) {
          workspace.open(entity)
        }
      })
  }
  private var displayedEntries: [EntitySummary] {
    let entries = isSaved ? savedEntries : workspace.search.entries
    switch sort {
    case .relevance: return entries
    case .name:
      return entries.sorted {
        $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
      }
    case .level: return entries.sorted { ($0.level ?? -1) > ($1.level ?? -1) }
    }
  }
  private var results: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(workspace.section.title).font(.title2.weight(.semibold))
          Text(
            isSaved
              ? "\(workspace.language.formatNumber(savedEntries.count)) saved locally"
              : workspace.search.query.isEmpty
                ? "Browse the game database" : "Results for “\(workspace.search.query)”"
          )
          .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer()
        Menu {
          Picker("Sort loaded results", selection: $sort) {
            ForEach(ResultSort.allCases) { Text($0.rawValue).tag($0) }
          }
        } label: {
          Image(systemName: "arrow.up.arrow.down")
        }.menuStyle(.borderlessButton).fixedSize().help("Sort loaded results")
          .accessibilityIdentifier("resultSort")
      }.padding(16)
      Divider()
      if !isSaved && workspace.search.isStale {
        Label("Cached results · connection unavailable", systemImage: "wifi.slash").font(.caption)
          .foregroundStyle(.secondary).padding(10)
      }
      if !isSaved && workspace.search.isLoading {
        ProgressView("Searching the archives…").frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if displayedEntries.isEmpty {
        if let error = workspace.search.error, !isSaved {
          ContentUnavailableView {
            Label("Couldn’t load the database", systemImage: "wifi.exclamationmark")
          } description: {
            Text(error)
          } actions: {
            Button("Try Again") { workspace.search.retry() }
          }
        } else {
          ContentUnavailableView(
            isSaved
              ? (workspace.section == .favorites
                ? "Keep your discoveries" : "Your journey starts here") : "No matching entities",
            systemImage: isSaved
              ? (workspace.section == .favorites ? "star" : "clock") : "magnifyingglass",
            description: Text(
              isSaved
                ? "Open an entity\(workspace.section == .favorites ? " and choose the star to save it." : " to find it here later.")"
                : "Try another name, select a category, or clear your search."))
          if !isSaved && workspace.search.canLoadMore {
            Button("Browse Next Rows") { Task { await workspace.search.loadMore() } }.padding()
          }
        }
      } else {
        List(selection: resultSelection) {
          ForEach(displayedEntries) { entity in
            ResultRow(
              entity: entity, language: workspace.language, icons: workspace.icons,
              favorite: workspace.library.isFavorite(entity.id)
            )
            .contentShape(Rectangle())
            .tag(entity.id)
            .accessibilityIdentifier("entity-\(entity.id.description)")
            // A row gesture can open details without triggering native List selection.
            .simultaneousGesture(
              TapGesture().onEnded {
                resultsFocused = true
                resultSelection.wrappedValue = entity.id
              }
            )
            .contextMenu {
              Button("Open Details") { resultSelection.wrappedValue = entity.id }
              Button(
                workspace.library.isFavorite(entity.id) ? "Remove Favorite" : "Add Favorite",
                systemImage: "star"
              ) { Task { await workspace.library.toggle(entity) } }
              Button("Copy Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entity.displayName, forType: .string)
              }
            }
          }
        }.listStyle(.inset).accessibilityIdentifier("entityResults")
          .focused($resultsFocused)
          .onKeyPress(.return) {
            let id = resultSelection.wrappedValue
            guard let entity = displayedEntries.first(where: { $0.id == id }) else {
              return .ignored
            }
            workspace.open(entity)
            return .handled
          }
        if let error = workspace.search.error, !isSaved {
          VStack(spacing: 5) {
            Text(error).font(.caption).foregroundStyle(.secondary)
            Button("Refresh Search") { workspace.search.retry() }.font(.caption)
          }.padding(8)
        }
      }
      Divider()
      HStack {
        Text(
          "\(workspace.language.formatNumber(displayedEntries.count)) \(isSaved ? "entities" : "loaded")"
        ).font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        if workspace.section == .history {
          Button("Clear History") { Task { await workspace.library.clearHistory() } }.font(.caption)
        }
        if !isSaved && workspace.search.canLoadMore {
          if workspace.search.isLoadingMore { ProgressView().controlSize(.small) }
          Button("Load More") { Task { await workspace.search.loadMore() } }.disabled(
            workspace.search.isLoadingMore)
        }
      }.padding(10)
    }.navigationTitle(workspace.section.title)
  }
}
private enum ResultSort: String, CaseIterable, Identifiable {
  case relevance = "Original order"
  case name = "Name"
  case level = "Level (highest first)"
  var id: Self { self }
}

struct ResultRow: View {
  let entity: EntitySummary
  let language: GameLanguage
  let icons: IconStore
  var favorite = false
  var body: some View {
    HStack(spacing: 11) {
      GameIcon(path: entity.iconPath, kind: entity.id.kind, icons: icons)
      VStack(alignment: .leading, spacing: 4) {
        Text(entity.displayName).font(.body.weight(.medium)).lineLimit(2)
        Text(entity.category.flatMap { $0.isEmpty ? nil : $0 } ?? entity.id.kind.singular).font(
          .caption
        ).foregroundStyle(.secondary).lineLimit(1)
      }
      Spacer(minLength: 4)
      VStack(alignment: .trailing, spacing: 5) {
        if let level = entity.level, level > 0 {
          Text(
            entity.id.kind == .item
              ? "i\(language.formatNumber(level))" : "Lv. \(language.formatNumber(level))"
          ).font(
            .caption.monospacedDigit()
          ).foregroundStyle(.secondary)
        }
        if favorite {
          Image(systemName: "star.fill").font(.caption2).foregroundStyle(.secondary)
            .accessibilityLabel("Favorite")
        }
      }
    }.padding(.vertical, 5).accessibilityElement(children: .combine)
  }
}
