import Foundation
import Observation

/// Map-specific content only; category paging, navigation, language choices and library state are shared.
@MainActor @Observable public final class MapDetailModel {
  public private(set) var map: GameMap?
  public private(set) var content: MapContent?
  public private(set) var isLoading = false
  public private(set) var error: String?
  public var layers = MapLayers()
  @ObservationIgnored private let repository: any MapRepository
  @ObservationIgnored private var revision = 0

  public init(repository: any MapRepository) { self.repository = repository }

  public func load(_ id: Int?, language: GameLanguage, refresh: Bool = false) async {
    revision += 1
    let token = revision
    if map?.id != id {
      map = nil
      content = nil
    }
    error = nil
    guard let id else {
      isLoading = false
      return
    }
    isLoading = true
    do {
      let record = try await repository.mapDetail(id: id, language: language, refresh: refresh)
      try Task.checkCancellation()
      guard token == revision else { return }
      map = record.map
      let value = try await repository.content(
        for: record.map, language: language, refresh: refresh)
      try Task.checkCancellation()
      guard token == revision else { return }
      content = MapContent(
        image: value.image, markers: value.markers, isStale: value.isStale || record.isStale,
        markerError: value.markerError)
      isLoading = false
    } catch {
      guard !Task.isCancelled, token == revision else { return }
      self.error = error.localizedDescription
      content = nil
      isLoading = false
    }
  }
}
