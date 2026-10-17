import Foundation

public enum APIError: Error, LocalizedError, Sendable, Equatable {
  case invalidURL, invalidResponse
  case decoding(String)
  case http(Int, String, retryAfter: String?)
  public var errorDescription: String? {
    switch self {
    case .invalidURL: "The request URL could not be created."
    case .invalidResponse: "XIVAPI returned an unexpected response."
    case .decoding:
      "The game data could not be read. Please retry; the game schema may have changed."
    case .http(let code, let message, let retry):
      code == 429
        ? "XIVAPI is busy. Try again \(retry.map { "after \($0) seconds" } ?? "in a moment")."
        : "XIVAPI (\(code)): \(message)"
    }
  }
}

public struct APIRequest: Sendable {
  public static let baseURL = URL(string: "https://v2.xivapi.com/api")!
  public let path: String
  public let parameters: [URLQueryItem]
  public init(path: String, parameters: [URLQueryItem] = []) {
    self.path = path
    self.parameters = parameters
  }
  public func url(base: URL = Self.baseURL) throws -> URL {
    var components = URLComponents(
      url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
    components?.queryItems = parameters
    // '+' has form semantics on the API; URLComponents leaves it literal by default.
    let encodedQuery = components?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    components?.percentEncodedQuery = encodedQuery
    guard let url = components?.url else { throw APIError.invalidURL }
    return url
  }
  public static func literal(_ text: String) -> String {
    "\""
      + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
        of: "\"", with: "\\\"") + "\""
  }
  public static func search(kind: EntityKind, text: String, cursor: String? = nil, limit: Int = 50)
    -> Self
  {
    var p = common(kind.summaryFields) + [URLQueryItem(name: "limit", value: String(limit))]
    if let cursor {
      p.append(URLQueryItem(name: "cursor", value: cursor))
    } else {
      p += [
        .init(name: "sheets", value: kind.rawValue),
        .init(name: "query", value: "\(kind.nameField)~\(literal(text))"),
      ]
    }
    return Self(path: "search", parameters: p)
  }
  public static func browse(kind: EntityKind, after: Int? = nil, limit: Int = 50) -> Self {
    var p = common(kind.summaryFields) + [.init(name: "limit", value: String(limit))]
    if let after { p.append(.init(name: "after", value: String(after))) }
    return Self(path: "sheet/\(kind.rawValue)", parameters: p)
  }
  public static func detail(_ id: EntityID) -> Self {
    var p = common(id.kind.detailFields)
    if id.kind == .action {
      p.append(.init(name: "transient", value: "Description,Description@as(html)"))
    }
    return Self(path: "sheet/\(id.kind.rawValue)/\(id.row)", parameters: p)
  }
  public static func recipes(item: Int, cursor: String? = nil) -> Self {
    var p = common(EntityKind.recipe.summaryFields) + [.init(name: "limit", value: "50")]
    if let cursor {
      p.append(.init(name: "cursor", value: cursor))
    } else {
      p += [
        .init(name: "sheets", value: "Recipe"), .init(name: "query", value: "ItemResult=\(item)"),
      ]
    }
    return Self(path: "search", parameters: p)
  }
  public static func asset(path: String) -> Self {
    Self(
      path: "asset",
      parameters: [.init(name: "path", value: path), .init(name: "format", value: "png")])
  }
  private static func common(_ fields: String) -> [URLQueryItem] {
    [.init(name: "fields", value: fields), .init(name: "language", value: "en")]
  }
}

public protocol HTTPTransport: Sendable {
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
public struct URLSessionTransport: HTTPTransport {
  private let session: URLSession
  public init(session: URLSession = .shared) { self.session = session }
  public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
    return (data, http)
  }
}

public struct XIVAPIClient: Sendable {
  public let transport: any HTTPTransport
  public init(transport: any HTTPTransport = URLSessionTransport()) { self.transport = transport }
  public func fetch(url: URL, etag: String? = nil) async throws -> HTTPPayload {
    var request = URLRequest(
      url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
    request.setValue(
      "AetherAtlas/1.0 (independent community browser)", forHTTPHeaderField: "User-Agent")
    if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
    let (data, response) = try await transport.data(for: request)
    try Task.checkCancellation()
    guard (200..<300).contains(response.statusCode) || response.statusCode == 304 else {
      struct Failure: Decodable { let message: String }
      let message =
        (try? JSONDecoder().decode(Failure.self, from: data).message)
        ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
      throw APIError.http(
        response.statusCode, message, retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
    }
    return HTTPPayload(
      data: data, status: response.statusCode, etag: response.value(forHTTPHeaderField: "ETag"),
      cacheControl: response.value(forHTTPHeaderField: "Cache-Control"))
  }
  public static func decode<T: Decodable & Sendable>(_ type: T.Type, from data: Data) throws -> T {
    do { return try JSONDecoder().decode(type, from: data) } catch {
      throw APIError.decoding(String(describing: error))
    }
  }
}
public struct HTTPPayload: Sendable {
  public let data: Data
  public let status: Int
  public let etag: String?
  public let cacheControl: String?
}
