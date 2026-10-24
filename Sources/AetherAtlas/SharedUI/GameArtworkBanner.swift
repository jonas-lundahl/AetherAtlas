import AppKit
import SwiftUI

struct GameArtworkBanner: View {
  let path: String
  let icons: IconStore
  @State private var image: NSImage?
  @State private var failed = false

  var body: some View {
    Group {
      if let image {
        Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
          .frame(maxHeight: 180)
          .clipShape(RoundedRectangle(cornerRadius: 4))
      } else if !failed {
        Rectangle().fill(.primary.opacity(0.04)).aspectRatio(3.2, contentMode: .fit)
          .frame(maxHeight: 180)
          .overlay { ProgressView().controlSize(.small) }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityHidden(true)
    .task(id: path) {
      image = nil
      failed = false
      do {
        let result = try await icons.image(path: path)
        try Task.checkCancellation()
        image = result
        failed = result == nil
      } catch {
        if !Task.isCancelled { failed = true }
      }
    }
  }
}
