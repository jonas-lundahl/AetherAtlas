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
      AppUpdateCommands()
      CommandGroup(after: .textEditing) {
        Button("Find") { workspace.searchFocus += 1 }.keyboardShortcut("f")
      }
      CommandMenu("Navigate") {
        Button("Back", systemImage: "chevron.left") { workspace.goBack() }
          .keyboardShortcut("[", modifiers: .command).disabled(
            !workspace.canGoBack)
        Button("Forward", systemImage: "chevron.right") { workspace.goForward() }
          .keyboardShortcut("]", modifiers: .command).disabled(
            !workspace.canGoForward)
        Divider()
        Button("Toggle Favorite", systemImage: "star") {
          workspace.toggleCurrentFavorite()
        }.keyboardShortcut("d", modifiers: .command).disabled(
          !workspace.canToggleFavorite)
        Button("Refresh Results") {
          workspace.refreshResults()
        }.keyboardShortcut(
          "r", modifiers: .command)
      }
    }
    Window("Software Update", id: "app-updates") {
      AppUpdateView(model: workspace.updates)
    }
    .windowResizability(.contentSize)
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)
    Settings { SettingsView(version: workspace.updates.currentVersion) }
  }
}
