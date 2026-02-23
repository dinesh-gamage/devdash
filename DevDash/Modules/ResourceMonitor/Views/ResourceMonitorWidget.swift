//
//  ResourceMonitorWidget.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-23.
//

import SwiftUI

struct ResourceMonitorWidget: View {
    @ObservedObject private var monitor = ResourceMonitorState.shared.monitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("System Resources")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.orange.opacity(0.1))

            // Content
            if let metrics = monitor.currentMetrics {
                VStack(spacing: 20) {
                    // CPU Usage
                    CPUUsageView(cpuPercent: metrics.cpuUsagePercent)

                    Divider()

                    // Memory Usage
                    MemoryUsageView(
                        usedGB: metrics.memoryUsedGB,
                        totalGB: metrics.memoryTotalGB,
                        percent: metrics.memoryUsagePercent
                    )
                }
                .padding(16)
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading metrics...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
        }
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .shadow(color: AppTheme.shadowColor, radius: 4, y: 2)
        .onAppear {
            monitor.startMonitoring()
        }
        .onDisappear {
            monitor.stopMonitoring()
        }
    }
}

// MARK: - CPU Usage View

struct CPUUsageView: View {
    let cpuPercent: Double

    private var usageLevel: UsageLevel {
        SystemMetrics.usageColor(percent: cpuPercent)
    }

    private var color: Color {
        switch usageLevel {
        case .normal:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            // Circular progress
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 6)
                    .frame(width: 60, height: 60)

                Circle()
                    .trim(from: 0, to: cpuPercent / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))

                Text("\(Int(cpuPercent))%")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("CPU Usage")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                HStack(spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)

                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
    }

    private var statusText: String {
        switch usageLevel {
        case .normal:
            return "Normal"
        case .warning:
            return "High"
        case .critical:
            return "Critical"
        }
    }
}

// MARK: - Memory Usage View

struct MemoryUsageView: View {
    let usedGB: Double
    let totalGB: Double
    let percent: Double

    private var usageLevel: UsageLevel {
        SystemMetrics.usageColor(percent: percent)
    }

    private var color: Color {
        switch usageLevel {
        case .normal:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Memory Usage")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Spacer()

                Text("\(String(format: "%.1f", usedGB)) GB / \(String(format: "%.1f", totalGB)) GB")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.2))
                        .frame(height: 8)

                    // Fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * (percent / 100), height: 8)
                }
            }
            .frame(height: 8)

            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)

                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(Int(percent))%")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
            }
        }
    }

    private var statusText: String {
        switch usageLevel {
        case .normal:
            return "Normal"
        case .warning:
            return "High"
        case .critical:
            return "Critical"
        }
    }
}
