//
//  VMModels.swift
//  DevDash
//

import Foundation

/// Tool that runs the VM
enum VMProvider: String, Codable, CaseIterable {
    case lima
    case apple

    var displayName: String {
        switch self {
        case .lima: return "Lima"
        case .apple: return "Apple Machine"
        }
    }

    var icon: String {
        switch self {
        case .lima: return "server.rack"
        case .apple: return "apple.logo"
        }
    }

    func startArgs(_ name: String) -> (tool: String, args: [String]) {
        switch self {
        case .lima: return ("limactl", ["start", "--tty=false", name])
        // Apple machines boot on `run`. There is no start subcommand.
        case .apple: return ("container", ["machine", "run", "-n", name, "--", "true"])
        }
    }

    func stopArgs(_ name: String) -> (tool: String, args: [String]) {
        switch self {
        case .lima: return ("limactl", ["stop", name])
        case .apple: return ("container", ["machine", "stop", name])
        }
    }

    func deleteArgs(_ name: String) -> (tool: String, args: [String]) {
        switch self {
        case .lima: return ("limactl", ["delete", "--force", name])
        case .apple: return ("container", ["machine", "delete", name])
        }
    }

    /// Shell command opened in Terminal
    func shellCommand(_ name: String) -> String {
        switch self {
        case .lima: return "limactl shell \(ShellCommand.quote(name))"
        case .apple: return "container machine run -n \(ShellCommand.quote(name))"
        }
    }
}

/// A VM read live from its provider. DevDash stores nothing about it.
struct VMInfo: Identifiable, Hashable {
    var id: String { "\(provider.rawValue)-\(name)" }
    let provider: VMProvider
    let name: String
    let status: String        // e.g. "Running", "Stopped"
    let cpus: Int?
    let memoryBytes: Int64?
    let diskBytes: Int64?
    let arch: String?
    let sshPort: Int?
    let dir: String?          // Lima instance folder (holds lima.yaml)

    var isRunning: Bool { status.lowercased() == "running" }
}

/// One VM in the backup file
struct VMBackupEntry: Codable {
    let provider: VMProvider
    let name: String
    let cpus: Int?
    let memoryBytes: Int64?
    let diskBytes: Int64?
    let limaYAML: String?     // Lima config, enough to recreate the VM
}
