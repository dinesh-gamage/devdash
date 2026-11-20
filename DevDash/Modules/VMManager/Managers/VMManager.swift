//
//  VMManager.swift
//  DevDash
//
//  Lists Lima VMs and Apple container machines live from their CLIs.
//

import Foundation
import Combine

@MainActor
class VMManager: ObservableObject {
    @Published var vms: [VMInfo] = []
    @Published var busy: [String: String] = [:]     // VM id → action in progress ("Starting")
    @Published private(set) var isLoading = false

    // Heavy: command output per VM, only observed by the detail view
    private var outputs: [String: CommandOutputViewModel] = [:]

    private weak var alertQueue: AlertQueue?
    private weak var toastQueue: ToastQueue?

    init(alertQueue: AlertQueue? = nil, toastQueue: ToastQueue? = nil) {
        self.alertQueue = alertQueue
        self.toastQueue = toastQueue
    }

    func output(for vm: VMInfo) -> CommandOutputViewModel {
        if let existing = outputs[vm.id] { return existing }
        let model = CommandOutputViewModel()
        outputs[vm.id] = model
        return model
    }

    // MARK: - List

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        let env = ProcessEnvironment.shared.getEnvironment()
        async let lima = ShellCommand.run("limactl", ["list", "--json"], env: env)
        async let apple = ShellCommand.run("container", ["machine", "list", "--format", "json"], env: env)
        let (l, a) = await (lima, apple)
        vms = (Self.parseLima(l.stdout) + Self.parseApple(a.stdout))
            .sorted { ($0.provider.rawValue, $0.name) < ($1.provider.rawValue, $1.name) }
    }

    /// `limactl list --json` prints one JSON object per line
    nonisolated static func parseLima(_ output: String) -> [VMInfo] {
        struct Lima: Decodable {
            let name: String
            let status: String
            let arch: String?
            let cpus: Int?
            let memory: Int64?
            let disk: Int64?
            let sshLocalPort: Int?
            let dir: String?
        }
        return output.split(whereSeparator: \.isNewline).compactMap { line in
            guard let l = try? JSONDecoder().decode(Lima.self, from: Data(line.utf8)) else { return nil }
            return VMInfo(provider: .lima, name: l.name, status: l.status, cpus: l.cpus, memoryBytes: l.memory,
                          diskBytes: l.disk, arch: l.arch, sshPort: l.sshLocalPort, dir: l.dir)
        }
    }

    /// `container machine list --format json`
    // ponytail: field names guessed from the table columns (no machine existed to check against).
    // Read loosely so a renamed field shows as blank instead of hiding the machine.
    nonisolated static func parseApple(_ output: String) -> [VMInfo] {
        guard let items = (try? JSONSerialization.jsonObject(with: Data(output.utf8))) as? [[String: Any]] else { return [] }
        func int(_ d: [String: Any], _ keys: String...) -> Int64? {
            for k in keys { if let n = d[k] as? NSNumber { return n.int64Value } }
            return nil
        }
        return items.compactMap { d in
            let config = d["configuration"] as? [String: Any] ?? [:]
            let merged = d.merging(config) { a, _ in a }
            guard let name = (merged["name"] ?? merged["id"]) as? String else { return nil }
            let status = (merged["state"] ?? merged["status"]) as? String
                ?? ((merged["status"] as? [String: Any])?["state"] as? String) ?? "unknown"
            return VMInfo(provider: .apple, name: name, status: status.capitalized,
                          cpus: int(merged, "cpus").map(Int.init),
                          memoryBytes: int(merged, "memoryInBytes", "memory"),
                          diskBytes: int(merged, "diskInBytes", "disk"),
                          arch: merged["arch"] as? String, sshPort: nil, dir: nil)
        }
    }

    // MARK: - Actions

    func start(_ vm: VMInfo) async { await run(vm, "Starting", vm.provider.startArgs(vm.name)) }
    func stop(_ vm: VMInfo) async { await run(vm, "Stopping", vm.provider.stopArgs(vm.name)) }

    func delete(_ vm: VMInfo) async {
        if await run(vm, "Deleting", vm.provider.deleteArgs(vm.name)) {
            outputs[vm.id] = nil
            toastQueue?.enqueue(message: "'\(vm.name)' deleted")
        }
    }

    func openShell(_ vm: VMInfo) {
        do {
            try TerminalLauncher.open(command: vm.provider.shellCommand(vm.name))
        } catch {
            alertQueue?.enqueue(title: "Couldn't Open Terminal", message: error.localizedDescription)
        }
    }

    /// Run a VM command, log it to the VM's output, then refresh the list.
    @discardableResult
    private func run(_ vm: VMInfo, _ label: String, _ command: (tool: String, args: [String])) async -> Bool {
        guard busy[vm.id] == nil else { return false }
        busy[vm.id] = label
        defer { busy[vm.id] = nil }

        let r = await ShellCommand.run(command.tool, command.args, env: ProcessEnvironment.shared.getEnvironment())
        output(for: vm).appendLog(ShellCommand.log(command.tool, command.args, r) + "\n")
        if r.exitCode != 0 {
            alertQueue?.enqueue(title: "\(label) '\(vm.name)' Failed", message: r.stderr.isEmpty ? "Exit code \(r.exitCode)" : String(r.stderr.suffix(1000)))
        }
        await refresh()
        return r.exitCode == 0
    }

    // MARK: - Backup

    /// VM list with each Lima VM's lima.yaml, so a VM can be recreated
    func exportBackupData() async throws -> Data {
        await refresh()
        let entries = vms.map { vm in
            VMBackupEntry(
                provider: vm.provider, name: vm.name, cpus: vm.cpus,
                memoryBytes: vm.memoryBytes, diskBytes: vm.diskBytes,
                limaYAML: vm.dir.flatMap { try? String(contentsOfFile: "\($0)/lima.yaml", encoding: .utf8) }
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(entries)
    }
}
