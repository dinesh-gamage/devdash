//
//  ProcessRow.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-25.
//

import SwiftUI

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
