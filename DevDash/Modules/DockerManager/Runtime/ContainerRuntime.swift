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

    private var cli: String { config.resolvedEngine.cli }

    // MARK: - Status Check

    /// Check container status (`docker ps` or `container inspect`)
    func checkStatus() async {
        let env = ProcessEnvironment.shared.getEnvironment()
        let state: String?
        switch config.resolvedEngine {
        case .docker:
            let r = await ShellCommand.run("docker", ["ps", "-a", "--filter", "name=^\(config.name)$", "--format", "{{.ID}},{{.State}}"], env: env)
            let parts = r.stdout.split(separator: ",").map(String.init)
            guard r.exitCode == 0, parts.count == 2 else { status = .unknown; dockerId = nil; return }
            dockerId = parts[0]
            state = parts[1]
        case .apple:
            // Apple's container ID is its name
            let r = await ShellCommand.run("container", ["inspect", config.name], env: env)
            struct Inspect: Decodable { struct Status: Decodable { let state: String? }; let status: Status? }
            let decoded = try? JSONDecoder().decode([Inspect].self, from: Data(r.stdout.utf8))
            guard r.exitCode == 0, let first = decoded?.first else { status = .unknown; dockerId = nil; return }
            dockerId = config.name
            state = first.status?.state
        }
        status = Self.status(from: state ?? "")
    }

    nonisolated static func status(from state: String) -> ContainerInfo.ContainerStatus {
        let s = state.lowercased()
        if s.contains("running") { return .running }
        if s.contains("exited") || s.contains("stopped") { return .stopped }
        if s.contains("created") { return .created }
        if s.contains("paused") { return .paused }
        return .unknown
    }

    // MARK: - Container Operations

    /// Create (if missing) and start the container
    func start() {
        if isRunning { return }

        processingAction = .starting

        Task {
            let host = DockerManagerState.shared.engineRuntime(config.resolvedEngine)
            await host.checkStatus()
            if !host.isRunning {
                logs += "[Error] \(host.name) is not running. Start \(host.name) first.\n"
                processingAction = nil
                return
            }

            await checkStatus()

            if status == .unknown {
                await createContainer()
                if status == .unknown {
                    processingAction = nil
                    return
                }
            }

            await run(["start", config.name], label: "Starting")
            await streamLogs()
            await checkStatus()
            processingAction = nil
        }
    }

    /// Stop the container
    func stop() {
        processingAction = .stopping

        Task {
            await checkStatus()
            if status == .running {
                await run(["stop", config.name], label: "Stopping")
            }
            stopLogStream()
            await checkStatus()
            processingAction = nil
        }
    }

    /// Restart the container
    func restart() {
        processingAction = .restarting

        Task {
            stopLogStream()
            await run(["stop", config.name], label: "Stopping")
            await run(["start", config.name], label: "Starting")
            await streamLogs()
            await checkStatus()
            processingAction = nil
        }
    }

    /// Delete the container from the engine
    func delete() async {
        processingAction = .deleting
        stopLogStream()
        switch config.resolvedEngine {
        case .docker: await run(["rm", "-f", config.name], label: "Deleting")
        case .apple: await run(["delete", "--force", config.name], label: "Deleting")
        }
        await checkStatus()
        processingAction = nil
    }

    // MARK: - CLI Commands

    private func createContainer() async {
        let engine = config.resolvedEngine
        var args = ["create", "--name", config.name]

        for port in config.ports {
            args += ["-p", port.dockerFormat]
        }
        for volume in config.volumes {
            args += ["-v", volume.dockerFormat]
        }
        for (key, value) in config.environment.sorted(by: { $0.key < $1.key }) {
            args += ["-e", "\(key)=\(value)"]
        }
        if let network = config.network, !network.isEmpty {
            args += ["--network", network]
        }
        // Apple's CLI has no restart policy
        if engine == .docker, let policy = config.restartPolicy, !policy.isEmpty {
            args += ["--restart", policy]
        }
        if let cpu = config.cpuLimit, !cpu.isEmpty {
            args += ["--cpus", cpu]
        }
        if let memory = config.memoryLimit, !memory.isEmpty {
            args += ["--memory", memory]
        }
        for param in config.additionalParams where !param.flag.isEmpty {
            args.append(param.flag)
            if !param.value.isEmpty { args.append(param.value) }
        }

        args.append(config.image)

        // ponytail: command split on spaces, quoted arguments are not kept together
        if let command = config.command, !command.isEmpty {
            args += command.split(separator: " ").map(String.init)
        }

        await run(args, label: "Creating")
        await checkStatus()
    }

    /// Run `<cli> args` and append the result to the logs
    private func run(_ args: [String], label: String) async {
        logs += "[\(label)] Container '\(config.name)'\n"
        let r = await ShellCommand.run(cli, args, env: ProcessEnvironment.shared.getEnvironment())
        if !r.stdout.isEmpty { logs += r.stdout + "\n" }
        if !r.stderr.isEmpty { logs += r.stderr + "\n" }
    }

    private func streamLogs() async {
        guard let dockerId = dockerId, process == nil else { return }

        logs += "[Logs] Streaming logs for '\(config.name)'\n"

        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [cli, "logs", "-f", dockerId]
        process.environment = ProcessEnvironment.shared.getEnvironment()

        process.standardOutput = pipe
        process.standardError = pipe

        self.process = process
        self.pipe = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard data.count > 0, let output = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.logBuffer += output
            }
        }

        startFlushTimer()

        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopLogStream()
            }
        }

        do {
            try process.run()
        } catch {
            logs += "[Error] Failed to stream logs: \(error.localizedDescription)\n"
            stopLogStream()
        }
    }

    /// Stop the `logs -f` process and flush what was read
    private func stopLogStream() {
        pipe?.fileHandleForReading.readabilityHandler = nil
        try? pipe?.fileHandleForReading.close()
        pipe = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil
        stopFlushTimer()
    }

    // MARK: - OutputViewDataSource Protocol

    func clearErrors() {
        errors.removeAll()
    }

    func clearWarnings() {
        warnings.removeAll()
    }
}
