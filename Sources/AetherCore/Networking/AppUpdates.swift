import Foundation

/// Numeric components keep timestamp versions and older versions in the same ordering.
public struct AppVersion: Comparable, Sendable {
  private let components: [UInt64]

  public init?(_ string: String) {
    let value = string.hasPrefix("v") ? String(string.dropFirst()) : string
    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    guard (1...4).contains(parts.count) else { return nil }
    var numbers: [UInt64] = []
    for part in parts {
      guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }),
        let number = UInt64(part)
      else { return nil }
      numbers.append(number)
    }
    while numbers.count > 1 && numbers.last == 0 { numbers.removeLast() }
    components = numbers
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    for index in 0..<max(lhs.components.count, rhs.components.count) {
      let left = index < lhs.components.count ? lhs.components[index] : 0
      let right = index < rhs.components.count ? rhs.components[index] : 0
      if left != right { return left < right }
    }
    return false
  }
}

public struct AppRelease: Equatable, Sendable {
  public let tag: String
  public let version: AppVersion
  public var url: URL {
    GitHubReleaseClient.releasesURL.appendingPathComponent("tag").appendingPathComponent(tag)
  }

  public init?(tag: String) {
    guard let version = AppVersion(tag) else { return nil }
    self.tag = tag
    self.version = version
  }
}

public enum UpdateCheckError: Error, LocalizedError, Sendable, Equatable {
  case noRelease, rateLimited, invalidRelease
  case http(Int)

  public var errorDescription: String? {
    switch self {
    case .noRelease:
      "No published release is available yet. You can check the releases page in your browser."
    case .rateLimited:
      "GitHub is limiting requests right now. Please try again later or open the releases page."
    case .invalidRelease:
      "The latest release could not be read. You can still open the releases page in your browser."
    case .http(let status):
      "GitHub could not provide update information (HTTP \(status)). Please try again later."
    }
  }
}

public protocol AppReleaseChecking: Sendable {
  func latestRelease() async throws -> AppRelease
}

public struct GitHubReleaseClient: AppReleaseChecking {
  public static let releasesURL = URL(
    string: "https://github.com/jonas-lundahl/AetherAtlas/releases")!
  public static let apiURL = URL(
    string: "https://api.github.com/repos/jonas-lundahl/AetherAtlas/releases/latest")!
  private let transport: any HTTPTransport

  public init(transport: any HTTPTransport = URLSessionTransport()) {
    self.transport = transport
  }

  public func latestRelease() async throws -> AppRelease {
    var request = URLRequest(
      url: Self.apiURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("AetherAtlas (manual update check)", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await transport.data(for: request)
    try Task.checkCancellation()
    switch response.statusCode {
    case 200: break
    case 404: throw UpdateCheckError.noRelease
    case 429: throw UpdateCheckError.rateLimited
    case 403
    where response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0"
      || response.value(forHTTPHeaderField: "Retry-After") != nil:
      throw UpdateCheckError.rateLimited
    default: throw UpdateCheckError.http(response.statusCode)
    }

    struct Release: Decodable {
      let tag: String
      let draft: Bool
      let prerelease: Bool
      enum CodingKeys: String, CodingKey {
        case tag = "tag_name"
        case draft, prerelease
      }
    }
    guard data.count <= 2 * 1024 * 1024,
      let info = try? JSONDecoder().decode(Release.self, from: data),
      !info.draft, !info.prerelease, let release = AppRelease(tag: info.tag)
    else { throw UpdateCheckError.invalidRelease }
    return release
  }
}
