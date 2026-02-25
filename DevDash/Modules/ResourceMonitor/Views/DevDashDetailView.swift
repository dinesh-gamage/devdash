//
//  DevDashDetailView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-25.
//

import SwiftUI

struct DevDashDetailView: View {
    private var monitor: SystemMetricsMonitor { ResourceMonitorState.shared.monitor }
    @State private var aggregatedMetrics: (totalCPU: Double, totalMemoryMB: Double, processCount: Int)?
    @State private var isLoading = false
    @State private var refreshTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ModuleDetailHeader(
                title: "DevDash Resources",
                actionButtons: {
                    VariantButton(icon: "arrow.clockwise", variant: .primary, tooltip: "Refresh Now", isLoading: isLoading) {
                        fetchMetrics()
                    }
                }
            )

            Divider()

            // Two-column layout
            HStack(alignment: .top, spacing: 20) {
                // Left column: DevDash Metrics Card (fixed width)
                DevDashMetricsCard(metrics: aggregatedMetrics)
                    .frame(width: 300)

                Divider()

                // Right column: DevDash Processes
                ProcessListPanel(source: .devdash, isLoading: $isLoading)
            }
            .padding(20)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            startAutoRefresh()
        }
        .onDisappear {
            stopAutoRefresh()
        }
    }

    // MARK: - Auto-Refresh Lifecycle

    private func startAutoRefresh() {
        fetchMetrics()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task { @MainActor in
                fetchMetrics()
            }
        }
    }

    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func fetchMetrics() {
        Task.detached {
            let metrics = await MainActor.run {
                monitor.getDevDashAggregatedMetrics()
            }

            await MainActor.run {
                aggregatedMetrics = metrics
            }
        }
    }
}
