import AppKit
import SwiftUI

struct GameIcon: View {
  let path: String?
  let kind: EntityKind
  let icons: IconStore
  var size: CGFloat = 36
  var framed = true
  var showsFallback = true
  @State private var image: NSImage?
  var body: some View {
    ZStack {
      if framed { RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.6)) }
      if let image {
        Image(nsImage: image).resizable().interpolation(.high).scaledToFit().padding(2)
      } else if showsFallback {
        Image(systemName: kind.symbol).font(.system(size: size * 0.40)).foregroundStyle(.secondary)
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: 7))
    .accessibilityHidden(true)
    .task(id: path) {
      image = nil
      let fallback = kind == .map ? GameMap.fallbackThumbnailPath : nil
      let candidates = [path, fallback].compactMap { $0 }.filter { !$0.isEmpty }
      var seen = Set<String>()
      for candidate in candidates where seen.insert(candidate).inserted {
        do {
          let value = try await icons.image(path: candidate)
          try Task.checkCancellation()
          if let value {
            image = value
            return
          }
        } catch { if Task.isCancelled { return } }
      }
    }
  }
}
