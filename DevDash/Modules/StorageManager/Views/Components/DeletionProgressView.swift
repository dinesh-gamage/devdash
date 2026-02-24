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

    private var allCompleted: Bool {
        items.allSatisfy { item in
            if case .completed = item.status {
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

    private var totalSize: Int64 {
        items.filter { item in
            if case .completed = item.status {
                return true
            }
            return false
        }.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(allCompleted ? "Cleanup Complete" : "Cleaning Up...")
                        .font(AppTheme.h2)
                        .foregroundColor(.primary)

                    if allCompleted {
                        Text("Deleted \(totalDeleted) items (\(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(totalDeleted) of \(items.count) items deleted")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if allCompleted {
                    VariantButton(
                        "Close",
                        icon: "xmark.circle",
                        variant: .secondary
                    ) {
                        onClose()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.secondary.opacity(0.05))

            Divider()

            // Items list
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        DeletionItemRow(itemInfo: item)
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Deletion Item Row

struct DeletionItemRow: View {
    let itemInfo: DeletionItemInfo

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            statusIndicator
                .frame(width: 20)

            // File info
            VStack(alignment: .leading, spacing: 4) {
                Text(itemInfo.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(textColor)

                HStack(spacing: 8) {
                    Text(itemInfo.formattedSize)
                        .font(.caption)
                        .foregroundColor(textColor.opacity(0.8))

                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(textColor.opacity(0.8))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(backgroundColor)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch itemInfo.status {
        case .pending:
            Circle()
                .fill(Color.gray)
                .frame(width: 8, height: 8)

        case .deleting:
            ProgressView()
                .scaleEffect(0.7)

        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.body)

        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.body)
        }
    }

    private var statusMessage: String {
        switch itemInfo.status {
        case .pending:
            return "Waiting..."
        case .deleting:
            return "Moving to trash..."
        case .completed:
            return "Moved to trash"
        case .failed(let error):
            return "Failed: \(error)"
        }
    }

    private var textColor: Color {
        switch itemInfo.status {
        case .pending:
            return .secondary
        case .deleting:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }

    private var backgroundColor: Color {
        switch itemInfo.status {
        case .pending:
            return Color.clear
        case .deleting:
            return Color.blue.opacity(0.05)
        case .completed:
            return Color.green.opacity(0.05)
        case .failed:
            return Color.red.opacity(0.05)
        }
    }
}
