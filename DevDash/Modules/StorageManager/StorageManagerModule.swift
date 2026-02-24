//
//  StorageManagerModule.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-23.
//

import SwiftUI
import Combine

struct StorageManagerModule: DevDashModule {
    let id = "storage-manager"
    let name = "Storage Manager"
    let icon = "internaldrive"
    let description = "Clean junk files and reclaim disk space"
    let accentColor = Color.purple

    func makeSidebarView() -> AnyView {
        AnyView(StorageManagerSidebarView())
    }

    func makeDetailView() -> AnyView {
        AnyView(StorageManagerDetailView())
    }

    // MARK: - Backup Support

    var backupFileName: String {
        "storage-manager.json"
    }

    func exportForBackup() async throws -> Data {
        // Storage manager doesn't have persistent data to backup
        return Data()
    }
}

// MARK: - Shared State

@MainActor
class StorageManagerState: ObservableObject {
    static let shared = StorageManagerState()

    @Published var manager: CleanupManager
    @Published var viewState: CleanupViewState = .initial
    @Published var showingCleanConfirmation = false
    @Published var showingCategoryCleanConfirmation = false
    @Published var categoryToClean: CleanupCategory?
    @Published var isDeleting = false

    let toastQueue = ToastQueue()
    let settingsManager = StorageScanSettingsManager.shared

    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.manager = CleanupManager()

        // Forward manager changes to state so views update
        manager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)

        // Update view state based on scan state
        manager.$scanState.sink { [weak self] scanState in
            guard let self = self else { return }

            switch scanState {
            case .idle:
                if self.viewState == .scanning {
                    // If we were scanning and now idle, check if we have results
                    if !self.manager.itemsByCategory.isEmpty {
                        self.viewState = .results
                    } else {
                        self.viewState = .initial
                    }
                }

            case .scanning:
                if self.viewState != .scanning {
                    self.viewState = .scanning
                }

            case .completed:
                self.viewState = .results

            case .error:
                self.viewState = .initial
            }
        }
        .store(in: &cancellables)
    }

    // MARK: - Actions

    func startScan() {
        manager.startScan()
    }

    func stopScan() {
        manager.stopScan()
        viewState = .initial
    }

    func startOver() {
        manager.stopScan()
        manager.itemsByCategory.removeAll()
        manager.selectedItemIds.removeAll()
        manager.categories = CleanupCategory.allCases.map { .empty(category: $0) }
        viewState = .initial
    }

    func reviewCategory(_ category: CleanupCategory) {
        // SAFETY: Clear any existing selections when entering review
        manager.clearCategorySelection(category)
        viewState = .reviewingCategory(category)
    }

    func confirmCleanup() {
        showingCleanConfirmation = true
    }

    func confirmCategoryCleanup(_ category: CleanupCategory) {
        categoryToClean = category
        showingCategoryCleanConfirmation = true
    }

    func performCategoryCleanup() {
        guard let category = categoryToClean else { return }

        Task {
            await MainActor.run {
                isDeleting = true
            }

            // Select all items in this category for deletion
            manager.toggleCategory(category, selected: true)

            // SAFETY: cleanSelected() always uses trash until app validation
            let results = await manager.cleanSelected()

            await MainActor.run {
                isDeleting = false
                categoryToClean = nil

                // Calculate total freed space
                let totalFreed = results.reduce(0) { $0 + $1.freedSpace }
                let totalCleaned = results.reduce(0) { $0 + $1.itemsCleaned }

                // Show toast notification
                let message = "Cleaned \(totalCleaned) items, freed \(ByteCountFormatter.string(fromByteCount: totalFreed, countStyle: .file))"
                toastQueue.enqueue(message: message)

                // Stay in results view after cleanup
                viewState = .results
            }
        }
    }

    func performCleanup() {
        Task {
            await MainActor.run {
                isDeleting = true
            }

            // SAFETY: cleanSelected() always uses trash until app validation
            let results = await manager.cleanSelected()

            await MainActor.run {
                isDeleting = false

                // Calculate total freed space
                let totalFreed = results.reduce(0) { $0 + $1.freedSpace }
                let totalCleaned = results.reduce(0) { $0 + $1.itemsCleaned }

                // Show toast notification
                let message = "Cleaned \(totalCleaned) items, freed \(ByteCountFormatter.string(fromByteCount: totalFreed, countStyle: .file))"
                toastQueue.enqueue(message: message)

                // Stay in current view after cleanup
            }
        }
    }
}
