//
//  CategoryDetailView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-23.
//

import SwiftUI

// MARK: - File Tree Row

struct FileTreeRow: View {
    let node: FileTreeNode
    @ObservedObject var manager: CleanupManager

    // Calculate selection state from manager
    private var isSelected: Bool {
        if let item = node.item {
            return manager.isItemSelected(id: item.id)
        } else {
            // Directory: selected if all descendant files are selected
            let descendantItems = node.allDescendantItems
            guard !descendantItems.isEmpty else { return false }
            return descendantItems.allSatisfy { manager.isItemSelected(id: $0.id) }
        }
    }

    private var isPartiallySelected: Bool {
        guard node.isDirectory else { return false }
        let descendantItems = node.allDescendantItems
        guard !descendantItems.isEmpty else { return false }
        let selectedCount = descendantItems.filter { manager.isItemSelected(id: $0.id) }.count
        return selectedCount > 0 && selectedCount < descendantItems.count
    }

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox for both files and directories
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { _ in
                    toggleNode()
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .buttonStyle(.plain)
            .opacity(isPartiallySelected ? 0.5 : 1.0)
            .onTapGesture {} // Prevent tap from propagating to list row

            // Icon
            Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundColor(node.isDirectory ? .blue : .secondary.opacity(0.7))
                .imageScale(.small)

            // Name
            Text(node.name)
                .font(.body)
                .foregroundColor(.primary)

            Spacer()

            // Size
            Text(node.formattedSize)
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)

            // Modified date
            if let modDate = node.modifiedDate {
                RelativeTimeText(date: modDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 100, alignment: .trailing)
            } else if node.isDirectory {
                Text("")
                    .font(.caption)
                    .frame(width: 100, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }

    // Toggle selection for both files and directories
    private func toggleNode() {
        if let item = node.item {
            // Toggle individual file
            manager.toggleItemSelection(id: item.id)
        } else {
            // Toggle all descendant files in directory
            let descendantItems = node.allDescendantItems
            let allSelected = descendantItems.allSatisfy { manager.isItemSelected(id: $0.id) }

            for item in descendantItems {
                if allSelected {
                    // Deselect all
                    if manager.isItemSelected(id: item.id) {
                        manager.toggleItemSelection(id: item.id)
                    }
                } else {
                    // Select all
                    if !manager.isItemSelected(id: item.id) {
                        manager.toggleItemSelection(id: item.id)
                    }
                }
            }
        }
    }
}

struct CategoryDetailView: View {
    let category: CleanupCategory
    @ObservedObject var manager: CleanupManager
    let onBack: () -> Void
    let onCleanUp: () -> Void

    @State private var showingDeleteConfirmation = false
    @State private var showingFinalDeleteConfirmation = false
    @ObservedObject private var settingsManager = StorageScanSettingsManager.shared

    // Cache tree to prevent rebuilding on every selection change
    @State private var treeNodes: [FileTreeNode] = []

    var categoryItems: [CleanupItem] {
        manager.items(for: category)
    }

    var selectedItemsInCategory: [CleanupItem] {
        manager.getSelectedItems(in: category)
    }

    var totalSelectedSize: Int64 {
        selectedItemsInCategory.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with back button and select all
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                    Text("Back")
                        .font(.body)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onBack)

                Spacer()

                Text(category.name)
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                // Select All toggle
                Button(action: {
                    let allSelected = selectedItemsInCategory.count == categoryItems.count
                    manager.toggleCategory(category, selected: !allSelected)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: selectedItemsInCategory.count == categoryItems.count && categoryItems.count > 0 ? "checkmark.square.fill" : "square")
                            .foregroundColor(selectedItemsInCategory.count == categoryItems.count && categoryItems.count > 0 ? .purple : .secondary)
                        Text("Select All")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.secondary.opacity(0.05))

            Divider()

            // Content: Hierarchical tree view
            List(treeNodes, id: \.id, children: \.children) { node in
                FileTreeRow(node: node, manager: manager)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .onAppear {
                // Build tree on first appearance
                if treeNodes.isEmpty {
                    treeNodes = FileTreeNode.buildTree(from: categoryItems, selectedIds: manager.selectedItemIds)
                }
            }
            .onChange(of: categoryItems.count) {
                // Rebuild tree only when items change, not on selection changes
                treeNodes = FileTreeNode.buildTree(from: categoryItems, selectedIds: manager.selectedItemIds)
            }

            Divider()

            // Bottom bar with selection info and clean button
            HStack(spacing: 20) {
                // Selection info
                HStack(spacing: 12) {
                    Text("\(selectedItemsInCategory.count) items selected")
                        .font(.body)
                        .foregroundColor(.primary)

                    Text(ByteCountFormatter.string(fromByteCount: totalSelectedSize, countStyle: .file))
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.purple)
                }

                Spacer()

                // Clean Up button
                VariantButton(
                    "Clean Up",
                    icon: "trash",
                    variant: .danger,
                    isLoading: manager.isProcessing
                ) {
                    showingDeleteConfirmation = true
                }
                .disabled(selectedItemsInCategory.isEmpty || manager.isProcessing)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.secondary.opacity(0.05))
        }
        .alert("Delete Selected Files?", isPresented: $showingDeleteConfirmation) {
            Button(actionButtonText, role: .destructive) {
                showingFinalDeleteConfirmation = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to \(actionVerb) \(selectedItemsInCategory.count) selected items?")
        }
        .alert("Final Confirmation", isPresented: $showingFinalDeleteConfirmation) {
            Button(actionButtonText, role: .destructive) {
                onCleanUp()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
        .overlay {
            // Deletion progress overlay
            if manager.showingDeletionProgress {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()

                    DeletionProgressView(
                        items: manager.deletionItems,
                        onClose: {
                            manager.showingDeletionProgress = false
                        },
                        onCancel: manager.isProcessing ? {
                            manager.cancelDeletion()
                        } : nil
                    )
                    .frame(maxWidth: 600, maxHeight: 500)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(12)
                    .shadow(radius: 20)
                }
            }
        }
    }

    // MARK: - Computed Properties for Messages

    private var actionVerb: String {
        settingsManager.settings.deletionMode == .moveToTrash ? "move to trash" : "permanently delete"
    }

    private var actionButtonText: String {
        // SAFETY: Always showing "Move to Trash" for now
        "Move to Trash"
    }

    private var confirmationMessage: String {
        let sizeStr = ByteCountFormatter.string(fromByteCount: totalSelectedSize, countStyle: .file)
        let itemCount = selectedItemsInCategory.count

        // SAFETY: Always moving to trash for now, show appropriate message
        if settingsManager.settings.deletionMode == .moveToTrash {
            return "This will move \(sizeStr) (\(itemCount) items) to Trash. You can recover these files from Trash if needed."
        } else {
            // Even though we're moving to trash, show what the setting says but clarify safety
            return "This will move \(sizeStr) (\(itemCount) items) to Trash for safety. (Permanent deletion is disabled until app validation is complete.)"
        }
    }
}
