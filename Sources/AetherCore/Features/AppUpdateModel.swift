import Foundation
import Observation

public enum AppUpdateState: Equatable, Sendable {
  case idle, checking, upToDate
  case available(AppRelease)
  case failed(String)
}

@MainActor @Observable public final class AppUpdateModel {
  public private(set) var state: AppUpdateState = .idle
  public let currentVersion: String
  private let client: any AppReleaseChecking
  private var generation = 0

  public init(currentVersion: String, client: any AppReleaseChecking = GitHubReleaseClient()) {
    self.currentVersion = currentVersion
    self.client = client
  }

  public func check() async {
    generation += 1
    let request = generation
    guard let installed = AppVersion(currentVersion) else {
      state = .failed(
        "The installed app version could not be read. Open the releases page to check for updates.")
      return
    }
    state = .checking
    do {
      let latest = try await client.latestRelease()
      try Task.checkCancellation()
      guard request == generation else { return }
      state = latest.version > installed ? .available(latest) : .upToDate
    } catch {
      guard request == generation else { return }
      if Task.isCancelled || error is CancellationError
        || (error as? URLError)?.code == .cancelled
      {
        state = .idle
      } else {
        state = .failed(
          (error as? UpdateCheckError)?.errorDescription
            ?? "Couldn’t connect to GitHub. Check your internet connection and try again.")
      }
    }
  }
}
