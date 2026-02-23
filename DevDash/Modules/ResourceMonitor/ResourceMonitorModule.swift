//
//  ResourceMonitorModule.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-23.
//

import SwiftUI
import Combine

// MARK: - Resource Monitor State

@MainActor
class ResourceMonitorState: ObservableObject {
    static let shared = ResourceMonitorState()

    @Published var monitor: SystemMetricsMonitor

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

    // Dashboard-only module - no sidebar view needed
    func makeSidebarView() -> AnyView {
        AnyView(EmptyView())
    }

    func makeDetailView() -> AnyView {
        AnyView(EmptyView())
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
