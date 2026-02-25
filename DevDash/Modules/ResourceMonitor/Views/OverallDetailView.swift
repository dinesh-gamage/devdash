//
//  OverallDetailView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-23.
//

import SwiftUI

struct OverallDetailView: View {
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ModuleDetailHeader(
                title: "System Overview",
                actionButtons: {
                    VariantButton(icon: "arrow.clockwise", variant: .primary, tooltip: "Refresh Now", isLoading: isLoading) {
                        // Refresh is handled by ProcessListPanel
                    }
                }
            )

            Divider()

            // Two-column layout
            HStack(alignment: .top, spacing: 20) {
                // Left column: Resource Monitor Widget (fixed width)
                ResourceMonitorWidget()
                    .frame(width: 300)

                Divider()

                // Right column: Top Processes
                ProcessListPanel(source: .overall, isLoading: $isLoading)
            }
            .padding(20)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}
