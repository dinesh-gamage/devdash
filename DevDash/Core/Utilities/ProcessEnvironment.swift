//
//  ProcessEnvironment.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import Foundation
import SwiftUI

/// Manages process environment variables, resolving the user's actual shell environment
/// macOS GUI apps don't inherit the user's shell environment from .zshrc/.zprofile
/// This utility discovers and caches the user's full shell environment on first access
class ProcessEnvironment {
    static let shared = ProcessEnvironment()

    private var cachedUserEnvironment: [String: String]?
    private let lock = NSLock()

    private init() {}

    /// Get the user's full environment from their login shell
    /// This is cached after first access for performance
    private func getUserEnvironment() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cachedUserEnvironment {
            return cached
        }

        // Discover environment by running a login shell
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "printenv"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()

            // Explicitly close pipe to release file handle immediately
            try? pipe.fileHandleForReading.close()

            if let output = String(data: data, encoding: .utf8) {
                // Parse printenv output (KEY=value format, one per line)
                var env: [String: String] = [:]
                let lines = output.components(separatedBy: .newlines)

                for line in lines {
                    guard !line.isEmpty else { continue }

                    // Split on first = only (value might contain =)
                    if let separatorIndex = line.firstIndex(of: "=") {
                        let key = String(line[..<separatorIndex])
                        let value = String(line[line.index(after: separatorIndex)...])
                        env[key] = value
                    }
                }

                if !env.isEmpty {
                    cachedUserEnvironment = env
                    return env
                }
            }
        } catch {
            // Ensure pipe is closed even on error
            try? pipe.fileHandleForReading.close()
            // Fall back to ProcessInfo if discovery fails
        }

        // Fallback: use ProcessInfo environment (limited to system defaults)
        let fallback = ProcessInfo.processInfo.environment
        cachedUserEnvironment = fallback
        return fallback
    }

    /// Get environment dictionary with user's shell environment and optional additional variables
    /// - Parameter additionalVars: Optional dictionary of additional environment variables to merge
    /// - Returns: Environment dictionary suitable for Process.environment
    func getEnvironment(additionalVars: [String: String] = [:]) -> [String: String] {
        var env = getUserEnvironment()

        // Merge additional variables (these override shell environment)
        for (key, value) in additionalVars {
            env[key] = value
        }

        return env
    }

    /// Get environment dictionary with AWS vault credentials for a specific profile
    /// This method retrieves cached session credentials from aws-vault
    /// Prompts for keychain password only once per app session
    /// - Parameters:
    ///   - profile: AWS profile name to use for credentials
    ///   - region: AWS region (optional)
    /// - Returns: Environment dictionary with AWS credentials, or base environment if session fetch fails
    @MainActor
    func getEnvironment(withAWSProfile profile: String, region: String? = nil) async -> [String: String] {
        // Get session credentials from vault manager
        if let session = await AWSVaultServerManager.shared.getSession(for: profile, region: region) {
            var awsEnv: [String: String] = [
                "AWS_ACCESS_KEY_ID": session.accessKeyId,
                "AWS_SECRET_ACCESS_KEY": session.secretAccessKey,
                "AWS_SESSION_TOKEN": session.sessionToken
            ]

            if let region = session.region {
                awsEnv["AWS_REGION"] = region
                awsEnv["AWS_DEFAULT_REGION"] = region
            }

            return getEnvironment(additionalVars: awsEnv)
        }

        // Fallback to base environment if session fetch failed
        return getEnvironment()
    }
}
