import AppKit

/// Decoded images have their own memory budget, independent of the raw response cache.
@MainActor final class IconStore {
  private let images = NSCache<NSString, NSImage>()
  private let responses: ResponseCache
  init(responses: ResponseCache) {
    self.responses = responses
    images.totalCostLimit = 16 * 1_024 * 1_024
    images.countLimit = 256
  }
  func image(path: String) async throws -> NSImage? {
    let key = path as NSString
    if let image = images.object(forKey: key) { return image }
    let resource = try await responses.resource(.asset(path: path), ttl: 86_400)
    try Task.checkCancellation()
    if let image = images.object(forKey: key) { return image }
    guard let image = NSImage(data: resource.data) else { return nil }
    let cost = image.representations.reduce(0) { $0 + $1.pixelsWide * $1.pixelsHigh * 4 }
    images.setObject(image, forKey: key, cost: cost)
    return image
  }
}
