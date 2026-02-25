//
//  CleanupManager.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-23.
//

import Foundation
import Combine
import CryptoKit

@MainActor
class CleanupManager: ObservableObject {

    // MARK: - Published Properties

    @Published var scanState: ScanState = .idle
    @Published var currentScanningCategory: CleanupCategory?
    @Published var currentPath: String?
    @Published var categories: [CategoryInfo] = []
    @Published var itemsByCategory: [CleanupCategory: [CleanupItem]] = [:]  // Items grouped by category
    @Published var selectedItemIds: Set<UUID> = []  // Separate selection tracking
    @Published var isProcessing = false
    @Published var locationScanInfos: [LocationScanInfo] = []  // Track scanning progress per location
    @Published var deletionItems: [DeletionItemInfo] = []  // Track deletion progress
    @Published var showingDeletionProgress = false

    // MARK: - Computed Properties

    var totalScannedSize: Int64 {
        itemsByCategory.values.flatMap { $0 }.reduce(0) { $0 + $1.size }
    }

    var selectedItemsCount: Int {
        selectedItemIds.count
    }

    var selectedItemsSize: Int64 {
        itemsByCategory.values.flatMap { $0 }
            .filter { selectedItemIds.contains($0.id) }
            .reduce(0) { $0 + $1.size }
    }

    // Group items by subcategory within a category
    func itemsBySubcategory(for category: CleanupCategory) -> [String: [CleanupItem]] {
        let categoryItems = itemsByCategory[category] ?? []
        let grouped = Dictionary(grouping: categoryItems) { $0.subcategory ?? "Other" }
        return grouped
    }

    // Get items for a specific category
    func items(for category: CleanupCategory) -> [CleanupItem] {
        itemsByCategory[category] ?? []
    }

    // Check if an item is selected
    func isItemSelected(id: UUID) -> Bool {
        selectedItemIds.contains(id)
    }

    // MARK: - Private Properties

    private let calculator = DirectorySizeCalculator()
    private let fileManager = FileManager.default
    private let settingsManager = StorageScanSettingsManager.shared
    private let safetyDatabase = SafetyDatabase.shared
    private var scanTask: Task<Void, Never>?

    // Deletion cancellation
    private var deletionTask: Task<Void, Never>?
    private var deletionCancelled = false

    // Deduplication: Track files already categorized
    private var categorizedPaths: Set<String> = []

    // Directories to exclude from user home scanning (system/already-scanned directories)
    private let excludedHomeDirs = [
        "Library",  // System libraries, caches already scanned separately
        ".Trash",   // Already scanned in trash category
        "Applications",  // System apps
        ".localized",
        ".CFUserTextEncoding"
    ]

    // MARK: - Initialization

    init() {
        // Initialize with all categories in empty state
        self.categories = CleanupCategory.allCases.map { .empty(category: $0) }
    }

    // MARK: - Public Methods - Scanning

    /// Start scanning all categories - priority-based with deduplication
    func startScan() {
        scanTask?.cancel()
        scanState = .scanning(progress: "Initializing scan...", currentPath: nil)
        itemsByCategory.removeAll()
        selectedItemIds.removeAll()
        categorizedPaths.removeAll()  // Clear deduplication tracking

        // Initialize all categories as empty (not yet scanned)
        categories = CleanupCategory.allCases.map { .empty(category: $0) }

        // Initialize location scan infos
        var scanTargets: [LocationScanInfo] = []

        // Add "System" target for system scans
        scanTargets.append(LocationScanInfo(
            id: "system",
            name: "System",
            path: "/System",
            status: .pending
        ))

        // Add enabled user folders
        let enabledLocations = settingsManager.getAllEnabledLocations()
        for location in enabledLocations {
            scanTargets.append(LocationScanInfo(
                id: location.id,
                name: location.name,
                path: location.path,
                status: .pending
            ))
        }

        locationScanInfos = scanTargets

        scanTask = Task {
            // Get enabled categories
            var enabledCategories = CleanupCategory.allCases.filter {
                settingsManager.isCategoryEnabled($0)
            }

            // IMPORTANT: If deletion mode is "Move to Trash", always skip the Trash category
            // (no point scanning trash if we're moving deleted files to trash)
            // If deletion mode is "Delete Permanently", respect the setting
            if settingsManager.settings.deletionMode == .moveToTrash {
                enabledCategories = enabledCategories.filter { $0 != .trash }
            }

            // STEP 1: Scan system categories first (priority order)
            // These have fixed paths and take precedence
            let systemCategories: [CleanupCategory] = [
                .systemCaches,
                .systemJunk,
                .developerTools,
                .trash,
                .downloads
            ].filter { enabledCategories.contains($0) }

            // Mark "System" as scanning
            await updateLocationScanStatus("system", status: .scanning(currentCategory: "System"))

            var systemFilesFound = 0
            var systemSizeFound: Int64 = 0

            for category in systemCategories {
                guard !Task.isCancelled else {
                    await MainActor.run {
                        scanState = .idle
                        refreshCategories()
                    }
                    return
                }

                await updateLocationScanStatus("system", status: .scanning(currentCategory: category.name))
                let items = await scanCategoryWithDedup(category)

                systemFilesFound += items.count
                systemSizeFound += items.reduce(0) { $0 + $1.size }

                // Track all categorized paths
                await MainActor.run {
                    for item in items {
                        categorizedPaths.insert(item.path.path)
                    }
                }
            }

            // Mark "System" as completed
            await updateLocationScanStatus("system", status: .completed(filesFound: systemFilesFound, sizeFound: systemSizeFound))

            // STEP 2: Scan user folders for cache/log/temp patterns
            // These get added to system categories (systemCaches or systemJunk)
            if enabledCategories.contains(.systemCaches) || enabledCategories.contains(.systemJunk) {
                guard !Task.isCancelled else {
                    await MainActor.run {
                        scanState = .idle
                        refreshCategories()
                    }
                    return
                }

                await scanUserFoldersForSystemFiles()
            }

            // STEP 3: Scan for large files (skip already categorized)
            if enabledCategories.contains(.largeOldFiles) {
                guard !Task.isCancelled else {
                    await MainActor.run {
                        scanState = .idle
                        refreshCategories()
                    }
                    return
                }

                let items = await scanCategoryWithDedup(.largeOldFiles)
                await MainActor.run {
                    for item in items {
                        categorizedPaths.insert(item.path.path)
                    }
                }
            }

            // Mark all remaining categories as complete (scanned but no results)
            await MainActor.run {
                scanState = .completed
                refreshCategories()
            }
        }
    }

    private func updateLocationScanStatus(_ locationId: String, status: LocationScanStatus) async {
        await MainActor.run {
            if let index = locationScanInfos.firstIndex(where: { $0.id == locationId }) {
                locationScanInfos[index].status = status
            }
        }
    }

    /// Stop current scan
    func stopScan() {
        scanTask?.cancel()
        scanState = .idle
        currentScanningCategory = nil
        currentPath = nil
        locationScanInfos.removeAll()
    }

    /// Scan user folders for cache/log/temp files and add to system categories
    private func scanUserFoldersForSystemFiles() async {
        // Get user-selected scan locations
        let enabledLocations = settingsManager.getAllEnabledLocations()

        // File patterns for cache files
        let cachePatterns = [
            "cache", ".cache", "Cache", "caches", "Caches",
            "*.cache", "*-cache", "*_cache"
        ]

        // File patterns for log/temp files
        let logTempPatterns = [
            "*.log", "*.tmp", "*.temp",
            "log", "logs", "Log", "Logs",
            "tmp", "temp", "Temp", "Tmp",
            "crash", "Crash", "*.crash"
        ]

        await MainActor.run {
            scanState = .scanning(progress: "Scanning user folders for cache/log/temp files...", currentPath: nil)
        }

        for location in enabledLocations {
            let locationURL = URL(fileURLWithPath: location.path)
            guard fileManager.fileExists(atPath: locationURL.path) else { continue }

            // Check cancellation
            guard !Task.isCancelled else { return }

            // Mark location as scanning
            await updateLocationScanStatus(location.id, status: .scanning(currentCategory: "Caches & Junk"))

            var locationFilesFound = 0
            var locationSizeFound: Int64 = 0

            // Scan for cache files
            do {
                let items = try await calculator.getItems(
                    at: locationURL,
                    category: .systemCaches,
                    includeSubdirectories: true,
                    ignorePatterns: settingsManager.settings.ignorePatterns,
                    safetyDatabase: safetyDatabase
                )

                // Filter items matching cache patterns
                let cacheItems = items.filter { item in
                    let path = item.path.path.lowercased()
                    let name = item.name.lowercased()

                    // Skip if already categorized
                    if categorizedPaths.contains(item.path.path) {
                        return false
                    }

                    // Check if name or path contains cache patterns
                    for pattern in cachePatterns {
                        if pattern.contains("*") {
                            // Wildcard pattern
                            let regex = pattern
                                .replacingOccurrences(of: ".", with: "\\.")
                                .replacingOccurrences(of: "*", with: ".*")
                            if name.range(of: regex, options: .regularExpression) != nil {
                                return true
                            }
                        } else {
                            // Exact match or contains
                            if name.contains(pattern.lowercased()) || path.contains("/\(pattern.lowercased())/") {
                                return true
                            }
                        }
                    }
                    return false
                }

                locationFilesFound += cacheItems.count
                locationSizeFound += cacheItems.reduce(0) { $0 + $1.size }

                await MainActor.run {
                    if !cacheItems.isEmpty {
                        itemsByCategory[.systemCaches, default: []].append(contentsOf: cacheItems)
                        for item in cacheItems {
                            categorizedPaths.insert(item.path.path)
                        }
                    }
                }
            } catch {
                // Continue on errors
            }

            // Scan for log/temp files
            do {
                let items = try await calculator.getItems(
                    at: locationURL,
                    category: .systemJunk,
                    includeSubdirectories: true,
                    ignorePatterns: settingsManager.settings.ignorePatterns,
                    safetyDatabase: safetyDatabase
                )

                // Filter items matching log/temp patterns
                let logTempItems = items.filter { item in
                    let path = item.path.path.lowercased()
                    let name = item.name.lowercased()

                    // Skip if already categorized
                    if categorizedPaths.contains(item.path.path) {
                        return false
                    }

                    // Check if name or path contains log/temp patterns
                    for pattern in logTempPatterns {
                        if pattern.contains("*") {
                            // Wildcard pattern
                            let regex = pattern
                                .replacingOccurrences(of: ".", with: "\\.")
                                .replacingOccurrences(of: "*", with: ".*")
                            if name.range(of: regex, options: .regularExpression) != nil {
                                return true
                            }
                        } else {
                            // Exact match or contains
                            if name.contains(pattern.lowercased()) || path.contains("/\(pattern.lowercased())/") {
                                return true
                            }
                        }
                    }
                    return false
                }

                locationFilesFound += logTempItems.count
                locationSizeFound += logTempItems.reduce(0) { $0 + $1.size }

                await MainActor.run {
                    if !logTempItems.isEmpty {
                        itemsByCategory[.systemJunk, default: []].append(contentsOf: logTempItems)
                        for item in logTempItems {
                            categorizedPaths.insert(item.path.path)
                        }
                    }
                }
            } catch {
                // Continue on errors
            }

            // Mark location as completed
            await updateLocationScanStatus(location.id, status: .completed(filesFound: locationFilesFound, sizeFound: locationSizeFound))
        }

        await MainActor.run {
            refreshCategories()
        }
    }

    // MARK: - Public Methods - Selection

    /// Toggle selection for a specific item
    func toggleItemSelection(id: UUID) {
        if selectedItemIds.contains(id) {
            selectedItemIds.remove(id)
        } else {
            selectedItemIds.insert(id)
        }
        refreshCategories()
    }

    /// Toggle selection for a specific item (convenience method that takes the item)
    func toggleItem(_ item: CleanupItem) {
        toggleItemSelection(id: item.id)
    }

    /// Clear all selections for a specific category
    func clearCategorySelection(_ category: CleanupCategory) {
        guard let categoryItems = itemsByCategory[category] else { return }

        for item in categoryItems {
            selectedItemIds.remove(item.id)
        }
        refreshCategories()
    }

    /// Toggle all items in a category
    func toggleCategory(_ category: CleanupCategory, selected: Bool) {
        guard let categoryItems = itemsByCategory[category] else { return }

        if selected {
            for item in categoryItems {
                selectedItemIds.insert(item.id)
            }
        } else {
            for item in categoryItems {
                selectedItemIds.remove(item.id)
            }
        }
        refreshCategories()
    }

    /// Toggle all items in a subcategory
    func toggleSubcategory(_ subcategory: String, in category: CleanupCategory, selected: Bool) {
        guard let categoryItems = itemsByCategory[category] else { return }

        let subcategoryItems = categoryItems.filter { $0.subcategory == subcategory }

        if selected {
            for item in subcategoryItems {
                selectedItemIds.insert(item.id)
            }
        } else {
            for item in subcategoryItems {
                selectedItemIds.remove(item.id)
            }
        }
        refreshCategories()
    }

    /// Select all items
    func selectAll() {
        for items in itemsByCategory.values {
            for item in items {
                selectedItemIds.insert(item.id)
            }
        }
        refreshCategories()
    }

    /// Deselect all items
    func deselectAll() {
        selectedItemIds.removeAll()
        refreshCategories()
    }

    /// Get selected items in a specific category
    func getSelectedItems(in category: CleanupCategory) -> [CleanupItem] {
        guard let categoryItems = itemsByCategory[category] else { return [] }
        return categoryItems.filter { selectedItemIds.contains($0.id) }
    }

    // MARK: - Public Methods - Cleanup

    /// Clean selected items
    func cleanSelected(operation: CleanupOperation? = nil) async -> [CleanupResult] {
        isProcessing = true
        deletionCancelled = false

        // Get all selected items from all categories
        var selectedItems: [CleanupItem] = []
        for (_, categoryItems) in itemsByCategory {
            selectedItems.append(contentsOf: categoryItems.filter { selectedItemIds.contains($0.id) })
        }

        // Initialize deletion tracking
        await MainActor.run {
            deletionItems = selectedItems.map { item in
                DeletionItemInfo(
                    id: item.id,
                    name: item.name,
                    path: item.path.path,
                    size: item.size,
                    status: .pending
                )
            }
            showingDeletionProgress = true
        }

        // SAFETY: Always use trash for now, never permanent delete
        // TODO: Re-enable permanent delete after validation
        let cleanupOperation: CleanupOperation = .moveToTrash

        var results: [CleanupResult] = []
        var allErrors: [String] = []

        // Delete items one by one with progress tracking
        for item in selectedItems {
            // Check if deletion was cancelled
            if deletionCancelled {
                break
            }

            // Update status to deleting
            await MainActor.run {
                if let index = deletionItems.firstIndex(where: { $0.id == item.id }) {
                    deletionItems[index].status = .deleting
                }
            }

            // Perform deletion
            let result = await deleteItem(item, operation: cleanupOperation)

            // Update status based on result
            await MainActor.run {
                if let index = deletionItems.firstIndex(where: { $0.id == item.id }) {
                    if result.success {
                        deletionItems[index].status = .completed
                    } else {
                        let errorMsg = result.errors.first ?? "Unknown error"
                        deletionItems[index].status = .failed(errorMsg)
                    }
                }
            }

            allErrors.append(contentsOf: result.errors)
        }

        // Create summary result
        let totalFreed = selectedItems.reduce(0) { $0 + $1.size }
        let successCount = deletionItems.filter { item in
            if case .completed = item.status { return true }
            return false
        }.count

        results.append(CleanupResult(
            category: selectedItems.first?.category ?? .systemCaches,
            freedSpace: totalFreed,
            itemsCleaned: successCount,
            errors: allErrors
        ))

        isProcessing = false

        // Remove cleaned items from the dictionary
        let cleanedIds = Set(selectedItems.filter { item in
            deletionItems.contains { delItem in
                if delItem.id == item.id {
                    if case .completed = delItem.status {
                        return true
                    }
                }
                return false
            }
        }.map { $0.id })

        for category in itemsByCategory.keys {
            itemsByCategory[category]?.removeAll { cleanedIds.contains($0.id) }
        }

        // Remove from selection
        selectedItemIds.subtract(cleanedIds)

        refreshCategories()

        return results
    }

    /// Cancel ongoing deletion
    func cancelDeletion() {
        deletionCancelled = true
    }

    /// Delete a single item and return result
    private func deleteItem(_ item: CleanupItem, operation: CleanupOperation) async -> CleanupResult {
        let fileManager = FileManager.default
        var errors: [String] = []
        var freedSpace: Int64 = 0

        // Check if file exists before attempting deletion
        guard fileManager.fileExists(atPath: item.path.path) else {
            // File doesn't exist (might have been deleted with parent folder)
            // Consider this a success - file is already gone
            return CleanupResult(
                category: item.category,
                freedSpace: 0,  // Don't count size since it was already deleted
                itemsCleaned: 1,  // Count as cleaned
                errors: []
            )
        }

        do {
            switch operation {
            case .moveToTrash:
                try fileManager.trashItem(at: item.path, resultingItemURL: nil)
                freedSpace = item.size

            case .permanentDelete:
                try fileManager.removeItem(at: item.path)
                freedSpace = item.size
            }
        } catch {
            errors.append("\(item.name): \(error.localizedDescription)")
        }

        return CleanupResult(
            category: item.category,
            freedSpace: freedSpace,
            itemsCleaned: errors.isEmpty ? 1 : 0,
            errors: errors
        )
    }

    // MARK: - Private Methods - Scanning

    /// Scan a specific category at a specific location
    private func scanCategoryAtLocation(_ category: CleanupCategory, at locationURL: URL) async throws -> [CleanupItem] {
        // Only these categories scan across user-selected locations
        let locationBasedCategories: Set<CleanupCategory> = [.largeOldFiles]

        if !locationBasedCategories.contains(category) {
            // For system categories and downloads, skip - they have specific paths
            return []
        }

        guard fileManager.fileExists(atPath: locationURL.path) else {
            return []
        }

        // Check cancellation
        try Task.checkCancellation()

        // Apply category-specific filtering
        let items = try await calculator.getItems(
            at: locationURL,
            category: category,
            includeSubdirectories: true,
            ignorePatterns: settingsManager.settings.ignorePatterns
        )

        // Apply additional filters based on category
        switch category {
        case .largeOldFiles:
            let sizeThreshold: Int64 = 100 * 1024 * 1024  // 100 MB
            return items.filter { $0.size >= sizeThreshold }

        default:
            return items
        }
    }

    private func scanCategory(_ category: CleanupCategory) async {
        await MainActor.run {
            currentScanningCategory = category
            scanState = .scanning(progress: category.scanningMessage, currentPath: nil)
            updateCategory(category, isScanning: true, scanError: nil)
        }

        do {
            let categoryItems = try await fetchItemsForCategory(category)

            await MainActor.run {
                // Add items to category dictionary
                itemsByCategory[category, default: []].append(contentsOf: categoryItems)

                // SAFETY: Do NOT auto-select items - user must manually select files to delete

                let totalSize = categoryItems.reduce(0) { $0 + $1.size }
                updateCategory(
                    category,
                    totalSize: totalSize,
                    itemCount: categoryItems.count,
                    isScanning: false,
                    scanError: nil
                )
            }
        } catch {
            await MainActor.run {
                updateCategory(
                    category,
                    isScanning: false,
                    scanError: error.localizedDescription
                )
            }
        }
    }

    /// Scan category with deduplication - filters out already categorized files
    private func scanCategoryWithDedup(_ category: CleanupCategory) async -> [CleanupItem] {
        // Mark category as scanning
        await MainActor.run {
            currentScanningCategory = category
            scanState = .scanning(progress: category.scanningMessage, currentPath: nil)
            updateCategory(category, isScanning: true, scanError: nil)
        }

        do {
            let allItems = try await fetchItemsForCategory(category)

            // Filter out already categorized files
            let newItems = allItems.filter { item in
                !categorizedPaths.contains(item.path.path)
            }

            // Mark category as complete with results
            await MainActor.run {
                // Add items to category dictionary
                itemsByCategory[category, default: []].append(contentsOf: newItems)

                let totalSize = newItems.reduce(0) { $0 + $1.size }
                updateCategory(
                    category,
                    totalSize: totalSize,
                    itemCount: newItems.count,
                    isScanning: false,
                    scanError: nil
                )
            }

            return newItems
        } catch {
            // Mark category as complete with error
            await MainActor.run {
                updateCategory(
                    category,
                    totalSize: 0,
                    itemCount: 0,
                    isScanning: false,
                    scanError: error.localizedDescription
                )
            }
            return []
        }
    }

    private func fetchItemsForCategory(_ category: CleanupCategory) async throws -> [CleanupItem] {
        switch category {
        case .systemCaches:
            // Combines app caches + package manager caches
            return try await fetchSystemCaches()

        case .systemJunk:
            // Combines logs + temp files
            return try await fetchSystemJunk()

        case .developerTools:
            // Xcode data
            return try await fetchXcodeDataItems()

        case .largeOldFiles:
            // Combines large files + duplicates
            return try await fetchLargeAndOldFiles()

        case .trash:
            return try await fetchTrashItems()

        case .downloads:
            return try await fetchOldDownloads()
        }
    }

    private func fetchItems(at url: URL, category: CleanupCategory, includeSubdirectories: Bool = true) async throws -> [CleanupItem] {
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }

        // SAFETY: Validate path before scanning
        guard await safetyDatabase.isSafeToScan(url) else {
            print("⚠️ SAFETY: Blocked scanning protected path: \(url.path)")
            return []
        }

        // Check cancellation
        try Task.checkCancellation()

        return try await calculator.getItems(
            at: url,
            category: category,
            includeSubdirectories: includeSubdirectories,
            ignorePatterns: settingsManager.settings.ignorePatterns,
            safetyDatabase: safetyDatabase
        )
    }

    /// Fetch system caches (app caches + package managers)
    private func fetchSystemCaches() async throws -> [CleanupItem] {
        var allItems: [CleanupItem] = []

        // Get approved cache directories from SafetyDatabase
        let approvedPaths = await safetyDatabase.getApprovedScanTargets(for: .systemCaches)

        for path in approvedPaths {
            // Check cancellation
            try Task.checkCancellation()

            guard fileManager.fileExists(atPath: path.path) else {
                continue
            }

            // Scan this approved directory
            let items = try await calculator.getItems(
                at: path,
                category: .systemCaches,
                includeSubdirectories: true,
                ignorePatterns: settingsManager.settings.ignorePatterns,
                safetyDatabase: safetyDatabase
            )
            allItems.append(contentsOf: items)
        }

        return allItems
    }

    /// Fetch system junk (logs + temp files)
    private func fetchSystemJunk() async throws -> [CleanupItem] {
        var allItems: [CleanupItem] = []

        // Get approved junk directories from SafetyDatabase
        let approvedPaths = await safetyDatabase.getApprovedScanTargets(for: .systemJunk)

        for path in approvedPaths {
            // Check cancellation
            try Task.checkCancellation()

            guard fileManager.fileExists(atPath: path.path) else {
                continue
            }

            // Scan this approved directory
            let items = try await calculator.getItems(
                at: path,
                category: .systemJunk,
                includeSubdirectories: true,
                ignorePatterns: settingsManager.settings.ignorePatterns,
                safetyDatabase: safetyDatabase
            )
            allItems.append(contentsOf: items)
        }

        return allItems
    }

    /// Fetch large and old files (combines duplicates + large files)
    /// ONLY includes files NOT already categorized in system categories
    private func fetchLargeAndOldFiles() async throws -> [CleanupItem] {
        let sizeThreshold: Int64 = 100 * 1024 * 1024  // 100 MB
        var results: [CleanupItem] = []

        // Get enabled scan locations from settings
        let enabledPaths = settingsManager.getAllEnabledPaths()

        // Scan each enabled location
        for locationURL in enabledPaths {
            // Check cancellation
            try Task.checkCancellation()

            guard fileManager.fileExists(atPath: locationURL.path) else {
                continue
            }

            // Scan this directory recursively
            let items = try await calculator.getItems(
                at: locationURL,
                category: .largeOldFiles,
                includeSubdirectories: true,
                ignorePatterns: settingsManager.settings.ignorePatterns,
                safetyDatabase: safetyDatabase
            )

            // Filter for large files AND not already categorized
            let largeFiles = items.filter { item in
                item.size >= sizeThreshold && !categorizedPaths.contains(item.path.path)
            }
            results.append(contentsOf: largeFiles)
        }

        // Also find duplicates (will skip already categorized files)
        let duplicates = try await findDuplicates(in: results)
        results.append(contentsOf: duplicates)

        return results
    }

    /// Find duplicate files by content hash
    /// ONLY includes files NOT already categorized in system categories
    private func findDuplicates(in items: [CleanupItem]) async throws -> [CleanupItem] {
        // Filter out already categorized items first
        let uncategorizedItems = items.filter { !categorizedPaths.contains($0.path.path) }

        // Group by size first (fast)
        let groupedBySize = Dictionary(grouping: uncategorizedItems) { $0.size }
        var duplicates: [CleanupItem] = []

        // Only check MD5 for files with matching sizes (>1 file of same size)
        // Skip very large files (>100MB) to avoid slow MD5 calculation
        let maxSizeForMD5: Int64 = 100 * 1024 * 1024  // 100 MB

        for (size, sizeGroup) in groupedBySize where sizeGroup.count > 1 && size < maxSizeForMD5 {
            // Check cancellation before MD5 hashing
            try Task.checkCancellation()

            let hashGroups = Dictionary(grouping: sizeGroup) { file in
                // Check cancellation during MD5 calculation
                if Task.isCancelled { return "" }
                return calculateMD5(for: file.path) ?? ""
            }

            // Mark duplicates (keep oldest, mark rest as duplicates)
            for (hash, hashGroup) in hashGroups where hash != "" && hashGroup.count > 1 {
                let sorted = hashGroup.sorted { ($0.modifiedDate ?? Date.distantPast) < ($1.modifiedDate ?? Date.distantPast) }
                // Keep first (oldest), mark rest as duplicates
                duplicates.append(contentsOf: Array(sorted.dropFirst()))
            }
        }

        return duplicates
    }

    private func fetchXcodeDataItems() async throws -> [CleanupItem] {
        let basePath = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode")

        let paths = [
            basePath.appendingPathComponent("DerivedData"),
            basePath.appendingPathComponent("Archives"),
            basePath.appendingPathComponent("iOS DeviceSupport")
        ]

        var allItems: [CleanupItem] = []
        for path in paths {
            if fileManager.fileExists(atPath: path.path) {
                let items = try await calculator.getItems(
                    at: path,
                    category: .developerTools,
                    includeSubdirectories: true,
                    ignorePatterns: settingsManager.settings.ignorePatterns,
                    safetyDatabase: safetyDatabase
                )
                allItems.append(contentsOf: items)
            }
        }
        return allItems
    }

    private func fetchOldDownloads() async throws -> [CleanupItem] {
        let downloadsPath = getDownloadsPath()
        guard fileManager.fileExists(atPath: downloadsPath.path) else {
            return []
        }

        let allItems = try await calculator.getItems(at: downloadsPath, category: .downloads, includeSubdirectories: true)

        // Filter items older than 30 days
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        return allItems.filter { item in
            guard let modDate = item.modifiedDate else { return false }
            return modDate < thirtyDaysAgo
        }
    }

    private func fetchTrashItems() async throws -> [CleanupItem] {
        var allItems: [CleanupItem] = []

        // 1. User's main Trash (~/.Trash)
        let userTrash = getTrashPath()
        if fileManager.fileExists(atPath: userTrash.path) {
            let items = try await calculator.getItems(at: userTrash, category: .trash, includeSubdirectories: true)
            allItems.append(contentsOf: items)
        }

        // 2. Volume-specific Trash folders (/.Trashes/<uid>)
        let mountedVolumes = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        let currentUID = getuid()

        for volume in mountedVolumes {
            let volumeTrash = volume.appendingPathComponent(".Trashes/\(currentUID)", isDirectory: true)
            if fileManager.fileExists(atPath: volumeTrash.path) {
                let items = try await calculator.getItems(at: volumeTrash, category: .trash, includeSubdirectories: true)
                allItems.append(contentsOf: items)
            }
        }

        return allItems
    }


    private func calculateMD5(for url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }

        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }

    // MARK: - Private Methods - Cleanup

    private func cleanItems(_ items: [CleanupItem], category: CleanupCategory, operation: CleanupOperation) async -> CleanupResult {
        var freedSpace: Int64 = 0
        var itemsCleaned = 0
        var errors: [String] = []

        for item in items {
            do {
                let itemSize = item.size

                switch operation {
                case .moveToTrash:
                    try fileManager.trashItem(at: item.path, resultingItemURL: nil)
                case .permanentDelete:
                    try fileManager.removeItem(at: item.path)
                }

                freedSpace += itemSize
                itemsCleaned += 1
            } catch {
                errors.append("\(item.name): \(error.localizedDescription)")
            }
        }

        return CleanupResult(
            category: category,
            freedSpace: freedSpace,
            itemsCleaned: itemsCleaned,
            errors: errors
        )
    }

    // MARK: - Private Helpers

    private func updateCategory(
        _ category: CleanupCategory,
        totalSize: Int64? = nil,
        itemCount: Int? = nil,
        isScanning: Bool? = nil,
        scanError: String?
    ) {
        guard let index = categories.firstIndex(where: { $0.category == category }) else { return }

        let current = categories[index]
        categories[index] = CategoryInfo(
            id: current.id,
            category: current.category,
            totalSize: totalSize ?? current.totalSize,
            itemCount: itemCount ?? current.itemCount,
            isScanning: isScanning ?? current.isScanning,
            scanError: scanError,
            isSelected: current.isSelected
        )
    }

    private func refreshCategories() {
        categories = CleanupCategory.allCases.map { category in
            let categoryItems = itemsByCategory[category] ?? []
            let totalSize = categoryItems.reduce(0) { $0 + $1.size }
            let selectedCount = categoryItems.filter { selectedItemIds.contains($0.id) }.count

            return CategoryInfo(
                id: category.rawValue,
                category: category,
                totalSize: totalSize,
                itemCount: categoryItems.count,
                isScanning: false,
                scanError: nil,
                isSelected: selectedCount == categoryItems.count && categoryItems.count > 0
            )
        }
    }

    // MARK: - Path Helpers

    private func getCachesPath() -> URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")
    }

    private func getLogsPath() -> URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs")
    }

    private func getTrashPath() -> URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
    }

    private func getDownloadsPath() -> URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }
}
