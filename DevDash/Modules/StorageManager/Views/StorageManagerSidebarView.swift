//
//  StorageManagerSidebarView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-23.
//

import SwiftUI

struct StorageManagerSidebarView: View {
    @ObservedObject var state = StorageManagerState.shared

    var body: some View {
        VStack(spacing: 0) {
            // Single list item: Scan & Cleanup
            HStack(spacing: 12) {
                // Label
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scan & Cleanup")
                        .font(.body)
                        .foregroundColor(.primary)

                    if state.manager.totalScannedSize > 0 {
                        Text(ByteCountFormatter.string(
                            fromByteCount: state.manager.totalScannedSize,
                            countStyle: .file
                        ))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color.purple.opacity(0.08))

            Spacer()
        }
    }
}
