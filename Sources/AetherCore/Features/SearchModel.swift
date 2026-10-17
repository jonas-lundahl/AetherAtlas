import Foundation
import Observation

@MainActor @Observable public final class SearchModel {
  public var query = "" { didSet { if query != oldValue { schedule() } } }
  public var kind: EntityKind = .item { didSet { if kind != oldValue { schedule() } } }
  public private(set) var entries: [EntitySummary] = []
  public private(set) var isLoading = false
  public private(set) var isLoadingMore = false
  public private(set) var error: String?
  public private(set) var isStale = false
  public private(set) var next: String?
  public private(set) var after: Int?
  public var selection: EntityID?
  @ObservationIgnored private let repository: any GameRepository
  @ObservationIgnored private let debounce: Duration
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var revision = 0
  public init(repository: any GameRepository, debounce: Duration = .milliseconds(300)) {
    self.repository = repository
    self.debounce = debounce
  }
  public var canLoadMore: Bool { next != nil || after != nil }
  public func start() { schedule(immediate: true) }
  public func retry() { schedule(immediate: true) }
  public func cancel() {
    task?.cancel()
    revision += 1
    isLoading = false
    isLoadingMore = false
  }
  public func clear() { query = "" }
  private func schedule(immediate: Bool = false) {
    task?.cancel()
    revision += 1
    let token = revision
    let kind = kind
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    entries = []
    next = nil
    after = nil
    error = nil
    selection = nil
    isStale = false
    isLoading = true
    isLoadingMore = false
    task = Task { [weak self, repository, debounce] in
      do {
        if !immediate { try await Task.sleep(for: debounce) }
        try Task.checkCancellation()
        let page =
          try await
          (text.isEmpty
          ? repository.browse(kind: kind, after: nil)
          : repository.search(kind: kind, text: text, cursor: nil))
        try Task.checkCancellation()
        guard let self, token == self.revision else { return }
        self.entries = page.entries
        self.next = page.next
        self.after = page.after
        self.isStale = page.isStale
        self.isLoading = false
      } catch {
        guard !Task.isCancelled, let self, token == self.revision else { return }
        self.error = error.localizedDescription
        self.isLoading = false
      }
    }
  }
  public func loadMore() async {
    guard canLoadMore, !isLoadingMore, !isLoading else { return }
    let token = revision
    let kind = kind
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let cursor = next
    let last = after
    isLoadingMore = true
    error = nil
    defer { if token == revision { isLoadingMore = false } }
    do {
      let page =
        try await
        (text.isEmpty
        ? repository.browse(kind: kind, after: last)
        : repository.search(kind: kind, text: text, cursor: cursor))
      try Task.checkCancellation()
      guard token == revision else { return }
      var seen = Set(entries.map(\.id))
      entries += page.entries.filter { seen.insert($0.id).inserted }
      next = page.next
      after = page.after
      isStale = isStale || page.isStale
    } catch { if token == revision, !Task.isCancelled { self.error = error.localizedDescription } }
  }
}

@MainActor @Observable public final class EntityNavigation {
  public private(set) var path: [EntitySummary] = []
  public private(set) var position = -1
  public init() {}
  public var current: EntitySummary? { path.indices.contains(position) ? path[position] : nil }
  public var canBack: Bool { position >= 0 }
  public var canForward: Bool { position + 1 < path.count }
  public func open(_ entity: EntitySummary) {
    guard current?.id != entity.id else { return }
    path = Array(path.prefix(position + 1))
    path.append(entity)
    position = path.count - 1
    if path.count > 100 {
      path.removeFirst()
      position -= 1
    }
  }
  public func back() { if canBack { position -= 1 } }
  public func forward() { if canForward { position += 1 } }
  public func close() { position = -1 }
}
