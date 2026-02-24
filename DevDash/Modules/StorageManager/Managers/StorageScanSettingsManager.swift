//
//  StorageScanSettingsManager.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-24.
//

import Foundation
import Combine

@MainActor
class StorageScanSettingsManager: ObservableObject {
    static let shared = StorageScanSettingsManager()

    @Published var settings: StorageScanSettings

    private let userDefaultsKey = "storageScanSettings"
    private let fileManager = FileManager.default

    // System paths that should NEVER be allowed
    private let blockedPaths = [
        "/System",
        "/Library",
        "/Applications",
        "/usr",
        "/bin",
        "/sbin",
        "/private/var",
        "/private/etc",
        "/dev",
        "/cores",
        "/Volumes/Macintosh HD/System"
    ]

    // User directory paths that should NEVER be allowed (within ~/)
    private let blockedUserPaths = [
        "Library/Application Support",
        "Library/Preferences",
        "Library/Containers",
        "Library/Keychains",
        "Library/Mail",
        "Library/Messages",
        "Library/Safari",
        "Library/Calendars",
        "Library/Reminders",
        "Library/Cookies",
        "Library/Saved Application State",
        "Library/Mobile Documents",
        "Library/Group Containers"
    ]

    private init() {
        // DEV: Reset to defaults (no backward compatibility during development)
        self.settings = .default
        save()
    }

    // MARK: - Persistence

    func save() {
        guard let encoded = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
    }

    func reset() {
        settings = .default
        save()
    }

    // MARK: - Location Management

    func addCustomLocation(path: String) throws {
        // Validate path
        try validateCustomPath(path)

        // Check if already exists
        guard !settings.customPaths.contains(path) else {
            throw SettingsError.pathAlreadyExists
        }

        // Add to custom paths
        settings.customPaths.append(path)
        save()
    }

    func removeCustomLocation(path: String) {
        settings.customPaths.removeAll { $0 == path }
        save()
    }

    func toggleLocation(id: String) {
        if let index = settings.scanLocations.firstIndex(where: { $0.id == id }) {
            settings.scanLocations[index].isEnabled.toggle()
            save()
        }
    }

    // MARK: - Category Management

    func toggleCategory(_ category: CleanupCategory) {
        if settings.enabledCategories.contains(category.rawValue) {
            settings.enabledCategories.remove(category.rawValue)
        } else {
            settings.enabledCategories.insert(category.rawValue)
        }
        save()
    }

    func isCategoryEnabled(_ category: CleanupCategory) -> Bool {
        settings.enabledCategories.contains(category.rawValue)
    }

    // MARK: - Ignore Patterns

    func addIgnorePattern(_ pattern: String) {
        guard !pattern.isEmpty, !settings.ignorePatterns.contains(pattern) else { return }
        settings.ignorePatterns.append(pattern)
        save()
    }

    func removeIgnorePattern(_ pattern: String) {
        settings.ignorePatterns.removeAll { $0 == pattern }
        save()
    }

    func shouldIgnore(path: URL) -> Bool {
        let pathString = path.path
        let lastComponent = path.lastPathComponent

        for pattern in settings.ignorePatterns {
            // Check if path contains pattern (e.g., "/path/node_modules/...")
            if pathString.contains("/\(pattern)/") || pathString.hasSuffix("/\(pattern)") {
                return true
            }
            // Check if last component matches pattern
            if lastComponent == pattern {
                return true
            }
            // Support wildcards (e.g., "*.log")
            if pattern.contains("*") {
                let regexPattern = pattern
                    .replacingOccurrences(of: ".", with: "\\.")
                    .replacingOccurrences(of: "*", with: ".*")
                if lastComponent.range(of: regexPattern, options: .regularExpression) != nil {
                    return true
                }
            }
        }

        return false
    }

    // MARK: - Deletion Mode

    func setDeletionMode(_ mode: DeletionMode) {
        settings.deletionMode = mode
        save()
    }

    // MARK: - Validation

    private func validateCustomPath(_ path: String) throws {
        let url = URL(fileURLWithPath: path)

        // Check if path exists
        guard fileManager.fileExists(atPath: path) else {
            throw SettingsError.pathDoesNotExist
        }

        // Check if it's a directory
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SettingsError.pathIsNotDirectory
        }

        // Check if path is blocked (system path)
        for blockedPath in blockedPaths {
            if path.hasPrefix(blockedPath) && path != "/private/tmp" {
                throw SettingsError.systemPathNotAllowed
            }
        }

        // Ensure path is within user's home directory or explicitly allowed
        let homePath = fileManager.homeDirectoryForCurrentUser.path
        if !path.hasPrefix(homePath) && path != "/private/tmp" {
            throw SettingsError.pathOutsideUserDirectory
        }

        // Check blocked user paths (within home directory)
        if path.hasPrefix(homePath) {
            let relativePath = String(path.dropFirst(homePath.count + 1))
            for blockedUserPath in blockedUserPaths {
                if relativePath.hasPrefix(blockedUserPath) {
                    throw SettingsError.criticalUserDataPath
                }
            }
        }

        // Use SafetyDatabase for final validation
        Task {
            do {
                try await SafetyDatabase.shared.validateCustomPath(path)
            } catch {
                throw SettingsError.safetyValidationFailed
            }
        }
    }

    // MARK: - Helper Methods

    func getAllEnabledPaths() -> [URL] {
        var paths: [URL] = []

        // Add default enabled locations
        for location in settings.scanLocations where location.isEnabled {
            paths.append(URL(fileURLWithPath: location.path))
        }

        // Add custom paths
        for customPath in settings.customPaths {
            paths.append(URL(fileURLWithPath: customPath))
        }

        return paths
    }
}

// MARK: - Settings Error

enum SettingsError: LocalizedError {
    case pathDoesNotExist
    case pathIsNotDirectory
    case systemPathNotAllowed
    case pathOutsideUserDirectory
    case pathAlreadyExists
    case criticalUserDataPath
    case safetyValidationFailed

    var errorDescription: String? {
        switch self {
        case .pathDoesNotExist:
            return "The selected path does not exist"
        case .pathIsNotDirectory:
            return "The selected path is not a directory"
        case .systemPathNotAllowed:
            return "System paths are not allowed for safety reasons"
        case .pathOutsideUserDirectory:
            return "Only paths within your home directory are allowed"
        case .pathAlreadyExists:
            return "This path is already added"
        case .criticalUserDataPath:
            return "⚠️ This path contains critical user data (app settings, passwords, mail, etc.) and cannot be scanned"
        case .safetyValidationFailed:
            return "This path failed safety validation and cannot be added"
        }
    }
}
