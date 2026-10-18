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
      guard let path, !path.isEmpty else { return }
      do {
        image = try await icons.image(path: path)
      } catch {
        // The entity remains readable with a native fallback symbol.
      }
    }
  }
}
