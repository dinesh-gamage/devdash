//
//  ColimaDetailView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-25.
//

import SwiftUI

struct ColimaDetailView: View {
    @ObservedObject var state = DockerManagerState.shared

    var colima: ColimaRuntime {
        state.getColimaRuntime()
    }

    var body: some View {
        ServiceOutputPanel(
            title: "Colima",
            metadata: [
                MetadataRow(icon: "info.circle", label: "Docker runtime engine for macOS")
            ],
            dataSource: colima,
            actionButtons: {
                HStack(spacing: 8) {
                    if colima.isRunning {
                        VariantButton("Stop", variant: .danger, isLoading: colima.processingAction == .stopping) {
                            colima.stop()
                        }
                        .disabled(colima.processingAction != nil)

                        VariantButton("Restart", variant: .warning, isLoading: colima.processingAction == .restarting) {
                            colima.restart()
                        }
                        .disabled(colima.processingAction != nil)
                    } else {
                        VariantButton("Start", icon: "play.fill", variant: .primary, isLoading: colima.processingAction == .starting) {
                            colima.start()
                        }
                        .disabled(colima.processingAction != nil)
                    }

                    VariantButton(icon: "arrow.clockwise", variant: .secondary, tooltip: "Check status") {
                        Task { await colima.checkStatus() }
                    }
                }
            },
            statusContent: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(colima.isRunning ? AppTheme.statusRunning : AppTheme.statusStopped)
                        .frame(width: 12, height: 12)

                    Text(colima.isRunning ? "Running" : "Stopped")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        )
        .task {
            await colima.checkStatus()
        }
    }
}
