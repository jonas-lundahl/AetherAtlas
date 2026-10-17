import Foundation
import Testing

#if SWIFT_PACKAGE
  @testable import AetherCore
#else
  @testable import AetherAtlas
#endif

actor StubTransport: HTTPTransport {
  var requests: [URLRequest] = []
  var payload: Data
  let status: Int
  let headers: [String: String]
  let delay: Duration
  var failure: URLError?
  init(
    _ text: String = "{}", status: Int = 200, headers: [String: String] = [:],
    delay: Duration = .zero
  ) {
    payload = Data(text.utf8)
    self.status = status
    self.headers = headers
    self.delay = delay
  }
  func setFailure(_ error: URLError?) { failure = error }
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests.append(request)
    if delay > .zero { try await Task.sleep(for: delay) }
    if let failure { throw failure }
    return (
      payload,
      HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
    )
  }
  var count: Int { requests.count }
}

@Test func searchEncodingAndEscaping() throws {
  let url = try APIRequest.search(kind: .item, text: "A+B & \"C\"\\").url()
  let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
  #expect(items.first { $0.name == "query" }?.value == "Name~\"A+B & \\\"C\\\"\\\\\"")
  #expect(url.absoluteString.contains("%2B"))
  #expect(url.path == "/api/search")
  #expect(items.first { $0.name == "sheets" }?.value == "Item")
}
@Test func cursorReplacesQuery() throws {
  let url = try APIRequest.search(kind: .recipe, text: "Potion", cursor: "cursor-id").url()
  let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
  #expect(items.contains { $0.name == "cursor" && $0.value == "cursor-id" })
  #expect(!items.contains { $0.name == "query" || $0.name == "sheets" })
}
@Test func decodeSearchAndMissingFields() throws {
  let json =
    #"{"next":"next-page","results":[{"sheet":"Item","row_id":4551,"fields":{"Name":"Potion","LevelItem@as(raw)":10,"Icon":{"id":1,"path":"icon.tex"}}}]}"#
  let envelope = try XIVAPIClient.decode(SearchEnvelope.self, from: Data(json.utf8))
  let item = envelope.results[0].summary(kind: .item)
  #expect(item.name == "Potion")
  #expect(item.level == 10)
  #expect(item.category == nil)
  #expect(envelope.next == "next-page")
}
@Test func httpErrorsAndMalformedResponses() async throws {
  let transport = StubTransport(
    #"{"code":429,"message":"slow down"}"#, status: 429, headers: ["Retry-After": "5"])
  do {
    _ = try await XIVAPIClient(transport: transport).fetch(url: APIRequest.baseURL)
    Issue.record("Expected error")
  } catch { #expect(error as? APIError == .http(429, "slow down", retryAfter: "5")) }
  #expect(throws: APIError.self) {
    try XIVAPIClient.decode(SearchEnvelope.self, from: Data("bad".utf8))
  }
}
@Test func cancellationReachesTransport() async throws {
  let transport = StubTransport(delay: .seconds(10))
  let task = Task { try await XIVAPIClient(transport: transport).fetch(url: APIRequest.baseURL) }
  try await Task.sleep(for: .milliseconds(20))
  task.cancel()
  do {
    _ = try await task.value
    Issue.record("Expected cancellation")
  } catch { #expect(error is CancellationError) }
}
@Test func assetAndBrowseRequests() throws {
  let url = try APIRequest.asset(path: "ui/icon/020000/020601_hr1.tex").url()
  #expect(url.path == "/api/asset")
  #expect(url.absoluteString.contains("format=png"))
  #expect(try APIRequest.browse(kind: .item, after: 50).url().absoluteString.contains("after=50"))
  #expect(
    try APIRequest.detail(EntityID(kind: .item, row: 4551)).url().path == "/api/sheet/Item/4551")
}

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "fixture.invalid"
  }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    guard let url = request.url else { return }
    let response = HTTPURLResponse(
      url: url, statusCode: 200, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(
      self,
      didLoad: Data(
        #"{"results":[{"sheet":"Item","row_id":4551,"fields":{"Name":"Potion"}}]}"#.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
@Test func injectedURLSessionUsesMockedURLLoading() async throws {
  let config = URLSessionConfiguration.ephemeral
  config.protocolClasses = [MockURLProtocol.self]
  let session = URLSession(configuration: config)
  defer { session.invalidateAndCancel() }
  let client = XIVAPIClient(transport: URLSessionTransport(session: session))
  let payload = try await client.fetch(url: #require(URL(string: "https://fixture.invalid/search")))
  let result = try XIVAPIClient.decode(SearchEnvelope.self, from: payload.data)
  #expect(result.results.first?.summary(kind: .item).name == "Potion")
}
