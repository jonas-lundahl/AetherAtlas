#if !SWIFT_PACKAGE
  import AppKit
  import Testing
  @testable import AetherAtlas

  @Suite(.serialized) @MainActor struct ResultsListTests {
    private let context = ResultsList.ContextID(
      section: .category(.item), query: "", sort: .original, language: .english)
    private let presentation = ResultsTableView.Presentation(
      language: .english, favorites: [], hasSymbolFont: false)

    private func entries(_ count: Int) -> [EntitySummary] {
      (0..<count).map { EntitySummary(id: EntityID(kind: .item, row: $0), name: "Item \($0)") }
    }

    private func makeTable() -> (ResultsTableView, ResultsScrollView) {
      let scroll = ResultsScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 320))
      let table = ResultsTableView()
      scroll.documentView = table
      table.apply(
        entries: entries(200), context: context, selectionReset: 0, presentation: presentation)
      scroll.layoutSubtreeIfNeeded()
      return (table, scroll)
    }

    private func click(_ row: Int, in table: ResultsTableView) throws {
      let point = table.convert(NSPoint(x: 100, y: table.rect(ofRow: row).midY), to: nil)
      let event = try #require(
        NSEvent.mouseEvent(
          with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
          windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
      table.mouseDown(with: event)
    }

    private func key(_ code: UInt16, characters: String, in table: ResultsTableView) throws {
      let event = try #require(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
          windowNumber: 0, context: nil, characters: characters,
          charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
      table.keyDown(with: event)
    }

    @Test func mouseAfterScrollingAndKeysShareOneSelection() throws {
      let (table, scroll) = makeTable()
      var opened: [Int] = []
      table.open = { opened.append($0.id.row) }
      try click(0, in: table)
      table.scrollRowToVisible(120)
      let origin = scroll.contentView.bounds.origin
      try click(120, in: table)
      #expect(table.selectedEntity?.id.row == 120)
      #expect(scroll.contentView.bounds.origin == origin)
      try key(13, characters: "w", in: table)
      try key(1, characters: "s", in: table)
      try key(125, characters: "\u{f701}", in: table)
      try key(126, characters: "\u{f700}", in: table)
      try key(36, characters: "\r", in: table)
      try click(120, in: table)
      #expect(opened == [0, 120, 119, 120, 121, 120, 120, 120])
      #expect(table.selectedRowIndexes.count == 1)
    }

    @Test func snapshotsAndPaginationNeverRevealOrActivateAnOldSelection() throws {
      let (table, scroll) = makeTable()
      var opens = 0
      table.open = { _ in opens += 1 }
      try click(0, in: table)
      table.scrollRowToVisible(120)
      let origin = scroll.contentView.bounds.origin
      #expect(origin.y > 0)
      let changedPresentation = ResultsTableView.Presentation(
        language: .english, favorites: [EntityID(kind: .item, row: 0)], hasSymbolFont: true)
      table.apply(
        entries: entries(200), context: context, selectionReset: 0,
        presentation: changedPresentation)
      #expect(scroll.contentView.bounds.origin == origin)
      table.apply(
        entries: entries(250), context: context, selectionReset: 0,
        presentation: changedPresentation)
      #expect(scroll.contentView.bounds.origin == origin)
      #expect(table.selectedEntity?.id.row == 0)
      #expect(opens == 1)
    }

    @Test func reorderedHistoryPreservesIdentitiesAndTheVisibleAnchor() throws {
      let (table, scroll) = makeTable()
      var opens = 0
      table.open = { _ in opens += 1 }
      table.scrollRowToVisible(120)
      try click(120, in: table)
      let oldOrigin = scroll.contentView.bounds.origin
      let top = table.row(at: NSPoint(x: 0, y: oldOrigin.y))
      let anchor = table.entries[top].id
      let offset = oldOrigin.y - table.rect(ofRow: top).minY
      var reordered = entries(200)
      reordered.insert(reordered.remove(at: 120), at: 0)
      table.apply(
        entries: reordered, context: context, selectionReset: 0, presentation: presentation)
      #expect(table.selectedEntity?.id.row == 120)
      let newTop = table.row(at: NSPoint(x: 0, y: scroll.contentView.bounds.origin.y))
      #expect(table.entries[newTop].id == anchor)
      #expect(scroll.contentView.bounds.origin.y - table.rect(ofRow: newTop).minY == offset)
      #expect(opens == 1)
    }

    @Test func resetsAndRemovedRowsDoNotOpenDetails() throws {
      let (table, scroll) = makeTable()
      var opens = 0
      table.open = { _ in opens += 1 }
      table.scrollRowToVisible(120)
      try click(120, in: table)
      let origin = scroll.contentView.bounds.origin
      table.apply(
        entries: entries(200), context: context, selectionReset: 1, presentation: presentation)
      #expect(table.selectedEntity == nil)
      #expect(scroll.contentView.bounds.origin == origin)
      try click(120, in: table)
      table.apply(
        entries: entries(200).filter { $0.id.row != 120 }, context: context,
        selectionReset: 1, presentation: presentation)
      #expect(table.selectedEntity == nil)
      let newContext = ResultsList.ContextID(
        section: .favorites, query: "", sort: .original, language: .english)
      table.apply(
        entries: entries(200), context: newContext, selectionReset: 1, presentation: presentation)
      #expect(table.selectedEntity == nil)
      #expect(scroll.contentView.bounds.origin.y == 0)
      #expect(opens == 2)
    }

    @Test func infiniteScrollWaitsUntilNearTheEndAndCoalescesEvents() async throws {
      let (table, scroll) = makeTable()
      var requests = 0
      scroll.loadMore = { requests += 1 }
      defer { scroll.loadMore = nil }
      try await Task.sleep(for: .milliseconds(10))
      #expect(requests == 0)
      table.scrollRowToVisible(180)
      try await Task.sleep(for: .milliseconds(10))
      #expect(requests == 0)
      // Keyboard navigation reveals the final row and uses the same trigger.
      try key(13, characters: "w", in: table)
      for _ in 0..<10 {
        NotificationCenter.default.post(
          name: NSView.boundsDidChangeNotification, object: scroll.contentView)
      }
      #expect(requests == 0)
      try await eventually { requests == 1 }
      #expect(table.selectedEntity?.id.row == 199)
      let origin = scroll.contentView.bounds.origin
      scroll.loadMore = nil
      table.apply(
        entries: entries(250), context: context, selectionReset: 0, presentation: presentation)
      scroll.loadMore = { requests += 1 }
      try await Task.sleep(for: .milliseconds(10))
      #expect(requests == 1)
      #expect(table.selectedEntity?.id.row == 199)
      #expect(scroll.contentView.bounds.origin == origin)
    }

    @Test func infiniteScrollRechecksWhenTheViewportGrows() async throws {
      let (table, scroll) = makeTable()
      table.apply(
        entries: entries(12), context: context, selectionReset: 0, presentation: presentation)
      var requests = 0
      scroll.loadMore = { requests += 1 }
      defer { scroll.loadMore = nil }
      try await Task.sleep(for: .milliseconds(10))
      #expect(requests == 0)
      scroll.setFrameSize(NSSize(width: 400, height: 640))
      scroll.layoutSubtreeIfNeeded()
      try await eventually { requests == 1 }
    }

    @Test func infiniteScrollFillsShortPagesAndHonorsDisabledAndRemovedCallbacks() async throws {
      let (table, scroll) = makeTable()
      table.apply(
        entries: entries(2), context: context, selectionReset: 0, presentation: presentation)
      var requests = 0
      scroll.loadMore = { requests += 1 }
      scroll.loadMore = nil
      try await Task.sleep(for: .milliseconds(10))
      #expect(requests == 0)
      scroll.loadMore = { requests += 1 }
      try await eventually { requests == 1 }
      // Disabled callbacks cover requests in flight, exhaustion, errors, and saved lists.
      scroll.loadMore = nil
      scroll.setFrameSize(NSSize(width: 400, height: 640))
      scroll.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(10))
      #expect(requests == 1)
      scroll.loadMore = { requests += 1 }
      try await eventually { requests == 2 }
      scroll.loadMore = nil
    }

    @Test func keyboardClampsAtTheEndsAndRevealsOnlyItsTarget() throws {
      let (table, scroll) = makeTable()
      try key(1, characters: "s", in: table)
      #expect(table.selectedEntity?.id.row == 0)
      try key(13, characters: "w", in: table)
      #expect(table.selectedEntity?.id.row == 0)
      table.deselectAll(nil)
      try key(13, characters: "w", in: table)
      #expect(table.selectedEntity?.id.row == 199)
      #expect(scroll.contentView.bounds.origin.y > 0)
      try key(1, characters: "s", in: table)
      #expect(table.selectedEntity?.id.row == 199)
      table.apply(entries: [], context: context, selectionReset: 0, presentation: presentation)
      try key(1, characters: "s", in: table)
      try key(13, characters: "w", in: table)
      #expect(table.selectedEntity == nil)
    }
  }
#endif
