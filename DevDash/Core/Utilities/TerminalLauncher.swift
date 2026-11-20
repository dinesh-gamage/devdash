//
//  TerminalLauncher.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-22.
//

import Foundation
import AppKit

enum TerminalLauncherError: LocalizedError {
    case keyFileNotFound(path: String)
    case scriptExecutionFailed(message: String)
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .keyFileNotFound(let path):
            return "SSH key file not found at: \(path)"
        case .scriptExecutionFailed(let message):
            return "Failed to open terminal: \(message)"
        case .permissionDenied:
            return "Permission denied. Please grant DevDash permission in System Settings > Privacy & Security > Automation."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            return "Go to System Settings > Privacy & Security > Automation, and enable iTerm (or Terminal) for DevDash. The SSH command has been copied to your clipboard."
        default:
            return nil
        }
    }
}

class TerminalLauncher {

    /// Opens the system's default Terminal app with an SSH command
    /// - Parameters:
    ///   - host: The hostname or IP address to connect to
    ///   - username: The SSH username
    ///   - keyPath: Path to the SSH private key file
    ///   - customOptions: Additional SSH command options (optional)
    /// - Throws: TerminalLauncherError if validation fails or terminal launch fails
    static func openSSH(host: String, username: String, keyPath: String, customOptions: String = "") throws {
        // Validate SSH key file exists
        let expandedKeyPath = NSString(string: keyPath).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expandedKeyPath) else {
            throw TerminalLauncherError.keyFileNotFound(path: expandedKeyPath)
        }

        // Build SSH command
        var command = "ssh -i \"\(expandedKeyPath)\" \(username)@\(host)"
        if !customOptions.isEmpty {
            command += " \(customOptions)"
        }

        try open(command: command)
    }

    /// Opens a shell command in a new iTerm2 tab, or a new Terminal window when iTerm2 isn't installed.
    /// On a permission error the command is copied to the clipboard.
    static func open(command: String) throws {
        // Escape command for AppleScript (escape quotes and backslashes)
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let iTermInstalled = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") != nil
        let script = iTermInstalled ? """
        tell application "iTerm"
            activate
            if (count of windows) = 0 then
                set w to (create window with default profile)
            else
                set w to current window
                tell w to create tab with default profile
            end if
            tell current session of w to write text "\(escapedCommand)"
        end tell
        """ : """
        tell application "Terminal"
            activate
            do script "\(escapedCommand)"
        end tell
        """

        var error: NSDictionary?
        guard let scriptObject = NSAppleScript(source: script) else {
            throw TerminalLauncherError.scriptExecutionFailed(message: "Failed to create AppleScript")
        }
        scriptObject.executeAndReturnError(&error)
        guard let error else { return }

        let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
        let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? 0
        // -1743 is "not authorized". Copy the command so the user can paste it.
        if errorNumber == -1743 || errorMessage.contains("not authorized") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            throw TerminalLauncherError.permissionDenied
        }
        throw TerminalLauncherError.scriptExecutionFailed(message: errorMessage)
    }
}
