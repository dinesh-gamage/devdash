//
//  StorageManagerDetailView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-23.
//

import SwiftUI
import Combine

struct StorageManagerDetailView: View {
    @ObservedObject var state = StorageManagerState.shared

    var body: some View {
        Group {
            switch state.viewState {
            case .initial:
                InitialStateView()
            case .scanning:
                ScanningStateView()
            case .results:
                ResultsStateView()
            case .reviewingCategory(let category):
                CategoryDetailView(
                    category: category,
                    manager: state.manager,
                    onBack: {
                        // SAFETY: Clear selections when navigating back
                        state.manager.clearCategorySelection(category)
                        state.viewState = .results
                    },
                    onCleanUp: {
                        state.performCleanup()
                    }
                )
            }
        }
        .toastQueue(state.toastQueue)
    }
}

// MARK: - Initial State View

struct InitialStateView: View {
    @ObservedObject var state = StorageManagerState.shared
    @ObservedObject var fdaManager = FullDiskAccessManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header with action buttons
            HStack {
                Text("Storage Manager")
                    .font(AppTheme.h2)

                Spacer()

                VariantButton(
                    "Start Scan",
                    icon: "magnifyingglass",
                    variant: .primary
                ) {
                    state.startScan()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.secondary.opacity(0.05))

            Divider()

            // Content
            VStack(spacing: 0) {
                // FDA Warning Banner (if no access)
                if fdaManager.hasChecked && !fdaManager.hasFullDiskAccess {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Full Disk Access Required")
                                .font(.headline)
                                .foregroundColor(.primary)

                            Text("To scan all files, grant Full Disk Access in System Settings")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        VariantButton(
                            "Open Settings",
                            icon: "gear",
                            variant: .warning
                        ) {
                            fdaManager.openSystemSettings()
                        }
                    }
                    .padding(16)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                    .padding(20)
                }

                // Simple message
                VStack(spacing: 24) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 72))
                        .foregroundColor(.purple.opacity(0.5))

                    Text("Clean your system to achieve maximum performance and reclaim free space")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 500)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Scanning State View

struct ScanningStateView: View {
    @ObservedObject var state = StorageManagerState.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header with Stop button
            HStack {
                Text("Storage Manager")
                    .font(AppTheme.h2)

                Spacer()

                VariantButton(
                    "Stop Scan",
                    icon: "stop.circle",
                    variant: .danger
                ) {
                    state.stopScan()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.secondary.opacity(0.05))

            Divider()

            // Scanning progress
            if case .scanning(let message, let path) = state.manager.scanState {
                ScanProgressView(
                    message: message,
                    currentPath: path,
                    locationInfos: state.manager.locationScanInfos
                )
            }
        }
    }
}

// MARK: - Results State View

struct ResultsStateView: View {
    @ObservedObject var state = StorageManagerState.shared

    var categoriesToClean: [CategoryInfo] {
        state.manager.categories.filter { $0.totalSize > 0 }
    }

    var cleanCategories: [CategoryInfo] {
        state.manager.categories.filter { $0.totalSize == 0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ModuleDetailHeader(
                title: "Storage Manager",
                metadata: [
                    MetadataRow(
                        icon: "externaldrive",
                        label: "Junk Files Found",
                        value: ByteCountFormatter.string(fromByteCount: state.manager.totalScannedSize, countStyle: .file)
                    )
                ],
                actionButtons: {
                    HStack(spacing: 12) {
                        VariantButton(
                            "Re-scan",
                            icon: "arrow.clockwise",
                            variant: .secondary
                        ) {
                            state.startScan()
                        }

                        VariantButton(
                            "Done",
                            variant: .primary
                        ) {
                            state.viewState = .initial
                        }
                    }
                }
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.secondary.opacity(0.05))

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    // Section 1: Categories that need cleaning
                    if !categoriesToClean.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Needs Cleaning")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .padding(.horizontal, 20)

                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16)
                            ], spacing: 16) {
                                ForEach(categoriesToClean) { categoryInfo in
                                    CategoryCard(
                                        categoryInfo: categoryInfo,
                                        onReviewAndCleanup: {
                                            state.reviewCategory(categoryInfo.category)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // Section 2: Already clean categories
                    if !cleanCategories.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Already Clean")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .padding(.horizontal, 20)

                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16)
                            ], spacing: 16) {
                                ForEach(cleanCategories) { categoryInfo in
                                    CategoryCard(
                                        categoryInfo: categoryInfo,
                                        onReviewAndCleanup: {}
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
                .padding(.vertical, 20)
            }
        }
        .alert("Clean Up All Items in Category?", isPresented: $state.showingCategoryCleanConfirmation) {
            Button("Move to Trash", role: .destructive) {
                state.performCategoryCleanup()
            }
            Button("Cancel", role: .cancel) {
                state.categoryToClean = nil
            }
        } message: {
            if let category = state.categoryToClean,
               let categoryInfo = state.manager.categories.first(where: { $0.category == category }) {
                let sizeStr = ByteCountFormatter.string(fromByteCount: categoryInfo.totalSize, countStyle: .file)
                let itemCount = categoryInfo.itemCount

                // SAFETY: Always moving to trash for now, show appropriate message
                if state.settingsManager.settings.deletionMode == .moveToTrash {
                    Text("This will move \(sizeStr) (\(itemCount) items) from \(category.name) to Trash. You can recover these files from Trash if needed.")
                } else {
                    Text("This will move \(sizeStr) (\(itemCount) items) from \(category.name) to Trash for safety. (Permanent deletion is disabled until app validation is complete.)")
                }
            }
        }
        .overlay {
            if state.isDeleting {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)

                        Text("Deleting files...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(32)
                    .background(Color.secondary.opacity(0.9))
                    .cornerRadius(12)
                }
            }
        }
    }
}
