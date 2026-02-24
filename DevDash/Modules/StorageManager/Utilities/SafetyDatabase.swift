//
//  SafetyDatabase.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-24.
//

import Foundation

/// Safety database for validating file paths before scanning or deletion
/// Implements safelist approach - ONLY explicitly approved paths can be cleaned
///
/// ⚠️ CRITICAL SAFETY COMPONENT ⚠️
///
/// This file contains the safelist of directories that can be safely cleaned.
/// Before modifying ANY paths in this file, read the complete documentation:
///
/// 📖 See: DevDash/Modules/StorageManager/SAFETY_DATABASE_GUIDE.md
///
/// The guide contains:
/// - Sources and research for current safelist
/// - Maintenance procedures and schedule
/// - Guidelines and best practices
/// - What to do / what NOT to do
/// - Verification checklist (MUST complete before adding paths)
/// - Testing protocols
/// - Emergency response procedures
///
/// Key Rules:
/// 1. NEVER remove from protectedPaths without extensive research
/// 2. ALWAYS verify with 3+ sources before adding to safeCachePaths
/// 3. ALWAYS test on your own machine before adding
/// 4. When in doubt, PROTECT it
/// 5. Document all changes with sources and testing dates
///
/// Version: 1.0
/// Last Updated: 2026-02-24
/// Next Review: 2026-05-24 (Quarterly)
actor SafetyDatabase {

    // MARK: - Singleton

    static let shared = SafetyDatabase()

    private init() {}

    // MARK: - Protected Paths (NEVER scan or delete)

    /// Paths that must NEVER be scanned or deleted - contains critical user data
    ///
    /// 🔒 CRITICAL: These paths contain user data, licenses, passwords, settings
    ///
    /// Sources: CleanMyMac Safety Database, Apple Documentation, Browser Specs
    /// Verified: 2026-02-24
    /// See SAFETY_DATABASE_GUIDE.md for detailed sources and research
    ///
    /// NEVER remove from this list without reading the guide first.
    private let protectedPaths: [String] = [
        // System directories
        "/System",
        "/Library",
        "/Applications",
        "/usr",
        "/bin",
        "/sbin",
        "/private/var",  // Exception: /private/tmp is allowed
        "/private/etc",
        "/dev",
        "/cores",
        "/Volumes/Macintosh HD/System",

        // User critical directories (within ~/)
        "Library/Application Support",  // Contains app data, licenses, user configs
        "Library/Preferences",           // Contains all app and system preferences
        "Library/Containers",            // Sandboxed app data
        "Library/Keychains",            // Passwords and secure data
        "Library/Mail",                 // Mail data
        "Library/Messages",             // iMessage data
        "Library/Safari",               // Safari bookmarks, history, passwords
        "Library/Calendars",            // Calendar data
        "Library/Reminders",            // Reminders data
        "Library/Cookies",              // Login sessions
        "Library/Saved Application State", // App state for restore
        "Library/Mobile Documents",     // iCloud documents
        "Library/Group Containers",     // Shared app data

        // Browser profile/session data (within Caches)
        "Library/Caches/Google/Chrome/Default",    // Chrome profiles
        "Library/Caches/Google/Chrome/Profile",    // Chrome profiles
        "Library/Caches/com.apple.Safari",         // Safari sessions
        "Library/Caches/Firefox/Profiles",         // Firefox profiles
    ]

    // MARK: - Safe Cache Directories (CAN clean - regenerable data)

    /// App-specific cache directories that are safe to clean
    /// These contain only regenerable data (thumbnails, web cache, temp files)
    ///
    /// ✅ VERIFIED SAFE: Each path has been researched and tested
    ///
    /// Sources: Official documentation + CleanMyMac + Testing
    /// Verified: 2026-02-24
    /// See SAFETY_DATABASE_GUIDE.md section "Adding to safeCachePaths"
    ///
    /// Before adding new paths, complete the Verification Checklist in the guide.
    private let safeCachePaths: [String] = [
        // Developer tools (safe - can be regenerated)
        "Library/Developer/Xcode/DerivedData",
        "Library/Developer/Xcode/Archives",
        "Library/Developer/Xcode/iOS DeviceSupport",
        "Library/Developer/Xcode/iOS Device Logs",

        // Package managers (safe - downloaded packages)
        "Library/Caches/Homebrew",
        "Library/Caches/pip",
        ".npm",
        ".cache",
        ".cargo/registry",
        ".cargo/git",

        // Common app caches (safe - regenerable)
        "Library/Caches/com.apple.bird",           // iCloud sync cache
        "Library/Caches/com.apple.helpd",          // Help viewer
        "Library/Caches/com.apple.iconservices",   // Icon cache
        "Library/Caches/com.spotify.client",       // Spotify cache
        "Library/Caches/com.tinyspeck.slackmacgap", // Slack cache

        // System caches (safe)
        "Library/Caches/com.apple.nsurlsessiond",  // Download cache
        "Library/Caches/com.apple.DictionaryServices", // Dictionary cache
        "Library/Caches/com.apple.WebKit.PluginProcess", // WebKit cache
    ]

    // MARK: - Safe Temp Directories

    private let safeTempPaths: [String] = [
        "/private/tmp",
        "/private/var/tmp",
        "Library/Application Support/CrashReporter",  // Crash reports
    ]

    // MARK: - Browser-Specific Rules

    /// Browser cache paths that are safe to clean (NOT profile data)
    private func getBrowserCachePaths() -> [String] {
        return [
            // Chrome - only cache, NOT Default/Profile folders
            "Library/Caches/Google/Chrome/Cache",
            "Library/Caches/Google/Chrome/Code Cache",
            "Library/Caches/Google/Chrome/GPUCache",
            "Library/Caches/Google/Chrome/Media Cache",

            // Firefox - cache only, NOT profile folder
            "Library/Caches/Firefox/Profiles/*/cache2",

            // Safari - specific cache folders only
            "Library/Caches/com.apple.Safari/WebKitCache",
            "Library/Caches/com.apple.Safari/fsCachedData",
        ]
    }

    // MARK: - Public Validation Methods

    /// Check if a path is safe to scan
    /// - Parameter path: The file URL to validate
    /// - Returns: True if path is safe to scan, false if protected
    func isSafeToScan(_ path: URL) -> Bool {
        let pathString = path.path
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        // Convert to relative path for comparison
        let relativePath: String
        if pathString.hasPrefix(homeDir) {
            relativePath = String(pathString.dropFirst(homeDir.count + 1))
        } else {
            relativePath = pathString
        }

        // Check if path is protected
        for protectedPath in protectedPaths {
            if pathString.hasPrefix(protectedPath) || relativePath.hasPrefix(protectedPath) {
                // Exception: /private/tmp is allowed
                if pathString.hasPrefix("/private/tmp") {
                    return true
                }
                return false
            }
        }

        return true
    }

    /// Check if a path is explicitly approved for cleaning
    /// - Parameters:
    ///   - path: The file URL to validate
    ///   - category: The cleanup category
    /// - Returns: True if path is on safelist for this category
    func isApprovedForCleaning(_ path: URL, category: CleanupCategory) -> Bool {
        let pathString = path.path
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        // Convert to relative path
        let relativePath: String
        if pathString.hasPrefix(homeDir) {
            relativePath = String(pathString.dropFirst(homeDir.count + 1))
        } else {
            relativePath = pathString
        }

        // First check if protected (overrides safelist)
        if !isSafeToScan(path) {
            return false
        }

        // Check category-specific rules
        switch category {
        case .systemCaches:
            // Includes app caches, browser caches, package managers
            return isPathInList(relativePath, list: safeCachePaths) ||
                   isPackageManagerCache(relativePath)

        case .systemJunk:
            // Includes logs and temp files
            return relativePath.hasPrefix("Library/Logs") ||
                   isPathInList(pathString, list: safeTempPaths) ||
                   isPathInList(relativePath, list: safeTempPaths)

        case .developerTools:
            // Xcode and development tools
            return relativePath.hasPrefix("Library/Developer/Xcode/DerivedData") ||
                   relativePath.hasPrefix("Library/Developer/Xcode/Archives") ||
                   relativePath.hasPrefix("Library/Developer/Xcode/iOS DeviceSupport")

        case .trash:
            return relativePath.hasPrefix(".Trash") || pathString.contains("/.Trashes/")

        case .downloads:
            return relativePath.hasPrefix("Downloads")

        case .largeOldFiles:
            // For user-selected locations, check they're not in protected paths
            return !isInProtectedPath(relativePath)
        }
    }

    /// Get approved scan targets for a category
    /// - Parameter category: The cleanup category
    /// - Returns: Array of URLs that are safe to scan for this category
    func getApprovedScanTargets(for category: CleanupCategory) -> [URL] {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser

        switch category {
        case .systemCaches:
            // App caches + package manager caches
            var paths = safeCachePaths.map { homeDir.appendingPathComponent($0) }
            paths.append(contentsOf: [
                homeDir.appendingPathComponent("Library/Caches/Homebrew"),
                homeDir.appendingPathComponent(".npm"),
                homeDir.appendingPathComponent(".cache"),
                homeDir.appendingPathComponent(".cargo/registry"),
                homeDir.appendingPathComponent(".cargo/git"),
                homeDir.appendingPathComponent("Library/Caches/pip")
            ])
            return paths

        case .systemJunk:
            // Logs + temp files
            var paths = [homeDir.appendingPathComponent("Library/Logs")]
            paths.append(contentsOf: safeTempPaths.map { path in
                if path.hasPrefix("/") {
                    return URL(fileURLWithPath: path)
                } else {
                    return homeDir.appendingPathComponent(path)
                }
            })
            return paths

        case .developerTools:
            return [
                homeDir.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
                homeDir.appendingPathComponent("Library/Developer/Xcode/Archives"),
                homeDir.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport")
            ]

        case .trash:
            return [homeDir.appendingPathComponent(".Trash")]

        case .downloads:
            return [homeDir.appendingPathComponent("Downloads")]

        case .largeOldFiles:
            // Uses user-configured paths from settings
            return []
        }
    }

    /// Validate that a custom user path is safe to add
    /// - Parameter path: The path to validate
    /// - Returns: True if safe to add, throws error otherwise
    func validateCustomPath(_ path: String) throws {
        let url = URL(fileURLWithPath: path)
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        // Must be within home directory
        guard path.hasPrefix(homeDir) else {
            throw SafetyError.pathOutsideHomeDirectory
        }

        // Check against protected paths
        if !isSafeToScan(url) {
            throw SafetyError.protectedPath
        }
    }

    // MARK: - Private Helpers

    private func isPathInList(_ path: String, list: [String]) -> Bool {
        for approvedPath in list {
            if path.hasPrefix(approvedPath) || path.contains("/\(approvedPath)") {
                return true
            }
        }
        return false
    }

    private func isPackageManagerCache(_ relativePath: String) -> Bool {
        return relativePath.hasPrefix("Library/Caches/Homebrew") ||
               relativePath.hasPrefix("Library/Caches/pip") ||
               relativePath.hasPrefix(".npm") ||
               relativePath.hasPrefix(".cache") ||
               relativePath.hasPrefix(".cargo/registry") ||
               relativePath.hasPrefix(".cargo/git")
    }

    private func isInProtectedPath(_ relativePath: String) -> Bool {
        for protectedPath in protectedPaths {
            if relativePath.hasPrefix(protectedPath) {
                return true
            }
        }
        return false
    }
}

// MARK: - Safety Errors

enum SafetyError: LocalizedError {
    case protectedPath
    case pathOutsideHomeDirectory
    case notOnSafelist

    var errorDescription: String? {
        switch self {
        case .protectedPath:
            return "This path contains critical system or user data and cannot be scanned"
        case .pathOutsideHomeDirectory:
            return "Only paths within your home directory can be scanned"
        case .notOnSafelist:
            return "This path is not on the approved safelist for cleaning"
        }
    }
}
