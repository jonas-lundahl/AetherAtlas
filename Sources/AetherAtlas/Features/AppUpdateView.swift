import SwiftUI

struct AppUpdateCommands: Commands {
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(after: .appInfo) {
      Button("Check for Updates…") { openWindow(id: "app-updates") }
    }
  }
}

struct AppUpdateView: View {
  let model: AppUpdateModel
  @Environment(\.openURL) private var openURL
  @Environment(\.dismissWindow) private var dismissWindow
  @State private var checkID = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(spacing: 14) {
        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
          .font(.system(size: 44)).foregroundStyle(.tint).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
          Text("Aether Atlas Updates").font(.title2.bold())
          Text("Installed version \(model.currentVersion)")
            .foregroundStyle(.secondary).textSelection(.enabled)
        }
      }
      Group {
        switch model.state {
        case .idle, .checking:
          HStack {
            ProgressView().controlSize(.small)
            Text("Checking GitHub for updates…")
          }
        case .upToDate:
          Label("You’re up to date.", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green).font(.headline)
        case .available(let release):
          VStack(alignment: .leading, spacing: 8) {
            Text("Version \(release.tag) is available.").font(.headline)
            Text(
              "Open the release in your browser to download the ZIP. Quit Aether Atlas, then replace the app in Applications."
            )
            .foregroundStyle(.secondary)
          }
        case .failed(let message):
          Text(message).foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityIdentifier("updateStatus")

      HStack {
        Link("All Releases", destination: GitHubReleaseClient.releasesURL)
        Spacer()
        Button("Check Again") { checkID += 1 }
          .disabled(model.state == .checking || model.state == .idle)
        if case .available(let release) = model.state {
          Button("Download Update…") { openURL(release.url) }
            .keyboardShortcut(.defaultAction)
        } else {
          Button("Done") { dismissWindow(id: "app-updates") }
            .keyboardShortcut(.defaultAction)
        }
      }
    }
    .padding(24).frame(width: 500)
    .fixedSize(horizontal: false, vertical: true)
    .task(id: checkID) { await model.check() }
  }
}
