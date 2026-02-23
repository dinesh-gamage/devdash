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
                ScrollView {
                    VStack(spacing: 12) {
                        // CPU Usage
                        MetricCard(
                            icon: "cpu",
                            title: "CPU Usage",
                            value: "\(Int(metrics.cpuUsagePercent))%",
                            percent: metrics.cpuUsagePercent
                        )

                        // Memory Usage
                        MetricCard(
                            icon: "memorychip",
                            title: "Memory",
                            value: "\(String(format: "%.1f", metrics.memoryUsedGB)) / \(String(format: "%.1f", metrics.memoryTotalGB)) GB",
                            subtitle: "\(Int(metrics.memoryUsagePercent))%",
                            percent: metrics.memoryUsagePercent
                        )

                        // Swap Usage
                        MetricCard(
                            icon: "arrow.2.squarepath",
                            title: "Swap",
                            value: "\(String(format: "%.1f", metrics.swapUsedGB)) / \(String(format: "%.1f", metrics.swapTotalGB)) GB",
                            subtitle: "\(Int(metrics.swapUsagePercent))%",
                            percent: metrics.swapUsagePercent
                        )

                        // Network Usage
                        MetricCard(
                            icon: "network",
                            title: "Network",
                            value: "↓ \(String(format: "%.1f", metrics.networkDownloadMBps)) MB/s",
                            subtitle: "↑ \(String(format: "%.1f", metrics.networkUploadMBps)) MB/s",
                            percent: nil
                        )

                        // Disk I/O
                        MetricCard(
                            icon: "internaldrive",
                            title: "Disk I/O",
                            value: "R: \(String(format: "%.1f", metrics.diskReadMBps)) MB/s",
                            subtitle: "W: \(String(format: "%.1f", metrics.diskWriteMBps)) MB/s",
                            percent: nil
                        )
                    }
                    .padding(16)
                }
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

// MARK: - Metric Card (Compact Horizontal Layout)

struct MetricCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String?
    let percent: Double?

    init(icon: String, title: String, value: String, subtitle: String? = nil, percent: Double? = nil) {
        self.icon = icon
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.percent = percent
    }

    private var usageLevel: UsageLevel? {
        guard let percent = percent else { return nil }
        return SystemMetrics.usageColor(percent: percent)
    }

    private var color: Color {
        guard let usageLevel = usageLevel else { return .secondary }
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
        HStack(spacing: 12) {
            // Icon
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 24, height: 24)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Chart visualization (if percent is available)
            if let percent = percent {
                VStack(spacing: 4) {
                    // Mini circular progress chart
                    ZStack {
                        Circle()
                            .stroke(color.opacity(0.2), lineWidth: 4)
                            .frame(width: 40, height: 40)

                        Circle()
                            .trim(from: 0, to: percent / 100)
                            .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .frame(width: 40, height: 40)
                            .rotationEffect(.degrees(-90))

                        Text("\(Int(percent))%")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }

                    // Status text below chart
                    Text(statusText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(percent != nil ? 0.3 : 0.1), lineWidth: 1)
        )
    }

    private var statusText: String {
        guard let usageLevel = usageLevel else { return "" }
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
