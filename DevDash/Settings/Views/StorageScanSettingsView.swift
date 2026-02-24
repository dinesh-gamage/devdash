//
//  StorageScanSettingsView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-24.
//

import SwiftUI
import AppKit

struct StorageScanSettingsView: View {
    @ObservedObject var settingsManager = StorageScanSettingsManager.shared
    @State private var showingAddCustomPath = false
    @State private var showingAddIgnorePattern = false
    @State private var newIgnorePattern = ""
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Storage Scan Settings")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Configure what to scan, where to scan, and what to ignore")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Section 1: Scan Locations
                scanLocationsSection

                Divider()

                // Section 2: Scan Categories
                scanCategoriesSection

                Divider()

                // Section 3: Ignore Patterns
                ignorePatternsSection

                Divider()

                // Section 4: Cleanup Behavior
                cleanupBehaviorSection

                // Reset button
                HStack {
                    Spacer()
                    VariantButton("Reset to Defaults", icon: "arrow.counterclockwise", variant: .secondary) {
                        settingsManager.reset()
                    }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
    }

    // MARK: - Section 1: Scan Locations

    private var scanLocationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scan Locations")
                .font(.headline)

            Text("Select which folders to scan for cleanup")
                .font(.caption)
                .foregroundColor(.secondary)

            // Default locations
            VStack(spacing: 8) {
                ForEach($settingsManager.settings.scanLocations) { $location in
                    HStack {
                        Toggle("", isOn: $location.isEnabled)
                            .toggleStyle(.checkbox)
                            .onChange(of: location.isEnabled) { _ in
                                settingsManager.save()
                            }

                        Image(systemName: "folder.fill")
                            .foregroundColor(.blue)

                        Text(location.name)
                            .font(.body)

                        Text(location.path)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }

            // Custom paths
            if !settingsManager.settings.customPaths.isEmpty {
                Divider()
                    .padding(.vertical, 8)

                Text("Custom Locations")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                VStack(spacing: 8) {
                    ForEach(settingsManager.settings.customPaths, id: \.self) { path in
                        HStack {
                            Image(systemName: "folder.badge.plus")
                                .foregroundColor(.purple)

                            Text(path)
                                .font(.caption)
                                .foregroundColor(.primary)

                            Spacer()

                            Button(action: {
                                settingsManager.removeCustomLocation(path: path)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            // Add custom path button
            VariantButton("Add Custom Location", icon: "plus", variant: .secondary) {
                selectCustomPath()
            }
        }
    }

    // MARK: - Section 2: Scan Categories

    private var scanCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What to Scan")
                .font(.headline)

            Text("Choose which types of files to look for during scan")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                ForEach(CleanupCategory.allCases, id: \.self) { category in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { settingsManager.isCategoryEnabled(category) },
                            set: { _ in settingsManager.toggleCategory(category) }
                        ))
                        .toggleStyle(.checkbox)

                        Image(systemName: category.icon)
                            .foregroundColor(.purple)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.name)
                                .font(.body)

                            Text(category.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Section 3: Ignore Patterns

    private var ignorePatternsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ignore Patterns")
                .font(.headline)

            Text("Files and folders matching these patterns will be skipped during scan")
                .font(.caption)
                .foregroundColor(.secondary)

            // Patterns list
            VStack(spacing: 8) {
                ForEach(settingsManager.settings.ignorePatterns, id: \.self) { pattern in
                    HStack {
                        Image(systemName: "nosign")
                            .foregroundColor(.orange)

                        Text(pattern)
                            .font(.body)
                            .font(.system(.body, design: .monospaced))

                        Spacer()

                        Button(action: {
                            settingsManager.removeIgnorePattern(pattern)
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }

            // Add pattern
            HStack {
                TextField("Pattern (e.g., node_modules, *.log)", text: $newIgnorePattern)
                    .textFieldStyle(.roundedBorder)

                VariantButton("Add", icon: "plus", variant: .primary) {
                    if !newIgnorePattern.isEmpty {
                        settingsManager.addIgnorePattern(newIgnorePattern)
                        newIgnorePattern = ""
                    }
                }
            }

            // Examples
            Text("Examples: node_modules, .git, *.log, build, dist")
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()
        }
    }

    // MARK: - Section 4: Cleanup Behavior

    private var cleanupBehaviorSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cleanup Behavior")
                .font(.headline)

            Text("Choose what happens when you delete files")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(DeletionMode.allCases, id: \.self) { mode in
                    HStack(alignment: .top, spacing: 12) {
                        Button(action: {
                            settingsManager.setDeletionMode(mode)
                        }) {
                            Image(systemName: settingsManager.settings.deletionMode == mode ? "largecircle.fill.circle" : "circle")
                                .foregroundColor(settingsManager.settings.deletionMode == mode ? .purple : .secondary)
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(mode.displayName)
                                .font(.body)
                                .fontWeight(settingsManager.settings.deletionMode == mode ? .semibold : .regular)

                            Text(mode.description)
                                .font(.caption)
                                .foregroundColor(mode == .permanentDelete ? .orange : .secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Custom Path Selection

    private func selectCustomPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to scan (system folders are not allowed)"

        // Set initial directory to user's home
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            do {
                try settingsManager.addCustomLocation(path: url.path)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
