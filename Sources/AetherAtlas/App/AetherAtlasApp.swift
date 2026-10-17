import SwiftUI

@main struct AetherAtlasApp: App {
  @State private var workspace = Workspace()
  var body: some Scene {
    WindowGroup("Aether Atlas") {
      BrowserView(workspace: workspace)
        .frame(minWidth: 960, minHeight: 620)
    }
    .defaultSize(width: 1320, height: 840)
    .commands {
      CommandGroup(after: .textEditing) {
        Button("Find in Game Database") { workspace.searchFocus += 1 }.keyboardShortcut("f")
      }
      CommandMenu("Navigate") {
        Button("Back", systemImage: "chevron.left") { workspace.navigation.back() }
          .keyboardShortcut("[", modifiers: .command).disabled(!workspace.navigation.canBack)
        Button("Forward", systemImage: "chevron.right") { workspace.navigation.forward() }
          .keyboardShortcut("]", modifiers: .command).disabled(!workspace.navigation.canForward)
        Divider()
        Button("Toggle Favorite", systemImage: "star") {
          if let entity = workspace.detail.detail?.entity ?? workspace.navigation.current {
            Task { await workspace.library.toggle(entity) }
          }
        }.keyboardShortcut("d", modifiers: .command).disabled(workspace.navigation.current == nil)
        Button("Refresh Results") { workspace.search.retry() }.keyboardShortcut(
          "r", modifiers: .command)
      }
    }
    Settings { SettingsView() }
  }
}
