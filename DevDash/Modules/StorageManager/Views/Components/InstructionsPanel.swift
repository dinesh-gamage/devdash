//
//  InstructionsPanel.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-23.
//

import SwiftUI

struct InstructionsPanel: View {
    var body: some View {
        HStack(spacing: 24) {
            // Left: Icon
            Image(systemName: "externaldrive.badge.minus")
                .font(.system(size: 56))
                .foregroundColor(.purple)
                .frame(width: 80)

            Divider()

            // Middle: Instructions
            VStack(alignment: .leading, spacing: 12) {
                Text("Safe & Non-Destructive Cleanup")
                    .font(.headline)
                    .foregroundColor(.primary)

                VStack(alignment: .leading, spacing: 6) {
                    InstructionRow(
                        icon: "checkmark.circle.fill",
                        text: "Only cleans regeneratable caches and logs"
                    )
                    InstructionRow(
                        icon: "checkmark.circle.fill",
                        text: "Files moved to Trash (recoverable)"
                    )
                    InstructionRow(
                        icon: "checkmark.circle.fill",
                        text: "Never touches system or user documents"
                    )
                    InstructionRow(
                        icon: "checkmark.circle.fill",
                        text: "Age-based filtering for Downloads folder"
                    )
                }
            }

            Spacer()

            // Right: Categories list
            VStack(alignment: .leading, spacing: 8) {
                Text("What We Scan:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 4) {
                    CategoryBadge(icon: "folder.badge.gearshape", label: "User Caches")
                    CategoryBadge(icon: "doc.text", label: "User Logs")
                    CategoryBadge(icon: "hammer", label: "Xcode Data")
                    CategoryBadge(icon: "shippingbox", label: "Package Managers")
                    CategoryBadge(icon: "arrow.down.circle", label: "Old Downloads")
                }
            }
        }
        .padding(20)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(12)
    }
}

struct InstructionRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.green)
                .imageScale(.small)
                .frame(width: 12)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct CategoryBadge: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(.purple.opacity(0.7))
                .frame(width: 14)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
