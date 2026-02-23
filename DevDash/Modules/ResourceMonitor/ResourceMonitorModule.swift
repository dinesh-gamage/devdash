//
//  ResourceMonitorModule.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-23.
//

import SwiftUI
import Combine

// MARK: - Resource Monitor State

enum ResourceMonitorView: String, CaseIterable, Identifiable {
    case devdash = "DevDash"
    case overall = "Overall"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overall:
            return "chart.bar.fill"
        case .devdash:
            return "app.badge.fill"
        }
    }
}

@MainActor
class ResourceMonitorState: ObservableObject {
    static let shared = ResourceMonitorState()

    @Published var monitor: SystemMetricsMonitor
    @Published var selectedView: ResourceMonitorView? = .devdash

    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.monitor = SystemMetricsMonitor()

        // Forward monitor changes to state (event-driven architecture)
        monitor.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)
    }
}

// MARK: - Resource Monitor Module

struct ResourceMonitorModule: DevDashModule {
    let id = "resource-monitor"
    let name = "Resource Monitor"
    let icon = "gauge.with.dots.needle.67percent"
    let description = "Monitor system CPU and memory usage"
    let accentColor = Color.orange

    func makeSidebarView() -> AnyView {
        AnyView(ResourceMonitorSidebarView())
    }

    func makeDetailView() -> AnyView {
        AnyView(ResourceMonitorDetailView())
    }

    // MARK: - Backup Support

    var backupFileName: String {
        "resource-monitor.json"
    }

    func exportForBackup() async throws -> Data {
        // Resource monitor has no persistent data to back up
        return Data()
    }
}

// MARK: - Sidebar View

struct ResourceMonitorSidebarView: View {
    @ObservedObject var state = ResourceMonitorState.shared

    var body: some View {
        ModuleSidebarList(
            toolbarButtons: [],  // No toolbar buttons for this module
            items: ResourceMonitorView.allCases,
            emptyState: EmptyStateConfig(
                icon: "gauge.with.dots.needle.67percent",
                title: "No Views",
                subtitle: "No resource monitoring views available"
            ),
            selectedItem: $state.selectedView,
            itemContent: { view, isSelected in
                ModuleSidebarListItem(
                    icon: .image(systemName: view.icon, color: .orange),
                    title: view.rawValue,
                    isSelected: isSelected,
                    onTap: {
                        state.selectedView = view
                    }
                )
            }
        )
    }
}

// MARK: - Detail View

struct ResourceMonitorDetailView: View {
    @ObservedObject var state = ResourceMonitorState.shared

    var body: some View {
        Group {
            if let selectedView = state.selectedView {
                switch selectedView {
                case .overall:
                    OverallDetailView()
                case .devdash:
                    DevDashDetailView()
                }
            } else {
                // Empty state if nothing selected
                VStack(spacing: 12) {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Select a view")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
    }
}
