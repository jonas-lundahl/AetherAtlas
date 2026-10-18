import Foundation
import Testing

#if SWIFT_PACKAGE
  @testable import AetherCore
#else
  import SwiftUI
  @testable import AetherAtlas
#endif

private let validFontData = Data("test-symbol-font".utf8)

private actor FontDownload {
  private(set) var calls = 0
  let data: Data?
  init(_ data: Data? = validFontData) { self.data = data }
  func fetch() async throws -> Data {
    calls += 1
    try await Task.sleep(for: .milliseconds(20))
    guard let data else { throw URLError(.notConnectedToInternet) }
    return data
  }
}

private func fontCache(file: URL, download: FontDownload) -> SymbolFontCache {
  SymbolFontCache(
    file: file, download: { try await download.fetch() }, validate: { $0 == validFontData })
}

@Test func symbolFontPersistsIndefinitelyAndLoadsWithoutNetworking() async throws {
  let directory = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let file = directory.appendingPathComponent("Fonts/font.ttf")
  let download = FontDownload()
  let cache = fontCache(file: file, download: download)
  async let first = cache.data()
  async let second = cache.data()
  let results = await (first, second)
  #expect(results.0 == validFontData && results.1 == validFontData)
  #expect(await download.calls == 1)
  #expect(try Data(contentsOf: file) == validFontData)
  try FileManager.default.setAttributes(
    [.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: file.path)
  let offline = FontDownload(nil)
  let relaunched = fontCache(file: file, download: offline)
  #expect(await relaunched.data() == validFontData)
  #expect(await offline.calls == 0)
}

@Test func optionalFontFailureIsSilentAndRetriesOnlyOnNextLaunch() async throws {
  let directory = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let file = directory.appendingPathComponent("font.ttf")
  let offline = FontDownload(nil)
  let cache = fontCache(file: file, download: offline)
  #expect(await cache.data() == nil)
  #expect(await cache.data() == nil)
  #expect(await offline.calls == 1)
  #expect(!FileManager.default.fileExists(atPath: file.path))
  let online = FontDownload()
  #expect(await fontCache(file: file, download: online).data() == validFontData)
  #expect(await online.calls == 1)
}

@Test func damagedFontIsReplacedOnlyByAValidatedDownload() async throws {
  let directory = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let file = directory.appendingPathComponent("font.ttf")
  let damaged = Data("damaged".utf8)
  try damaged.write(to: file)
  let invalid = FontDownload(Data("<html>not a font</html>".utf8))
  #expect(await fontCache(file: file, download: invalid).data() == nil)
  #expect(try Data(contentsOf: file) == damaged)
  let replacement = FontDownload()
  #expect(await fontCache(file: file, download: replacement).data() == validFontData)
  #expect(try Data(contentsOf: file) == validFontData)
}

@Test func oversizedFontFilesAndDownloadsAreRejected() async throws {
  let directory = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let file = directory.appendingPathComponent("font.ttf")
  let oversized = Data(repeating: 0, count: SymbolFontCache.maximumBytes + 1)
  try oversized.write(to: file)
  let cache = SymbolFontCache(file: file, download: { oversized }, validate: { _ in true })
  #expect(await cache.data() == nil)
  #expect(try Data(contentsOf: file) == oversized)
}

@Test func unavailableFontStorageStillAllowsSessionUse() async throws {
  let directory = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let blocker = directory.appendingPathComponent("blocker")
  try Data("file, not directory".utf8).write(to: blocker)
  let file = blocker.appendingPathComponent("font.ttf")
  #expect(await fontCache(file: file, download: FontDownload()).data() == validFontData)
  #expect(!FileManager.default.fileExists(atPath: file.path))
}

private final class FontURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "font.fixture.invalid"
  }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    guard let url = request.url else { return }
    let path = url.lastPathComponent
    let headers =
      path == "large-header"
      ? ["Content-Length": String(SymbolFontCache.maximumBytes + 1)] : [:]
    let response = HTTPURLResponse(
      url: url, statusCode: path == "missing" ? 404 : 200, httpVersion: nil,
      headerFields: headers)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    let data =
      path == "large-body"
      ? Data(repeating: 0, count: SymbolFontCache.maximumBytes + 1) : validFontData
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

@Test func fontDownloadHandlesChangedLinksAndBoundsStreamedBodies() async throws {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [FontURLProtocol.self]
  let session = URLSession(configuration: configuration)
  defer { session.invalidateAndCancel() }
  func request(_ path: String) -> URLRequest {
    URLRequest(url: URL(string: "https://font.fixture.invalid/\(path)")!)
  }
  #expect(
    try await SymbolFontCache.download(session: session, request: request("font.ttf"))
      == validFontData)
  for path in ["missing", "large-header", "large-body"] {
    await #expect(throws: URLError.self) {
      try await SymbolFontCache.download(session: session, request: request(path))
    }
  }
}

#if !SWIFT_PACKAGE
  @Test @MainActor func symbolStylingPreservesOtherFontsAndRichText() throws {
    let description = GameDescription(
      plainText: nil,
      html: "<span style=\"color:#00cc22\"><b>Effect \u{e0bf}</b></span> 日本語 \u{e001}")
    let source = GameDescriptionText.attributed(description, colorScheme: .dark)
    let symbolFont = Font.custom(GameSymbolFont.name, fixedSize: 26)
    let text = GameText.attributed(source, characters: [0xE0BF], font: symbolFont)
    #expect(String(text.characters) == "Effect \u{e0bf} 日本語 \u{e001}")
    let symbol = try #require(text.runs.first { $0.font != nil })
    #expect(String(text[symbol.range].characters) == "\u{e0bf}")
    #expect(symbol.font == Font.custom(GameSymbolFont.name, fixedSize: 26))
    #expect(symbol.foregroundColor == source.runs.first?.foregroundColor)
    #expect(symbol.inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
    #expect(text.runs.first?.font == nil)
    #expect(text.runs.last?.font == nil)
    #expect(GameText.attributed(source, characters: [], font: symbolFont) == source)
    #expect(GameSymbolFont(Data("<html>Not a font</html>".utf8)) == nil)
  }
#endif
