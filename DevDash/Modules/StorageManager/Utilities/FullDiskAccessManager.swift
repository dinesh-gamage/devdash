//
//  FullDiskAccessManager.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-24.
//

import Foundation
import AppKit
import Combine

/// Manager for checking and prompting Full Disk Access permission
@MainActor
class FullDiskAccessManager: ObservableObject {
    static let shared = FullDiskAccessManager()

    @Published var hasFullDiskAccess: Bool = false
    @Published var hasChecked: Bool = false

    private init() {
        checkFullDiskAccess()
        setupAppActivationListener()
    }

    /// Setup listener for app activation to recheck FDA
    private func setupAppActivationListener() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.recheckAccess()
        }
    }

    /// Check if the app has Full Disk Access permission
    /// This works by attempting to actually read a protected file that requires FDA
    func checkFullDiskAccess() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser

        // Try to list contents of a protected directory (Safari)
        let safariDir = homeDir.appendingPathComponent("Library/Safari")

        do {
            // Actually attempt to read the directory contents
            _ = try FileManager.default.contentsOfDirectory(at: safariDir, includingPropertiesForKeys: nil)

            // If we can list Safari directory, we have FDA
            hasFullDiskAccess = true
            hasChecked = true
            return
        } catch {
            // Can't read Safari directory
        }

        // Try another protected location - Mail
        let mailDir = homeDir.appendingPathComponent("Library/Mail")
        do {
            _ = try FileManager.default.contentsOfDirectory(at: mailDir, includingPropertiesForKeys: nil)
            hasFullDiskAccess = true
            hasChecked = true
            return
        } catch {
            // Can't read Mail directory
        }

        // If none are readable, we don't have FDA
        hasFullDiskAccess = false
        hasChecked = true
    }

    /// Open System Settings to Full Disk Access pane
    func openSystemSettings() {
        // Deep link to Full Disk Access in System Settings
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Recheck FDA status (useful after user grants permission)
    func recheckAccess() {
        checkFullDiskAccess()
    }
}
