//
//  OverallDetailView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-23.
//

import SwiftUI

struct OverallDetailView: View {
    private var monitor: SystemMetricsMonitor { ResourceMonitorState.shared.monitor }
    @State private var selectedSort: ProcessSortOption = .memory
    @State private var processes: [SystemProcess] = []
    @State private var isLoading = false
    @State private var refreshTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ModuleDetailHeader(
                title: "System Overview",
                actionButtons: {
                    VariantButton(icon: "arrow.clockwise", variant: .primary, tooltip: "Refresh Now", isLoading: isLoading) {
                        fetchProcesses()
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
                VStack(alignment: .leading, spacing: 12) {
                    // Filter tabs
                    HStack(spacing: 8) {
                        ForEach(ProcessSortOption.allCases, id: \.self) { option in
                            VariantButton(
                                option.rawValue,
                                icon: option.icon,
                                variant: selectedSort == option ? .primary : .secondary
                            ) {
                                selectedSort = option
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    // Process list
                    if processes.isEmpty && !isLoading {
                        VStack(spacing: 12) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary.opacity(0.5))

                            Text("No processes to display")
                                .font(.callout)
                                .foregroundColor(.secondary)

                            VariantButton("Load Processes", icon: "arrow.clockwise", variant: .primary) {
                                fetchProcesses()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(processes) { process in
                                    ProcessRow(process: process, sortBy: selectedSort)

                                    if process.id != processes.last?.id {
                                        Divider()
                                            .padding(.leading, 56)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .onChange(of: selectedSort) { _, _ in
            fetchProcesses()  // Immediately fetch when sort option changes
        }
    }

    // MARK: - Auto-Refresh Lifecycle

    private func startAutoRefresh() {
        // Immediate fetch
        fetchProcesses()

        // Schedule recurring fetch (3 seconds to match metrics polling)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task { @MainActor in
                fetchProcesses()
            }
        }
    }

    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func fetchProcesses() {
        isLoading = true
        // Run in background to avoid blocking UI
        Task.detached {
            let results = await MainActor.run {
                monitor.getTopProcesses(sortBy: selectedSort, limit: 10)
            }

            await MainActor.run {
                processes = results
                isLoading = false
            }
        }
    }
}

// MARK: - Process Row

struct ProcessRow: View {
    let process: SystemProcess
    let sortBy: ProcessSortOption

    var body: some View {
        HStack(spacing: 12) {
            // PID
            Text("\(process.id)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)

            // Process name
            Text(process.name)
                .font(.callout)
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Metric based on sort option
            HStack(spacing: 4) {
                Image(systemName: sortBy.icon)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text(metricValue)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(width: 80, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var metricValue: String {
        switch sortBy {
        case .cpu:
            return String(format: "%.1f%%", process.cpuPercent)
        case .memory:
            return String(format: "%.1f MB", process.memoryMB)
        case .network:
            return String(format: "%.1f MB/s", process.networkMBps)
        case .disk:
            return String(format: "%.1f MB/s", process.diskMBps)
        }
    }
}

// MARK: - DevDash Detail View

struct DevDashDetailView: View {
    private var monitor: SystemMetricsMonitor { ResourceMonitorState.shared.monitor }
    @State private var selectedSort: ProcessSortOption = .memory
    @State private var processes: [SystemProcess] = []
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
                        fetchData()
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
                VStack(alignment: .leading, spacing: 12) {
                    // Filter tabs
                    HStack(spacing: 8) {
                        ForEach(ProcessSortOption.allCases, id: \.self) { option in
                            VariantButton(
                                option.rawValue,
                                icon: option.icon,
                                variant: selectedSort == option ? .primary : .secondary
                            ) {
                                selectedSort = option
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    // Process list
                    if processes.isEmpty && !isLoading {
                        VStack(spacing: 12) {
                            Image(systemName: "app.badge")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary.opacity(0.5))

                            Text("No DevDash processes found")
                                .font(.callout)
                                .foregroundColor(.secondary)

                            VariantButton("Load Processes", icon: "arrow.clockwise", variant: .primary) {
                                fetchData()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(processes) { process in
                                    ProcessRow(process: process, sortBy: selectedSort)

                                    if process.id != processes.last?.id {
                                        Divider()
                                            .padding(.leading, 56)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .onChange(of: selectedSort) { _, _ in
            fetchData()
        }
    }

    // MARK: - Auto-Refresh Lifecycle

    private func startAutoRefresh() {
        fetchData()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task { @MainActor in
                fetchData()
            }
        }
    }

    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func fetchData() {
        isLoading = true
        Task.detached {
            let processList = await MainActor.run {
                monitor.getDevDashProcesses(sortBy: selectedSort)
            }

            let metrics = await MainActor.run {
                monitor.getDevDashAggregatedMetrics()
            }

            await MainActor.run {
                processes = processList
                aggregatedMetrics = metrics
                isLoading = false
            }
        }
    }
}

// MARK: - DevDash Metrics Card

struct DevDashMetricsCard: View {
    let metrics: (totalCPU: Double, totalMemoryMB: Double, processCount: Int)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Content
            if let metrics = metrics {
                VStack(spacing: 12) {
                    // Process Count
                    HStack {
                        Image(systemName: "number")
                            .foregroundColor(.orange)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Processes")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text("\(metrics.processCount)")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                        }

                        Spacer()
                    }

                    Divider()

                    // Total Memory
                    HStack {
                        Image(systemName: "memorychip")
                            .foregroundColor(.orange)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Total Memory")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(String(format: "%.1f MB", metrics.totalMemoryMB))
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                        }

                        Spacer()
                    }

                    Divider()

                    // Total CPU
                    HStack {
                        Image(systemName: "cpu")
                            .foregroundColor(.orange)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Total CPU")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(String(format: "%.1f%%", metrics.totalCPU))
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                        }

                        Spacer()
                    }
                }
                .padding(16)
            } else {
                // Loading state
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)

                    Text("Loading metrics...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
            }

            Spacer()
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
