import Foundation
import Observation

@MainActor @Observable public final class DetailModel {
  public private(set) var detail: EntityDetail?
  public private(set) var isLoading = false
  public private(set) var error: String?
  public private(set) var recipes: [EntitySummary] = []
  public private(set) var recipesLoading = false
  public private(set) var recipesError: String?
  public private(set) var recipesNext: String?
  public private(set) var recipesStale = false
  @ObservationIgnored private let repository: any GameRepository
  @ObservationIgnored private var revision = 0
  public init(repository: any GameRepository) { self.repository = repository }
  public func load(_ id: EntityID?, refresh: Bool = false) async {
    revision += 1
    let token = revision
    detail = nil
    error = nil
    recipes = []
    recipesError = nil
    recipesNext = nil
    recipesStale = false
    recipesLoading = false
    guard let id else {
      isLoading = false
      return
    }
    isLoading = true
    do {
      let result = try await repository.detail(id, refresh: refresh)
      try Task.checkCancellation()
      guard token == revision else { return }
      detail = result
      isLoading = false
      if id.kind == .item { await loadRecipes(item: id.row) }
    } catch {
      guard token == revision, !Task.isCancelled else { return }
      self.error = error.localizedDescription
      isLoading = false
    }
  }
  public func loadRecipes(item: Int, more: Bool = false) async {
    guard !recipesLoading else { return }
    let token = revision
    let cursor = more ? recipesNext : nil
    recipesLoading = true
    recipesError = nil
    defer { if token == revision { recipesLoading = false } }
    do {
      let result = try await repository.recipes(item: item, cursor: cursor)
      try Task.checkCancellation()
      guard token == revision else { return }
      var seen = Set((more ? recipes : []).map(\.id))
      recipes = (more ? recipes : []) + result.entries.filter { seen.insert($0.id).inserted }
      recipesNext = result.next
      recipesStale = result.isStale
    } catch {
      if token == revision, !Task.isCancelled { recipesError = error.localizedDescription }
    }
  }
}
