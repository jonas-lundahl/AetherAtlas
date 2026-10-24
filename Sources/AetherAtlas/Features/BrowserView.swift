import SwiftUI

struct BrowserView: View {
  @Bindable var workspace: Workspace
  @FocusState private var searchFocused: Bool
  @State private var selectionReset = 0
  @State private var sort: ResultSort = .original
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
    .environment(\.gameSymbolFont, workspace.symbolFont.font)
    .task { await workspace.symbolFont.load() }
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
      if case .category(let kind) = section {
        if !kind.sorts.contains(sort) { sort = .original }
        search.sort = sort
        search.kind = kind
      }
    }
    .onChange(of: sort) { if !isSaved { search.sort = sort } }
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
        selectionReset += 1
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
        Text(
          (try? GameDataIndex.bundled.get().snapshot.patch).map { "Game data · Patch \($0)" }
            ?? "Game data unavailable"
        ).font(.caption2).foregroundStyle(.secondary)
          .accessibilityIdentifier("gameDataPatch")
        Text("An Eorzean field guide").font(.caption2).foregroundStyle(.tertiary)
      }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
    }
  }
  private var savedEntries: [EntitySummary] {
    workspace.section == .favorites
      ? workspace.library.snapshot.favorites : workspace.library.snapshot.history
  }
  private var isSaved: Bool { if case .category = workspace.section { false } else { true } }
  private var displayedEntries: [EntitySummary] {
    isSaved ? sort.ordered(savedEntries, language: workspace.language) : workspace.search.entries
  }

  private var results: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(workspace.section.title).font(.title2.weight(.semibold))
            .accessibilityIdentifier("resultsHeading")
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
          Picker("Sort results", selection: $sort) {
            ForEach(isSaved ? ResultSort.allCases : workspace.search.kind.sorts) {
              Text($0 == .original && !isSaved ? "ID (highest first)" : $0.rawValue).tag($0)
            }
          }
        } label: {
          Image(systemName: "arrow.up.arrow.down")
        }.menuStyle(.borderlessButton).fixedSize().help("Sort all results")
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
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !isSaved && workspace.search.canLoadMore {
          ProgressView("Looking for more results…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: workspace.search.next ?? workspace.search.after.map(String.init)) {
              await workspace.search.loadMore()
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
                : "Try another name, select a category, or clear your search.")
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      } else {
        ResultsList(
          entries: displayedEntries,
          context: ResultsList.ContextID(
            section: workspace.section, query: workspace.search.query, sort: sort,
            language: workspace.language),
          selectionReset: selectionReset,
          language: workspace.language, icons: workspace.icons,
          favorites: Set(workspace.library.snapshot.favorites.map(\.id)),
          open: workspace.openResult,
          toggleFavorite: { entity in Task { await workspace.library.toggle(entity) } },
          loadMore: canAutomaticallyLoadMore
            ? {
              Task {
                guard canAutomaticallyLoadMore else { return }
                await workspace.search.loadMore()
              }
            } : nil
        )
        .overlay(alignment: .bottom) {
          if let error = workspace.search.error, !isSaved {
            VStack(spacing: 5) {
              Text(error).font(.caption).foregroundStyle(.secondary)
              Button("Retry Loading More") { Task { await workspace.search.loadMore() } }
                .font(.caption).disabled(workspace.search.isLoadingMore)
            }
            .padding(8).frame(maxWidth: .infinity).background(.regularMaterial)
          }
        }
      }
      Divider()
      HStack {
        Text(
          "\(workspace.language.formatNumber(displayedEntries.count)) \(isSaved ? "entities" : "loaded")"
        ).font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("resultsCount")
        Spacer()
        if workspace.section == .history {
          Button("Clear History") { Task { await workspace.library.clearHistory() } }.font(.caption)
        }
        if !isSaved && workspace.search.isLoadingMore {
          ProgressView().controlSize(.small).accessibilityLabel("Loading more results")
        }
      }.frame(minHeight: 28).padding(10)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .navigationTitle(workspace.section.title)
  }

  private var canAutomaticallyLoadMore: Bool {
    !isSaved && workspace.search.canLoadMore && !workspace.search.isLoading
      && !workspace.search.isLoadingMore && workspace.search.error == nil
  }
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
        GameText(entity.displayName).font(.body.weight(.medium)).lineLimit(2)
        GameText(entity.category.flatMap { $0.isEmpty ? nil : $0 } ?? entity.id.kind.singular).font(
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
