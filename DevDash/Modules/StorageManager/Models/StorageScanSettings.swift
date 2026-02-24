//
//  StorageScanSettings.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-24.
//

import Foundation

// MARK: - Storage Scan Settings

struct StorageScanSettings: Codable {
    // 1. Scan Locations
    var scanLocations: [ScanLocation]
    var customPaths: [String]

    // 2. What to Scan (enabled categories)
    var enabledCategories: Set<String>  // CleanupCategory.rawValue

    // 3. Ignore Patterns
    var ignorePatterns: [String]

    // 4. Deletion Preference
    var deletionMode: DeletionMode

    // Default settings
    static var `default`: StorageScanSettings {
        StorageScanSettings(
            scanLocations: ScanLocation.defaultLocations,
            customPaths: [],
            enabledCategories: Set(CleanupCategory.allCases.map { $0.rawValue }),
            ignorePatterns: [
                "node_modules",
                ".git",
                ".next",
                ".nuxt",
                "dist",
                "build",
                "__pycache__",
                ".venv",
                "venv",
                "target",  // Rust/Java
                "vendor",  // PHP/Go
                ".terraform"
            ],
            deletionMode: .moveToTrash
        )
    }
}

// MARK: - Scan Location

struct ScanLocation: Identifiable, Codable, Hashable {
    let id: String
    let path: String
    let name: String
    var isEnabled: Bool
    let isCustom: Bool

    static var defaultLocations: [ScanLocation] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        return [
            // User folders - ONLY these are scanned by "Large & Old Files"
            // System folders (Caches, Logs, Trash, Temp) are handled by dedicated categories
            ScanLocation(id: "desktop", path: "\(home)/Desktop", name: "Desktop", isEnabled: true, isCustom: false),
            ScanLocation(id: "documents", path: "\(home)/Documents", name: "Documents", isEnabled: true, isCustom: false),
            ScanLocation(id: "downloads", path: "\(home)/Downloads", name: "Downloads", isEnabled: true, isCustom: false),
            ScanLocation(id: "movies", path: "\(home)/Movies", name: "Movies", isEnabled: false, isCustom: false),
            ScanLocation(id: "music", path: "\(home)/Music", name: "Music", isEnabled: false, isCustom: false),
            ScanLocation(id: "pictures", path: "\(home)/Pictures", name: "Pictures", isEnabled: false, isCustom: false),
        ]
    }
}

// MARK: - Deletion Mode

enum DeletionMode: String, Codable, CaseIterable {
    case moveToTrash = "move_to_trash"
    case permanentDelete = "permanent_delete"

    var displayName: String {
        switch self {
        case .moveToTrash:
            return "Move to Trash"
        case .permanentDelete:
            return "Delete Permanently"
        }
    }

    var description: String {
        switch self {
        case .moveToTrash:
            return "Files can be recovered from Trash"
        case .permanentDelete:
            return "⚠️ Files are deleted immediately and cannot be recovered"
        }
    }
}
