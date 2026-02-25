//
//  ContainerDetailView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-25.
//

import SwiftUI

struct ContainerDetailView: View {
    @ObservedObject var container: ContainerRuntime

    var body: some View {
        ServiceOutputPanel(
            title: container.config.name,
            metadata: buildMetadata(),
            dataSource: container,
            actionButtons: {
                HStack(spacing: 8) {
                    if container.isRunning {
                        VariantButton("Stop", variant: .danger, isLoading: container.processingAction == .stopping) {
                            container.stop()
                        }
                        .disabled(container.processingAction != nil)

                        VariantButton("Restart", variant: .warning, isLoading: container.processingAction == .restarting) {
                            container.restart()
                        }
                        .disabled(container.processingAction != nil)
                    } else {
                        VariantButton("Start", icon: "play.fill", variant: .primary, isLoading: container.processingAction == .starting) {
                            container.start()
                        }
                        .disabled(container.processingAction != nil)
                    }

                    VariantButton(icon: "arrow.clockwise", variant: .secondary, tooltip: "Check container status") {
                        Task { await container.checkStatus() }
                    }
                }
            },
            statusContent: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 12, height: 12)

                    Text(container.status.rawValue.capitalized)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        )
        .task {
            await container.checkStatus()
        }
    }

    private var statusColor: Color {
        switch container.status {
        case .running:
            return AppTheme.statusRunning
        case .stopped, .created, .paused:
            return AppTheme.statusStopped
        case .unknown:
            return .gray
        }
    }

    private func buildMetadata() -> [MetadataRow] {
        var rows: [MetadataRow] = []

        // Image
        rows.append(MetadataRow(
            icon: "cube",
            label: "Image",
            value: container.config.image,
            copyable: true
        ))

        // Docker ID (if available)
        if let dockerId = container.dockerId {
            rows.append(MetadataRow(
                icon: "number",
                label: "Container ID",
                value: dockerId,
                copyable: true,
                monospaced: true
            ))
        }

        // Ports
        if !container.config.ports.isEmpty {
            let portsStr = container.config.ports.map { $0.dockerFormat }.joined(separator: ", ")
            rows.append(MetadataRow(
                icon: "network",
                label: "Ports",
                value: portsStr
            ))
        }

        // Volumes
        if !container.config.volumes.isEmpty {
            rows.append(MetadataRow(
                icon: "externaldrive",
                label: "Volumes",
                value: "\(container.config.volumes.count) mount(s)"
            ))
        }

        // Environment
        if !container.config.environment.isEmpty {
            rows.append(MetadataRow(
                icon: "gearshape",
                label: "Environment",
                value: container.config.environment.keys.joined(separator: ", ")
            ))
        }

        // Network
        if let network = container.config.network {
            rows.append(MetadataRow(
                icon: "network",
                label: "Network",
                value: network
            ))
        }

        // Restart Policy
        if let policy = container.config.restartPolicy {
            rows.append(MetadataRow(
                icon: "arrow.clockwise",
                label: "Restart Policy",
                value: policy
            ))
        }

        return rows
    }
}
