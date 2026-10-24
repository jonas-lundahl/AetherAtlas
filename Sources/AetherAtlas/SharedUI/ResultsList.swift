import AppKit
import SwiftUI

/// SwiftUI supplies snapshots; the native table owns selection, focus, and scrolling.
struct ResultsList: NSViewRepresentable {
  struct ContextID: Equatable {
    let section: BrowserSection
    let query: String
    let sort: ResultSort
    let language: GameLanguage
  }

  let entries: [EntitySummary]
  let context: ContextID
  let selectionReset: Int
  let language: GameLanguage
  let icons: IconStore
  let favorites: Set<EntityID>
  let open: (EntitySummary) -> Void
  let toggleFavorite: (EntitySummary) -> Void
  var loadMore: (() -> Void)? = nil
  @Environment(\.gameSymbolFont) private var symbolFont

  func makeNSView(context: Context) -> ResultsScrollView {
    let scroll = ResultsScrollView()
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    scroll.documentView = ResultsTableView()
    return scroll
  }

  func updateNSView(_ scroll: ResultsScrollView, context: Context) {
    guard let table = scroll.documentView as? ResultsTableView else { return }
    table.open = open
    table.toggleFavorite = toggleFavorite
    table.rowContent = { entity in
      AnyView(
        ResultRow(
          entity: entity, language: language, icons: icons, favorite: favorites.contains(entity.id)
        )
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.gameSymbolFont, symbolFont)
        .accessibilityIdentifier("entity-\(entity.id.description)"))
    }
    table.apply(
      entries: entries, context: self.context, selectionReset: selectionReset,
      presentation: .init(
        language: language, favorites: favorites, hasSymbolFont: symbolFont != nil))
    scroll.loadMore = loadMore
  }

  static func dismantleNSView(_ scroll: ResultsScrollView, coordinator: ()) {
    scroll.loadMore = nil
  }
}

/// Check after layout/snapshot updates, without publishing SwiftUI state during an update.
final class ResultsScrollView: NSScrollView {
  var loadMore: (() -> Void)? {
    didSet {
      if loadMore == nil {
        paginationCheck?.cancel()
        paginationCheck = nil
      } else {
        schedulePaginationCheck()
      }
    }
  }
  private var paginationCheck: Task<Void, Never>?

  override init(frame: NSRect) {
    super.init(frame: frame)
    contentView.postsBoundsChangedNotifications = true
    NotificationCenter.default.addObserver(
      self, selector: #selector(visibleBoundsChanged(_:)),
      name: NSView.boundsDidChangeNotification, object: contentView)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layout() {
    super.layout()
    schedulePaginationCheck()
  }

  @objc private func visibleBoundsChanged(_ notification: Notification) {
    schedulePaginationCheck()
  }

  private func schedulePaginationCheck() {
    guard loadMore != nil, paginationCheck == nil else { return }
    paginationCheck = Task { @MainActor [weak self] in
      guard !Task.isCancelled, let self else { return }
      self.paginationCheck = nil
      guard let table = self.documentView as? ResultsTableView, !table.entries.isEmpty,
        self.documentVisibleRect.height > 0
      else { return }
      let threshold = 5 * (table.rowHeight + table.intercellSpacing.height)
      let bottom = table.rect(ofRow: table.entries.count - 1).maxY
      if self.documentVisibleRect.maxY >= bottom - threshold { self.loadMore?() }
    }
  }
}

final class ResultsTableView: NSTableView, NSTableViewDataSource, NSTableViewDelegate {
  struct Presentation: Equatable {
    let language: GameLanguage
    let favorites: Set<EntityID>
    let hasSymbolFont: Bool
  }

  private(set) var entries: [EntitySummary] = []
  private var context: ResultsList.ContextID?
  private var presentation: Presentation?
  private var selectionReset = 0
  private var applyingSnapshot = false
  var open: (EntitySummary) -> Void = { _ in }
  var toggleFavorite: (EntitySummary) -> Void = { _ in }
  var rowContent: (EntitySummary) -> AnyView = { _ in AnyView(EmptyView()) }

  init() {
    super.init(frame: .zero)
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("entity"))
    column.resizingMask = .autoresizingMask
    addTableColumn(column)
    headerView = nil
    columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    style = .inset
    rowHeight = 64
    intercellSpacing = .zero
    allowsMultipleSelection = false
    allowsEmptySelection = true
    allowsTypeSelect = false
    usesAutomaticRowHeights = false
    backgroundColor = .clear
    dataSource = self
    delegate = self
    setAccessibilityIdentifier("entityResults")
    setAccessibilityLabel("Results")
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  var selectedEntity: EntitySummary? {
    entries.indices.contains(selectedRow) ? entries[selectedRow] : nil
  }

  func apply(
    entries: [EntitySummary], context: ResultsList.ContextID, selectionReset: Int,
    presentation: Presentation
  ) {
    let changedContext = self.context != context
    let clearSelection = changedContext || self.selectionReset != selectionReset
    let changedRows = self.entries != entries || self.presentation != presentation
    guard changedRows || clearSelection else { return }

    let selectedID = clearSelection ? nil : selectedEntity?.id
    let clip = enclosingScrollView?.contentView
    var origin = clip?.bounds.origin ?? .zero
    let topRow = row(at: NSPoint(x: 0, y: origin.y))
    let topID = self.entries.indices.contains(topRow) ? self.entries[topRow].id : nil
    let offset = origin.y - rect(ofRow: topRow).minY

    // Restoring a snapshot must never open details or reveal an old selection.
    applyingSnapshot = true
    defer { applyingSnapshot = false }
    self.entries = entries
    self.context = context
    self.presentation = presentation
    self.selectionReset = selectionReset
    if changedRows { reloadData() }
    if let row = entries.firstIndex(where: { $0.id == selectedID }) {
      selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    } else {
      deselectAll(nil)
    }
    layoutSubtreeIfNeeded()
    if changedContext {
      origin = .zero
    } else if let row = entries.firstIndex(where: { $0.id == topID }) {
      origin.y = rect(ofRow: row).minY + offset
    }
    if let clip {
      clip.scroll(
        to: clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin)
      enclosingScrollView?.reflectScrolledClipView(clip)
    }
  }

  func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    let identifier = NSUserInterfaceItemIdentifier("resultCell")
    let cell =
      makeView(withIdentifier: identifier, owner: self) as? ResultCell
      ?? ResultCell(rootView: AnyView(EmptyView()))
    cell.identifier = identifier
    cell.rootView = rowContent(entries[row])
    return cell
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    // Native accessibility selection is also an explicit user action.
    guard !applyingSnapshot, let entity = selectedEntity else { return }
    open(entity)
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    let clicked = row(at: convert(event.locationInWindow, from: nil))
    // No native mouse-tracking loop, second gesture, or implicit autoscroll.
    activate(row: clicked, reveal: false)
  }

  override func keyDown(with event: NSEvent) {
    guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
      super.keyDown(with: event)
      return
    }
    switch event.keyCode {
    case 126: moveSelection(by: -1)
    case 125: moveSelection(by: 1)
    case 36, 76: activate(row: selectedRow, reveal: false)
    default:
      switch event.charactersIgnoringModifiers?.lowercased() {
      case "w": moveSelection(by: -1)
      case "s": moveSelection(by: 1)
      default: super.keyDown(with: event)
      }
    }
  }

  private func moveSelection(by step: Int) {
    guard !entries.isEmpty else { return }
    let row = selectedRow < 0 ? (step > 0 ? 0 : entries.count - 1) : selectedRow + step
    activate(row: min(max(row, 0), entries.count - 1), reveal: true)
  }

  private func activate(row: Int, reveal: Bool) {
    guard entries.indices.contains(row) else { return }
    let entity = entries[row]
    applyingSnapshot = true
    selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    applyingSnapshot = false
    if reveal { scrollRowToVisible(row) }
    open(entity)
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    let row = row(at: convert(event.locationInWindow, from: nil))
    guard entries.indices.contains(row) else { return nil }
    let entity = entries[row]
    let menu = NSMenu()
    for (title, action) in [
      ("Open Details", #selector(openFromMenu(_:))),
      (
        presentation?.favorites.contains(entity.id) == true ? "Remove Favorite" : "Add Favorite",
        #selector(toggleFromMenu(_:))
      ),
      ("Copy Name", #selector(copyFromMenu(_:))),
    ] {
      let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
      item.target = self
      item.representedObject = entity
    }
    return menu
  }

  @objc private func openFromMenu(_ item: NSMenuItem) {
    guard let entity = item.representedObject as? EntitySummary,
      let row = entries.firstIndex(where: { $0.id == entity.id })
    else { return }
    window?.makeFirstResponder(self)
    activate(row: row, reveal: false)
  }

  @objc private func toggleFromMenu(_ item: NSMenuItem) {
    guard let entity = item.representedObject as? EntitySummary else { return }
    toggleFavorite(entity)
  }

  @objc private func copyFromMenu(_ item: NSMenuItem) {
    guard let entity = item.representedObject as? EntitySummary else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(entity.displayName, forType: .string)
  }
}

/// Keep native hit testing and accessibility while forwarding row clicks to the table.
private final class ResultCell: NSHostingView<AnyView> {
  private var table: ResultsTableView? {
    var parent = superview
    while let view = parent {
      if let table = view as? ResultsTableView { return table }
      parent = view.superview
    }
    return nil
  }

  override func mouseDown(with event: NSEvent) { table?.mouseDown(with: event) }

  override func menu(for event: NSEvent) -> NSMenu? { table?.menu(for: event) }
}
