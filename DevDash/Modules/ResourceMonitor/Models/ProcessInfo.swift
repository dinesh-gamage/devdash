//
//  ProcessInfo.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-23.
//

import Foundation

// MARK: - System Process Info

struct SystemProcess: Identifiable {
    let id: Int32                // Process ID (PID)
    let name: String             // Process name
    let cpuPercent: Double       // CPU usage percentage
    let memoryMB: Double         // Memory usage in MB
    let networkMBps: Double      // Network usage in MB/s (placeholder for now)
    let diskMBps: Double         // Disk I/O in MB/s (placeholder for now)
}

// MARK: - Process Sort Option

enum ProcessSortOption: String, CaseIterable {
    case cpu = "CPU"
    case memory = "Memory"
    case network = "Network"
    case disk = "Disk"

    var icon: String {
        switch self {
        case .cpu:
            return "cpu"
        case .memory:
            return "memorychip"
        case .network:
            return "network"
        case .disk:
            return "internaldrive"
        }
    }
}
