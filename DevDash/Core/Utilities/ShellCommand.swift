//
//  ShellCommand.swift
//  DevDash
//

import Foundation

/// Runs a CLI tool with an argument array (no shell), off the main thread.
/// Arguments are passed as-is, so user input can't inject shell code.
enum ShellCommand {
    struct Result {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    /// - Parameters:
    ///   - tool: Tool name resolved via PATH in `env` (e.g. "aws")
    ///   - args: Arguments passed directly to the tool
    ///   - env: Process environment (use `ProcessEnvironment`)
    nonisolated static func run(_ tool: String, _ args: [String], env: [String: String]) async -> Result {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [tool] + args
            process.environment = env

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
                // Read both pipes before waiting, concurrently, so a full buffer on either can't deadlock.
                // (limactl/colima write long progress logs to stderr.)
                let errRead = Task.detached { errPipe.fileHandleForReading.readDataToEndOfFile() }
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = await errRead.value
                process.waitUntilExit()
                return Result(
                    stdout: String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
                    stderr: String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
                    exitCode: process.terminationStatus
                )
            } catch {
                return Result(stdout: "", stderr: "Process error: \(error.localizedDescription)", exitCode: -1)
            }
        }.value
    }

    /// Single-quote a value for a shell command string (e.g. one opened in Terminal).
    nonisolated static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Readable "[Command] / [Exit Code] / [STDOUT] / [STDERR]" log, matching the EC2 output panel format.
    nonisolated static func log(_ tool: String, _ args: [String], _ r: Result) -> String {
        var s = "[Command] \(([tool] + args).joined(separator: " "))\n\n[Exit Code] \(r.exitCode)\n\n"
        if !r.stdout.isEmpty { s += "[STDOUT]\n\(r.stdout)\n\n" }
        if !r.stderr.isEmpty { s += "[STDERR]\n\(r.stderr)\n" }
        return s
    }
}
