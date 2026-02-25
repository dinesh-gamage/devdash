//
//  ColimaRuntime.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-25.
//

import Foundation
import SwiftUI
import Combine

/// Colima treated as a service (like ServiceRuntime)
@MainActor
class ColimaRuntime: ObservableObject, Identifiable, Hashable, OutputViewDataSource {

    let id = UUID()
    let name = "Colima"

    @Published var logs: String = ""
    @Published var isRunning: Bool = false
    @Published var errors: [LogEntry] = []
    @Published var warnings: [LogEntry] = []
    @Published var processingAction: ServiceAction? = nil

    private var process: Process?
    private var pipe: Pipe?
    private var logLines: [String] = []
    private let maxBufferLines = 1000
    private var logBuffer = ""
    private var flushTimer: DispatchSourceTimer?

    init() {
        Task {
            await checkStatus()
        }
    }

    deinit {
        flushTimer?.cancel()
        flushTimer = nil
        pipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
    }

    // Hashable conformance
    static func == (lhs: ColimaRuntime, rhs: ColimaRuntime) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Status Check

    func checkStatus() async {
        let running = await Task.detached(priority: .userInitiated) { () -> Bool in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            task.arguments = ["-l", "-c", "colima status"]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            do {
                try task.run()
                task.waitUntilExit()
                return task.terminationStatus == 0
            } catch {
                return false
            }
        }.value

        isRunning = running
    }

    // MARK: - Start/Stop

    func start() {
        if isRunning { return }

        processingAction = .starting
        logs += "[Starting] Colima\n"

        Task {
            let output = await runCommand("colima start")
            logs += output
            await checkStatus()
            processingAction = nil
        }
    }

    func stop() {
        processingAction = .stopping
        logs += "[Stopping] Colima\n"

        Task {
            let output = await runCommand("colima stop")
            logs += output
            await checkStatus()
            processingAction = nil
        }
    }

    func restart() {
        processingAction = .restarting
        logs += "[Restarting] Colima\n"

        Task {
            let stopOutput = await runCommand("colima stop")
            logs += stopOutput

            try? await Task.sleep(nanoseconds: 1_000_000_000)

            let startOutput = await runCommand("colima start")
            logs += startOutput

            await checkStatus()
            processingAction = nil
        }
    }

    // MARK: - Helper

    private func runCommand(_ command: String) async -> String {
        await Task.detached(priority: .userInitiated) { () -> String in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            task.arguments = ["-l", "-c", command]
            task.environment = ProcessEnvironment.shared.getEnvironment()

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                return output.isEmpty ? "" : output + "\n"
            } catch {
                return "[Error] \(error.localizedDescription)\n"
            }
        }.value
    }

    // MARK: - OutputViewDataSource Protocol

    func clearErrors() {
        errors.removeAll()
    }

    func clearWarnings() {
        warnings.removeAll()
    }
}
