//
//  EngineRuntime.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-25.
//

import Foundation
import SwiftUI
import Combine

/// The host a container engine needs (Colima for Docker, `container system` for Apple),
/// treated as a service (like ServiceRuntime).
@MainActor
class EngineRuntime: ObservableObject, Identifiable, Hashable, OutputViewDataSource {

    let engine: ContainerEngine
    var id: String { engine.rawValue }
    var name: String { engine.hostName }

    @Published var logs: String = ""
    @Published var isRunning: Bool = false
    @Published var errors: [LogEntry] = []
    @Published var warnings: [LogEntry] = []
    @Published var processingAction: ServiceAction? = nil
    @Published var colima: ColimaInstance?    // Docker only. nil = no instance yet.

    init(engine: ContainerEngine) {
        self.engine = engine
        Task {
            await checkStatus()
        }
    }

    // Hashable conformance
    static func == (lhs: EngineRuntime, rhs: EngineRuntime) -> Bool {
        lhs.engine == rhs.engine
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(engine)
    }

    // MARK: - Status Check

    func checkStatus() async {
        let (tool, args) = engine.statusArgs
        let r = await ShellCommand.run(tool, args, env: ProcessEnvironment.shared.getEnvironment())
        switch engine {
        case .docker:
            colima = ColimaInstance.parse(r.stdout)
            isRunning = colima?.isRunning == true
        case .apple:
            // `container system status` prints "status running" / "status stopped"
            isRunning = r.exitCode == 0 && r.stdout.contains("running")
        }
    }

    // MARK: - Start/Stop

    func start() {
        if isRunning { return }
        processingAction = .starting
        Task {
            await run(engine.startArgs, label: "Starting")
            await checkStatus()
            processingAction = nil
        }
    }

    func stop() {
        processingAction = .stopping
        Task {
            await run(engine.stopArgs, label: "Stopping")
            await checkStatus()
            processingAction = nil
        }
    }

    func restart() {
        processingAction = .restarting
        Task {
            await run(engine.stopArgs, label: "Stopping")
            await run(engine.startArgs, label: "Starting")
            await checkStatus()
            processingAction = nil
        }
    }

    // MARK: - Colima Instance

    /// Create the Colima instance, or apply new specs to it. Colima saves the specs on start.
    func configureColima(cpus: Int, memoryGiB: Int, diskGiB: Int) {
        let creating = colima == nil
        processingAction = creating ? .starting : .restarting
        Task {
            if isRunning { await run(engine.stopArgs, label: "Stopping") }
            await run(("colima", ["start", "--cpus", "\(cpus)", "--memory", "\(memoryGiB)", "--disk", "\(diskGiB)"]),
                      label: creating ? "Creating" : "Applying")
            await checkStatus()
            processingAction = nil
        }
    }

    /// Delete the Colima instance. Without `withData` its images and volumes are kept for the next instance.
    func deleteColima(withData: Bool) {
        processingAction = .stopping
        Task {
            await run(("colima", ["delete", "--force"] + (withData ? ["--data"] : [])), label: "Deleting")
            await checkStatus()
            processingAction = nil
        }
    }

    // MARK: - Helper

    private func run(_ command: (tool: String, args: [String]), label: String) async {
        logs += "[\(label)] \(engine.hostName)\n"
        let r = await ShellCommand.run(command.tool, command.args, env: ProcessEnvironment.shared.getEnvironment())
        logs += ShellCommand.log(command.tool, command.args, r) + "\n"
    }

    // MARK: - OutputViewDataSource Protocol

    func clearErrors() {
        errors.removeAll()
    }

    func clearWarnings() {
        warnings.removeAll()
    }
}
