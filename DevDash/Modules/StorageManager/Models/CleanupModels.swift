//
//  CleanupModels.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-23.
//

import Foundation
import Combine
import SwiftUI

// MARK: - Cleanup Category

enum CleanupCategory: String, CaseIterable, Identifiable {
    case systemCaches = "system_caches"
    case systemJunk = "system_junk"
    case developerTools = "developer_tools"
    case largeOldFiles = "large_old_files"
    case trash = "trash"
    case downloads = "downloads"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .systemCaches: return "System Caches"
        case .systemJunk: return "System Junk"
        case .developerTools: return "Developer Tools"
        case .largeOldFiles: return "Large & Old Files"
        case .trash: return "Trash"
        case .downloads: return "Downloads"
        }
    }

    var description: String {
        switch self {
        case .systemCaches:
            return "Application caches, browser caches, and package manager caches that regenerate automatically"
        case .systemJunk:
            return "User logs, temporary files, crash reports, and system junk that's safe to remove"
        case .developerTools:
            return "Xcode build artifacts, iOS device support files, and development tool caches"
        case .largeOldFiles:
            return "Large files (>100 MB) and duplicate files across your selected folders"
        case .trash:
            return "Files in all Trash bins across mounted volumes"
        case .downloads:
            return "Old files in Downloads folder (>30 days)"
        }
    }

    var icon: String {
        switch self {
        case .systemCaches: return "folder.badge.gearshape"
        case .systemJunk: return "doc.text.fill"
        case .developerTools: return "hammer.fill"
        case .largeOldFiles: return "doc.badge.arrow.up.fill"
        case .trash: return "trash.fill"
        case .downloads: return "arrow.down.circle.fill"
        }
    }

    var safetyLevel: SafetyLevel {
        switch self {
        case .systemCaches, .systemJunk, .developerTools:
            return .safe
        case .largeOldFiles:
            return .caution
        case .trash, .downloads:
            return .userData
        }
    }

    var scanningMessage: String {
        switch self {
        case .systemCaches: return "Scanning system caches..."
        case .systemJunk: return "Finding system junk..."
        case .developerTools: return "Checking developer tools..."
        case .largeOldFiles: return "Finding large and old files..."
        case .trash: return "Checking Trash bins..."
        case .downloads: return "Scanning Downloads folder..."
        }
    }
}

// MARK: - Safety Level

enum SafetyLevel {
    case safe       // Automatically regenerated data, safe to delete
    case caution    // Permanent deletion, requires review
    case userData   // User files, must be carefully reviewed
    case disabled   // Feature disabled for safety

    var color: String {
        switch self {
        case .safe: return "green"
        case .caution: return "orange"
        case .userData: return "blue"
        case .disabled: return "gray"
        }
    }
}

// MARK: - Cleanup Item

struct CleanupItem: Identifiable, Hashable {
    let id = UUID()
    let path: URL
    let name: String
    let size: Int64
    let modifiedDate: Date?
    let category: CleanupCategory
    let subcategory: String?  // e.g., "Google", "Homebrew" for caches

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    // Helper to create item
    static func create(
        path: URL,
        name: String,
        size: Int64,
        modifiedDate: Date?,
        category: CleanupCategory,
        subcategory: String? = nil
    ) -> CleanupItem {
        CleanupItem(
            path: path,
            name: name,
            size: size,
            modifiedDate: modifiedDate,
            category: category,
            subcategory: subcategory
        )
    }
}

// MARK: - File Tree Node (for hierarchical display)

class FileTreeNode: Identifiable {
    let id = UUID()
    let name: String
    let path: URL
    let size: Int64
    let modifiedDate: Date?
    let isDirectory: Bool
    var children: [FileTreeNode]?
    let item: CleanupItem?  // Reference to original item if this is a file

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var allDescendantItems: [CleanupItem] {
        var items: [CleanupItem] = []
        if let item = item {
            items.append(item)
        }
        for child in children ?? [] {
            items.append(contentsOf: child.allDescendantItems)
        }
        return items
    }

    init(name: String, path: URL, size: Int64, modifiedDate: Date?, isDirectory: Bool, children: [FileTreeNode]? = nil, item: CleanupItem? = nil) {
        self.name = name
        self.path = path
        self.size = size
        self.modifiedDate = modifiedDate
        self.isDirectory = isDirectory
        self.children = children
        self.item = item
    }

    // Build tree from flat list of CleanupItems
    // Creates proper nested hierarchy with depth limiting for performance
    static func buildTree(from items: [CleanupItem], selectedIds: Set<UUID>, maxDepth: Int = 3) -> [FileTreeNode] {
        guard !items.isEmpty else { return [] }

        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        // Find common root paths to create top-level nodes
        let rootPaths = findCommonRootPaths(items: items, homeDir: homeDir, maxDepth: maxDepth)

        var rootNodes: [FileTreeNode] = []

        for rootPath in rootPaths {
            // Get all items under this root
            let itemsInRoot = items.filter { item in
                item.path.path.hasPrefix(rootPath)
            }

            guard !itemsInRoot.isEmpty else { continue }

            // Build tree recursively from this root
            if let rootNode = buildNode(
                at: URL(fileURLWithPath: rootPath),
                items: itemsInRoot,
                homeDir: homeDir,
                currentDepth: 0,
                maxDepth: maxDepth
            ) {
                rootNodes.append(rootNode)
            }
        }

        return rootNodes.sorted { $0.name < $1.name }
    }

    // Find common root paths to avoid deeply nested single-child trees
    private static func findCommonRootPaths(items: [CleanupItem], homeDir: String, maxDepth: Int) -> [String] {
        // Extract all unique parent paths
        let allPaths = items.map { $0.path.deletingLastPathComponent().path }
        let uniquePaths = Set(allPaths)

        // Find root-level paths (paths that are not children of other paths in the set)
        var rootPaths: Set<String> = []

        for path in uniquePaths {
            var isRoot = true
            var currentPath = path
            var depth = 0

            // Walk up the directory tree
            while currentPath != "/" && currentPath.hasPrefix(homeDir) && depth < maxDepth {
                let parentPath = (currentPath as NSString).deletingLastPathComponent

                // If parent exists in our unique paths, this is not a root
                if uniquePaths.contains(parentPath) && parentPath != currentPath {
                    isRoot = false
                    break
                }

                currentPath = parentPath
                depth += 1
            }

            if isRoot {
                // Use the path at maxDepth or the original path if shallower
                var finalPath = path
                var pathDepth = pathComponents(path, relativeTo: homeDir).count

                if pathDepth > maxDepth {
                    // Truncate to maxDepth
                    let components = pathComponents(path, relativeTo: homeDir)
                    let truncated = components.prefix(maxDepth)
                    finalPath = homeDir + "/" + truncated.joined(separator: "/")
                }

                rootPaths.insert(finalPath)
            }
        }

        return Array(rootPaths)
    }

    // Get path components relative to home directory
    private static func pathComponents(_ path: String, relativeTo homeDir: String) -> [String] {
        if path.hasPrefix(homeDir) {
            let relative = String(path.dropFirst(homeDir.count))
            return relative.split(separator: "/").map(String.init)
        }
        return path.split(separator: "/").map(String.init)
    }

    // Recursively build a tree node for a directory
    private static func buildNode(
        at directoryURL: URL,
        items: [CleanupItem],
        homeDir: String,
        currentDepth: Int,
        maxDepth: Int
    ) -> FileTreeNode? {
        let directoryPath = directoryURL.path

        // Get items directly in this directory (not in subdirectories)
        let filesInThisDir = items.filter { item in
            item.path.deletingLastPathComponent().path == directoryPath
        }

        // Get items in subdirectories
        let itemsInSubdirs = items.filter { item in
            item.path.path.hasPrefix(directoryPath + "/") &&
            item.path.deletingLastPathComponent().path != directoryPath
        }

        // If we've reached max depth, aggregate all remaining items
        if currentDepth >= maxDepth && !itemsInSubdirs.isEmpty {
            // Create aggregated child nodes
            let totalSize = items.reduce(0) { $0 + $1.size }
            let displayName = compactPath(directoryPath, homeDir: homeDir)

            // Show aggregated count
            let fileCount = items.count
            let aggregatedName = "\(displayName) (\(fileCount) files)"

            return FileTreeNode(
                name: aggregatedName,
                path: directoryURL,
                size: totalSize,
                modifiedDate: nil,
                isDirectory: true,
                children: [], // No children shown at max depth
                item: nil
            )
        }

        // Build child nodes
        var childNodes: [FileTreeNode] = []

        // Add file nodes for files in this directory
        for item in filesInThisDir {
            let fileNode = FileTreeNode(
                name: item.name,
                path: item.path,
                size: item.size,
                modifiedDate: item.modifiedDate,
                isDirectory: false,
                children: nil,
                item: item
            )
            childNodes.append(fileNode)
        }

        // Add subdirectory nodes
        if !itemsInSubdirs.isEmpty {
            // Group by immediate subdirectory
            let subdirGroups = Dictionary(grouping: itemsInSubdirs) { item -> String in
                let itemPath = item.path.path
                let relativePath = String(itemPath.dropFirst(directoryPath.count + 1))
                let firstComponent = relativePath.split(separator: "/").first.map(String.init) ?? ""
                return directoryPath + "/" + firstComponent
            }

            for (subdirPath, subdirItems) in subdirGroups {
                if let subdirNode = buildNode(
                    at: URL(fileURLWithPath: subdirPath),
                    items: subdirItems,
                    homeDir: homeDir,
                    currentDepth: currentDepth + 1,
                    maxDepth: maxDepth
                ) {
                    childNodes.append(subdirNode)
                }
            }
        }

        // Calculate total size
        let totalSize = items.reduce(0) { $0 + $1.size }

        // Create display name
        let displayName = compactPath(directoryPath, homeDir: homeDir)

        return FileTreeNode(
            name: displayName,
            path: directoryURL,
            size: totalSize,
            modifiedDate: nil,
            isDirectory: true,
            children: childNodes.isEmpty ? nil : childNodes.sorted { $0.name < $1.name },
            item: nil
        )
    }

    // Convert full path to compact display format (~/path instead of /Users/name/path)
    private static func compactPath(_ path: String, homeDir: String) -> String {
        if path.hasPrefix(homeDir) {
            let relative = String(path.dropFirst(homeDir.count))
            return "~" + relative
        }
        return path
    }
}

// MARK: - Category Info (Lightweight State)

struct CategoryInfo: Identifiable, Equatable, Hashable {
    let id: String  // CleanupCategory.rawValue
    let category: CleanupCategory
    let totalSize: Int64
    let itemCount: Int
    let isScanning: Bool
    let scanError: String?
    let isSelected: Bool

    var formattedSize: String {
        guard totalSize > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    static func empty(category: CleanupCategory) -> CategoryInfo {
        CategoryInfo(
            id: category.rawValue,
            category: category,
            totalSize: 0,
            itemCount: 0,
            isScanning: false,
            scanError: nil,
            isSelected: false
        )
    }
}

// MARK: - Cleanup Operation

enum CleanupOperation {
    case moveToTrash   // Safe, recoverable
    case permanentDelete  // Irreversible
}

// MARK: - Cleanup Result

struct CleanupResult {
    let category: CleanupCategory
    let freedSpace: Int64
    let itemsCleaned: Int
    let errors: [String]

    var success: Bool {
        errors.isEmpty
    }

    var formattedFreedSpace: String {
        ByteCountFormatter.string(fromByteCount: freedSpace, countStyle: .file)
    }
}

// MARK: - Scan Progress

struct ScanProgress {
    let category: CleanupCategory
    let message: String
    let currentPath: String?
    let filesScanned: Int
}

// MARK: - Location Scan Status

enum LocationScanStatus: Equatable {
    case pending
    case scanning(currentCategory: String)
    case completed(filesFound: Int, sizeFound: Int64)
}

struct LocationScanInfo: Identifiable, Equatable {
    let id: String  // Path
    let name: String
    let path: String
    var status: LocationScanStatus

    static func from(location: ScanLocation) -> LocationScanInfo {
        LocationScanInfo(
            id: location.path,
            name: location.name,
            path: location.path,
            status: .pending
        )
    }

    static func from(customPath: String) -> LocationScanInfo {
        let url = URL(fileURLWithPath: customPath)
        return LocationScanInfo(
            id: customPath,
            name: url.lastPathComponent,
            path: customPath,
            status: .pending
        )
    }
}

// MARK: - Scan State

enum ScanState: Equatable {
    case idle
    case scanning(progress: String, currentPath: String?)
    case completed
    case error(String)
}

// MARK: - View State

enum CleanupViewState: Equatable {
    case initial
    case scanning
    case results
    case reviewingCategory(CleanupCategory)
}
