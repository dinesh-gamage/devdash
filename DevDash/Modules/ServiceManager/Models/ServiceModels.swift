//
//  ServiceModels.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import Foundation

// MARK: - Prerequisite Command

struct PrerequisiteCommand: Codable, Identifiable {
    let id: UUID
    var command: String
    var delay: Int
    var isRequired: Bool

    init(id: UUID = UUID(), command: String, delay: Int = 0, isRequired: Bool = false) {
        self.id = id
        self.command = command
        self.delay = delay
        self.isRequired = isRequired
    }
}

// MARK: - Service Configuration

struct ServiceConfig: Codable, Identifiable {
    let id: UUID
    var name: String
    var command: String
    var workingDirectory: String
    var port: Int?
    var environment: [String: String]
    var prerequisites: [PrerequisiteCommand]?
    var checkCommand: String?
    var stopCommand: String?
    var restartCommand: String?
    var maxLogLines: Int?
    var script: ScriptConfig?   // Set for script services. command/stop/check are built from it.
    var logFile: String?        // Tailed into the logs while the service runs

    init(id: UUID = UUID(), name: String, command: String, workingDirectory: String, port: Int? = nil, environment: [String: String] = [:], prerequisites: [PrerequisiteCommand]? = nil, checkCommand: String? = nil, stopCommand: String? = nil, restartCommand: String? = nil, maxLogLines: Int? = 1000, script: ScriptConfig? = nil, logFile: String? = nil) {
        self.id = id
        self.name = name
        self.command = command
        self.workingDirectory = workingDirectory
        self.port = port
        self.environment = environment
        self.prerequisites = prerequisites
        self.checkCommand = checkCommand
        self.stopCommand = stopCommand
        self.restartCommand = restartCommand
        self.maxLogLines = maxLogLines
        self.script = script
        self.logFile = logFile
    }
}

// MARK: - Script Service

/// A script that takes an action argument, e.g. `ivivaweb.sh start|stop|status`
struct ScriptConfig: Codable, Equatable {
    var path: String = ""
    var startArgs = "start"
    var stopArgs = "stop"
    var statusArgs = "status"
    var runningPattern = "RUNNING"   // Empty = status exit code 0 means running

    func command(_ args: String) -> String {
        args.isEmpty ? ShellCommand.quote(path) : "\(ShellCommand.quote(path)) \(args)"
    }

    var checkCommand: String {
        let status = command(statusArgs)
        return runningPattern.isEmpty ? status : "\(status) | grep -q \(ShellCommand.quote(runningPattern))"
    }

    /// Fill fields from a script. Scripts built on svc-lib.sh also give their log file.
    // ponytail: only svc-lib.sh scripts are recognised. Others get the defaults.
    static func detect(path: String) -> (script: ScriptConfig, logFile: String?) {
        let script = ScriptConfig(path: path)
        guard let text = try? String(contentsOfFile: path, encoding: .utf8), text.contains("svc-lib.sh"),
              let match = text.firstMatch(of: /svc\s+"\$\{1:-start\}"\s+(\S+)/) else { return (script, nil) }
        // svc scripts live in <env>/services and log to <env>/logs/<name>.out
        let env = URL(fileURLWithPath: path).deletingLastPathComponent().deletingLastPathComponent()
        return (script, env.appendingPathComponent("logs/\(match.1).out").path)
    }
}

// MARK: - Form Draft (shared by Add and Edit)

enum ServiceTracking: String, CaseIterable, Identifiable {
    case process = "Process"
    case port = "Port"
    case check = "Check Command"
    var id: String { rawValue }
}

struct ServiceDraft {
    var name = ""
    var isScript = false
    var script = ScriptConfig()
    var command = ""
    var workingDirectory = NSHomeDirectory()
    var tracking: ServiceTracking = .process
    var port = ""
    var checkCommand = ""
    var stopCommand = ""
    var restartCommand = ""
    var logFile = ""
    var envVars: [EnvVar] = []
    var prerequisites: [PrerequisiteCommand] = []
    var maxLogLines = "1000"

    init() {}

    init(_ c: ServiceConfig) {
        name = c.name
        isScript = c.script != nil
        script = c.script ?? ScriptConfig()
        command = c.command
        workingDirectory = c.workingDirectory
        port = c.port.map { "\($0)" } ?? ""
        checkCommand = c.checkCommand ?? ""
        tracking = !checkCommand.isEmpty ? .check : c.port != nil ? .port : .process
        stopCommand = c.stopCommand ?? ""
        restartCommand = c.restartCommand ?? ""
        logFile = c.logFile ?? ""
        envVars = c.environment.map { EnvVar(key: $0.key, value: $0.value) }
        prerequisites = c.prerequisites ?? []
        maxLogLines = c.maxLogLines.map { "\($0)" } ?? ""
    }

    var isValid: Bool {
        !name.isEmpty && !workingDirectory.isEmpty && (isScript ? !script.path.isEmpty : !command.isEmpty)
    }

    /// Script services store their built commands, so the runtime runs both types the same way.
    func config(id: UUID = UUID()) -> ServiceConfig {
        let opt = { (s: String) in s.isEmpty ? nil : s }
        let prereqs = prerequisites.filter { !$0.command.isEmpty }
        return ServiceConfig(
            id: id, name: name,
            command: isScript ? script.command(script.startArgs) : command,
            workingDirectory: workingDirectory,
            port: tracking == .port || isScript ? Int(port) : nil,
            environment: Dictionary(envVars.filter { !$0.key.isEmpty }.map { ($0.key, $0.value) }) { _, last in last },
            prerequisites: prereqs.isEmpty ? nil : prereqs,
            checkCommand: isScript ? script.checkCommand : tracking == .check ? opt(checkCommand) : nil,
            stopCommand: isScript ? script.command(script.stopArgs) : opt(stopCommand),
            restartCommand: opt(restartCommand),
            maxLogLines: Int(maxLogLines),
            script: isScript ? script : nil,
            logFile: opt(logFile)
        )
    }
}

// MARK: - Service Action

enum ServiceAction: Equatable {
    case starting
    case stopping
    case restarting
    case killingAndRestarting
}

// MARK: - Service Info (Lightweight ViewModel)

struct ServiceInfo: Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let isRunning: Bool
    let isExternallyManaged: Bool
    let hasPortConflict: Bool
    let processingAction: ServiceAction?
    let port: Int?
    let workingDirectory: String
    let command: String
}

// MARK: - Log Entry

struct LogEntry: Identifiable {
    let id = UUID()
    let message: String
    let lineNumber: Int
    let timestamp: Date
    let type: LogType
    var stackTrace: [String]?

    enum LogType {
        case error
        case warning
    }
}
