//
//  ServiceRuntime.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class ServiceRuntime: ObservableObject, Identifiable, Hashable, OutputViewDataSource {

    let config: ServiceConfig

    @Published var logs: String = ""
    @Published var isRunning: Bool = false
    @Published var isExternallyManaged: Bool = false
    @Published var hasPortConflict: Bool = false
    @Published var conflictingPID: Int? = nil
    @Published var errors: [LogEntry] = []
    @Published var warnings: [LogEntry] = []
    @Published var processingAction: ServiceAction? = nil

    private var process: Process?
    private var pipe: Pipe?

    // Ring buffer for logs: fixed-size array of lines
    private var logLines: [String] = []
    private let maxBufferLines: Int

    // Log batching: buffer incoming data, flush on timer
    private var logBuffer = ""
    private var flushTimer: DispatchSourceTimer?

    // Store prerequisite task for cancellation
    private var prerequisiteTask: Task<Void, Never>?

    // Track if logs need rebuilding (optimization to avoid rebuilding on every flush)
    private var logsNeedRebuild = false

    // Flag set when "EADDRINUSE" is seen in a chunk (avoids full log scan at termination)
    private var seenEADDRINUSE = false

    // Cap on errors/warnings arrays to prevent unbounded memory growth
    private static let maxEntries = 500
    private static let trimToEntries = 400

    // Identifiable conformance
    var id: UUID { config.id }

    init(config: ServiceConfig) {
        self.config = config
        self.maxBufferLines = config.maxLogLines ?? 1000
    }

    deinit {
        // Clean up resources - must happen synchronously in deinit
        prerequisiteTask?.cancel()
        flushTimer?.cancel()
        flushTimer = nil
        pipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
    }

    // Hashable conformance
    static func == (lhs: ServiceRuntime, rhs: ServiceRuntime) -> Bool {
        lhs.config.id == rhs.config.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(config.id)
    }

    // Parse log line for errors and warnings
    private var lineNumber = 0
    private var collectingStackTrace = false
    private var currentStackTrace: [String] = []

    private func parseLine(_ line: String) {
        lineNumber += 1
        let lowercased = line.lowercased()
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Stack trace line patterns (indented, starts with "at ", frame info, etc.)
        let isStackTraceLine = line.hasPrefix("    ") ||
                               line.hasPrefix("\t") ||
                               trimmed.hasPrefix("at ") ||
                               trimmed.contains("(") && trimmed.contains(")") && trimmed.contains(":") ||
                               trimmed.hasPrefix("File ") ||
                               trimmed.contains(LogParser.stackTraceLineRegex)

        // If we're collecting a stack trace
        if collectingStackTrace {
            if isStackTraceLine && !trimmed.isEmpty {
                currentStackTrace.append(trimmed)
                return
            } else {
                // Stack trace ended, attach to last error
                if !currentStackTrace.isEmpty, !errors.isEmpty {
                    errors[errors.count - 1].stackTrace = currentStackTrace
                }
                collectingStackTrace = false
                currentStackTrace = []
            }
        }

        // Check for errors
        for pattern in LogParser.errorPatterns {
            if lowercased.contains(pattern) {
                let entry = LogEntry(
                    message: trimmed,
                    lineNumber: lineNumber,
                    timestamp: Date(),
                    type: .error,
                    stackTrace: nil
                )
                errors.append(entry)
                if errors.count > Self.maxEntries {
                    // Use array slicing instead of removeFirst for better performance
                    errors = Array(errors.suffix(Self.trimToEntries))
                }
                collectingStackTrace = true
                currentStackTrace = []
                return
            }
        }

        // Check for warnings
        for pattern in LogParser.warningPatterns {
            if lowercased.contains(pattern) {
                let entry = LogEntry(
                    message: trimmed,
                    lineNumber: lineNumber,
                    timestamp: Date(),
                    type: .warning,
                    stackTrace: nil
                )
                warnings.append(entry)
                if warnings.count > Self.maxEntries {
                    // Use array slicing instead of removeFirst for better performance
                    warnings = Array(warnings.suffix(Self.trimToEntries))
                }
                return
            }
        }
    }

    // MARK: - Log flush (called on main queue by timer)

    private func startFlushTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        // Flush every 250ms instead of 100ms to reduce UI update frequency
        // This significantly reduces CPU usage while keeping logs responsive
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
        // Flush any remaining buffered data
        flushLogBuffer()
    }

    private func flushLogBuffer() {
        guard !logBuffer.isEmpty else {
            // If logs need rebuilding but buffer is empty, rebuild now
            if logsNeedRebuild {
                logs = logLines.joined(separator: "\n")
                logsNeedRebuild = false
            }
            return
        }

        let chunk = logBuffer
        logBuffer = ""

        // Check for EADDRINUSE in the chunk (cheap, only chunk-sized)
        if !seenEADDRINUSE && chunk.contains("EADDRINUSE") {
            seenEADDRINUSE = true
        }

        // Parse new lines and add to ring buffer
        let lines = chunk.components(separatedBy: .newlines)
        var hasNewLines = false

        for line in lines where !line.isEmpty {
            parseLine(line)

            // Add to ring buffer with proactive trimming
            logLines.append(line)
            hasNewLines = true

            if logLines.count > maxBufferLines {
                // Use array slicing instead of removeFirst for better performance
                logLines = Array(logLines.suffix(maxBufferLines))
            }
        }

        // Only rebuild logs string if we actually added lines
        if hasNewLines {
            logs = logLines.joined(separator: "\n")
            logsNeedRebuild = false
        }
    }

    // Start the service
    func start() {
        if isRunning { return }

        processingAction = .starting
        logs = ""
        logLines = []
        errors = []
        warnings = []
        lineNumber = 0
        logBuffer = ""
        seenEADDRINUSE = false
        collectingStackTrace = false
        currentStackTrace = []

        let config = self.config

        prerequisiteTask = Task {
            // Execute prerequisites off main
            let prereqs = config.prerequisites ?? []
            if !prereqs.isEmpty {
                // Check if cancelled before starting
                guard !Task.isCancelled else {
                    await MainActor.run { self.processingAction = nil }
                    return
                }
                await MainActor.run { self.logs += "[Prerequisites] Running \(prereqs.count) prerequisite command(s)\n" }

                for (index, prereq) in prereqs.enumerated() {
                    // Check if cancelled between prerequisites
                    guard !Task.isCancelled else {
                        await MainActor.run { self.processingAction = nil }
                        return
                    }

                    await MainActor.run { self.logs += "[Prerequisites] [\(index + 1)/\(prereqs.count)] Running: \(prereq.command)\n" }

                    let result = await Task.detached(priority: .userInitiated) { () -> (Int32, String) in
                        let task = Process()
                        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
                        task.arguments = ["-c", prereq.command]
                        task.currentDirectoryURL = URL(fileURLWithPath: config.workingDirectory)
                        task.environment = ProcessEnvironment.shared.getEnvironment(additionalVars: config.environment)
                        let pipe = Pipe()
                        task.standardOutput = pipe
                        task.standardError = pipe
                        do {
                            try task.run()
                            task.waitUntilExit()
                            let data = pipe.fileHandleForReading.readDataToEndOfFile()
                            let output = String(data: data, encoding: .utf8) ?? ""
                            return (task.terminationStatus, output)
                        } catch {
                            return (-1, error.localizedDescription)
                        }
                    }.value

                    let (exitCode, output) = result
                    if !output.isEmpty { await MainActor.run { self.logs += output } }

                    if exitCode != 0 {
                        if prereq.isRequired {
                            await MainActor.run {
                                self.logs += "[Prerequisites] ❌ Required prerequisite failed with exit code \(exitCode)\n"
                                self.logs += "[Prerequisites] Stopping service start due to required prerequisite failure\n"
                            }
                            return
                        } else {
                            await MainActor.run { self.logs += "[Prerequisites] ⚠️ Optional prerequisite failed with exit code \(exitCode), continuing...\n" }
                        }
                    } else {
                        await MainActor.run { self.logs += "[Prerequisites] ✓ Command completed successfully\n" }
                    }

                    if prereq.delay > 0 {
                        await MainActor.run { self.logs += "[Prerequisites] Waiting \(prereq.delay)s before continuing...\n" }
                        try? await Task.sleep(nanoseconds: UInt64(prereq.delay) * 1_000_000_000)

                        // Check if cancelled during delay
                        guard !Task.isCancelled else {
                            await MainActor.run { self.processingAction = nil }
                            return
                        }
                    }
                }
            }

            // Check if cancelled before port check
            guard !Task.isCancelled else {
                await MainActor.run { self.processingAction = nil }
                return
            }

            // Check port before starting
            if let port = config.port {
                let pid = await Task.detached(priority: .userInitiated) { () -> Int? in
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
                    task.arguments = ["-i", ":\(port)", "-t"]
                    let pipe = Pipe()
                    task.standardOutput = pipe
                    try? task.run()
                    task.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let trimmed = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return trimmed.components(separatedBy: .newlines).first.flatMap { Int($0) }
                }.value

                await MainActor.run {
                    self.hasPortConflict = pid != nil
                    self.conflictingPID = pid
                    if pid != nil {
                        self.logs += "Port \(port) is already in use by process \(pid!). Click 'Kill & Restart' to stop it.\n"
                    }
                }
                if pid != nil { return }
            }

            await MainActor.run { self.logs += "[Starting] \(config.name)\n" }

            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", config.command]
            process.currentDirectoryURL = URL(fileURLWithPath: config.workingDirectory)
            process.environment = ProcessEnvironment.shared.getEnvironment(additionalVars: config.environment)

            process.standardOutput = pipe
            process.standardError = pipe

            await MainActor.run {
                self.process = process
                self.pipe = pipe
            }

            // Live log streaming using readabilityHandler
            // readabilityHandler is efficient - only called when data is actually ready
            let fileHandle = pipe.fileHandleForReading
            fileHandle.readabilityHandler = { [weak self] handle in
                guard let self else { return }

                // Read ALL available data in one go to minimize handler invocations
                // We use availableData here which is safe because:
                // 1. We're already inside readabilityHandler (data IS available)
                // 2. This won't spin-loop like the old code (handler only fires when data ready)
                // 3. Reading everything at once means fewer handler calls = lower CPU
                let data = handle.availableData

                guard data.count > 0, let output = String(data: data, encoding: .utf8) else {
                    return
                }

                Task { @MainActor [weak self] in
                    self?.logBuffer += output
                }
            }

            // Start the flush timer on main queue
            await MainActor.run { self.startFlushTimer() }

            // Termination handler
            process.terminationHandler = { [weak self] proc in
                Task { @MainActor [weak self] in
                    guard let self else { return }

                    // CRITICAL: Clean up pipe and handler FIRST to prevent leaks
                    self.pipe?.fileHandleForReading.readabilityHandler = nil
                    try? self.pipe?.fileHandleForReading.close()
                    self.pipe = nil

                    self.stopFlushTimer()
                    self.logBuffer += "\n[Process terminated with code \(proc.terminationStatus)]\n"
                    self.flushLogBuffer()

                    if self.seenEADDRINUSE {
                        self.detectPortConflict()
                    }
                    // If a check command or port is configured, re-check true state
                    // (handles fire-and-forget launchers like `open -a Docker`)
                    if self.config.checkCommand != nil || self.config.port != nil {
                        Task { await self.checkStatus() }
                    } else {
                        self.process = nil
                        self.isRunning = false
                    }
                    self.processingAction = nil
                }
            }

            do {
                try process.run()
                await MainActor.run {
                    self.isRunning = true
                    self.processingAction = nil
                }
            } catch {
                await MainActor.run {
                    self.logs += "Failed to start process: \(error.localizedDescription)\n"
                    self.processingAction = nil
                }
            }
        }
    }

    // Check if port is in use — runs async off main thread
    func checkPort(_ port: Int) {
        Task.detached(priority: .userInitiated) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            task.arguments = ["-i", ":\(port)", "-t"]

            let pipe = Pipe()
            task.standardOutput = pipe

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    await MainActor.run {
                        if !trimmed.isEmpty {
                            let pids = trimmed.components(separatedBy: .newlines)
                            if let firstPID = pids.first, let pid = Int(firstPID) {
                                self.hasPortConflict = true
                                self.conflictingPID = pid
                                self.logs += "[Port Check] Port \(port) is in use by PID \(pid)\n"
                            }
                        } else {
                            self.hasPortConflict = false
                            self.conflictingPID = nil
                            self.logs += "[Port Check] Port \(port) is free\n"
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.logs += "[Port Check] Failed to check port \(port): \(error.localizedDescription)\n"
                }
            }
        }
    }

    // Detect port conflict from error logs
    func detectPortConflict() {
        guard let port = config.port else { return }
        checkPort(port)
    }

    // Check if service is running (via checkCommand or port fallback)
    // Async function that runs blocking work off main thread
    func checkStatus() async {
        let config = self.config
        let ownedProcess = self.process

        if let checkCmd = config.checkCommand, !checkCmd.isEmpty {
            Task.detached {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/zsh")
                task.arguments = ["-c", checkCmd]
                task.currentDirectoryURL = URL(fileURLWithPath: config.workingDirectory)
                task.environment = ProcessEnvironment.shared.getEnvironment(additionalVars: config.environment)
                do {
                    try task.run()
                    task.waitUntilExit()
                    let running = task.terminationStatus == 1
                    await MainActor.run {
                        if running && ownedProcess == nil {
                            self.isExternallyManaged = true
                            self.isRunning = true
                        } else if !running {
                            self.isExternallyManaged = false
                            self.isRunning = ownedProcess?.isRunning ?? false
                        }
                        self.logs += "[Check] Service is \(running ? "running" : "not running")\(self.isExternallyManaged ? " (external)" : "")\n"
                    }
                } catch {
                    await MainActor.run {
                        self.logs += "[Check] Failed to run check command: \(error.localizedDescription)\n"
                    }
                }
            }
        } else if let port = config.port {
            Task.detached {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
                task.arguments = ["-i", ":\(port)", "-t"]
                let pipe = Pipe()
                task.standardOutput = pipe
                do {
                    try task.run()
                    task.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let trimmed = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let pid = trimmed.components(separatedBy: .newlines).first.flatMap { Int($0) }
                    await MainActor.run {
                        self.hasPortConflict = pid != nil
                        self.conflictingPID = pid
                        if pid != nil && ownedProcess == nil {
                            // Port is in use by external process
                            self.isExternallyManaged = true
                            self.isRunning = true
                        } else if pid == nil && ownedProcess == nil {
                            // Port is free and we don't own the process - service is stopped
                            self.isExternallyManaged = false
                            self.isRunning = false
                        }
                        self.logs += "[Check] Port \(port) is \(pid != nil ? "in use by PID \(pid!)" : "free")\n"
                    }
                } catch {
                    await MainActor.run {
                        self.logs += "[Check] Failed to check port \(port): \(error.localizedDescription)\n"
                    }
                }
            }
        } else {
            logs += "[Check] No check command or port configured\n"
        }
    }

    // Kill conflicting process and restart
    func killAndRestart() {
        processingAction = .killingAndRestarting

        Task {
            // First try to use conflictingPID if available, otherwise find via port
            let targetPID: Int?
            if let conflicting = conflictingPID {
                targetPID = conflicting
            } else if let port = config.port {
                targetPID = await findPIDForPort(port)
            } else {
                targetPID = nil
            }

            guard let pid = targetPID else {
                logs += "[Kill & Start] No process found to kill\n"
                processingAction = nil
                return
            }

            // Kill the process using helper
            let success = await killProcess(pid)

            if success {
                hasPortConflict = false
                conflictingPID = nil
                isExternallyManaged = false
                logs += "[Kill & Start] Killed process \(pid)\n"

                // Wait for process to fully terminate
                try? await Task.sleep(nanoseconds: 500_000_000)

                // Start the service
                start()
                // processingAction will be cleared by start()
            } else {
                logs += "[Kill & Start] Failed to kill process \(pid)\n"
                processingAction = nil
            }
        }
    }

    // Stop the service
    func stop() {
        // Cancel any running prerequisite tasks
        prerequisiteTask?.cancel()
        prerequisiteTask = nil

        processingAction = .stopping

        Task {
            // Use the async version for actual stop logic
            await stopAsync()

            // Clear processing action when done
            await MainActor.run {
                self.processingAction = nil
            }
        }
    }

    // Restart the service
    func restart() {
        let config = self.config
        if let restartCmd = config.restartCommand, !restartCmd.isEmpty {
            processingAction = .restarting
            Task {
                let output = await runShellCommand(restartCmd)
                if !output.isEmpty { logs += output }
                logs += "[Restart] Command completed\n"
                processingAction = nil
            }
        } else {
            // No custom restart command - stop then start with proper sequencing
            processingAction = .restarting
            Task {
                // Stop the service and wait for completion
                await stopAsync()

                // Wait a bit for process to fully terminate
                try? await Task.sleep(nanoseconds: 500_000_000)

                // Start the service
                start()

                // processingAction will be cleared by start() on success/failure
            }
        }
    }

    // Async version of stop for proper sequencing
    private func stopAsync() async {
        await MainActor.run {
            // Don't set processingAction here - caller manages it
            self.stopFlushTimer()
            self.pipe?.fileHandleForReading.readabilityHandler = nil
        }

        let config = self.config

        // Case 1: custom stop command
        if let stopCmd = config.stopCommand, !stopCmd.isEmpty {
            let output = await runShellCommand(stopCmd)
            await MainActor.run {
                if !output.isEmpty { self.logs += output }
                self.process = nil
                self.isRunning = false
                self.isExternallyManaged = false
            }
            return
        }

        // Case 2: we own the process
        let ownedProcess = await MainActor.run { self.process }
        if let proc = ownedProcess {
            let pid = proc.processIdentifier
            proc.terminate()
            await MainActor.run {
                self.process = nil
                self.isRunning = false
                self.isExternallyManaged = false
            }
            // Wait and force kill if needed
            try? await Task.sleep(nanoseconds: 500_000_000)
            let stillRunning = await Task.detached(priority: .userInitiated) { proc.isRunning }.value
            if stillRunning {
                _ = await killProcess(Int(pid))
            }
            return
        }

        // Case 3: externally managed — use port-based PID kill
        if let port = config.port {
            if let pid = await findPIDForPort(port) {
                let killed = await killProcess(pid)
                await MainActor.run {
                    self.logs += killed ? "[Stop] Killed external process \(pid) on port \(port)\n"
                                       : "[Stop] Failed to kill external process \(pid)\n"
                }
            } else {
                await MainActor.run {
                    self.logs += "[Stop] No process found on port \(port)\n"
                }
            }
            await MainActor.run {
                self.isRunning = false
                self.isExternallyManaged = false
                self.hasPortConflict = false
                self.conflictingPID = nil
            }
            return
        }

        // Case 4: no way to stop
        await MainActor.run {
            self.logs += "[Stop] Cannot stop: no stop command or port configured\n"
        }
    }

    // MARK: - Private Helper Methods

    /// Find process ID listening on a specific port using lsof
    private func findPIDForPort(_ port: Int) async -> Int? {
        await Task.detached(priority: .userInitiated) { () -> Int? in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            task.arguments = ["-i", ":\(port)", "-t"]
            let pipe = Pipe()
            task.standardOutput = pipe
            try? task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let trimmed = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.components(separatedBy: .newlines).first.flatMap { Int($0) }
        }.value
    }

    /// Kill a process by PID using SIGKILL
    private func killProcess(_ pid: Int) async -> Bool {
        await Task.detached(priority: .userInitiated) { () -> Bool in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/kill")
            task.arguments = ["-9", "\(pid)"]
            do {
                try task.run()
                task.waitUntilExit()
                return true
            } catch {
                return false
            }
        }.value
    }

    /// Run a shell command and return its output
    private func runShellCommand(_ command: String) async -> String {
        let config = self.config
        return await Task.detached(priority: .userInitiated) { () -> String in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            task.arguments = ["-c", command]
            task.currentDirectoryURL = URL(fileURLWithPath: config.workingDirectory)
            task.environment = ProcessEnvironment.shared.getEnvironment(additionalVars: config.environment)
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            do {
                try task.run()
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8) ?? ""
            } catch {
                return "Failed: \(error.localizedDescription)\n"
            }
        }.value
    }

    // MARK: - Public Methods

    // Clear errors
    func clearErrors() {
        errors.removeAll()
    }

    // Clear warnings
    func clearWarnings() {
        warnings.removeAll()
    }
}
