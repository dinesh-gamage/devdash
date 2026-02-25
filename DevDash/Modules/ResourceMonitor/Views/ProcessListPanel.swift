//
//  ProcessListPanel.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-25.
//

import SwiftUI

enum ProcessSource {
    case overall
    case devdash

    var emptyStateIcon: String {
        switch self {
        case .overall:
            return "list.bullet"
        case .devdash:
            return "app.badge"
        }
    }

    var emptyStateMessage: String {
        switch self {
        case .overall:
            return "No processes to display"
        case .devdash:
            return "No DevDash processes found"
        }
    }
}

struct ProcessListPanel: View {
    let source: ProcessSource
    @Binding var isLoading: Bool

    private var monitor: SystemMetricsMonitor { ResourceMonitorState.shared.monitor }
    @State private var selectedSort: ProcessSortOption = .memory
    @State private var processes: [SystemProcess] = []
    @State private var refreshTimer: Timer?

    var body: some View {
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
                    Image(systemName: source.emptyStateIcon)
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))

                    Text(source.emptyStateMessage)
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
        .onAppear {
            startAutoRefresh()
        }
        .onDisappear {
            stopAutoRefresh()
        }
        .onChange(of: selectedSort) { _, _ in
            fetchProcesses()
        }
    }

    // MARK: - Auto-Refresh Lifecycle

    private func startAutoRefresh() {
        fetchProcesses()

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
        Task.detached {
            let results = await MainActor.run {
                switch source {
                case .overall:
                    return monitor.getTopProcesses(sortBy: selectedSort, limit: 10)
                case .devdash:
                    return monitor.getDevDashProcesses(sortBy: selectedSort)
                }
            }

            await MainActor.run {
                processes = results
                isLoading = false
            }
        }
    }
}
