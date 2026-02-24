//
//  DeletionProgressView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-24.
//

import SwiftUI

// MARK: - Deletion Item Status

enum DeletionItemStatus: Equatable {
    case pending
    case deleting
    case completed
    case failed(String)
}

struct DeletionItemInfo: Identifiable, Equatable {
    let id: UUID
    let name: String
    let path: String
    let size: Int64
    var status: DeletionItemStatus

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - Deletion Progress View

struct DeletionProgressView: View {
    let items: [DeletionItemInfo]
    let onClose: () -> Void
    let onCancel: (() -> Void)?

    private var allCompleted: Bool {
        items.allSatisfy { item in
            if case .completed = item.status {
                return true
            }
            if case .failed = item.status {
                return true
            }
            return false
        }
    }

    private var totalDeleted: Int {
        items.filter { item in
            if case .completed = item.status {
                return true
            }
            return false
        }.count
    }

    private var totalFailed: Int {
        items.filter { item in
            if case .failed = item.status {
                return true
            }
            return false
        }.count
    }

    private var totalSize: Int64 {
        items.filter { item in
            if case .completed = item.status {
                return true
            }
            return false
        }.reduce(0) { $0 + $1.size }
    }

    private var progress: Double {
        guard items.count > 0 else { return 0 }
        return Double(totalDeleted + totalFailed) / Double(items.count)
    }

    var body: some View {
        VStack(spacing: 12) {
            // Title
            Text(allCompleted ? "Cleanup Complete" : "Cleaning Up...")
                .font(.headline)
                .foregroundColor(.primary)

            // Progress bar
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(.linear)

            // Status text
            if allCompleted {
                VStack(spacing: 2) {
                    Text("Deleted \(totalDeleted) of \(items.count) items")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if totalFailed > 0 {
                        Text("\(totalFailed) items failed")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }

                    if totalSize > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file) + " freed")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
            } else {
                Text("\(totalDeleted) of \(items.count) items deleted")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Buttons
            HStack(spacing: 8) {
                if allCompleted {
                    VariantButton(
                        "Done",
                        icon: "checkmark.circle",
                        variant: .primary
                    ) {
                        onClose()
                    }
                } else if let cancel = onCancel {
                    VariantButton(
                        "Cancel",
                        icon: "xmark.circle",
                        variant: .danger
                    ) {
                        cancel()
                        onClose()  // Close popup on cancel
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}

