//
//  DirectorySizeCalculator.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-23.
//

import Foundation

/// Utility for calculating directory sizes asynchronously with concurrent scanning
actor DirectorySizeCalculator {

    // MARK: - Calculate Single Directory

    /// Calculate total size of a directory and its contents
    /// - Parameters:
    ///   - url: Directory URL to scan
    ///   - includeSubdirectories: Whether to recursively scan subdirectories (default: true)
    /// - Returns: Total size in bytes
    func calculateSize(at url: URL, includeSubdirectories: Bool = true) async throws -> Int64 {
        let fileManager = FileManager.default

        // Check if path exists and is accessible
        guard fileManager.fileExists(atPath: url.path) else {
            return 0
        }

        var totalSize: Int64 = 0

        // Get resource keys for efficient querying
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .fileSizeKey,
            .totalFileSizeKey
        ]

        if includeSubdirectories {
            // Use enumerator for recursive scanning - run on background thread
            let size = await Task.detached {
                var totalSize: Int64 = 0
                guard let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: Array(resourceKeys),
                    options: [],  // Don't skip hidden files - we want to scan all files including .cache, .npm, etc.
                    errorHandler: { _, error in
                        // Continue scanning on errors (permission denied, etc.)
                        return true
                    }
                ) else {
                    return totalSize
                }

                for case let fileURL as URL in enumerator {
                    guard let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys) else {
                        continue
                    }

                    // Skip directories, only count files
                    if resourceValues.isDirectory == true {
                        continue
                    }

                    // Use totalFileSize if available (includes resource forks), otherwise fileSize
                    if let size = resourceValues.totalFileSize {
                        totalSize += Int64(size)
                    } else if let size = resourceValues.fileSize {
                        totalSize += Int64(size)
                    }
                }
                return totalSize
            }.value

            totalSize = size
        } else {
            // Only scan immediate children (no subdirectories)
            guard let contents = try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: Array(resourceKeys),
                options: []  // Don't skip hidden files
            ) else {
                return 0
            }

            for fileURL in contents {
                guard let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys) else {
                    continue
                }

                // Only count files in immediate directory
                if resourceValues.isDirectory != true {
                    if let size = resourceValues.totalFileSize {
                        totalSize += Int64(size)
                    } else if let size = resourceValues.fileSize {
                        totalSize += Int64(size)
                    }
                }
            }
        }

        return totalSize
    }

    // MARK: - Calculate Multiple Directories Concurrently

    /// Calculate total size across multiple directories concurrently
    /// - Parameter urls: Array of directory URLs to scan
    /// - Returns: Total size in bytes across all directories
    func calculateTotalSize(for urls: [URL]) async -> Int64 {
        await withTaskGroup(of: Int64.self) { group in
            for url in urls {
                group.addTask {
                    (try? await self.calculateSize(at: url)) ?? 0
                }
            }

            var totalSize: Int64 = 0
            for await size in group {
                totalSize += size
            }
            return totalSize
        }
    }

    // MARK: - Get Items with Size Info

    /// Get list of items in directory with size information
    /// - Parameters:
    ///   - url: Directory URL to scan
    ///   - includeSubdirectories: Whether to list subdirectories recursively
    ///   - category: The cleanup category these items belong to
    ///   - ignorePatterns: Patterns to ignore during scanning
    ///   - safetyDatabase: Optional safety database for path validation
    /// - Returns: Array of CleanupItem objects with size info
    func getItems(at url: URL, category: CleanupCategory, includeSubdirectories: Bool = false, ignorePatterns: [String] = [], safetyDatabase: SafetyDatabase? = nil) async throws -> [CleanupItem] {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }

        var items: [CleanupItem] = []

        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .fileSizeKey,
            .totalFileSizeKey,
            .nameKey,
            .contentModificationDateKey
        ]

        if includeSubdirectories {
            let foundItems = await Task.detached {
                var items: [CleanupItem] = []
                guard let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: Array(resourceKeys),
                    options: [],
                    errorHandler: { _, _ in true }
                ) else {
                    return items
                }

                var fileCount = 0
                for case let fileURL as URL in enumerator {
                    // Check cancellation every iteration
                    if Task.isCancelled {
                        break
                    }

                    fileCount += 1

                    // SAFETY: Validate path if safetyDatabase provided
                    if let safetyDB = safetyDatabase {
                        let isSafe = await safetyDB.isApprovedForCleaning(fileURL, category: category)
                        if !isSafe {
                            continue
                        }
                    }

                    // Check ignore patterns
                    if self.shouldIgnore(fileURL, patterns: ignorePatterns) {
                        continue
                    }

                    if let item = try? self.createCleanupItem(from: fileURL, category: category, resourceKeys: resourceKeys) {
                        items.append(item)
                    }
                }
                return items
            }.value

            items = foundItems
        } else {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: Array(resourceKeys),
                options: []
            ) else {
                return []
            }

            for fileURL in contents {
                // Check cancellation
                try Task.checkCancellation()

                // SAFETY: Validate path if safetyDatabase provided
                if let safetyDB = safetyDatabase {
                    let isSafe = await safetyDB.isApprovedForCleaning(fileURL, category: category)
                    if !isSafe {
                        continue
                    }
                }

                // Check ignore patterns
                if shouldIgnore(fileURL, patterns: ignorePatterns) {
                    continue
                }

                if let item = try? createCleanupItem(from: fileURL, category: category, resourceKeys: resourceKeys) {
                    items.append(item)
                }
            }
        }

        return items
    }

    // MARK: - Ignore Patterns

    nonisolated private func shouldIgnore(_ url: URL, patterns: [String]) -> Bool {
        let pathString = url.path
        let lastComponent = url.lastPathComponent

        for pattern in patterns {
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

    // MARK: - Private Helpers

    nonisolated private func createCleanupItem(from url: URL, category: CleanupCategory, resourceKeys: Set<URLResourceKey>) throws -> CleanupItem {
        let resourceValues = try url.resourceValues(forKeys: resourceKeys)

        let size: Int64
        if let totalSize = resourceValues.totalFileSize {
            size = Int64(totalSize)
        } else if let fileSize = resourceValues.fileSize {
            size = Int64(fileSize)
        } else {
            size = 0
        }

        // Extract subcategory from path (e.g., "Google" from ~/Library/Caches/Google)
        let subcategory: String? = url.deletingLastPathComponent().lastPathComponent

        return CleanupItem.create(
            path: url,
            name: resourceValues.name ?? url.lastPathComponent,
            size: size,
            modifiedDate: resourceValues.contentModificationDate,
            category: category,
            subcategory: subcategory
        )
    }
}
