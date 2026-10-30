import Foundation
import Security

import SheepdogCore

// CodeTrust decides whether a downloaded Sheepdog bundle may replace the running app. Each check
// refuses on any mismatch and names the step that refused.
enum CodeTrust {
    // bundleID is the identifier every Sheepdog release carries.
    static let bundleID = "com.dcadolph.sheepdog"
    // assessTimeout bounds the spctl run.
    static let assessTimeout: TimeInterval = 20

    // verify runs the signature, designated requirement, notarization and Info.plist checks on the
    // bundle in that order and returns the first refusal, or nil when every check passes. running
    // is the running app's designated requirement, and current is its version.
    static func verify(bundle: URL, version: String, current: ReleaseVersion, running: String?) -> UpdateVerdict? {
        guard Install.signed(bundle.path, requirement: Install.releaseRequirement) else {
            return .signature
        }
        guard let running, let candidate = designatedRequirement(of: bundle), candidate == running else {
            return .requirement
        }
        guard Install.notarized(assess(bundle)) else {
            return .notarization
        }
        guard plistMatches(bundle, version: version, current: current) else {
            return .plist
        }
        return nil
    }

    // designatedRequirement returns the designated requirement of the bundle as text, or nil when
    // it has none.
    static func designatedRequirement(of bundle: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code else {
            return nil
        }
        return text(of: code)
    }

    // runningRequirement returns the running app's designated requirement as text, or nil when the
    // app is unsigned.
    static func runningRequirement() -> String? {
        var me: SecCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me else {
            return nil
        }
        var code: SecStaticCode?
        guard SecCodeCopyStaticCode(me, [], &code) == errSecSuccess, let code else {
            return nil
        }
        return text(of: code)
    }

    // text renders the designated requirement of the static code.
    private static func text(of code: SecStaticCode) -> String? {
        var req: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(code, [], &req) == errSecSuccess, let req else {
            return nil
        }
        var out: CFString?
        guard SecRequirementCopyString(req, [], &out) == errSecSuccess, let out else {
            return nil
        }
        return out as String
    }

    // assess runs spctl's execute assessment on the bundle and returns what it printed, or an
    // empty string when it could not run or ran past assessTimeout. The output goes to a file rather
    // than a pipe, so the wait is bounded by the timeout and never by spctl closing its output.
    static func assess(_ bundle: URL) -> String {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("spctl-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: out.path, contents: nil),
            let handle = try? FileHandle(forWritingTo: out)
        else {
            return ""
        }
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: out)
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/spctl")
        task.arguments = ["--assess", "--type", "execute", "--verbose=4", bundle.path]
        task.standardOutput = handle
        task.standardError = handle
        let done = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in done.signal() }
        do {
            try task.run()
        } catch {
            return ""
        }
        guard done.wait(timeout: .now() + assessTimeout) == .success else {
            task.terminate()
            return ""
        }
        guard task.terminationStatus == 0, let data = try? Data(contentsOf: out) else {
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }

    // plistMatches reports whether the bundle's Info.plist names Sheepdog at the expected version,
    // that version is newer than current, and the bundle runs on os.
    static func plistMatches(
        _ bundle: URL, version: String, current: ReleaseVersion,
        os: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> Bool {
        let url = bundle.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            plist["CFBundleIdentifier"] as? String == bundleID,
            let short = plist["CFBundleShortVersionString"] as? String, short == version,
            let got = ReleaseVersion(short)
        else {
            return false
        }
        return got > current && Install.runs(minimum: plist["LSMinimumSystemVersion"] as? String, on: os)
    }
}
