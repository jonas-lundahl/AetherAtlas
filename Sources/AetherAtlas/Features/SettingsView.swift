import SwiftUI

struct SettingsView: View {
  let version: String
  @Environment(\.openWindow) private var openWindow
  var body: some View {
    Form {
      Section("Aether Atlas") {
        Text("A native field guide to Final Fantasy XIV.").font(.headline)
        Text(
          "Search items, recipes, quests, NPCs, and actions. Use ⌘F to search, ⌘D to save a favorite, and ⌘[ / ⌘] to navigate."
        )
      }
      Section("Updates") {
        Text("Version \(version)")
        Button("Check for Updates…") { openWindow(id: "app-updates") }
      }
      Section("Local data") {
        Text(
          "Favorites and the last 100 viewed entities are saved in Application Support/AetherAtlas. Responses and icons use a cache limited to 128 MiB on disk. Cached data may be shown if the connection fails; it is labeled as a saved copy. The optional FFXIV symbol font is downloaded once from the Lodestone and kept in Application Support without expiry. If unavailable, normal fonts are used."
        )
      }
      Section("Data & attribution") {
        Link(
          "XIVAPI documentation", destination: URL(string: "https://v2.xivapi.com/docs/welcome/")!)
        Text(
          "FINAL FANTASY XIV © SQUARE ENIX. Aether Atlas is an independent community tool, unaffiliated with Square Enix. Icons are requested from XIVAPI as you browse and are not bundled with the app. The optional XIV AXIS symbol font is downloaded from Square Enix; its copyright notices remain in the cached font. No account, API key, analytics, or backend is used."
        )
      }
    }.formStyle(.grouped).frame(width: 540, height: 520)
  }
}
