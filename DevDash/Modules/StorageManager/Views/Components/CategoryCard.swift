//
//  CategoryCard.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-23.
//

import SwiftUI

struct CategoryCard: View {
    let categoryInfo: CategoryInfo
    let onReviewAndCleanup: () -> Void

    private var needsCleaning: Bool {
        categoryInfo.totalSize > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: needsCleaning ? 12 : 8) {
            // Header: Icon + Title + Size/Status
            HStack(spacing: 12) {
                Image(systemName: categoryInfo.category.icon)
                    .font(.title2)
                    .foregroundColor(needsCleaning ? .primary : .green)

                HStack(spacing: 4) {
                    Text(categoryInfo.category.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    if needsCleaning {
                        Text(categoryInfo.formattedSize)
                            .font(.body)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                            Text("Clean")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
            }

            // Description
            Text(categoryInfo.category.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Action button (only for categories that need cleaning)
            if needsCleaning {
                Spacer()

                VariantButton(
                    "Review & Clean Up",
                    icon: "trash",
                    variant: .danger
                ) {
                    onReviewAndCleanup()
                }
            }
        }
        .padding(16)
        .frame(minWidth: 200, minHeight: 80)
        .background(Color.secondary.opacity(needsCleaning ? 0.08 : 0.02))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(needsCleaning ? Color.red.opacity(0.5) : Color.green.opacity(0.3), lineWidth: needsCleaning ? 2 : 1)
        )
    }
}
