import Foundation

// LaunchMarker is how a build says it started, and how the next launch learns the last one ended
// without Quit. The relaunch helper reads it to decide whether to roll back.
struct LaunchMarker {
    // folder holds the marker files.
    let folder: URL

    // marker holds the build number of the last launch that finished starting.
    var marker: URL { folder.appendingPathComponent("launched") }
    // starting holds the build number and pid of a launch under way.
    var starting: URL { folder.appendingPathComponent("launched.pid") }
    // quitNote is present when the last run ended through Quit.
    var quitNote: URL { folder.appendingPathComponent("quit") }

    // begin records the build and pid of a launch under way, and reports whether the last run of the
    // same build ended without Quit.
    func begin(build: String, pid: Int32) -> Bool {
        let files = FileManager.default
        try? files.createDirectory(at: folder, withIntermediateDirectories: true)
        let last = (try? String(contentsOf: marker, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let crashed = last == build && !files.fileExists(atPath: quitNote.path)
        try? "\(build) \(pid)\n".write(to: starting, atomically: true, encoding: .utf8)
        return crashed
    }

    // finish records that the build finished starting and clears the last run's quit note.
    func finish(build: String) {
        try? FileManager.default.removeItem(at: quitNote)
        try? "\(build)\n".write(to: marker, atomically: true, encoding: .utf8)
    }

    // quit records a clean quit.
    func quit() {
        try? Data().write(to: quitNote)
    }
}

// Relaunch starts a bundle once this process has exited. With a launch marker it also waits for the
// new build to say it started and, when it never does, stops it, puts the previous bundle back and
// starts that. A new build that is running but never wrote its pid is found by its path.
enum Relaunch {
    // script is the detached helper. It takes the waited pid, the opener, the bundle, the previous
    // bundle, where to park a failed bundle, the marker, the build the marker must hold, the seconds
    // to wait, then the opener's extra arguments. An empty marker skips the wait and the rollback.
    static let script = """
        pid=$1 opener=$2 bundle=$3 previous=$4 failed=$5 marker=$6 build=$7 wait=$8
        shift 8
        while /bin/kill -0 "$pid" 2>/dev/null; do /bin/sleep 0.2; done
        "$opener" "$bundle" "$@" &
        [ -n "$marker" ] || exit 0
        n=$((wait * 5))
        while [ "$n" -gt 0 ]; do
            if [ -f "$marker" ]; then
                got=
                read -r got < "$marker"
                [ "$got" = "$build" ] && exit 0
            fi
            /bin/sleep 0.2
            n=$((n - 1))
        done
        if [ -f "$marker.pid" ]; then
            b= p=
            read -r b p < "$marker.pid"
            [ "$b" = "$build" ] && [ -n "$p" ] && /bin/kill "$p" 2>/dev/null
        fi
        for p in $(/usr/bin/pgrep -f -- "$bundle"); do
            [ "$p" = "$$" ] || /bin/kill "$p" 2>/dev/null
        done
        /bin/sleep 1
        /bin/mv "$bundle" "$failed" && /bin/mv "$previous" "$bundle" && exec "$opener" "$bundle"
        """

    // Plan names what the helper starts and how it rolls back.
    struct Plan {
        // bundle is what the helper starts.
        var bundle: URL
        // previous is the bundle put back when the new one never writes the marker.
        var previous: URL?
        // failed is where a bundle that never wrote the marker is parked.
        var failed: URL?
        // marker is the file the new build writes its build number to once it has started.
        var marker: URL?
        // build is the build number the marker must hold.
        var build = ""
        // wait is how many seconds the helper waits for the marker.
        var wait = 30
        // opener starts the bundle. /usr/bin/open in the app.
        var opener = "/usr/bin/open"
        // pid is the process the helper waits on before it starts the bundle.
        var pid = ProcessInfo.processInfo.processIdentifier
    }

    // arguments returns the helper's command line for the plan.
    static func arguments(_ plan: Plan, extra: [String] = []) -> [String] {
        [
            "-c", script, "sh", String(plan.pid), plan.opener, plan.bundle.path, plan.previous?.path ?? "",
            plan.failed?.path ?? "", plan.marker?.path ?? "", plan.build, String(plan.wait),
        ] + extra
    }

    // start runs the helper detached and returns at once.
    @discardableResult
    static func start(_ plan: Plan, extra: [String] = []) throws -> Process {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = arguments(plan, extra: extra)
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()
        return task
    }
}
