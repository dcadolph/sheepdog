import Foundation
import Testing

@testable import SheepdogCore

// VersionCase is one text and the version it should parse to.
struct VersionCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Text is the version text.
    let text: String
    // Want is the parsed numbers, or nil when the text is not a release version.
    let want: [Int]?

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// versionCases cover accepted and refused spellings.
let versionCases: [VersionCase] = [
    VersionCase(name: "plain", text: "1.2.3", want: [1, 2, 3]), // Test 0: Plain.
    VersionCase(name: "v prefix", text: "v1.2.3", want: [1, 2, 3]), // Test 1: Prefixed.
    VersionCase(name: "two parts", text: "1.2", want: nil), // Test 2: Two parts.
    VersionCase(name: "four parts", text: "1.2.3.4", want: nil), // Test 3: Four parts.
    VersionCase(name: "prerelease", text: "v1.2.3-rc1", want: nil), // Test 4: Prerelease.
    VersionCase(name: "garbage", text: "latest", want: nil), // Test 5: Words.
    VersionCase(name: "empty", text: "", want: nil), // Test 6: Empty.
    VersionCase(name: "empty part", text: "1..3", want: nil), // Test 7: Empty part.
    VersionCase(name: "sign", text: "1.+2.3", want: nil), // Test 8: Sign.
    VersionCase(name: "non-ASCII digit", text: "1.٢.3", want: nil), // Test 9: Arabic-Indic digit.
    VersionCase(name: "double v", text: "vv1.2.3", want: nil), // Test 10: Double prefix.
]

// testReleaseVersionParse checks which spellings parse.
@Test(arguments: versionCases)
func testReleaseVersionParse(test: VersionCase) {
    let got = ReleaseVersion(test.text).map { [$0.major, $0.minor, $0.patch] }
    #expect(got == test.want)
}

// testReleaseVersionOrder checks ordering, including numeric rather than text order.
@Test func testReleaseVersionOrder() throws {
    let v190 = try #require(ReleaseVersion("1.9.0"))
    let v1100 = try #require(ReleaseVersion("1.10.0"))
    let v120 = try #require(ReleaseVersion("1.2.0"))
    let v121 = try #require(ReleaseVersion("1.2.1"))
    #expect(v1100 > v190)
    #expect(v121 > v120)
    #expect(!(v120 > v120))
    #expect(!(v120 > v121))
}

// UpdateCase is one fake GitHub response and the outcome the checker should give.
struct UpdateCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Status is the HTTP status returned.
    let status: Int
    // Body is the response body.
    let body: String
    // WantTag is the tag expected back, or nil when no update is reported.
    let wantTag: String?
    // Want is the error expected, or nil for none.
    let want: UpdateError?

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// release builds a GitHub release body.
func release(tag: String, url: String = "https://github.com/dcadolph/sheepdog/releases/tag/v9", extra: String = "") -> String {
    "{\"tag_name\":\"\(tag)\",\"html_url\":\"\(url)\"\(extra)}"
}

// updateCases run the checker against the running version 1.2.0.
let updateCases: [UpdateCase] = [
    UpdateCase( // Test 0: A newer release is reported.
        name: "newer", status: 200, body: release(tag: "v1.3.0"), wantTag: "v1.3.0", want: nil
    ),
    UpdateCase( // Test 1: The same release is not.
        name: "same", status: 200, body: release(tag: "v1.2.0"), wantTag: nil, want: nil
    ),
    UpdateCase( // Test 2: An older release is not.
        name: "older", status: 200, body: release(tag: "v1.1.1"), wantTag: nil, want: nil
    ),
    UpdateCase( // Test 3: A prerelease is ignored.
        name: "prerelease flag", status: 200, body: release(tag: "v1.3.0", extra: ",\"prerelease\":true"),
        wantTag: nil, want: nil
    ),
    UpdateCase( // Test 4: A draft is ignored.
        name: "draft", status: 200, body: release(tag: "v1.3.0", extra: ",\"draft\":true"), wantTag: nil, want: nil
    ),
    UpdateCase( // Test 5: A tag that does not parse is ignored.
        name: "odd tag", status: 200, body: release(tag: "nightly"), wantTag: nil, want: nil
    ),
    UpdateCase( // Test 6: A page off github.com is ignored.
        name: "foreign page", status: 200, body: release(tag: "v1.3.0", url: "https://example.com/x"),
        wantTag: nil, want: nil
    ),
    UpdateCase( // Test 7: A plain http page is ignored.
        name: "http page", status: 200, body: release(tag: "v1.3.0", url: "http://github.com/x"),
        wantTag: nil, want: nil
    ),
    UpdateCase( // Test 8: A missing release is a server error.
        name: "not found", status: 404, body: "{}", wantTag: nil, want: .server(status: 404)
    ),
    UpdateCase( // Test 9: A rate limit is a server error.
        name: "rate limited", status: 403, body: "{}", wantTag: nil, want: .server(status: 403)
    ),
    UpdateCase( // Test 10: Too many requests is a server error.
        name: "too many", status: 429, body: "{}", wantTag: nil, want: .server(status: 429)
    ),
    UpdateCase( // Test 11: A body that is not a release is a decode error.
        name: "malformed", status: 200, body: "not json", wantTag: nil, want: .decode
    ),
    UpdateCase( // Test 12: A release with no tag is a decode error.
        name: "no tag", status: 200, body: "{\"html_url\":\"https://github.com/x\"}", wantTag: nil, want: .decode
    ),
]

// testUpdateChecker checks the outcome for each fake response.
@Test(arguments: updateCases)
func testUpdateChecker(test: UpdateCase) async throws {
    let client = HTTPClientFunc { _ in (Data(test.body.utf8), test.status) }
    let checker = UpdateChecker(client: client, current: try #require(ReleaseVersion("1.2.0")))
    if let want = test.want {
        await #expect(throws: want) { try await checker.check() }
        return
    }
    let got = try await checker.check()
    #expect(got?.tag == test.wantTag)
}

// testUpdateCheckerTransportError checks that a thrown transport error passes through.
@Test func testUpdateCheckerTransportError() async throws {
    struct Down: Error {}
    let client = HTTPClientFunc { _ in throw Down() }
    let checker = UpdateChecker(client: client, current: try #require(ReleaseVersion("1.2.0")))
    await #expect(throws: Down.self) { try await checker.check() }
}

// testUpdateSchedule checks the launch delay, the daily freshness and a clock set backward.
@Test func testUpdateSchedule() {
    let launched = stamp("2026-10-23 09:00")
    let last = stamp("2026-10-23 09:01")
    #expect(!UpdateSchedule.isDue(lastChecked: nil, launched: launched, now: stamp("2026-10-23 09:00")))
    #expect(UpdateSchedule.isDue(lastChecked: nil, launched: launched, now: stamp("2026-10-23 09:01")))
    #expect(!UpdateSchedule.isDue(lastChecked: last, launched: launched, now: stamp("2026-10-24 09:00")))
    #expect(UpdateSchedule.isDue(lastChecked: last, launched: launched, now: stamp("2026-10-24 09:01")))
    #expect(UpdateSchedule.isDue(lastChecked: stamp("2026-10-25 09:00"), launched: launched, now: last))
}

// testCheckForUpdatesDefault checks that settings saved before the toggle existed turn it on.
@Test func testCheckForUpdatesDefault() throws {
    let settings = try JSONDecoder().decode(AlertSettings.self, from: Data("{}".utf8))
    #expect(settings.checkForUpdates)
}
