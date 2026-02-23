//
//  SystemMetrics.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-23.
//

import Foundation

// MARK: - System Metrics

/// Lightweight snapshot of system resource usage
struct SystemMetrics: Equatable {
    let cpuUsagePercent: Double     // 0-100
    let memoryUsedGB: Double
    let memoryTotalGB: Double

    var memoryUsagePercent: Double {
        guard memoryTotalGB > 0 else { return 0 }
        return (memoryUsedGB / memoryTotalGB) * 100
    }

    /// Returns color based on usage percentage
    static func usageColor(percent: Double) -> UsageLevel {
        switch percent {
        case 0..<60:
            return .normal
        case 60..<80:
            return .warning
        default:
            return .critical
        }
    }
}

// MARK: - Usage Level

enum UsageLevel {
    case normal
    case warning
    case critical
}
