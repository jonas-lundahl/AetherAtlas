import Foundation

/// An optional, durable download. A successful copy has no expiry or revalidation.
public actor SymbolFontCache {
  public static let maximumBytes = 256 * 1_024
  public static let sourceURL = URL(
    string: "https://img.finalfantasyxiv.com/lds/pc/global/fonts/FFXIV_Lodestone_SSF.ttf")!

  private let file: URL
  private let download: @Sendable () async throws -> Data
  private let validate: @Sendable (Data) -> Bool
  private var task: Task<Data?, Never>?

  public init(
    file: URL,
    download: @escaping @Sendable () async throws -> Data = SymbolFontCache.download,
    validate: @escaping @Sendable (Data) -> Bool
  ) {
    self.file = file
    self.download = download
    self.validate = validate
  }

  /// Concurrent startup callers share one attempt. Failures can retry next launch.
  public func data() async -> Data? {
    if let task { return await task.value }
    let task = Task { await self.load() }
    self.task = task
    return await task.value
  }

  private func load() async -> Data? {
    if let handle = try? FileHandle(forReadingFrom: file) {
      let data = try? handle.read(upToCount: Self.maximumBytes + 1)
      try? handle.close()
      if let data, valid(data) { return data }
    }
    do {
      let data = try await download()
      try Task.checkCancellation()
      guard valid(data) else { return nil }
      // A read-only/full disk must not prevent using the font for this session.
      try? FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? data.write(to: file, options: .atomic)
      return data
    } catch {
      return nil
    }
  }

  private func valid(_ data: Data) -> Bool {
    !data.isEmpty && data.count <= Self.maximumBytes && validate(data)
  }

  public static func download() async throws -> Data {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.timeoutIntervalForRequest = 10
    configuration.timeoutIntervalForResource = 15
    configuration.waitsForConnectivity = false
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    var request = URLRequest(
      url: sourceURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
    request.setValue("AetherAtlas (optional symbol font)", forHTTPHeaderField: "User-Agent")
    return try await download(session: session, request: request)
  }

  static func download(session: URLSession, request: URLRequest) async throws -> Data {
    let (bytes, response) = try await session.bytes(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
      http.url?.scheme == "https", response.expectedContentLength <= Int64(maximumBytes)
    else { throw URLError(.badServerResponse) }
    var data = Data()
    for try await byte in bytes {
      try Task.checkCancellation()
      guard data.count < maximumBytes else { throw URLError(.dataLengthExceedsMaximum) }
      data.append(byte)
    }
    return data
  }
}
