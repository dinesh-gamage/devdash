//
//  ContainerRuntime.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-25.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class ContainerRuntime: ObservableObject, Identifiable, Hashable, OutputViewDataSource {

    let config: ContainerConfig

    @Published var logs: String = ""
    @Published var status: ContainerInfo.ContainerStatus = .unknown
    @Published var dockerId: String? = nil
    @Published var processingAction: ContainerAction? = nil
    @Published var errors: [LogEntry] = []
    @Published var warnings: [LogEntry] = []

    private var process: Process?
    private var pipe: Pipe?

    // Ring buffer for logs
    private var logLines: [String] = []
    private let maxBufferLines: Int

    // Log batching
    private var logBuffer = ""
    private var flushTimer: DispatchSourceTimer?

    // Identifiable conformance
    var id: UUID { config.id }

    var isRunning: Bool {
        status == .running
    }

    init(config: ContainerConfig) {
        self.config = config
        self.maxBufferLines = config.maxLogLines ?? 1000
    }

    deinit {
        flushTimer?.cancel()
        flushTimer = nil
        pipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
    }

    // Hashable conformance
    static func == (lhs: ContainerRuntime, rhs: ContainerRuntime) -> Bool {
        lhs.config.id == rhs.config.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(config.id)
    }

    // MARK: - Log Management

    private func startFlushTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            self?.flushLogBuffer()
        }
        timer.resume()
        flushTimer = timer
    }

    private func stopFlushTimer() {
        flushTimer?.cancel()
        flushTimer = nil
        flushLogBuffer()
    }

    private func flushLogBuffer() {
        guard !logBuffer.isEmpty else { return }

        let chunk = logBuffer
        logBuffer = ""

        let lines = chunk.components(separatedBy: .newlines)
        for line in lines where !line.isEmpty {
            logLines.append(line)
            if logLines.count > maxBufferLines {
                logLines = Array(logLines.suffix(maxBufferLines))
            }
        }

        logs = logLines.joined(separator: "\n")
    }

    // MARK: - Status Check

    /// Check container status using docker ps
    func checkStatus() async {
        let containerName = config.name

        let result = await Task.detached(priority: .userInitiated) { () -> (ContainerInfo.ContainerStatus, String?) in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            task.arguments = ["-l", "-c", "docker ps -a --filter name=^\(containerName)$ --format '{{.ID}},{{.State}}'"]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if output.isEmpty {
                    return (.unknown, nil)
                }

                let parts = output.split(separator: ",").map(String.init)
                guard parts.count == 2 else {
                    return (.unknown, nil)
                }

                let dockerId = parts[0]
                let stateString = parts[1].lowercased()

                let status: ContainerInfo.ContainerStatus
                if stateString.contains("running") {
                    status = .running
                } else if stateString.contains("exited") {
                    status = .stopped
                } else if stateString.contains("created") {
                    status = .created
                } else if stateString.contains("paused") {
                    status = .paused
                } else {
                    status = .unknown
                }

                return (status, dockerId)
            } catch {
                return (.unknown, nil)
            }
        }.value

        self.status = result.0
        self.dockerId = result.1
    }

    // MARK: - Container Operations

    /// Create and start the container
    func start() {
        if isRunning { return }

        processingAction = .starting

        Task {
            // Check Colima first
            await DockerManagerState.shared.getColimaRuntime().checkStatus()
            if !DockerManagerState.shared.colimaInfo.isRunning {
                logs += "[Error] Colima is not running. Start Colima first.\n"
                processingAction = nil
                return
            }

            // Check if container exists
            await checkStatus()

            if status == .unknown {
                // Container doesn't exist - create it
                await createContainer()
                if status == .unknown {
                    // Creation failed
                    processingAction = nil
                    return
                }
            }

            // Start the container
            await startContainer()

            // Stream logs
            await streamLogs()

            // Verify started
            await checkStatus()
            processingAction = nil
        }
    }

    /// Stop the container
    func stop() {
        processingAction = .stopping

        Task {
            await checkStatus()

            if status == .running, let dockerId = dockerId {
                await stopContainer(dockerId)
            }

            stopFlushTimer()
            await checkStatus()
            processingAction = nil
        }
    }

    /// Restart the container
    func restart() {
        processingAction = .restarting

        Task {
            await stopContainer(config.name)
            try? await Task.sleep(nanoseconds: 500_000_000)
            await startContainer()
            await streamLogs()
            await checkStatus()
            processingAction = nil
        }
    }

    /// Delete the container
    func delete() async {
        processingAction = .deleting

        // Stop first if running
        if isRunning {
            await stopContainer(config.name)
        }

        await deleteContainer(config.name)
        await checkStatus()
        processingAction = nil
    }

    // MARK: - Docker Commands

    private func createContainer() async {
        logs += "[Creating] Container '\(config.name)'\n"

        var args = ["docker", "create", "--name", config.name]

        // Ports
        for port in config.ports {
            args.append("-p")
            args.append(port.dockerFormat)
        }

        // Volumes
        for volume in config.volumes {
            args.append("-v")
            args.append(volume.dockerFormat)
        }

        // Environment
        for (key, value) in config.environment {
            args.append("-e")
            args.append("\(key)=\(value)")
        }

        // Network
        if let network = config.network, !network.isEmpty {
            args.append("--network")
            args.append(network)
        }

        // Restart policy
        if let policy = config.restartPolicy, !policy.isEmpty {
            args.append("--restart")
            args.append(policy)
        }

        // CPU limit
        if let cpu = config.cpuLimit, !cpu.isEmpty {
            args.append("--cpus")
            args.append(cpu)
        }

        // Memory limit
        if let memory = config.memoryLimit, !memory.isEmpty {
            args.append("--memory")
            args.append(memory)
        }

        // Additional params
        for param in config.additionalParams {
            if !param.flag.isEmpty {
                args.append(param.flag)
                if !param.value.isEmpty {
                    args.append(param.value)
                }
            }
        }

        // Image
        args.append(config.image)

        // Command override
        if let command = config.command, !command.isEmpty {
            args.append(contentsOf: command.split(separator: " ").map(String.init))
        }

        let output = await runDockerCommand(args)
        logs += output

        await checkStatus()
    }

    private func startContainer() async {
        logs += "[Starting] Container '\(config.name)'\n"

        let output = await runDockerCommand(["docker", "start", config.name])
        logs += output
    }

    private func stopContainer(_ nameOrId: String) async {
        logs += "[Stopping] Container '\(nameOrId)'\n"

        let output = await runDockerCommand(["docker", "stop", nameOrId])
        logs += output
    }

    private func deleteContainer(_ nameOrId: String) async {
        logs += "[Deleting] Container '\(nameOrId)'\n"

        let output = await runDockerCommand(["docker", "rm", "-f", nameOrId])
        logs += output
    }

    private func streamLogs() async {
        guard let dockerId = dockerId else { return }

        logs += "[Logs] Streaming logs for '\(config.name)'\n"

        // Start log streaming in background
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "docker logs -f \(dockerId)"]
        process.environment = ProcessEnvironment.shared.getEnvironment()

        process.standardOutput = pipe
        process.standardError = pipe

        self.process = process
        self.pipe = pipe

        let fileHandle = pipe.fileHandleForReading
        fileHandle.readabilityHandler = { [weak self] handle in
            guard let self else { return }

            let data = handle.availableData
            guard data.count > 0, let output = String(data: data, encoding: .utf8) else {
                return
            }

            Task { @MainActor [weak self] in
                self?.logBuffer += output
            }
        }

        startFlushTimer()

        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pipe?.fileHandleForReading.readabilityHandler = nil
                try? self.pipe?.fileHandleForReading.close()
                self.pipe = nil
                self.stopFlushTimer()
            }
        }

        do {
            try process.run()
        } catch {
            logs += "[Error] Failed to stream logs: \(error.localizedDescription)\n"
        }
    }

    private func runDockerCommand(_ args: [String]) async -> String {
        await Task.detached(priority: .userInitiated) { () -> String in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            task.arguments = ["-l", "-c", args.joined(separator: " ")]
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
