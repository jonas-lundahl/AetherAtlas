import Foundation
import Observation

@MainActor @Observable final class Workspace {
  let cache: ResponseCache
  let icons: IconStore
  let search: SearchModel
  let detail: DetailModel
  let library: LibraryModel
  let updates: AppUpdateModel
  let navigation = EntityNavigation()
  @ObservationIgnored private let preferences: UserDefaults
  var language: GameLanguage {
    didSet {
      guard language != oldValue else { return }
      preferences.set(language.rawValue, forKey: "gameLanguage")
      search.language = language
      detail.language = objectLanguage
    }
  }
  private var objectLanguages: [EntityID: GameLanguage] = [:]
  var objectLanguageOverride: GameLanguage? {
    get { navigation.current.flatMap { objectLanguages[$0.id] } }
    set {
      guard let id = navigation.current?.id else { return }
      objectLanguages[id] = newValue
      detail.language = objectLanguage
    }
  }
  var objectLanguage: GameLanguage { objectLanguageOverride ?? language }
  var section: BrowserSection = .category(.item)
  var searchFocus = 0
  init() {
    let fm = FileManager.default
    let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("AetherAtlas")
    let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(
      "AetherAtlas/Responses-v1")
    cache = ResponseCache(client: XIVAPIClient(), directory: caches)
    var iconResponses = cache
    var repo: any GameRepository = LiveGameRepository(cache: cache)
    var libraryFile = support.appendingPathComponent("library.json")
    var releaseClient: any AppReleaseChecking = GitHubReleaseClient()
    var preferences = UserDefaults.standard
    #if DEBUG
      if ProcessInfo.processInfo.environment["AETHER_UI_TESTING"] == "1"
        || NSClassFromString("XCTestCase") != nil
      {
        repo = UITestRepository()
        releaseClient = UITestReleaseChecker()
        let session =
          ProcessInfo.processInfo.environment["AETHER_UI_TEST_SESSION"] ?? UUID().uuidString
        preferences = UserDefaults(suiteName: "AetherAtlas-UI-\(session)")!
        libraryFile = fm.temporaryDirectory.appendingPathComponent(
          "AetherAtlas-UI-\(session)/library.json")
        iconResponses = ResponseCache(
          client: XIVAPIClient(transport: UITestIconTransport()),
          directory: fm.temporaryDirectory.appendingPathComponent("AetherAtlas-UI-\(session)/Icons")
        )
      }
    #endif
    icons = IconStore(responses: iconResponses)
    self.preferences = preferences
    let language =
      preferences.string(forKey: "gameLanguage").flatMap(GameLanguage.init(rawValue:)) ?? .english
    self.language = language
    search = SearchModel(repository: repo, language: language)
    detail = DetailModel(repository: repo, language: language)
    library = LibraryModel(store: LibraryStore(file: libraryFile))
    updates = AppUpdateModel(
      currentVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        as? String
        ?? "Unknown", client: releaseClient)
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
