//
//  ServiceCountWidget.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import SwiftUI

struct ServiceCountWidget: View {
    let onTap: (() -> Void)?
    @ObservedObject private var manager = ServiceManagerState.shared.manager

    init(onTap: (() -> Void)? = nil) {
        self.onTap = onTap
    }

    var runningCount: Int {
        manager.servicesList.filter { $0.isRunning }.count
    }

    var stoppedCount: Int {
        manager.servicesList.filter { !$0.isRunning }.count
    }

    var body: some View {
        StatCard(
            icon: "server.rack",
            label: "Services",
            value: "\(runningCount)/\(manager.servicesList.count)",
            color: .blue,
            onTap: onTap
        )
        .task {
            manager.checkAllServices()
        }
    }
}
