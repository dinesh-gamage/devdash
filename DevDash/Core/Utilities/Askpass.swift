//
//  Askpass.swift
//  DevDash
//
//  Password popups for service commands. sudo and ssh call a helper script that shows
//  a macOS dialog and prints the answer. DevDash never sees or stores the password.
//

import Foundation

enum Askpass {
    /// ~/Library/Application Support/DevDash/askpass
    nonisolated private static let dir = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("DevDash/askpass")

    /// Dialog helper. $1 is the prompt from sudo or ssh. Cancel exits 1, so the command fails.
    nonisolated private static let helper = """
    #!/bin/sh
    exec /usr/bin/osascript - "${1:-Password:}" "${DEVDASH_SERVICE:-DevDash}" <<'EOF'
    on run argv
        set r to display dialog (item 1 of argv) with title (item 2 of argv) default answer "" with hidden answer with icon caution
        return text returned of r
    end run
    EOF
    """

    /// macOS sudo only uses an askpass helper when called with -A. This wrapper sits first on PATH and adds it.
    /// `exec` keeps the pid, so stopping the service still signals sudo, which passes it on.
    nonisolated private static let sudoWrapper = """
    #!/bin/sh
    for a in "$@"; do [ "$a" = "-S" ] && exec /usr/bin/sudo "$@"; done
    exec /usr/bin/sudo -A "$@"
    """

    /// Written once per launch
    nonisolated private static let installed: Bool = {
        let fm = FileManager.default
        let bin = dir.appendingPathComponent("bin")
        do {
            try fm.createDirectory(at: bin, withIntermediateDirectories: true)
            for (url, text) in [(dir.appendingPathComponent("askpass.sh"), helper), (bin.appendingPathComponent("sudo"), sudoWrapper)] {
                try text.write(to: url, atomically: true, encoding: .utf8)
                try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            }
            return true
        } catch {
            return false
        }
    }()

    /// Adds the askpass variables to a service's environment
    nonisolated static func environment(_ base: [String: String], service: String) -> [String: String] {
        guard installed else { return base }
        var env = base
        let askpass = dir.appendingPathComponent("askpass.sh").path
        env["PATH"] = dir.appendingPathComponent("bin").path + ":" + (base["PATH"] ?? "/usr/bin:/bin")
        env["SUDO_ASKPASS"] = askpass
        env["SSH_ASKPASS"] = askpass
        env["SSH_ASKPASS_REQUIRE"] = "force"
        env["DEVDASH_SERVICE"] = service
        return env
    }
}
