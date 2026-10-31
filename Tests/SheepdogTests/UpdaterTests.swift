import Foundation
import Testing

@testable import Sheepdog
@testable import SheepdogCore

// testDownloader refuses every download, since these tests stage a bundle directly.
struct testDownloader: Downloader {
    // download always fails with a 404.
    func download(_ url: URL, to file: URL, limit: Int) async throws {
        throw DownloadError.status(404)
    }
}

// testTrust accepts every bundle.
struct testTrust: Trust {
    // verify reports no refusal.
    func verify(bundle: URL, version: String) -> UpdateVerdict? {
        nil
    }
}

// newTestUpdater builds an updater for 1.0.0 whose network and trust are fakes.
@MainActor
func newTestUpdater() throws -> Updater {
    let client = HTTPClientFunc { _ in (Data(), 404) }
    let current = try #require(ReleaseVersion("1.0.0"))
    let cache = FileManager.default.temporaryDirectory.appendingPathComponent("sheepdog-updater-test")
    return Updater(
        client: client, downloader: testDownloader(), trust: testTrust(), current: current,
        bundle: URL(fileURLWithPath: "/Applications/Sheepdog.app"), cache: cache)
}

// testUpdaterTickInstallsWhenQuiet checks that a staged update installs once on a quiet tick.
@MainActor
@Test func testUpdaterTickInstallsWhenQuiet() throws {
    let updater = try newTestUpdater()
    var installed: [String] = []
    updater.quiet = { true }
    updater.install = { _, tag in installed.append(tag) }
    updater.stage(URL(fileURLWithPath: "/tmp/Sheepdog.app"), tag: "v1.1.0")
    updater.tick()
    updater.tick()
    #expect(installed == ["v1.1.0"])
    #expect(updater.state == .installing("v1.1.0"))
}
