//
//  DevDashResourceWidget.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-23.
//

import SwiftUI

struct DevDashResourceWidget: View {
    @ObservedObject private var monitor = ResourceMonitorState.shared.monitor
    @State private var metrics: (totalCPU: Double, totalMemoryMB: Double, processCount: Int)?
    @State private var refreshTimer: Timer?

    var body: some View {
        HStack(spacing: 16) {
            // CPU Usage Card
            StatCard(
                icon: "cpu",
                label: "DevDash CPU",
                value: String(format: "%.0f%%", metrics?.totalCPU ?? 0.0),
                color: .blue
            )

            // Memory Usage Card
            StatCard(
                icon: "memorychip",
                label: "DevDash Memory",
                value: String(format: "%.0f MB", metrics?.totalMemoryMB ?? 0.0),
                color: .orange
            )
        }
        .onAppear {
            startAutoRefresh()
        }
        .onDisappear {
            stopAutoRefresh()
        }
    }

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
        metrics = monitor.getDevDashAggregatedMetrics()
    }
}
