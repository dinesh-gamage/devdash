//
//  DevDashCountWidgets.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-25.
//

import SwiftUI

// MARK: - DevDash CPU Count Widget

struct DevDashCPUCountWidget: View {
    let onTap: (() -> Void)?
    @ObservedObject private var monitor = ResourceMonitorState.shared.monitor
    @State private var metrics: (totalCPU: Double, totalMemoryMB: Double, processCount: Int)?
    @State private var refreshTimer: Timer?

    init(onTap: (() -> Void)? = nil) {
        self.onTap = onTap
    }

    var body: some View {
        StatCard(
            icon: "cpu",
            label: "DevDash CPU",
            value: String(format: "%.0f%%", metrics?.totalCPU ?? 0.0),
            color: .blue,
            onTap: onTap
        )
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

// MARK: - DevDash Memory Count Widget

struct DevDashMemoryCountWidget: View {
    let onTap: (() -> Void)?
    @ObservedObject private var monitor = ResourceMonitorState.shared.monitor
    @State private var metrics: (totalCPU: Double, totalMemoryMB: Double, processCount: Int)?
    @State private var refreshTimer: Timer?

    init(onTap: (() -> Void)? = nil) {
        self.onTap = onTap
    }

    var body: some View {
        StatCard(
            icon: "memorychip",
            label: "DevDash Memory",
            value: String(format: "%.0f MB", metrics?.totalMemoryMB ?? 0.0),
            color: .orange,
            onTap: onTap
        )
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
