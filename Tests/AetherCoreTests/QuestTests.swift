import Foundation
import Testing

#if SWIFT_PACKAGE
  @testable import AetherCore
#else
  @testable import AetherAtlas
#endif

@Test func questFixtureUsesAvailableMSQIconAndJournalText() throws {
  let envelope = try XIVAPIClient.decode(DetailEnvelope.self, from: fixture("quest-detail"))
  let summary = envelope.row.summary(kind: .quest)
  #expect(summary.name == "When It Rains")
  #expect(summary.level == 76)
  #expect(summary.iconPath == "ui/icon/071000/071201_hr1.tex")
  #expect(summary.iconPath != envelope.row["Icon"].iconPath)
  let text = try XIVAPIClient.decode(BrowseEnvelope.self, from: fixture("quest-journal"))
  let journal = QuestJournal(rows: text.rows)
  #expect(journal.description.plainText.hasPrefix("You learn from the manager of suites"))
  #expect(
    journal.objectives.map(\.plainText) == [
      "Survey the Exedra.", "Activate the first anchor.", "Activate the second anchor.",
      "Speak with Alphinaud.", "Speak with Alphinaud.", "Speak with Alisaie.",
    ])
  let growth = try XIVAPIClient.decode(DetailEnvelope.self, from: fixture("quest-growth"))
  #expect(QuestPresentation.experience(factor: 400, growth: growth.row) == 224_640)
  #expect(QuestPresentation.experience(factor: Int.max, growth: growth.row) == nil)
}

@Test(arguments: [(62319, 62017), (62308, 62026), (62309, 62029), (62409, 62028), (62422, 62042)])
func jobQuestThumbnailsUseSetNineEvenBeforeJobUnlock(genre: Int, icon: Int) {
  let row = SheetRow(
    rowID: 1,
    fields: [
      "JournalGenre": .object(["fields": .object(["Icon": .object(["id": .number(Double(genre))])])]
      ),
      "ClassJobRequired": .object(["row_id": .number(0)]),
    ])
  #expect(row.summary(kind: .quest).iconPath == QuestPresentation.iconPath(icon))
}

@Test func ordinaryAndUnlockQuestsUseAvailableIconWithSafeMissingDataFallback() {
  for icon in [71220, 71340] {
    let row = SheetRow(
      rowID: 1,
      fields: [
        "EventIconType": .object([
          "fields": .object([
            "NpcIconAvailable": .object([
              "id": .number(Double(icon)), "path": .string("available-\(icon).tex"),
            ])
          ])
        ]),
        "Icon": .object(["id": .number(100913), "path": .string("banner.tex")]),
      ])
    #expect(row.summary(kind: .quest).iconPath == QuestPresentation.iconPath(icon + 1))
  }
  #expect(
    SheetRow(rowID: 1, fields: [:]).summary(kind: .quest).iconPath
      == QuestPresentation.iconPath(71221))
  let hidden = SheetRow(
    rowID: 1,
    fields: [
      "EventIconType": .object([
        "fields": .object([
          "NpcIconAvailable": .object(["id": .number(60091), "path": .string("placeholder.tex")])
        ])
      ])
    ])
  #expect(hidden.summary(kind: .quest).iconPath == QuestPresentation.iconPath(71221))
}

@Test(arguments: GameLanguage.allCases)
func questTextRequestsEscapeSheetSlashesAndCarryLanguage(language: GameLanguage) throws {
  let request = try #require(APIRequest.questJournal(id: "LucKmd101_03606", language: language))
  let url = try request.url()
  #expect(url.absoluteString.contains("/sheet/quest%2F036%2FLucKmd101_03606?"))
  #expect(!url.absoluteString.contains("%252F"))
  #expect(request.parameters.contains { $0.name == "language" && $0.value == language.rawValue })
  #expect(APIRequest.questJournal(id: "../../other") == nil)
  #expect(APIRequest.questJournal(id: "ClsHrv001_00003")?.path == "sheet/quest/000/ClsHrv001_00003")
}

@Test func missingAcceptedJournalFallsBackToOfferAndRejectsBattleDialogue() {
  let journal = QuestJournal(rows: [
    SheetRow(
      rowID: 0, fields: ["unknown0": .string("TEXT_TEST_SEQ_00"), "unknown4": .string("Offer.")]),
    SheetRow(rowID: 1, fields: ["unknown0": .string("TEXT_TEST_SEQ_01"), "unknown4": .string("")]),
    SheetRow(
      rowID: 24, fields: ["unknown0": .string("TEXT_TEST_TODO_00"), "unknown4": .string("Speak.")]),
    SheetRow(
      rowID: 80,
      fields: ["unknown0": .string("TEXT_TEST_QIB_001_TODO_01"), "unknown4": .string("Battle.")]),
  ])
  #expect(journal.description.plainText == "Offer.")
  #expect(journal.objectives.map(\.plainText) == ["Speak."])
}

private actor QuestTransport: HTTPTransport {
  var requests: [URLRequest] = []
  let failJournal: Bool
  init(failJournal: Bool = false) { self.failJournal = failJournal }
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests.append(request)
    let url = request.url!
    let name: String
    if url.absoluteString.contains("quest%2F") {
      if failJournal { throw URLError(.notConnectedToInternet) }
      name = "quest-journal"
    } else if url.path.contains("ParamGrow") {
      name = "quest-growth"
    } else {
      name = "quest-detail"
    }
    return (
      try fixture(name),
      HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
    )
  }
}

@Test(arguments: [false, true])
func questRepositoryEnrichesDetailsAndPreservesUsablePartialResults(failJournal: Bool) async throws
{
  let directory = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let transport = QuestTransport(failJournal: failJournal)
  let repository = LiveGameRepository(
    cache: ResponseCache(client: XIVAPIClient(transport: transport), directory: directory))
  let detail = try await repository.detail(EntityID(kind: .quest, row: 69142), language: .japanese)
  #expect(detail.entity.name == "When It Rains")
  #expect(detail.questExperience == 224_640)
  #expect((detail.questJournal == nil) == failJournal)
  #expect((detail.questContentError != nil) == failJournal)
  let requests = await transport.requests
  #expect(requests.count == 3)
  for request in requests {
    #expect(
      URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains {
        $0.name == "language" && $0.value == "ja"
      } == true)
  }
}
