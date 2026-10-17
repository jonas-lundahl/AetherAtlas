import Foundation
import Testing

#if SWIFT_PACKAGE
  @testable import AetherCore
#else
  @testable import AetherAtlas
#endif

private let updateReleaseJSON =
  #"{"tag_name":"20261017.1102","draft":false,"prerelease":false,"html_url":"https://untrusted.invalid/update"}"#

@Test func numericUpdateVersionOrdering() throws {
  let old = try #require(AppVersion("20261017.0959"))
  let new = try #require(AppVersion("20261017.1102"))
  #expect(old < new)
  #expect(new < AppVersion("20261018.0000")!)
  #expect(AppVersion("1.0")! < new)
  #expect(AppVersion("v20261017.1102") == new)
  #expect(AppVersion("1.0.0") == AppVersion("1"))
  #expect(AppVersion("1.10")! > AppVersion("1.9")!)
  #expect(AppVersion("1.0.1")! > AppVersion("1.0")!)
}

@Test(arguments: [
  "", "1..0", "1.", "nightly", "20261017.1102-beta", "1/2", "-1", "1.２", "1.2.3.4.5",
  "18446744073709551616",
])
func invalidUpdateVersionsAreRejected(_ value: String) {
  #expect(AppVersion(value) == nil)
  #expect(AppRelease(tag: value) == nil)
}

@Test func updateRequestUsesAnonymousGitHubAPIAndTrustedReleaseURL() async throws {
  let transport = StubTransport(updateReleaseJSON)
  let release = try await GitHubReleaseClient(transport: transport).latestRelease()
  #expect(release.tag == "20261017.1102")
  #expect(
    release.url.absoluteString
      == "https://github.com/jonas-lundahl/AetherAtlas/releases/tag/20261017.1102")
  let request = try #require(await transport.requests.first)
  #expect(request.url == GitHubReleaseClient.apiURL)
  #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
  #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
  #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
}

@Test(arguments: [
  (404, [:], UpdateCheckError.noRelease),
  (429, [:], UpdateCheckError.rateLimited),
  (403, ["X-RateLimit-Remaining": "0"], UpdateCheckError.rateLimited),
  (403, ["Retry-After": "60"], UpdateCheckError.rateLimited),
  (403, [:], UpdateCheckError.http(403)),
  (503, [:], UpdateCheckError.http(503)),
])
func updateHTTPFailuresAreDistinct(
  status: Int, headers: [String: String], expected: UpdateCheckError
) async {
  let client = GitHubReleaseClient(transport: StubTransport(status: status, headers: headers))
  do {
    _ = try await client.latestRelease()
    Issue.record("Expected an update check failure")
  } catch { #expect(error as? UpdateCheckError == expected) }
}

@Test(arguments: [
  "bad json", "{}",
  #"{"tag_name":"nightly","draft":false,"prerelease":false}"#,
  #"{"tag_name":"20261017.1102","draft":true,"prerelease":false}"#,
  #"{"tag_name":"20261017.1102","draft":false,"prerelease":true}"#,
])
func invalidOrUnpublishedUpdateIsNotOffered(_ payload: String) async {
  do {
    _ = try await GitHubReleaseClient(transport: StubTransport(payload)).latestRelease()
    Issue.record("Expected invalid release")
  } catch { #expect(error as? UpdateCheckError == .invalidRelease) }
}

@MainActor @Test(arguments: ["1.0", "20261017.0959", "20261017.1102", "20261018.0000"])
func updateCheckComparesInstalledVersion(_ installed: String) async throws {
  let model = AppUpdateModel(
    currentVersion: installed,
    client: GitHubReleaseClient(transport: StubTransport(updateReleaseJSON)))
  await model.check()
  let latest = try #require(AppRelease(tag: "20261017.1102"))
  #expect(model.state == (AppVersion(installed)! < latest.version ? .available(latest) : .upToDate))
}

@MainActor @Test func failedUpdateCheckDoesNotClaimAppIsCurrent() async {
  let transport = StubTransport()
  await transport.setFailure(URLError(.notConnectedToInternet))
  let model = AppUpdateModel(
    currentVersion: "1.0", client: GitHubReleaseClient(transport: transport))
  await model.check()
  guard case .failed(let message) = model.state else {
    Issue.record("Expected an error instead of an up-to-date result")
    return
  }
  #expect(message.contains("internet connection"))
}

private actor PendingReleaseChecker: AppReleaseChecking {
  private var requests: [CheckedContinuation<AppRelease, any Error>] = []
  private var observers: [(Int, CheckedContinuation<Void, Never>)] = []

  func latestRelease() async throws -> AppRelease {
    try await withCheckedThrowingContinuation { continuation in
      requests.append(continuation)
      for (count, observer) in observers where requests.count >= count { observer.resume() }
      observers.removeAll { requests.count >= $0.0 }
    }
  }

  func waitForRequests(_ count: Int) async {
    guard requests.count < count else { return }
    await withCheckedContinuation { observers.append((count, $0)) }
  }

  func complete(_ index: Int, tag: String) {
    requests[index].resume(returning: AppRelease(tag: tag)!)
  }
}

@MainActor @Test func earlierUpdateCheckCannotReplaceNewerResult() async {
  let checker = PendingReleaseChecker()
  let model = AppUpdateModel(currentVersion: "20261017.1102", client: checker)
  let earlier = Task { await model.check() }
  await checker.waitForRequests(1)
  let later = Task { await model.check() }
  await checker.waitForRequests(2)
  await checker.complete(1, tag: "20261018.1102")
  await later.value
  await checker.complete(0, tag: "20261017.1102")
  await earlier.value
  #expect(model.state == .available(AppRelease(tag: "20261018.1102")!))
}

@MainActor @Test func cancelledUpdateCheckDoesNotShowErrorOrStaleResult() async {
  let checker = PendingReleaseChecker()
  let model = AppUpdateModel(currentVersion: "1.0", client: checker)
  let task = Task { await model.check() }
  await checker.waitForRequests(1)
  task.cancel()
  await checker.complete(0, tag: "20261017.1102")
  await task.value
  #expect(model.state == .idle)
}
