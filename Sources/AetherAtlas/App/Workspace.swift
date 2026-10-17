import Foundation
import Observation

@MainActor @Observable final class Workspace {
  let cache: ResponseCache
  let icons: IconStore
  let search: SearchModel
  let detail: DetailModel
  let library: LibraryModel
  let navigation = EntityNavigation()
  var section: BrowserSection = .category(.item)
  var searchFocus = 0
  init() {
    let fm = FileManager.default
    let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("AetherAtlas")
    let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(
      "AetherAtlas/Responses-v1")
    cache = ResponseCache(client: XIVAPIClient(), directory: caches)
    icons = IconStore(responses: cache)
    var repo: any GameRepository = LiveGameRepository(cache: cache)
    var libraryFile = support.appendingPathComponent("library.json")
    #if DEBUG
      if ProcessInfo.processInfo.environment["AETHER_UI_TESTING"] == "1"
        || NSClassFromString("XCTestCase") != nil
      {
        repo = UITestRepository()
        let session =
          ProcessInfo.processInfo.environment["AETHER_UI_TEST_SESSION"] ?? UUID().uuidString
        libraryFile = fm.temporaryDirectory.appendingPathComponent(
          "AetherAtlas-UI-\(session)/library.json")
      }
    #endif
    search = SearchModel(repository: repo)
    detail = DetailModel(repository: repo)
    library = LibraryModel(store: LibraryStore(file: libraryFile))
  }
  func open(_ entity: EntitySummary) { navigation.open(entity) }
}
enum BrowserSection: Hashable {
  case category(EntityKind)
  case favorites, history
  var title: String {
    switch self {
    case .category(let kind): kind.title
    case .favorites: "Favorites"
    case .history: "Recently Viewed"
    }
  }
}
