//
//  DevDashMetricsCard.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-25.
//

import SwiftUI

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
